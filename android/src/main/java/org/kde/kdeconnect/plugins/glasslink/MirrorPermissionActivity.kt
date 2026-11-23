/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.app.Activity
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.getSystemService

/**
 * Invisible: shows Android's "Start sharing?" prompt (whole screen, or one app on Android 14+)
 * and hands the answer to [MirrorService].
 */
class MirrorPermissionActivity : AppCompatActivity() {
    private val consent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val deviceId = intent.getStringExtra(MirrorService.EXTRA_DEVICE_ID)
        val data = result.data
        if (deviceId != null && result.resultCode == Activity.RESULT_OK && data != null) {
            MirrorService.start(this, deviceId, result.resultCode, data)
        } else if (deviceId != null) {
            MirrorPlugin.reportState(deviceId, "denied")
        }
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            consent.launch(getSystemService<MediaProjectionManager>()!!.createScreenCaptureIntent())
        }
    }
}
