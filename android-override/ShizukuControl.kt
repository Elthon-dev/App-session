package com.elthondev.openbridge

import android.content.pm.PackageManager
import rikka.shizuku.Shizuku

/**
 * Runs shell-level input commands (tap / swipe / keyevent / text) with shell
 * privileges through Shizuku. When Shizuku is running and OpenBridge has been
 * authorized inside the Shizuku app, commands execute via Shizuku.newProcess().
 * Otherwise we fall back to a plain Runtime.exec() (which is normally denied
 * for a regular app process — the Dart side reports capability so the UI can
 * nudge the user to authorize in Shizuku).
 */
object ShizukuControl {
    const val REQUEST_CODE = 4242

    fun available(): Boolean = try {
        Shizuku.pingBinder()
    } catch (_: Throwable) {
        false
    }

    fun isPreV11(): Boolean = try {
        Shizuku.isPreV11()
    } catch (_: Throwable) {
        true
    }

    fun permissionGranted(): Boolean = try {
        if (isPreV11()) true
        else Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
    } catch (_: Throwable) {
        false
    }

    /** True when shell commands will actually execute with elevated rights. */
    fun canControl(): Boolean = available() && permissionGranted()

    /** Prompt the user to authorize OpenBridge inside the Shizuku app. */
    fun requestPermission(): Boolean = try {
        Shizuku.requestPermission(REQUEST_CODE)
    } catch (_: Throwable) {
        false
    }

    /** Fire-and-forget execution of a shell command through the Shizuku server. */
    fun execute(cmd: String) {
        if (!canControl()) return
        Thread {
            try {
                val p = Shizuku.newProcess(arrayOf("sh", "-c", cmd), null, null)
                p.waitFor()
            } catch (_: Throwable) {
            }
        }.start()
    }
}