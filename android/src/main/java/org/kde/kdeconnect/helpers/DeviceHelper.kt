/*
 * SPDX-FileCopyrightText: 2024 Albert Vaca Cintora <albertvaka@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.helpers

import android.content.Context
import android.content.SharedPreferences
import android.provider.Settings
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.text.SpannableStringBuilder
import androidx.core.content.edit
import androidx.preference.PreferenceManager
import org.kde.kdeconnect.DeviceInfo
import org.kde.kdeconnect.DeviceType
import org.kde.kdeconnect.helpers.security.SslHelper
import org.kde.kdeconnect.plugins.PluginFactory
import java.util.UUID

object DeviceHelper {
    const val PROTOCOL_VERSION = 8

    const val KEY_DEVICE_NAME_PREFERENCE = "device_name_preference"
    private const val KEY_DEVICE_NAME_FETCHED_FROM_THE_INTERNET = "device_name_downloaded_preference"
    private const val KEY_GLASSLINK_NAME_MIGRATED = "glasslink_device_name_migrated"
    private const val KEY_DEVICE_ID_PREFERENCE = "device_id_preference"



    private val NAME_INVALID_CHARACTERS_REGEX = "[\"',;:.!?()\\[\\]<>]".toRegex()
    const val MAX_DEVICE_NAME_LENGTH = 32

    val isTablet: Boolean by lazy {
        val config = Resources.getSystem().configuration
        //This assumes that the values for the screen sizes are consecutive, so XXLARGE > XLARGE > LARGE
        ((config.screenLayout and Configuration.SCREENLAYOUT_SIZE_MASK) >= Configuration.SCREENLAYOUT_SIZE_LARGE)
    }

    val isTv: Boolean by lazy {
        val uiMode = Resources.getSystem().configuration.uiMode
        (uiMode and Configuration.UI_MODE_TYPE_MASK) == Configuration.UI_MODE_TYPE_TELEVISION
    }

    val deviceType: DeviceType by lazy {
        if (isTv) {
            DeviceType.TV
        } else if (isTablet) {
            DeviceType.TABLET
        } else {
            DeviceType.PHONE
        }
    }

    /**
     * GlassLink: a name typed in GlassLink's settings wins; otherwise the name the phone was given
     * in Android's settings (About phone › Device name, e.g. "Astrum"); the model only as a last
     * resort. Unlike upstream, nothing is looked up on the internet.
     */
    fun getDeviceName(context: Context): String {
        val preferences = PreferenceManager.getDefaultSharedPreferences(context)
        dropDownloadedName(preferences)
        preferences.getString(KEY_DEVICE_NAME_PREFERENCE, null)?.takeIf { it.isNotBlank() }?.let { return it }
        return systemDeviceName(context) ?: filterInvalidCharactersFromDeviceNameAndLimitLength(Build.MODEL)
    }

    /** The name given to the phone in Android's settings, if it has one. */
    fun systemDeviceName(context: Context): String? {
        val resolver = context.contentResolver
        val raw = Settings.Global.getString(resolver, "device_name") ?: Settings.Secure.getString(resolver, "bluetooth_name")
        return raw?.let { filterInvalidCharactersFromDeviceNameAndLimitLength(it) }?.takeIf { it.isNotBlank() }
    }

    /** Forget a typed name, so the phone's own name is used again. */
    fun clearCustomDeviceName(context: Context) {
        PreferenceManager.getDefaultSharedPreferences(context).edit { remove(KEY_DEVICE_NAME_PREFERENCE) }
    }

    /** Upstream saved a marketing name downloaded from Google's device list (e.g. "Galaxy S23+").
     *  Drop it once, so the phone's own name shows instead. */
    private fun dropDownloadedName(preferences: SharedPreferences) {
        if (preferences.getBoolean(KEY_GLASSLINK_NAME_MIGRATED, false)) return
        preferences.edit {
            if (preferences.getBoolean(KEY_DEVICE_NAME_FETCHED_FROM_THE_INTERNET, false)) remove(KEY_DEVICE_NAME_PREFERENCE)
            putBoolean(KEY_GLASSLINK_NAME_MIGRATED, true)
        }
    }

    fun setDeviceName(context: Context, name: String) {
        val filteredName = filterInvalidCharactersFromDeviceNameAndLimitLength(name)
        val preferences = PreferenceManager.getDefaultSharedPreferences(context)
        preferences.edit { putString(KEY_DEVICE_NAME_PREFERENCE, filteredName) }
    }

    fun initializeDeviceId(context: Context) {
        val preferences = PreferenceManager.getDefaultSharedPreferences(context)
        val deviceId = preferences.getString(KEY_DEVICE_ID_PREFERENCE, "")!!
        if (DeviceInfo.isValidDeviceId(deviceId)) {
            return // We already have an ID
        }
        val deviceName = UUID.randomUUID().toString().replace("-", "")
        preferences.edit { putString(KEY_DEVICE_ID_PREFERENCE, deviceName) }
    }

    fun getDeviceId(context: Context): String {
        val preferences = PreferenceManager.getDefaultSharedPreferences(context)
        return preferences.getString(KEY_DEVICE_ID_PREFERENCE, null)!!
    }

    fun getDeviceInfo(context: Context): DeviceInfo {
        return DeviceInfo(
            getDeviceId(context),
            SslHelper.certificate,
            getDeviceName(context),
            deviceType,
            PROTOCOL_VERSION,
            PluginFactory.incomingCapabilities,
            PluginFactory.outgoingCapabilities
        )
    }

    fun filterInvalidCharactersFromDeviceNameAndLimitLength(input: String): String = filterInvalidCharactersFromDeviceName(input).trim().take(MAX_DEVICE_NAME_LENGTH)

    fun filterInvalidCharactersFromDeviceName(input: String): String = input.replace(NAME_INVALID_CHARACTERS_REGEX, "")

    /**
     * Filter implementation suitable for [android.text.InputFilter].
     * Returns null if no characters are stripped to accept the replacement as-is
     * and avoid breaking IME composing state/spans (which causes text duplication in Gboard/Samsung Keyboard).
     */
    fun filterDeviceNameInput(source: CharSequence, start: Int, end: Int): CharSequence? {
        val input = source.subSequence(start, end)
        val matches = NAME_INVALID_CHARACTERS_REGEX.findAll(input).toList()
        if (matches.isEmpty()) return null
        return SpannableStringBuilder(input).apply {
            matches.asReversed().forEach { delete(it.range.first, it.range.last + 1) }
        }
    }

}
