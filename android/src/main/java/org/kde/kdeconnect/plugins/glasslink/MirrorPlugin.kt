/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Path
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.getSystemService
import org.kde.kdeconnect.KdeConnect
import org.kde.kdeconnect.KdeConnectAccessibilityService
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.helpers.NotificationHelper
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect_tp.R

/**
 * Screen mirroring for GlassLink for Mac, like Phone Link's: the Mac asks, the phone shows
 * Android's sharing prompt, and [MirrorService] streams the screen. Clicks and drags on the Mac
 * come back as taps and swipes, performed by GlassLink's accessibility service.
 *
 * Packets: the Mac sends `glasslink.mirror.request` (`start`: true/false) and
 * `glasslink.mirror.input` (`action`: tap, longpress, swipe, back, home, recents; positions are
 * fractions of the screen, 0–1). The phone answers with `glasslink.mirror` (`state`: ready with
 * `port`/`width`/`height`, denied, stopped, failed, or noInput).
 */
@LoadablePlugin
class MirrorPlugin : Plugin() {
    override val displayName: String
        get() = context.getString(R.string.pref_plugin_glasslink_mirror)

    override val description: String
        get() = context.getString(R.string.pref_plugin_glasslink_mirror_desc)

    override val supportedPacketTypes: Array<String> = arrayOf(PACKET_TYPE_MIRROR_REQUEST, PACKET_TYPE_MIRROR_INPUT)
    override val outgoingPacketTypes: Array<String> = arrayOf(PACKET_TYPE_MIRROR)

    override fun onPacketReceived(np: NetworkPacket): Boolean {
        when (np.type) {
            PACKET_TYPE_MIRROR_REQUEST -> if (np.getBoolean("start", true)) askToShare() else MirrorService.stop(context)
            PACKET_TYPE_MIRROR_INPUT -> perform(np)
        }
        return true
    }

    /** Shows the sharing prompt; if Android won't let us open it from the background, a notification does. */
    private fun askToShare() {
        val intent = Intent(context, MirrorPermissionActivity::class.java)
            .putExtra(MirrorService.EXTRA_DEVICE_ID, device.deviceId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
        if (Settings.canDrawOverlays(context)) {
            context.startActivity(intent)
        } else {
            val tap = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification = NotificationCompat.Builder(context, NotificationHelper.Channels.HIGHPRIORITY)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(context.getString(R.string.glasslink_mirror_request_title, device.name))
                .setContentText(context.getString(R.string.glasslink_mirror_request_text))
                .setContentIntent(tap)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            runCatching { NotificationManagerCompat.from(context).notify(REQUEST_NOTIFICATION_ID, notification) }
        }
    }

    private fun perform(np: NetworkPacket) {
        val service = KdeConnectAccessibilityService.instance
        if (service == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            device.sendPacket(NetworkPacket(PACKET_TYPE_MIRROR).apply { this["state"] = "noInput" })
            return
        }
        val metrics = DisplayMetrics().also {
            @Suppress("DEPRECATION")
            context.getSystemService<WindowManager>()!!.defaultDisplay.getRealMetrics(it)
        }
        fun px(key: String, size: Int) = (np.getDouble(key, 0.5).coerceIn(0.0, 1.0) * (size - 1)).toFloat()
        val x = px("x", metrics.widthPixels)
        val y = px("y", metrics.heightPixels)
        when (np.getString("action", "")) {
            "tap" -> service.dispatchGesture(stroke(x, y, x, y, 1), null, null)
            "longpress" -> service.dispatchGesture(stroke(x, y, x, y, 650), null, null)
            "swipe" -> {
                val duration = np.getLong("duration", 250).coerceIn(50, 2000)
                service.dispatchGesture(stroke(x, y, px("x2", metrics.widthPixels), px("y2", metrics.heightPixels), duration), null, null)
            }
            "back" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            "home" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            "recents" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
        }
    }

    private fun stroke(x: Float, y: Float, x2: Float, y2: Float, durationMs: Long): GestureDescription {
        val path = Path().apply {
            moveTo(x, y)
            if (x2 != x || y2 != y) lineTo(x2, y2)
        }
        return GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, durationMs)).build()
    }

    companion object {
        const val PACKET_TYPE_MIRROR = "glasslink.mirror"
        const val PACKET_TYPE_MIRROR_REQUEST = "glasslink.mirror.request"
        const val PACKET_TYPE_MIRROR_INPUT = "glasslink.mirror.input"
        private const val REQUEST_NOTIFICATION_ID = 0x6C6E

        fun reportState(deviceId: String, state: String) {
            KdeConnect.getInstance().getDevice(deviceId)?.sendPacket(NetworkPacket(PACKET_TYPE_MIRROR).apply { this["state"] = state })
        }
    }
}
