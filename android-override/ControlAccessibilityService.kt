package com.elthondev.openbridge

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
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
 * Home / Back / Recents / text are injected through an AccessibilityService
 * instead. Shizuku is still preferred when its shell binder is actually
 * connected; this service is the fallback that works everywhere the user
 * enables it.
 */
class ControlAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "OpenBridgeControl"

        @Volatile private var current: ControlAccessibilityService? = null

        /** True when the user has enabled OpenBridge in Accessibility settings. */
        fun connected(): Boolean = current != null

        fun tap(x: Float, y: Float): Boolean = current?.tap(x, y) ?: false

        fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean =
            current?.swipe(x1, y1, x2, y2, durationMs) ?: false

        fun global(action: Int): Boolean = current?.performGlobalAction(action) ?: false

        fun setText(text: String): Boolean = current?.setText(text) ?: false

        const val GLOBAL_BACK = AccessibilityService.GLOBAL_ACTION_BACK
        const val GLOBAL_HOME = AccessibilityService.GLOBAL_ACTION_HOME
        const val GLOBAL_RECENTS = AccessibilityService.GLOBAL_ACTION_RECENTS
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

    private fun tap(x: Float, y: Float): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply { moveTo(x, y) }
        return gesture(path, 50L)
    }

    private fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val path = Path().apply {
            moveTo(x1, y1)
            lineTo(x2, y2)
        }
        return gesture(path, durationMs.coerceIn(50L, 3000L))
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

    private fun setText(text: String): Boolean {
        return try {
            val focused = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?: rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                ?: return false
            val args = Bundle().apply {
                putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
            }
            focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
        } catch (e: Throwable) {
            Log.e(TAG, "setText failed: $e")
            false
        }
    }
}