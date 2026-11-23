/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityOptions
import android.app.Notification
import android.app.PendingIntent
import android.os.Build
import android.service.notification.StatusBarNotification
import android.telecom.TelecomManager
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.getSystemService
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect.plugins.notifications.NotificationReceiver
import org.kde.kdeconnect_tp.R

/**
 * Answers, declines and ends phone calls from the Mac (`glasslink.call.request`, `action`: answer,
 * decline or end). The call itself stays on the phone: talk through the phone or its earbuds.
 *
 * Carrier calls go through Telecom. Calls from apps such as WhatsApp manage themselves and Android
 * ignores Telecom requests for them, so for those GlassLink presses the Answer or Decline button
 * of the app's own call notification instead (it can see notifications for notification sync).
 */
@LoadablePlugin
class CallControlPlugin : Plugin() {
    override val displayName: String
        get() = context.getString(R.string.pref_plugin_glasslink_calls)

    override val description: String
        get() = context.getString(R.string.pref_plugin_glasslink_calls_desc)

    override val supportedPacketTypes: Array<String> = arrayOf(PACKET_TYPE_CALL_REQUEST)
    override val outgoingPacketTypes: Array<String> = emptyArray()

    override val minSdk: Int = Build.VERSION_CODES.P
    override val requiredPermissions: Array<String> = arrayOf(Manifest.permission.ANSWER_PHONE_CALLS)
    override val permissionExplanation: Int = R.string.glasslink_calls_permission_explanation

    @SuppressLint("MissingPermission") // requiredPermissions: the plugin only loads once it's granted
    override fun onPacketReceived(np: NetworkPacket): Boolean {
        val action = np.getString("action", "")
        if (action !in ACTIONS) return false
        val telecom = context.getSystemService<TelecomManager>() ?: return false
        val carrierCall = runCatching { telecom.isInManagedCall }.getOrDefault(true)
        if (!carrierCall && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            NotificationReceiver.hasReadNotificationsPermission(context)
        ) {
            NotificationReceiver.RunCommand(context) { service ->
                val pressed = runCatching { pressCallNotification(service.activeNotifications.orEmpty(), action) }
                    .onFailure { Log.w(TAG, "Couldn't use the call notification", it) }
                    .getOrDefault(false)
                if (!pressed) telecomRequest(telecom, action)
            }
        } else {
            telecomRequest(telecom, action)
        }
        return true
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION") // still the only call control for apps that aren't the phone's dialer
    private fun telecomRequest(telecom: TelecomManager, action: String) {
        try {
            if (action == "answer") telecom.acceptRingingCall() else telecom.endCall()
        } catch (e: SecurityException) {
            Log.w(TAG, "Not allowed to control calls", e)
        }
    }

    /** Fires the app's own Answer, Decline or Hang up button; false if no call notification has one. */
    @RequiresApi(Build.VERSION_CODES.S)
    private fun pressCallNotification(notifications: Array<out StatusBarNotification>, action: String): Boolean {
        val calls = notifications
            .filter { it.packageName != context.packageName && isCallNotification(it.notification) }
            .sortedByDescending { it.postTime }
        for (call in calls) {
            val intent = callIntent(call.notification, action) ?: continue
            Log.i(TAG, "Pressing $action on ${call.packageName}'s call notification")
            intent.send(context, 0, null, null, null, null, backgroundStartOptions())
            return true
        }
        return false
    }

    private fun isCallNotification(n: Notification): Boolean =
        n.category == Notification.CATEGORY_CALL ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && n.extras.containsKey(Notification.EXTRA_CALL_TYPE))

    /** Android 12+ call-style notifications name their buttons; older ones are matched by title. */
    @RequiresApi(Build.VERSION_CODES.S)
    private fun callIntent(n: Notification, action: String): PendingIntent? {
        val extras = n.extras
        fun extra(key: String): PendingIntent? = extras.getParcelable(key, PendingIntent::class.java)
        val named = when (action) {
            "answer" -> extra(Notification.EXTRA_ANSWER_INTENT)
            "decline" -> extra(Notification.EXTRA_DECLINE_INTENT) ?: extra(Notification.EXTRA_HANG_UP_INTENT)
            else -> extra(Notification.EXTRA_HANG_UP_INTENT) ?: extra(Notification.EXTRA_DECLINE_INTENT)
        }
        if (named != null) return named
        val words = if (action == "answer") ANSWER_WORDS else DECLINE_WORDS
        return n.actions.orEmpty().firstOrNull { button ->
            val title = button.title?.toString()?.lowercase().orEmpty()
            (action == "answer" && button.semanticAction == Notification.Action.SEMANTIC_ACTION_CALL) ||
                words.any { title.contains(it) }
        }?.actionIntent
    }

    /** Answering usually opens the app's call screen, which Android only allows if we say so. */
    private fun backgroundStartOptions() = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA -> ActivityOptions.makeBasic()
            .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS).toBundle()
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> @Suppress("DEPRECATION") ActivityOptions.makeBasic()
            .setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED).toBundle()
        else -> null
    }

    companion object {
        const val PACKET_TYPE_CALL_REQUEST = "glasslink.call.request"
        private const val TAG = "GlassLinkCalls"
        private val ACTIONS = setOf("answer", "decline", "end")
        private val ANSWER_WORDS = listOf("answer", "accept")
        private val DECLINE_WORDS = listOf("decline", "reject", "hang up", "end call", "end")
    }
}
