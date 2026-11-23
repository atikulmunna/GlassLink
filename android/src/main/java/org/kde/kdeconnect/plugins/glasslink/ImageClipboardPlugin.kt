/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.helpers.ThreadHelper
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect.plugins.clipboard.ClipboardFloatingActivity
import org.kde.kdeconnect.plugins.clipboard.ClipboardListener
import org.kde.kdeconnect_tp.R
import java.io.File

/**
 * Copy an image on one device, paste it on the other. Images copied on the Mac go onto the
 * Android clipboard (through our FileProvider); images copied here go to the Mac clipboard.
 *
 * Reading the clipboard in the background needs the same READ_LOGS setup as text clipboard sync.
 * Only loads for devices that speak [PACKET_TYPE_CLIPBOARD_IMAGE] (GlassLink for Mac).
 */
@LoadablePlugin
class ImageClipboardPlugin : Plugin(), ClipboardListener.ImageObserver {
    override val displayName: String
        get() = context.getString(R.string.pref_plugin_glasslink_image_clipboard)

    override val description: String
        get() = context.getString(R.string.pref_plugin_glasslink_image_clipboard_desc)

    override val supportedPacketTypes: Array<String> = arrayOf(PACKET_TYPE_CLIPBOARD_IMAGE, PACKET_TYPE_CLIPBOARD_REQUEST)
    override val outgoingPacketTypes: Array<String> = arrayOf(PACKET_TYPE_CLIPBOARD_IMAGE)

    override fun onCreate() {
        ClipboardListener.instance(context).registerImageObserver(this)
    }

    /** Mirrors the Mac's "Get Phone's Clipboard": the Mac answers with its text or image. */
    override fun getUiButtons(): List<PluginUiButton> = listOf(
        PluginUiButton(context.getString(R.string.glasslink_get_mac_clipboard), R.drawable.ic_baseline_content_paste_24) {
            device.sendPacket(NetworkPacket(PACKET_TYPE_CLIPBOARD_REQUEST))
        }
    )

    override fun onDestroy() {
        ClipboardListener.instance(context).removeImageObserver(this)
    }

    override fun onPacketReceived(np: NetworkPacket): Boolean {
        if (np.type == PACKET_TYPE_CLIPBOARD_REQUEST) {
            // Android only lets the focused app read the clipboard: briefly raise the invisible
            // clipboard activity (needs "draw over other apps" when we're in the background).
            context.startActivity(ClipboardFloatingActivity.getIntent(context, false, force = true))
            return true
        }
        val payload = np.payload ?: return false
        val mimeType = np.getString("mimeType", "image/png")
        ThreadHelper.runOnNewThread {
            try {
                val folder = File(context.cacheDir, "clipboard").apply { mkdirs() }
                folder.listFiles()?.forEach { it.delete() } // keep only the latest image
                val extension = if (mimeType == "image/jpeg") "jpg" else "png"
                val file = File(folder, "clip-${System.currentTimeMillis()}.$extension")
                payload.inputStream?.use { input -> file.outputStream().use { input.copyTo(it) } }
                val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
                ClipboardListener.instance(context).setImage(uri, mimeType)
            } catch (e: Exception) {
                Log.e(TAG, "Couldn't put the image on the clipboard", e)
            } finally {
                payload.close()
            }
        }
        return true
    }

    override fun clipboardImageChanged(uri: Uri, mimeType: String) {
        // Read now: access to another app's clipboard image is only granted for a short while.
        ThreadHelper.runOnNewThread {
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@runOnNewThread
                if (bytes.isEmpty() || bytes.size > MAX_BYTES) return@runOnNewThread
                val packet = NetworkPacket(PACKET_TYPE_CLIPBOARD_IMAGE)
                packet["mimeType"] = mimeType
                packet.payload = NetworkPacket.Payload(bytes)
                device.sendPacket(packet)
            } catch (e: Exception) {
                Log.w(TAG, "Couldn't read the copied image", e)
            }
        }
    }

    companion object {
        private const val TAG = "GlassLinkImageClipboard"
        private const val MAX_BYTES = 25 * 1024 * 1024
        const val PACKET_TYPE_CLIPBOARD_IMAGE = "glasslink.clipboard.image"
        const val PACKET_TYPE_CLIPBOARD_REQUEST = "glasslink.clipboard.request"
    }
}
