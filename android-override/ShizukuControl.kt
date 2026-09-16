package com.elthondev.openbridge

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.IBinder
import android.os.Parcel
import android.os.SystemClock
import android.util.Log
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
    @Volatile private var lastBindError: String? = null
    @Volatile private var lastBindAt = 0L
    @Volatile private var bindAttempts = 0
    private var args: Shizuku.UserServiceArgs? = null

    /** Invoked whenever shell-connection state changes (for live UI updates). */
    @Volatile var onStateChanged: (() -> Unit)? = null

    // Commands received while the user-service binder is still connecting are
    // queued here and flushed once onServiceConnected fires, so the very first
    // control command is never silently dropped.
    private val pendingCommands = ArrayDeque<String>()

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            shell = binder
            binding = false
            lastBindAt = 0L
            lastBindError = null
            Log.i(TAG, "ShellService connected after attempt #$bindAttempts")
            flushPending()
            onStateChanged?.invoke()
        }

        override fun onServiceDisconnected(name: ComponentName) {
            Log.w(TAG, "ShellService disconnected")
            shell = null
            binding = false
            lastBindAt = 0L
            onStateChanged?.invoke()
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

    /** The Shizuku server API version in use (-1 when unavailable). */
    fun version(): Int = try {
        Shizuku.getVersion()
    } catch (_: Throwable) {
        -1
    }

    /** True when shell commands will actually run with elevated rights. */
    fun canControl(): Boolean = available() && permissionGranted()

    /** Most recent user-service bind failure reason (or null). */
    fun lastBindError(): String? = lastBindError

    /** Number of bind attempts made this app run. */
    fun bindAttempts(): Int = bindAttempts

    /** True when a bind attempt is currently stuck waiting for the binder. */
    fun stuckBinding(): Boolean = binding && lastBindAt != 0L &&
        SystemClock.uptimeMillis() - lastBindAt > 3000

    /** Ask the user to authorize OpenBridge inside the Shizuku app. */
    fun requestPermission(): Boolean = try {
        Shizuku.requestPermission(REQUEST_CODE)
        true
    } catch (_: Throwable) {
        false
    }

    /**
     * Version code for the user-service identity. Derived from the APK's
     * lastUpdateTime, so every fresh install gets a brand-new service key.
     * Shizuku keeps a cached record per (package, tag, version) and — after a
     * reinstall/update — a stale record can point at a dead process whose
     * binder never connects (stuck "warming up"). Changing the version each
     * install forces Shizuku's server to drop the stale record and spawn fresh.
     */
    private fun serviceVersion(context: Context): Int = try {
        val pi = context.packageManager.getPackageInfo(context.packageName, 0)
        (pi.lastUpdateTime / 1000L).toInt()
    } catch (_: Throwable) {
        1
    }

    /** Bind the shell user-service so commands run as the shell UID. */
    fun bind(context: Context) {
        if (bound()) {
            binding = false
            return
        }
        if (binding) {
            // A bind that hasn't delivered its binder within 3s is treated as
            // stuck: force-remove the (possibly stale) service on the Shizuku
            // server and re-bind instead of deadlocking.
            if (!stuckBinding()) return
            Log.w(TAG, "bind stuck after ${bindAttempts} attempts, rebinding fresh")
            try {
                if (args != null) Shizuku.unbindUserService(args!!, connection, true)
            } catch (_: Throwable) {}
            shell = null
        }
        binding = true
        lastBindAt = SystemClock.uptimeMillis()
        lastBindError = null
        bindAttempts += 1
        val a = args ?: Shizuku.UserServiceArgs(
            ComponentName(context.packageName, ShellService::class.java.name)
        ).daemon(false)
            .processNameSuffix(ShellService.PROCESS_SUFFIX)
            .tag(ShellService.TAG)
            .version(serviceVersion(context))
            .also { args = it }
        try {
            Shizuku.bindUserService(a, connection)
        } catch (e: Throwable) {
            lastBindError = e.toString()
            binding = false
            lastBindAt = 0L
            Log.e(TAG, "bindUserService failed: $e")
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