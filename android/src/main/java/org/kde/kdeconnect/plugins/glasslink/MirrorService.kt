/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import androidx.core.content.getSystemService
import org.kde.kdeconnect.KdeConnect
import org.kde.kdeconnect.NetworkPacket
import org.kde.kdeconnect.backends.lan.LanLinkProvider
import org.kde.kdeconnect.helpers.NotificationHelper
import org.kde.kdeconnect.helpers.security.SslHelper
import org.kde.kdeconnect_tp.R
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.ServerSocket
import java.net.SocketTimeoutException
import kotlin.concurrent.thread
import kotlin.math.max

/**
 * Shares the screen (or, on Android 14+, one app) with a paired GlassLink Mac.
 *
 * The screen is encoded as H.264 by the hardware encoder and streamed over a TLS socket that only
 * the paired Mac can open (the same pinned certificates as file transfers). Each frame is sent as
 * `[length: u32][presentation time µs: i64][flags: u8][Annex-B H.264]`; flag 1 marks codec config
 * (SPS/PPS), flag 2 a key frame. Rotating the phone restarts the encoder at the new size.
 */
class MirrorService : Service() {
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var server: ServerSocket? = null
    private var worker: Thread? = null
    @Volatile private var running = false
    @Volatile private var resized = false
    private var deviceId: String? = null
    private val callbackThread = HandlerThread("GlassLinkMirror").apply { start() }
    private val callbacks = Handler(callbackThread.looper)

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayChanged(displayId: Int) { resized = true }
        override fun onDisplayAdded(displayId: Int) {}
        override fun onDisplayRemoved(displayId: Int) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopMirroring("stopped")
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra(EXTRA_DEVICE_ID)
        val resultCode = intent?.getIntExtra(EXTRA_RESULT_CODE, 0) ?: 0
        val data: Intent? = intent?.let { IntentCompat.getParcelableExtra(it, EXTRA_RESULT_DATA, Intent::class.java) }
        if (id == null || data == null || running) return START_NOT_STICKY
        deviceId = id

        // Must be in the foreground (with the mediaProjection type) before using the projection.
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION else 0
        ServiceCompat.startForeground(this, NOTIFICATION_ID, buildNotification(id), type)

