package com.elthondev.openbridge

import android.app.Service
import android.content.Intent
import android.os.IBinder

/**
 * Shizuku "user service". Shizuku spawns this in a separate process running as
 * the shell (or root) UID, which is what lets it inject `input ...` events.
 * The remote process calls back into this class over the IShellCommand AIDL.
 */
class ShellService : Service() {

    companion object {
        const val PROCESS_SUFFIX = "sh"
        const val TAG = "sh"
        const val VERSION = 1
    }

    private val binder = object : IShellCommand.Stub() {
        override fun exec(cmd: String) {
            try {
                val p = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                p.waitFor()
            } catch (_: Throwable) {
            }
        }

        override fun destroy() {
            stopSelf()
        }
    }

    override fun onBind(intent: Intent): IBinder = binder
}