/*
 * SPDX-FileCopyrightText: 2024 Albert Vaca Cintora <albertvaka@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

package org.kde.kdeconnect.ui.compose

import android.content.Context
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

@Composable
fun KdeTheme(context : Context, content: @Composable () -> Unit) {
    // GlassLink: dark mode is the midnight palette shared with the Mac app; light mode follows
    // Android's Material colours (wallpaper-based Material You on Android 12+, the Material 3
    // baseline before that).
    val colorScheme = when {
        isSystemInDarkTheme() -> GlassLinkPalette.dark
        android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S -> androidx.compose.material3.dynamicLightColorScheme(context)
        else -> androidx.compose.material3.lightColorScheme()
    }
    MaterialTheme(
        colorScheme = colorScheme,
        shapes = GlassLinkPalette.shapes,
        content = content,
    )
}