        val manager = getSystemService<MediaProjectionManager>()!!
        val projection = manager.getMediaProjection(resultCode, data)
        if (projection == null) {
            stopMirroring("failed")
            return START_NOT_STICKY
        }
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() { stopMirroring("stopped") }
        }, callbacks)
        this.projection = projection
        getSystemService<DisplayManager>()?.registerDisplayListener(displayListener, callbacks)
        running = true
        isRunning = true
        worker = thread(name = "GlassLinkMirrorStream") { stream(id, projection) }
        return START_NOT_STICKY
    }

    private fun stream(deviceId: String, projection: MediaProjection) {
        try {
            val server = LanLinkProvider.openServerSocketOnFreePort(LanLinkProvider.PAYLOAD_TRANSFER_MIN_PORT)
            server.soTimeout = 20_000
            this.server = server
            val size = captureSize()
            send(deviceId, NetworkPacket(MirrorPlugin.PACKET_TYPE_MIRROR).apply {
                this["state"] = "ready"
                this["port"] = server.localPort
                this["width"] = size.first
                this["height"] = size.second
            })
            val socket = try { server.accept() } catch (e: SocketTimeoutException) {
                Log.w(TAG, "The Mac didn't connect")
                stopMirroring("failed")
                return
            }
            socket.tcpNoDelay = true
            val ssl = SslHelper.convertToSslSocket(this, socket, deviceId, true, false)
            ssl.startHandshake()
            val out = DataOutputStream(BufferedOutputStream(ssl.outputStream, 64 * 1024))

            var first = true
            while (running) {
                resized = false
                val (width, height) = captureSize()
                val codec = createEncoder(width, height)
                val surface = codec.createInputSurface()
                codec.start()
                if (first) {
                    display = projection.createVirtualDisplay("GlassLink", width, height, densityDpi(),
                        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, callbacks)
                    first = false
                } else {
                    display?.resize(width, height, densityDpi())
                    display?.surface = surface
                }
                pump(codec, out)
                codec.stop()
                codec.release()
                surface.release()
            }
            ssl.close()
        } catch (e: IOException) {
            Log.i(TAG, "Mirroring ended: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Mirroring failed", e)
        } finally {
            stopMirroring("stopped")
        }
    }

    /** Moves encoded frames to the Mac until mirroring stops or the screen changes size. */
    private fun pump(codec: MediaCodec, out: DataOutputStream) {
        val info = MediaCodec.BufferInfo()
        var chunk = ByteArray(256 * 1024)
        while (running && !resized) {
            val index = codec.dequeueOutputBuffer(info, 20_000)
            if (index < 0) continue
            val buffer = codec.getOutputBuffer(index)
            if (buffer != null && info.size > 0) {
                if (chunk.size < info.size) chunk = ByteArray(info.size)
                buffer.position(info.offset)
                buffer.get(chunk, 0, info.size)
                var flags = 0
                if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) flags = flags or 1
                if (info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0) flags = flags or 2
                out.writeInt(info.size)
                out.writeLong(info.presentationTimeUs)
                out.writeByte(flags)
                out.write(chunk, 0, info.size)
                out.flush()
            }
            codec.releaseOutputBuffer(index, false)
        }
    }

    private fun createEncoder(width: Int, height: Int): MediaCodec {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, 8_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, 60)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            // Keep sending frames when the screen is still, so a newly attached view fills in.
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000)
            setInteger(MediaFormat.KEY_PRIORITY, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
        }
        return MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).apply {
            configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
    }

    /** The real screen size, scaled so the long side is at most 1600 px (even numbers for H.264). */
    private fun captureSize(): Pair<Int, Int> {
        val metrics = realMetrics()
        val scale = minOf(1.0, MAX_LONG_SIDE.toDouble() / max(metrics.widthPixels, metrics.heightPixels))
        fun even(v: Double) = (v.toInt() / 2) * 2
        return even(metrics.widthPixels * scale) to even(metrics.heightPixels * scale)
    }

    private fun densityDpi(): Int = realMetrics().densityDpi

    @Suppress("DEPRECATION")
    private fun realMetrics(): DisplayMetrics = DisplayMetrics().also {
        getSystemService<WindowManager>()!!.defaultDisplay.getRealMetrics(it)
    }

    private fun buildNotification(deviceId: String) = NotificationCompat.Builder(this, NotificationHelper.Channels.DEFAULT)
        .setSmallIcon(R.drawable.ic_notification)
        .setContentTitle(getString(R.string.glasslink_mirror_notification_title, KdeConnect.getInstance().getDevice(deviceId)?.name ?: "Mac"))
        .setContentText(getString(R.string.glasslink_mirror_notification_text))
        .setOngoing(true)
        .addAction(0, getString(R.string.glasslink_mirror_stop),
            PendingIntent.getService(this, 0, Intent(this, MirrorService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE))
        .build()

    @Synchronized
    private fun stopMirroring(state: String) {
        isRunning = false
        if (!running && projection == null) {
            stopSelf()
            return
        }
        running = false
        getSystemService<DisplayManager>()?.unregisterDisplayListener(displayListener)
        runCatching { server?.close() }
        runCatching { display?.release() }
        runCatching { projection?.stop() }
        display = null
        projection = null
        deviceId?.let { send(it, NetworkPacket(MirrorPlugin.PACKET_TYPE_MIRROR).apply { this["state"] = state }) }
        deviceId = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopMirroring("stopped")
        callbackThread.quitSafely()
        super.onDestroy()
    }

    private fun send(deviceId: String, packet: NetworkPacket) {
        KdeConnect.getInstance().getDevice(deviceId)?.sendPacket(packet)
    }

    companion object {
        private const val TAG = "GlassLinkMirror"
        private const val NOTIFICATION_ID = 0x6C6D
        private const val MAX_LONG_SIDE = 1600
        private const val ACTION_STOP = "org.kde.kdeconnect.glasslink.MIRROR_STOP"
        const val EXTRA_DEVICE_ID = "deviceId"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"

        @Volatile var isRunning = false
            private set

        fun start(context: Context, deviceId: String, resultCode: Int, data: Intent) {
            val intent = Intent(context, MirrorService::class.java)
                .putExtra(EXTRA_DEVICE_ID, deviceId)
                .putExtra(EXTRA_RESULT_CODE, resultCode)
                .putExtra(EXTRA_RESULT_DATA, data)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.startService(Intent(context, MirrorService::class.java).setAction(ACTION_STOP))
        }
    }
}
