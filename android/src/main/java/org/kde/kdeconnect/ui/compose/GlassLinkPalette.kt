/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.ui.compose

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * GlassLink's look: midnight black and white. Pure black, white type and icons, greyscale
 * surfaces with hairline borders, no tints. The light theme is the same, inverted.
 */
object GlassLinkPalette {
    val dark = darkColorScheme(
        primary = Color.White,
        onPrimary = Color.Black,
        primaryContainer = Color(0xFF1F1F1F),
        onPrimaryContainer = Color.White,
        secondary = Color(0xFFE6E6E6),
        onSecondary = Color.Black,
        secondaryContainer = Color(0xFF262626),
        onSecondaryContainer = Color.White,
        tertiary = Color(0xFFBDBDBD),
        onTertiary = Color.Black,
        tertiaryContainer = Color(0xFF262626),
        onTertiaryContainer = Color.White,
        background = Color.Black,
        onBackground = Color.White,
        surface = Color.Black,
        onSurface = Color(0xFFF5F5F5),
        surfaceVariant = Color(0xFF1A1A1A),
        onSurfaceVariant = Color(0xFF9A9A9A),
        surfaceContainerLowest = Color.Black,
        surfaceContainerLow = Color(0xFF0A0A0A),
        surfaceContainer = Color(0xFF101010),
        surfaceContainerHigh = Color(0xFF161616),
        surfaceContainerHighest = Color(0xFF1E1E1E),
        outline = Color(0xFF3A3A3A),
        outlineVariant = Color(0xFF232323),
        inverseSurface = Color.White,
        inverseOnSurface = Color.Black,
    )

    /** Dark mode: midnight surfaces, with [accent]'s colour roles for icons, switches and highlights. */
    fun darkWithAccent(accent: androidx.compose.material3.ColorScheme) = dark.copy(
        primary = accent.primary,
        onPrimary = accent.onPrimary,
        primaryContainer = accent.primaryContainer,
        onPrimaryContainer = accent.onPrimaryContainer,
        secondary = accent.secondary,
        onSecondary = accent.onSecondary,
        secondaryContainer = accent.secondaryContainer,
        onSecondaryContainer = accent.onSecondaryContainer,
        tertiary = accent.tertiary,
        onTertiary = accent.onTertiary,
    )

    val light = lightColorScheme(
        primary = Color.Black,
        onPrimary = Color.White,
        primaryContainer = Color(0xFFEDEDED),
        onPrimaryContainer = Color.Black,
        secondary = Color(0xFF1A1A1A),
        onSecondary = Color.White,
        secondaryContainer = Color(0xFFE8E8E8),
        onSecondaryContainer = Color.Black,
        tertiary = Color(0xFF424242),
        onTertiary = Color.White,
        tertiaryContainer = Color(0xFFE8E8E8),
        onTertiaryContainer = Color.Black,
        background = Color.White,
        onBackground = Color.Black,
        surface = Color.White,
        onSurface = Color(0xFF0A0A0A),
        surfaceVariant = Color(0xFFF2F2F2),
        onSurfaceVariant = Color(0xFF666666),
        surfaceContainerLowest = Color.White,
        surfaceContainerLow = Color(0xFFFAFAFA),
        surfaceContainer = Color(0xFFF5F5F5),
        surfaceContainerHigh = Color(0xFFEFEFEF),
        surfaceContainerHighest = Color(0xFFE8E8E8),
        outline = Color(0xFFBDBDBD),
        outlineVariant = Color(0xFFE3E3E3),
        inverseSurface = Color.Black,
        inverseOnSurface = Color.White,
    )

    val shapes = Shapes(
        extraSmall = RoundedCornerShape(8.dp),
        small = RoundedCornerShape(12.dp),
        medium = RoundedCornerShape(18.dp),
        large = RoundedCornerShape(24.dp),
        extraLarge = RoundedCornerShape(30.dp),
    )
}
