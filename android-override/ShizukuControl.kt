package com.elthondev.openbridge

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import rikka.shizuku.Shizuku

/**
 * Provides shell-level input control (tap / swipe / keyevent / text) through
 * Shizuku. When Shizuku is running and OpenBridge is authorized inside the
 * Shizuku app, we bind a Shizuku "user service" (ShellService) that runs in a
 * separate process with the shell UID and executes `input ...` on our behalf.
 * Shizuku 13 removed the old public Shizuku.newProcess(), so bindUserService
 * is the supported way to run commands. Without Shizuku authorization nothing
 * is executed — the Dart side reflects capability so the UI can nudge the user.
 */
object ShizukuControl {
    const val REQUEST_CODE = 4242
    const val TAG = "OpenBridgeShizuku"

    @Volatile private var shell: IShellCommand? = null
    private var args: Shizuku.UserServiceArgs? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            shell = IShellCommand.Stub.asInterface(binder)
        }

        override fun onServiceDisconnected(name: ComponentName) {
            shell = null
        }
    }

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

    /** True when shell commands will actually run with elevated rights. */
    fun canControl(): Boolean = available() && permissionGranted()

    /** Ask the user to authorize OpenBridge inside the Shizuku app. */
    fun requestPermission(): Boolean = try {
        Shizuku.requestPermission(REQUEST_CODE)
        true
    } catch (_: Throwable) {
        false
    }

    /** Bind the shell user-service so commands run as the shell UID. */
    fun bind(context: Context) {
        val a = args ?: Shizuku.UserServiceArgs(
            ComponentName(context.packageName, ShellService::class.java.name)
        ).daemon(false)
            .processNameSuffix(ShellService.PROCESS_SUFFIX)
            .tag(ShellService.TAG)
            .version(ShellService.VERSION)
            .also { args = it }
        try {
            Shizuku.bindUserService(a, connection)
        } catch (_: Throwable) {}
    }

    /** Fire-and-forget execution of a shell command via the shell process. */
    fun execute(context: Context, cmd: String) {
        if (!canControl()) return
        if (shell == null) bind(context)
        try {
            shell?.exec(cmd)
        } catch (_: Throwable) {}
    }
}