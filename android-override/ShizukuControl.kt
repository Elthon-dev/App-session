package com.elthondev.openbridge

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.Parcel
import rikka.shizuku.Shizuku
import java.util.ArrayDeque

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

    const val RESULT_OK = 0
    const val RESULT_WAIT_BIND = -2
    const val RESULT_NO_PERMISSION = -1
    const val RESULT_TRANSACT_FAILED = -3

    @Volatile private var shell: IBinder? = null
    @Volatile private var binding = false
    private var args: Shizuku.UserServiceArgs? = null

    // Commands received while the user-service binder is still connecting are
    // queued here and flushed once onServiceConnected fires, so the very first
    // control command is never silently dropped.
    private val pendingCommands = ArrayDeque<String>()

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            shell = binder
            binding = false
            flushPending()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            shell = null
            binding = false
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

    /** The shell user-service binder is currently connected and alive. */
    fun bound(): Boolean = try {
        shell?.pingBinder() == true
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
        if (binding || bound()) return
        binding = true
        val a = args ?: Shizuku.UserServiceArgs(
            ComponentName(context.packageName, ShellService::class.java.name)
        ).daemon(false)
            .processNameSuffix(ShellService.PROCESS_SUFFIX)
            .tag(ShellService.TAG)
            .version(ShellService.VERSION)
            .also { args = it }
        try {
            Shizuku.bindUserService(a, connection)
        } catch (_: Throwable) {
        }
    }

    /**
     * Execute a shell command via the shell process. Never drops commands: if
     * the binder is still connecting, the command is queued and runs right
     * after onServiceConnected. Returns the shell exit code (0 = success).
     */
    fun execute(context: Context, cmd: String): Int {
        if (!canControl()) return RESULT_NO_PERMISSION
        val shellBinder = shell
        if (shellBinder == null || !shellBinder.pingBinder()) {
            synchronized(pendingCommands) {
                pendingCommands.addLast(cmd)
            }
            bind(context)
            return RESULT_WAIT_BIND
        }
        return transact(shellBinder, cmd)
    }

    private fun transact(binder: IBinder, cmd: String): Int {
        var data: Parcel? = null
        var reply: Parcel? = null
        return try {
            data = Parcel.obtain()
            reply = Parcel.obtain()
            data.writeInterfaceToken(ShellService.DESCRIPTOR)
            data.writeString(cmd)
            binder.transact(ShellService.TRANSACTION_EXEC, data, reply, 0)
            reply.readException()
            reply.readInt()
        } catch (_: Throwable) {
            RESULT_TRANSACT_FAILED
        } finally {
            try {
                reply?.recycle()
                data?.recycle()
            } catch (_: Throwable) {}
        }
    }

    private fun flushPending() {
        val cmds = synchronized(pendingCommands) {
            if (pendingCommands.isEmpty()) return
            val list = ArrayList<String>(pendingCommands.size)
            while (pendingCommands.isNotEmpty()) list.add(pendingCommands.removeFirst())
            list
        }
        for (cmd in cmds) {
            val b = shell ?: return
            transact(b, cmd)
        }
    }
}