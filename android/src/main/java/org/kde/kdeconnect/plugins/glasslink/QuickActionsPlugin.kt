/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.plugins.clipboard.ClipboardFloatingActivity
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
    override val outgoingPacketTypes: Array<String> =
        arrayOf(PACKET_TYPE_FIND, PACKET_TYPE_PING, PACKET_TYPE_MIRROR_OFFER, PACKET_TYPE_LOCK)

    /** Whether the Mac's GlassLink handles this packet type (newer Macs only for some tiles). */
    private fun macHandles(type: String) = device.deviceInfo.incomingCapabilities?.contains(type) == true

    override fun getUiButtons(): List<PluginUiButton> = buildList {
        add(PluginUiButton(context.getString(R.string.glasslink_ring), R.drawable.glasslink_sym_ring) {
            device.sendPacket(NetworkPacket(PACKET_TYPE_FIND))
        })
        // Send this phone's clipboard to the Mac (it's read in a brief foreground activity, as Android requires).
        add(PluginUiButton(context.getString(R.string.send_clipboard), R.drawable.glasslink_sym_send_clipboard) { activity ->
            activity.startActivity(ClipboardFloatingActivity.getIntent(activity, true))
        })
        add(PluginUiButton(context.getString(R.string.glasslink_ping), R.drawable.glasslink_sym_wave) {
            device.sendPacket(NetworkPacket(PACKET_TYPE_PING).apply { this["message"] = "👋" })
        })
        if (macHandles(PACKET_TYPE_MIRROR_OFFER)) {
            // Opens the Phone Screen window on the Mac, which then asks to share this screen.
            add(PluginUiButton(context.getString(R.string.glasslink_mirror_to_mac), R.drawable.glasslink_sym_mirror) {
                device.sendPacket(NetworkPacket(PACKET_TYPE_MIRROR_OFFER))
            })
        }
        if (macHandles(PACKET_TYPE_LOCK)) {
            add(PluginUiButton(context.getString(R.string.glasslink_lock_mac), R.drawable.glasslink_sym_lock) {
                device.sendPacket(NetworkPacket(PACKET_TYPE_LOCK))
            })
        }
    }

    companion object {
        private const val PACKET_TYPE_FIND = "kdeconnect.findmyphone.request"
        private const val PACKET_TYPE_PING = "kdeconnect.ping"
        private const val PACKET_TYPE_MIRROR_OFFER = "glasslink.mirror.offer"
        private const val PACKET_TYPE_LOCK = "glasslink.mac.lock"

        /** Tile order: Ring, Send files, Mac's clipboard, Send clipboard, Wave, Mirror to Mac, Lock Mac. */
        val buttonOrder = listOf(
            "QuickActionsPlugin#0", "SharePlugin#0", "ImageClipboardPlugin#0", "QuickActionsPlugin#1",
            "QuickActionsPlugin#2", "QuickActionsPlugin#3", "QuickActionsPlugin#4",
        )
    }
}
