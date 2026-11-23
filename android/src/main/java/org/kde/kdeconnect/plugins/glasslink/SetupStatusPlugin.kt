/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.app.PendingIntent
import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.kde.kdeconnect.Device
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.helpers.NotificationHelper
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect.ui.MainActivity
import org.kde.kdeconnect_tp.R

/**
 * Tells the Mac which features are waiting for a permission on this phone (the "Finish setting up"
 * list), so it can say why notifications or calls aren't arriving instead of staying silent.
 *
 * The Mac sends `glasslink.setup.request` (with `show`: true to open the setup screen here) and
 * gets `glasslink.setup` back: `missing` (features that can't run) and `limited` (features running
 * without an optional permission), as names to show. It's sent again whenever that changes.
 */
@LoadablePlugin
class SetupStatusPlugin : Plugin() {
    override val displayName: String
        get() = context.getString(R.string.pref_plugin_glasslink_setup)

    override val description: String
        get() = context.getString(R.string.pref_plugin_glasslink_setup_desc)

    override val supportedPacketTypes: Array<String> = arrayOf(PACKET_TYPE_SETUP_REQUEST)
    override val outgoingPacketTypes: Array<String> = arrayOf(PACKET_TYPE_SETUP)

    private var lastReport: Pair<List<String>, List<String>>? = null
    private val listener = Device.PluginsChangedListener { report(force = false) }

    override fun onCreate() {
        device.addPluginsChangedListener(listener)
        report(force = true)
    }

    override fun onDestroy() {
        device.removePluginsChangedListener(listener)
    }

    override fun onPacketReceived(np: NetworkPacket): Boolean {
        if (np.getBoolean("show", false)) showSetup()
        report(force = true)
        return true
    }

    private fun missing() = device.pluginsWithoutPermissions.values.map { it.displayName }.sorted()
    private fun limited() = device.pluginsWithoutOptionalPermissions.values.map { it.displayName }.sorted()

    private fun report(force: Boolean) {
        val current = missing() to limited()
        if (!force && current == lastReport) return
        lastReport = current
        device.sendPacket(NetworkPacket(PACKET_TYPE_SETUP).apply {
            this["missing"] = current.first
            this["limited"] = current.second
        })
    }

    /** Opens this Mac's page, where "Finish setting up" is; from the background, via a notification. */
    private fun showSetup() {
        val intent = Intent(context, MainActivity::class.java)
            .putExtra(MainActivity.EXTRA_DEVICE_ID, device.deviceId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (Settings.canDrawOverlays(context)) {
            context.startActivity(intent)
            return
        }
        val features = (missing() + limited()).distinct()
        val text = if (features.isEmpty()) context.getString(R.string.glasslink_setup_text_none)
                   else context.getString(R.string.glasslink_setup_text, features.joinToString(", "))
        val notification = NotificationCompat.Builder(context, NotificationHelper.Channels.HIGHPRIORITY)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.glasslink_setup_title, device.name))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(PendingIntent.getActivity(context, 2, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification) }
    }

    companion object {
        const val PACKET_TYPE_SETUP = "glasslink.setup"
        const val PACKET_TYPE_SETUP_REQUEST = "glasslink.setup.request"
        private const val NOTIFICATION_ID = 0x6C70
    }
}
