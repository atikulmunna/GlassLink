/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.glasslink

import android.Manifest
import androidx.appcompat.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import org.kde.kdeconnect_tp.R

/**
 * Android 13+ "restricted settings": for apps installed from a downloaded file, Android refuses
 * SMS and call-log permissions, accessibility and notification access until the person opens the
 * app's App info, taps ⋮ and chooses Allow restricted settings (once; it's kept across updates).
 * GlassLink is installed that way, so explain it where those permissions are asked for.
 */
object RestrictedSettings {
    /** Permissions Android holds back from sideloaded apps. */
    private val restricted = setOf(
        Manifest.permission.READ_SMS, Manifest.permission.SEND_SMS, Manifest.permission.RECEIVE_SMS,
        Manifest.permission.RECEIVE_MMS, Manifest.permission.READ_CALL_LOG,
    )

    /** Settings screens that are locked for sideloaded apps. */
    private val restrictedScreens = setOf(
        Settings.ACTION_ACCESSIBILITY_SETTINGS, Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS,
    )

    /** True if this copy came from a file (browser download or this app's own updater). */
    fun mayApply(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val source = runCatching { context.packageManager.getInstallSourceInfo(context.packageName).packageSource }
            .getOrDefault(PackageInstaller.PACKAGE_SOURCE_UNSPECIFIED)
        return source == PackageInstaller.PACKAGE_SOURCE_LOCAL_FILE || source == PackageInstaller.PACKAGE_SOURCE_DOWNLOADED_FILE
    }

    fun involves(permissions: Collection<String>) = permissions.any { it in restricted }
    fun involvesScreen(action: String?) = action in restrictedScreens

    fun openAppInfo(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /** After Android refused a restricted permission: how to allow it. */
    fun explain(context: Context) {
        MaterialAlertDialogBuilder(context)
            .setTitle(R.string.glasslink_restricted_title)
            .setMessage(R.string.glasslink_restricted_text)
            .setPositiveButton(R.string.glasslink_restricted_open) { _, _ -> openAppInfo(context) }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    /** For dialogs that send people to Accessibility or Notification access: the same, up front. */
    fun addHint(dialog: AlertDialog, context: Context, message: CharSequence) {
        dialog.setMessage(message.toString() + "\n\n" + context.getString(R.string.glasslink_restricted_hint))
        dialog.setButton(AlertDialog.BUTTON_NEUTRAL, context.getString(R.string.glasslink_restricted_app_info)) { _, _ ->
            openAppInfo(context)
        }
    }
}
