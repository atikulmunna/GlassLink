/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.Manifest
import android.content.ContentUris
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.provider.MediaStore
import android.util.Log
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect_tp.R

/**
 * Sends each new screenshot to the paired GlassLink Mac the moment it is saved, so it lands on
 * the Mac clipboard (like Phone Link). Watches MediaStore instead of polling the folder.
 *
 * Only loads for devices that accept [PACKET_TYPE_SCREENSHOT] (GlassLink for Mac).
 */
@LoadablePlugin
class ScreenshotPushPlugin : Plugin() {
    private var thread: HandlerThread? = null
    private var observer: ContentObserver? = null
    private val sent = LinkedHashSet<Long>()
    private var startedAt = 0L

    override val displayName: String
        get() = context.getString(R.string.pref_plugin_glasslink_screenshots)

    override val description: String
        get() = context.getString(R.string.pref_plugin_glasslink_screenshots_desc)

    override val supportedPacketTypes: Array<String> = emptyArray()
    override val outgoingPacketTypes: Array<String> = arrayOf(PACKET_TYPE_SCREENSHOT)

    override val requiredPermissions: Array<String>
        get() = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
        } else {
            arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    private val check = Runnable { sendNewScreenshots() }

    override fun onCreate() {
        startedAt = System.currentTimeMillis() / 1000
        val handlerThread = HandlerThread("GlassLinkScreenshots").also { it.start() }
        thread = handlerThread
        val handler = Handler(handlerThread.looper)
        val contentObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                // MediaStore fires several changes per screenshot; coalesce them.
                handler.removeCallbacks(check)
                handler.postDelayed(check, 350)
            }
        }
        context.contentResolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, contentObserver)
        observer = contentObserver
    }

    override fun onDestroy() {
        observer?.let { context.contentResolver.unregisterContentObserver(it) }
        observer = null
        thread?.quitSafely()
        thread = null
    }

    private fun sendNewScreenshots() {
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val columns = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.MIME_TYPE,
            MediaStore.Images.Media.SIZE,
        )
        var selection = "${MediaStore.Images.Media.DATE_ADDED} >= ?"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            columns += MediaStore.Images.Media.RELATIVE_PATH
            selection += " AND ${MediaStore.Images.Media.IS_PENDING} = 0" // still being written otherwise
        }
        try {
            context.contentResolver.query(
                collection, columns.toTypedArray(), selection, arrayOf((startedAt - 5).toString()),
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )?.use { cursor ->
                var looked = 0
                while (cursor.moveToNext() && looked++ < 5) {
                    val id = cursor.getLong(0)
                    if (id in sent) continue
                    val name = cursor.getString(1) ?: continue
                    val path = if (cursor.columnCount > 4) cursor.getString(4) ?: "" else ""
                    if (!path.contains("Screenshot", ignoreCase = true) && !name.startsWith("Screenshot", ignoreCase = true)) continue
                    val size = cursor.getLong(3)
                    if (size <= 0) continue
                    sent += id
                    while (sent.size > 50) sent.remove(sent.first())
                    val stream = context.contentResolver.openInputStream(ContentUris.withAppendedId(collection, id)) ?: continue
                    val packet = NetworkPacket(PACKET_TYPE_SCREENSHOT)
                    packet["filename"] = name
                    packet["mimeType"] = cursor.getString(2) ?: "image/png"
                    packet.payload = NetworkPacket.Payload(stream, size)
                    device.sendPacket(packet)
                }
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "No permission to read screenshots", e)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send screenshot", e)
        }
    }

    companion object {
        private const val TAG = "GlassLinkScreenshots"
        const val PACKET_TYPE_SCREENSHOT = "glasslink.screenshot"
    }
}
