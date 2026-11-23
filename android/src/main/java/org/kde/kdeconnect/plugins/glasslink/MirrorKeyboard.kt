/*
 * SPDX-FileCopyrightText: 2026 GlassLink contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */
package org.kde.kdeconnect.plugins.glasslink

import android.accessibilityservice.AccessibilityService
import android.os.SystemClock
import android.text.InputType
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import androidx.annotation.RequiresApi

/**
 * Typing from the Mac's keyboard into the focused text field, through the accessibility service's
 * input connection: the same channel the on-screen keyboard uses, so text, Backspace, arrows,
 * Ctrl shortcuts and Enter (send, search, new line) behave as they do on a real keyboard.
 * Needs Android 14+, where the service is allowed to act as an input method.
 */
@RequiresApi(34)
internal object MirrorKeyboard {
    fun type(service: AccessibilityService, text: String) {
        if (text.isEmpty()) return
        service.inputMethod?.currentInputConnection?.commitText(text, 1, null)
    }

    fun key(service: AccessibilityService, name: String, shift: Boolean, ctrl: Boolean, alt: Boolean) {
        val inputMethod = service.inputMethod ?: return
        val connection = inputMethod.currentInputConnection ?: return

        if (name == "enter") {
            val info = inputMethod.currentInputEditorInfo
            val options = info?.imeOptions ?: 0
            val action = options and EditorInfo.IME_MASK_ACTION
            val hasAction = action != EditorInfo.IME_ACTION_NONE && action != EditorInfo.IME_ACTION_UNSPECIFIED
            val multiLine = info != null &&
                info.inputType and InputType.TYPE_MASK_CLASS == InputType.TYPE_CLASS_TEXT &&
                info.inputType and InputType.TYPE_TEXT_FLAG_MULTI_LINE != 0
            val enterIsAction = hasAction && !multiLine && options and EditorInfo.IME_FLAG_NO_ENTER_ACTION == 0
            when {
                ctrl && hasAction -> { connection.performEditorAction(action); return } // ⌘↩: send
                shift && multiLine -> { connection.commitText("\n", 1, null); return }
                !shift && enterIsAction -> { connection.performEditorAction(action); return }
            }
        }

        val code = keyCode(name) ?: return
        var meta = 0
        if (shift) meta = meta or KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON
        if (ctrl && name != "enter") meta = meta or KeyEvent.META_CTRL_ON or KeyEvent.META_CTRL_LEFT_ON
        if (alt) meta = meta or KeyEvent.META_ALT_ON or KeyEvent.META_ALT_LEFT_ON
        val now = SystemClock.uptimeMillis()
        val flags = KeyEvent.FLAG_SOFT_KEYBOARD or KeyEvent.FLAG_KEEP_TOUCH_MODE
        connection.sendKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_DOWN, code, 0, meta, KeyCharacterMap.VIRTUAL_KEYBOARD, 0, flags))
        connection.sendKeyEvent(KeyEvent(now, now, KeyEvent.ACTION_UP, code, 0, meta, KeyCharacterMap.VIRTUAL_KEYBOARD, 0, flags))
    }

    private fun keyCode(name: String): Int? = when (name) {
        "enter" -> KeyEvent.KEYCODE_ENTER
        "tab" -> KeyEvent.KEYCODE_TAB
        "backspace" -> KeyEvent.KEYCODE_DEL
        "delete" -> KeyEvent.KEYCODE_FORWARD_DEL
        "left" -> KeyEvent.KEYCODE_DPAD_LEFT
        "right" -> KeyEvent.KEYCODE_DPAD_RIGHT
        "up" -> KeyEvent.KEYCODE_DPAD_UP
        "down" -> KeyEvent.KEYCODE_DPAD_DOWN
        "home" -> KeyEvent.KEYCODE_MOVE_HOME
        "end" -> KeyEvent.KEYCODE_MOVE_END
        "pageup" -> KeyEvent.KEYCODE_PAGE_UP
        "pagedown" -> KeyEvent.KEYCODE_PAGE_DOWN
        else -> name.singleOrNull()?.takeIf { it in 'a'..'z' }?.let { KeyEvent.KEYCODE_A + (it - 'a') }
    }
}
