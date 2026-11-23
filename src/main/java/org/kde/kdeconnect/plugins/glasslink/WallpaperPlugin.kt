/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.app.WallpaperColors
import android.app.WallpaperManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.graphics.drawable.toBitmap
import androidx.core.graphics.scale
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.helpers.ThreadHelper
import org.kde.kdeconnect.plugins.Plugin
import org.kde.kdeconnect.plugins.PluginFactory.LoadablePlugin
import org.kde.kdeconnect_tp.R
import java.io.ByteArrayOutputStream

/**
 * Shares the phone's home-screen wallpaper (downscaled) and its colours, so GlassLink for Mac
 * can draw the phone the way it looks. Sent on connect, on request, and whenever it changes.
 */
@LoadablePlugin
class WallpaperPlugin : Plugin() {
    private val handler = Handler(Looper.getMainLooper())
    private var listener: WallpaperManager.OnColorsChangedListener? = null
    private val sendNow = Runnable { ThreadHelper.runOnNewThread { sendWallpaper() } }

    override val displayName: String
        get() = context.getString(R.string.pref_plugin_glasslink_wallpaper)

    override val description: String
        get() = context.getString(R.string.pref_plugin_glasslink_wallpaper_desc)

    override val supportedPacketTypes: Array<String> = arrayOf(PACKET_TYPE_WALLPAPER_REQUEST)
    override val outgoingPacketTypes: Array<String> = arrayOf(PACKET_TYPE_WALLPAPER)

    override fun onCreate() {
        val manager = WallpaperManager.getInstance(context)
        val changed = WallpaperManager.OnColorsChangedListener { _, _ ->
            handler.removeCallbacks(sendNow)
            handler.postDelayed(sendNow, 1500) // changes arrive in bursts (home + lock)
        }
        manager.addOnColorsChangedListener(changed, handler)
        listener = changed
        handler.postDelayed(sendNow, 1000)
    }

    override fun onDestroy() {
        handler.removeCallbacks(sendNow)
        listener?.let { WallpaperManager.getInstance(context).removeOnColorsChangedListener(it) }
        listener = null
    }

    override fun onPacketReceived(np: NetworkPacket): Boolean {
        handler.removeCallbacks(sendNow)
        handler.post(sendNow)
        return true
    }

    private fun sendWallpaper() {
        val manager = WallpaperManager.getInstance(context)
        val packet = NetworkPacket(PACKET_TYPE_WALLPAPER)

        // Colours need no permission, so the Mac can at least tint the phone.
        val colors = manager.getWallpaperColors(WallpaperManager.FLAG_SYSTEM)
        colors?.let { packet["colors"] = hexColors(it) }

        try {
            homeScreenBitmap(manager)?.let { bitmap ->
                val scale = TARGET_WIDTH.toFloat() / bitmap.width
                val small = if (scale < 1f) bitmap.scale(TARGET_WIDTH, (bitmap.height * scale).toInt()) else bitmap
                val bytes = ByteArrayOutputStream().use { out ->
                    small.compress(Bitmap.CompressFormat.JPEG, 85, out)
                    out.toByteArray()
                }
                packet["width"] = small.width
                packet["height"] = small.height
                packet.payload = NetworkPacket.Payload(bytes)
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Not allowed to read the wallpaper; sending colours only", e)
        } catch (e: Exception) {
            Log.e(TAG, "Couldn't read the wallpaper", e)
        }
        device.sendPacket(packet)
    }

    /** The home-screen wallpaper. */
    private fun homeScreenBitmap(manager: WallpaperManager): Bitmap? {
        manager.getWallpaperFile(WallpaperManager.FLAG_SYSTEM)?.use { file ->
            BitmapFactory.decodeFileDescriptor(file.fileDescriptor)?.let { return it }
        }
        val drawable: Drawable = manager.drawable ?: return null
        return (drawable as? BitmapDrawable)?.bitmap ?: drawable.toBitmap()
    }

    private fun hexColors(colors: WallpaperColors): List<String> =
        listOfNotNull(colors.primaryColor, colors.secondaryColor, colors.tertiaryColor)
            .map { String.format("#%06X", 0xFFFFFF and it.toArgb()) }

    companion object {
        private const val TAG = "GlassLinkWallpaper"
        private const val TARGET_WIDTH = 540
        const val PACKET_TYPE_WALLPAPER = "glasslink.wallpaper"
        const val PACKET_TYPE_WALLPAPER_REQUEST = "glasslink.wallpaper.request"
    }
}
