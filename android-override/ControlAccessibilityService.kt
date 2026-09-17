package com.elthondev.openbridge

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Input backend that needs no Shizuku and no root.
 *
 * Several devices (notably MediaTek ROMs) cannot start Shizuku user services
 * and third-party ROMs may also block shell injection, so tap / swipe /
 * long-press / double-tap / Home / Back / Recents / text are injected through
 * an AccessibilityService instead. Shizuku is still preferred when its shell
 * binder is actually connected; this service is the fallback that works
 * everywhere the user enables it.
 */
class ControlAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "OpenBridgeControl"

        @Volatile private var current: ControlAccessibilityService? = null

        /** True when the user has enabled OpenBridge in Accessibility settings. */
        fun connected(): Boolean = current != null

        fun tap(x: Float, y: Float): Boolean = current?.tap(x, y) ?: false

        fun longPress(x: Float, y: Float, durationMs: Long): Boolean =
            current?.longPress(x, y, durationMs) ?: false

        fun doubleTap(x: Float, y: Float): Boolean = current?.doubleTap(x, y) ?: false

        fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean =
            current?.swipe(x1, y1, x2, y2, durationMs) ?: false

        fun global(action: Int): Boolean = current?.performGlobalAction(action) ?: false

        fun setText(text: String): Boolean = current?.setText(text) ?: false

        /** Current focused editable text (used to append / clear fields). */
        fun focusedText(): String? = current?.focusedText()

        fun clearText(): Boolean = current?.setText("") ?: false

        // Global actions actually available across supported Android versions.
        const val GLOBAL_BACK = AccessibilityService.GLOBAL_ACTION_BACK
        const val GLOBAL_HOME = AccessibilityService.GLOBAL_ACTION_HOME
        const val GLOBAL_RECENTS = AccessibilityService.GLOBAL_ACTION_RECENTS
        const val GLOBAL_NOTIFICATIONS = AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
        const val GLOBAL_QUICK_SETTINGS = AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS
        const val GLOBAL_POWER_DIALOG = AccessibilityService.GLOBAL_ACTION_POWER_DIALOG

        /** Map a symbolic global action name to its AccessibilityService constant. */
        fun globalFor(name: String): Int? = when (name) {
            "back" -> GLOBAL_BACK
            "home" -> GLOBAL_HOME
            "recents", "recent" -> GLOBAL_RECENTS
            "notifications", "notification_shade", "statusbar" -> GLOBAL_NOTIFICATIONS
            "quickSettings", "quick_settings", "quick", "quicksettings" -> GLOBAL_QUICK_SETTINGS
            "powerDialog", "power_dialog", "power_dialog_menu", "power" -> GLOBAL_POWER_DIALOG
            "lock", "lock_screen" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN else null
            "split", "split_screen" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) AccessibilityService.GLOBAL_ACTION_TOGGLE_SPLIT_SCREEN else null
            "screenshot" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) AccessibilityService.GLOBAL_ACTION_TAKE_SCREENSHOT else null
            else -> null
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        current = this
        Log.i(TAG, "accessibility service connected")
    }

    override fun onDestroy() {
        if (current === this) current = null
        Log.i(TAG, "accessibility service destroyed")
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    private fun canGesture(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N

    private fun tap(x: Float, y: Float): Boolean {
        if (!canGesture()) return false
        val path = Path().apply { moveTo(x, y) }
        return gesture(path, 50L)
    }

    private fun longPress(x: Float, y: Float, durationMs: Long): Boolean {
        if (!canGesture()) return false
        val path = Path().apply { moveTo(x, y) }
        return gesture(path, durationMs.coerceIn(400L, 3000L))
    }

    /**
     * Two discrete taps dispatched as a single gesture, which the framework
     * recognises as a double-tap (unlike two independent gestures, which the
     * system debounces apart).
     */
    private fun doubleTap(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val path = Path().apply { moveTo(x, y) }
            val first = GestureDescription.StrokeDescription(path, 0, 40)
            val second = GestureDescription.StrokeDescription(path, 120, 40)
            dispatchGesture(
                GestureDescription.Builder()
                    .addStroke(first)
                    .addStroke(second)
                    .build(),
                null,
                null
            )
        } catch (e: Throwable) {
            Log.e(TAG, "doubleTap failed: $e")
            false
        }
    }

    private fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean {
        if (!canGesture()) return false
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        return gesture(path, durationMs.coerceIn(50L, 5000L))
    }

    private fun gesture(path: Path, durationMs: Long): Boolean {
        return try {
            dispatchGesture(
                GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
                    .build(),
                null,
                null
            )
        } catch (e: Throwable) {
            Log.e(TAG, "dispatchGesture failed: $e")
            false
        }
    }

    private fun focusedNode(): AccessibilityNodeInfo? {
        return try {
            findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?: rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        } catch (_: Throwable) {
            null
        }
    }

    private fun setText(text: String): Boolean {
        return try {
            val focused = focusedNode() ?: return false
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        } catch (e: Throwable) {
            Log.e(TAG, "setText failed: $e")
            false
        }
    }

    private fun focusedText(): String? {
        return try {
            focusedNode()?.text?.toString()
        } catch (_: Throwable) {
            null
        }
    }
}
