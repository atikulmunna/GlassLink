/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.glasslink

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.core.content.edit
import androidx.lifecycle.lifecycleScope
import androidx.preference.PreferenceManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.progressindicator.LinearProgressIndicator
import com.google.android.material.snackbar.Snackbar
import android.view.View
import java.util.WeakHashMap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.kde.kdeconnect_tp.BuildConfig
import org.kde.kdeconnect_tp.R
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Checks GitHub for a newer GlassLink, downloads the APK, checks it against the release's
 * SHA256SUMS, and opens Android's installer. Android itself only installs it over this app if it's
 * signed with the same GlassLink release key, so a tampered APK can't replace the app. The only
 * request is to GitHub's public releases API, with no identifying data.
 */
object Updater {
    /** Version and notes of the newest release, served from its files: not limited like GitHub's API. */
    private const val MANIFEST = "https://github.com/atikulmunna/GlassLink/releases/latest/download/latest.json"
    /** Only for releases from before latest.json (60 anonymous requests an hour per network). */
    private const val LATEST = "https://api.github.com/repos/atikulmunna/GlassLink/releases/latest"
    private fun download(version: String, file: String) =
        "https://github.com/atikulmunna/GlassLink/releases/download/v$version/$file"

    /** GitHub refused because too many requests came from this network. */
    class RateLimited : Exception("GitHub rate limit")
    const val KEY_AUTOMATIC = "glasslink_check_for_updates"
    private const val KEY_LAST_CHECK = "glasslink_last_update_check"
    private const val KEY_PENDING = "glasslink_pending_update"
    private const val KEY_ANNOUNCED = "glasslink_announced_update"
    private const val UPDATE_NOTIFICATION_ID = 0x6C72
    private var backgroundChecks: kotlinx.coroutines.Job? = null
    private val reminders = WeakHashMap<Activity, Snackbar>()
    private const val DAY_MS = 24 * 60 * 60 * 1000L

    data class Release(val version: String, val notes: String, val apk: String, val apkName: String, val sums: String)

    val currentVersion: String get() = BuildConfig.VERSION_NAME

    fun automaticChecks(context: Context): Boolean =
        PreferenceManager.getDefaultSharedPreferences(context).getBoolean(KEY_AUTOMATIC, true)

    /** The latest release, or null if this is already the newest. Throws if GitHub can't be reached. */
    suspend fun newerRelease(): Release? = withContext(Dispatchers.IO) {
        val (version, notes) = try {
            val manifest = JSONObject(String(fetch(MANIFEST)))
            manifest.getString("version") to manifest.optString("notes")
        } catch (e: RateLimited) {
            throw e
        } catch (e: Exception) {
            // Releases before latest.json: ask the API instead.
            val json = JSONObject(String(fetch(LATEST, json = true)))
            json.getString("tag_name").removePrefix("v") to json.optString("body")
        }
        if (!isVersion(version, newerThan = currentVersion)) return@withContext null
        val apkName = "GlassLink-$version.apk"
        Release(version, notes, download(version, apkName), apkName, download(version, "SHA256SUMS"))
    }

    /** "0.10.0" is newer than "0.9.3". */
    fun isVersion(a: String, newerThan: String): Boolean {
        fun parts(v: String) = v.split(Regex("[^0-9]+")).filter { it.isNotEmpty() }.map { it.toInt() }
        val (x, y) = parts(a) to parts(newerThan)
        for (i in 0 until maxOf(x.size, y.size)) {
            val (p, q) = x.getOrElse(i) { 0 } to y.getOrElse(i) { 0 }
            if (p != q) return p > q
        }
        return false
    }

    /** When the app opens: at most once a day, quietly, and only says something if there's an update. */
    fun checkAutomatically(activity: AppCompatActivity) {
        val prefs = PreferenceManager.getDefaultSharedPreferences(activity)
        if (!automaticChecks(activity)) return
        if (System.currentTimeMillis() - prefs.getLong(KEY_LAST_CHECK, 0) < DAY_MS) return
        activity.lifecycleScope.launch {
            val release = runCatching { newerRelease() }.getOrNull()
            prefs.edit { putLong(KEY_LAST_CHECK, System.currentTimeMillis()) }
            if (release != null) {
                remember(activity, release)
                if (!activity.isFinishing) showReminder(activity)
            }
        }
    }

