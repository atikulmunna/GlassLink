/*
 * SPDX-FileCopyrightText: 2018 Philip Cohn-Cort <cliabhach@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.ui

import android.app.Application
import android.os.Build
import android.util.Log
import androidx.appcompat.app.AppCompatDelegate
import androidx.preference.PreferenceManager
import com.google.android.material.color.DynamicColors
import com.google.android.material.color.DynamicColorsOptions

/**
 * Utilities for working with android [Themes][android.content.res.Resources.Theme].
 */
object ThemeUtil {
    @Suppress("MemberVisibilityCanBePrivate")
    const val LIGHT_MODE: String = "light"
    @Suppress("MemberVisibilityCanBePrivate")
    const val DARK_MODE: String = "dark"
    const val DEFAULT_MODE: String = "default"

    fun applyTheme(themePref: String) {
        when (themePref) {
            LIGHT_MODE -> {
                AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_NO)
            }

            DARK_MODE -> {
                AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_YES)
            }

            else -> {
                if (themePref == DEFAULT_MODE) {
                    Log.d("ThemeUtil", "Theme preference not set, using system default.")
                } else {
                    Log.w("ThemeUtil", "Unknown theme preference: $themePref, falling back to system default.")
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
                } else {
                    AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_AUTO_BATTERY)
                }
            }
        }
    }

    /**
     * Called when an activity is created for the first time to reliably load the correct theme.
     */
    fun setUserPreferredTheme(application: Application) {
        val appTheme = PreferenceManager
            .getDefaultSharedPreferences(application)
            .getString("theme_pref", DEFAULT_MODE)!!
        applyTheme(appTheme)
        // GlassLink: dark mode keeps the midnight palette shared with the Mac app; light mode
        // follows Android's Material colours, from the wallpaper (Material You) where available.
        DynamicColors.applyToActivitiesIfAvailable(
            application,
            DynamicColorsOptions.Builder().setPrecondition { activity, _ -> !isNight(activity) && hasColorfulDynamicColors(activity) }.build(),
        )
    }

    /**
     * Whether the phone's Material You palette has real colour. With a black-and-white wallpaper,
     * or Samsung's Color palette switched off, Android hands apps near-grey "dynamic" colours; then
     * GlassLink uses the Material 3 baseline (light) instead, so light mode still looks like Material.
     */
    fun hasColorfulDynamicColors(context: android.content.Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        val accent = context.getColor(android.R.color.system_accent1_500)
        val hsv = FloatArray(3)
        android.graphics.Color.colorToHSV(accent, hsv)
        return hsv[1] > 0.2f
    }

    private fun isNight(context: android.content.Context): Boolean =
        context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
}
