/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.Manifest
import android.annotation.SuppressLint
import android.os.Build
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.content.getSystemService
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect_tp.R

/**
 * Answers, declines and ends phone calls from the Mac (`glasslink.call.request`, `action`: answer,
 * decline or end). The call itself stays on the phone: talk through the phone or its earbuds.
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
    @Suppress("DEPRECATION") // still the only call control for apps that aren't the phone's dialer
    override fun onPacketReceived(np: NetworkPacket): Boolean {
        val telecom = context.getSystemService<TelecomManager>() ?: return false
        try {
            when (np.getString("action", "")) {
                "answer" -> telecom.acceptRingingCall()
                "decline", "end" -> telecom.endCall()
                else -> return false
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Not allowed to control calls", e)
            return false
        }
        return true
    }

    companion object {
        const val PACKET_TYPE_CALL_REQUEST = "glasslink.call.request"
        private const val TAG = "GlassLinkCalls"
    }
}
