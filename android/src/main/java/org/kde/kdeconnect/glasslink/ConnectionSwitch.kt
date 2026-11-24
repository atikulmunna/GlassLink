/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.glasslink

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.view.Menu
import android.view.MenuItem
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.edit
import androidx.preference.PreferenceManager
import org.kde.kdeconnect.BackgroundService
import org.kde.kdeconnect.KdeConnect
import org.kde.kdeconnect.helpers.NotificationHelper
import org.kde.kdeconnect.ui.MainActivity
import org.kde.kdeconnect_tp.R

/**
 * Disconnect: turns GlassLink off on this phone until it's turned back on. The connection service
 * stops (so no Mac can find or reach the phone, and nothing restarts it: boot, network changes and
 * opening the app all respect this) and every link closes. From the persistent notification, the
 * power button in the app's top bar, or the "Reconnect" notification shown while it's off.
 */
object ConnectionSwitch {
    const val ACTION_DISCONNECT = "org.kde.kdeconnect.glasslink.DISCONNECT"
    const val ACTION_RECONNECT = "org.kde.kdeconnect.glasslink.RECONNECT"
    private const val KEY_DISCONNECTED = "glasslink_disconnected"
    private const val NOTIFICATION_ID = 0x6C71

    fun isDisconnected(context: Context): Boolean =
        PreferenceManager.getDefaultSharedPreferences(context).getBoolean(KEY_DISCONNECTED, false)

    fun disconnect(context: Context) {
        val app = context.applicationContext
        PreferenceManager.getDefaultSharedPreferences(app).edit { putBoolean(KEY_DISCONNECTED, true) }
        // Stop listening first, so the Mac can't connect straight back, then close the links.
        app.stopService(Intent(app, BackgroundService::class.java))
        KdeConnect.getInstance().devices.values.forEach { it.disconnect() }
        showDisconnectedNotification(app)
    }

    fun reconnect(context: Context) {
        val app = context.applicationContext
        PreferenceManager.getDefaultSharedPreferences(app).edit { putBoolean(KEY_DISCONNECTED, false) }
        NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
        BackgroundService.ForceRefreshConnections(app)
    }

    fun pendingIntent(context: Context, action: String): PendingIntent =
        PendingIntent.getBroadcast(
            context, action.hashCode(),
            Intent(context, ConnectionSwitchReceiver::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    /** The power button in the top bar: Disconnect while connected, Reconnect (dimmed) while off. */
    fun addMenuItem(menu: Menu, activity: Activity) {
        if (menu.findItem(R.id.glasslink_power) != null) return
        val off = isDisconnected(activity)
        menu.add(Menu.NONE, R.id.glasslink_power, Menu.FIRST, if (off) R.string.glasslink_reconnect else R.string.glasslink_disconnect).apply {
            setIcon(R.drawable.glasslink_ic_power_24)
            icon?.mutate()?.alpha = if (off) 110 else 255
            setShowAsAction(MenuItem.SHOW_AS_ACTION_ALWAYS)
            setOnMenuItemClickListener {
                if (isDisconnected(activity)) {
                    reconnect(activity)
                    Toast.makeText(activity, R.string.glasslink_reconnecting, Toast.LENGTH_SHORT).show()
                } else {
                    disconnect(activity)
                    Toast.makeText(activity, R.string.glasslink_disconnected_toast, Toast.LENGTH_LONG).show()
                }
                activity.invalidateOptionsMenu()
                true
            }
        }
    }

    private fun showDisconnectedNotification(context: Context) {
        val open = PendingIntent.getActivity(
            context, 3, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = NotificationCompat.Builder(context, NotificationHelper.Channels.PERSISTENT)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.glasslink_disconnected_title))
            .setContentText(context.getString(R.string.glasslink_disconnected_text))
            .setContentIntent(open)
            .addAction(0, context.getString(R.string.glasslink_reconnect), pendingIntent(context, ACTION_RECONNECT))
            .setShowWhen(false)
            .setSilent(true)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification) }
    }
}

/** Handles Disconnect and Reconnect from notifications. */
class ConnectionSwitchReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ConnectionSwitch.ACTION_DISCONNECT -> ConnectionSwitch.disconnect(context)
            ConnectionSwitch.ACTION_RECONNECT -> ConnectionSwitch.reconnect(context)
        }
    }
}