    /**
     * From the connection service, which runs all the time: checks at most once a day even if the
     * app is never opened, and announces each new version once with a notification.
     */
    fun startBackgroundChecks(context: Context) {
        if (backgroundChecks?.isActive == true) return
        val app = context.applicationContext
        backgroundChecks = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + Dispatchers.IO).launch {
            kotlinx.coroutines.delay(30_000) // let the connection come up first
            while (true) {
                runCatching { checkInBackground(app) }
                kotlinx.coroutines.delay(6 * 60 * 60 * 1000L) // looks every 6 hours; asks GitHub at most daily
            }
        }
    }

    fun stopBackgroundChecks() {
        backgroundChecks?.cancel()
        backgroundChecks = null
    }

    private suspend fun checkInBackground(context: Context) {
        if (!automaticChecks(context)) return
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        if (System.currentTimeMillis() - prefs.getLong(KEY_LAST_CHECK, 0) >= DAY_MS) {
            val release = runCatching { newerRelease() }.getOrNull()
            prefs.edit { putLong(KEY_LAST_CHECK, System.currentTimeMillis()) }
            if (release != null) remember(context, release)
        }
        pending(context)?.let { announce(context, it) }
    }

    /** "GlassLink 0.2.9 is available": once per version; tapping opens the app (and its Update bar). */
    private fun announce(context: Context, release: Release) {
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        if (prefs.getString(KEY_ANNOUNCED, null) == release.version) return
        val open = android.app.PendingIntent.getActivity(
            context, 4,
            Intent(context, org.kde.kdeconnect.ui.MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = androidx.core.app.NotificationCompat.Builder(context, org.kde.kdeconnect.helpers.NotificationHelper.Channels.DEFAULT)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.glasslink_update_available, release.version))
            .setContentText(context.getString(R.string.glasslink_update_notification_text, currentVersion))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { androidx.core.app.NotificationManagerCompat.from(context).notify(UPDATE_NOTIFICATION_ID, notification) }
        prefs.edit { putString(KEY_ANNOUNCED, release.version) }
    }

    /** "Check for updates" in Settings: always answers. */
    fun checkNow(activity: AppCompatActivity, onResult: (String) -> Unit = {}) {
        activity.lifecycleScope.launch {
            val result = runCatching { newerRelease() }
            PreferenceManager.getDefaultSharedPreferences(activity).edit { putLong(KEY_LAST_CHECK, System.currentTimeMillis()) }
            val release = result.getOrNull()
            when {
                result.exceptionOrNull() is RateLimited -> onResult(activity.getString(R.string.glasslink_update_rate_limited))
                result.isFailure -> onResult(activity.getString(R.string.glasslink_update_failed_check))
                release == null -> onResult(activity.getString(R.string.glasslink_update_none, currentVersion))
                else -> {
                    onResult(activity.getString(R.string.glasslink_update_available_short, release.version))
                    remember(activity, release)
                    showReminder(activity)
                    offer(activity, release)
                }
            }
        }
    }

    /** Keeps the found release, so the reminder survives restarts until the app is updated. */
    private fun remember(context: Context, release: Release) {
        val json = JSONObject().put("version", release.version).put("notes", release.notes)
            .put("apk", release.apk).put("apkName", release.apkName).put("sums", release.sums)
        PreferenceManager.getDefaultSharedPreferences(context).edit { putString(KEY_PENDING, json.toString()) }
    }

    /** The remembered release, while it's still newer than this app. */
    private fun pending(context: Context): Release? {
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        val json = prefs.getString(KEY_PENDING, null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
        val release = Release(json.optString("version"), json.optString("notes"), json.optString("apk"),
            json.optString("apkName"), json.optString("sums"))
        if (!isVersion(release.version, newerThan = currentVersion)) {
            prefs.edit { remove(KEY_PENDING) } // updated since
            return null
        }
        return release
    }

    /** A bar at the bottom of the app: "GlassLink 0.2.4 is available · Update", until it's installed. */
    fun showReminder(activity: AppCompatActivity) {
        val release = pending(activity) ?: return
        if (reminders[activity]?.isShownOrQueued == true) return
        val root = activity.findViewById<View>(android.R.id.content) ?: return
        val bar = Snackbar.make(root, activity.getString(R.string.glasslink_update_available, release.version), Snackbar.LENGTH_INDEFINITE)
            .setAction(R.string.glasslink_update_install) { install(activity, release) }
        reminders[activity] = bar
        bar.show()
    }

    private fun offer(activity: AppCompatActivity, release: Release) {
        MaterialAlertDialogBuilder(activity)
            .setTitle(activity.getString(R.string.glasslink_update_available, release.version))
            .setMessage(activity.getString(R.string.glasslink_update_you_have, currentVersion) + "\n\n" + summary(release.notes))
            .setPositiveButton(R.string.glasslink_update_install) { _, _ -> install(activity, release) }
            .setNegativeButton(R.string.glasslink_update_later, null)
            .show()
    }

    private fun install(activity: AppCompatActivity, release: Release) {
        // Android 8+ asks per app; before that it's the global "Unknown sources" setting, and the
        // installer explains it itself.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O && !activity.packageManager.canRequestPackageInstalls()) {
            Toast.makeText(activity, R.string.glasslink_update_allow_installs, Toast.LENGTH_LONG).show()
            activity.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}"))
            )
            return
        }
        val bar = LinearProgressIndicator(activity).apply { max = 100; isIndeterminate = true; setPadding(64, 32, 64, 0) }
        val dialog: AlertDialog = MaterialAlertDialogBuilder(activity)
            .setTitle(activity.getString(R.string.glasslink_update_downloading, release.version))
            .setView(bar)
            .setCancelable(false)
            .show()
        activity.lifecycleScope.launch {
            val apk = runCatching { download(activity, release) { percent -> bar.isIndeterminate = false; bar.progress = percent } }
            dialog.dismiss()
            apk.onSuccess { openInstaller(activity, it) }.onFailure {
                Toast.makeText(activity, R.string.glasslink_update_failed_download, Toast.LENGTH_LONG).show()
            }
            reminders.remove(activity)
            showReminder(activity)
        }
    }

    /** Downloads the APK into the cache and checks it against SHA256SUMS. */
    private suspend fun download(context: Context, release: Release, progress: (Int) -> Unit): File {
        val folder = File(context.cacheDir, "updates").apply { deleteRecursively(); mkdirs() }
        val file = File(folder, release.apkName)
        val expected = withContext(Dispatchers.IO) {
            String(fetch(release.sums)).lines().map { it.trim().split(Regex("\\s+")) }
                .firstOrNull { it.size == 2 && it[1] == release.apkName }?.get(0)?.lowercase()
        } ?: error("No checksum for ${release.apkName}")
        val digest = MessageDigest.getInstance("SHA-256")
        withContext(Dispatchers.IO) {
            val connection = open(release.apk)
            val total = connection.contentLengthLong
            connection.inputStream.use { input ->
                file.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var done = 0L
                    var shown = -1
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                        digest.update(buffer, 0, n)
                        done += n
                        val percent = if (total > 0) (done * 100 / total).toInt() else -1
                        if (percent >= 0 && percent != shown) {
                            shown = percent
                            withContext(Dispatchers.Main) { progress(percent) }
                        }
                    }
                }
            }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (actual != expected) {
            file.delete()
            error("Checksum mismatch")
        }
        return file
    }

    private fun openInstaller(activity: Activity, apk: File) {
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", apk)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    private fun open(url: String, json: Boolean = false): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "GlassLink-Updater")
            if (json) setRequestProperty("Accept", "application/vnd.github+json")
            val code = responseCode
            if (code == HttpURLConnection.HTTP_FORBIDDEN || code == 429) throw RateLimited()
            if (code != HttpURLConnection.HTTP_OK) error("HTTP $code")
        }

    private fun fetch(url: String, json: Boolean = false): ByteArray = open(url, json).inputStream.use { it.readBytes() }

    /** Release notes as plain text, short enough for a dialog. */
    private fun summary(notes: String): String {
        val plain = notes.replace("**", "").replace("`", "").lines()
            .filterNot { it.startsWith("#") || it.startsWith("Downloads:") }
            .joinToString("\n").trim()
        return if (plain.length > 700) plain.take(700) + "…" else plain
    }
}
