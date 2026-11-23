/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect_tp.R

/**
 * Ring and Ping as tiles on the device screen, mirroring the Mac app's quick actions
 * (upstream only offers them in the overflow menu).
 */
@LoadablePlugin
class QuickActionsPlugin : Plugin() {
    override val displayName: String
        get() = context.getString(R.string.pref_plugin_glasslink_quick_actions)

    override val description: String
        get() = context.getString(R.string.pref_plugin_glasslink_quick_actions_desc)

    override val supportedPacketTypes: Array<String> = emptyArray()
    override val outgoingPacketTypes: Array<String> = arrayOf(PACKET_TYPE_FIND, PACKET_TYPE_PING)

    override fun getUiButtons(): List<PluginUiButton> = listOf(
        PluginUiButton(context.getString(R.string.glasslink_ring), R.drawable.glasslink_ic_ring_24) {
            device.sendPacket(NetworkPacket(PACKET_TYPE_FIND))
        },
        PluginUiButton(context.getString(R.string.glasslink_ping), R.drawable.ic_baseline_send_24) {
            device.sendPacket(NetworkPacket(PACKET_TYPE_PING).apply { this["message"] = "👋" })
        },
    )

    companion object {
        private const val PACKET_TYPE_FIND = "kdeconnect.findmyphone.request"
        private const val PACKET_TYPE_PING = "kdeconnect.ping"

        /** Tile order, matching the Mac's quick actions: Ring, Send files, Clipboard, Ping. */
        val buttonOrder = listOf("QuickActionsPlugin#0", "SharePlugin#0", "ImageClipboardPlugin#0", "ClipboardPlugin#0", "QuickActionsPlugin#1")
    }
}
