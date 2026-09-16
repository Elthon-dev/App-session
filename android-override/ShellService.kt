package com.elthondev.openbridge

import android.app.Service
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.os.Parcel

/**
 * Shizuku "user service". Shizuku spawns this in a separate process running as
 * the shell (or root) UID, which is what lets it inject `input ...` events.
 * The client (ShizukuControl) talks to it with a tiny hand-rolled Binder
 * protocol — the same shape AIDL would generate, but without needing AGP's
 * (often disabled by default) AIDL compilation.
 */
class ShellService : Service() {

    companion object {
        const val PROCESS_SUFFIX = "sh"
        const val TAG = "sh"
        const val VERSION = 1
        const val DESCRIPTOR = "com.elthondev.openbridge.IShellCommand"

        const val TRANSACTION_EXEC = 1
        const val TRANSACTION_DESTROY = 2
    }

    override fun onBind(intent: Intent): IBinder {
        return object : Binder() {
            override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
                when (code) {
                    TRANSACTION_EXEC -> {
                        data.enforceInterface(DESCRIPTOR)
                        val cmd = data.readString() ?: ""
                        Thread {
                            try {
                                val p = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                                p.waitFor()
                            } catch (_: Throwable) {
                            }
                        }.start()
                        reply?.writeNoException()
                        return true
                    }

                    TRANSACTION_DESTROY -> {
                        data.enforceInterface(DESCRIPTOR)
                        reply?.writeNoException()
                        stopSelf()
                        return true
                    }
                }
                return super.onTransact(code, data, reply, flags)
            }
        }
    }
}