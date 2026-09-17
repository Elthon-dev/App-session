package com.elthondev.openbridge

import android.app.Activity
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioManager
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.PowerManager
import android.provider.Settings
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import kotlin.math.max

/**
 * Bridges MediaProjection screen capture *and* on-device device control to Dart
 * over the `openbridge/screen` MethodChannel.
 *
 * Frames are captured on a dedicated HandlerThread, scaled to a max side,
 * JPEG-compressed and returned as base64 data URLs on demand.
 *
 * Control commands are injected through whichever backend is able to run:
 *  1. AccessibilityService  — no root/Shizuku, handles gestures + global actions
 *  2. Shizuku shell         — `input ...`, `am ...`, `settings ...`
 *  3. App APIs              — intents for launching apps / opening URLs
 */
class ScreenCaptureChannel(
    private val engine: FlutterEngine,
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "openbridge/screen"
        const val REQUEST_CAPTURE = 92451
        const val REQUEST_NOTIFICATION_PERMISSION = 92452
        const val REQUEST_WRITE_SETTINGS = 92453
    }

    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var captureHandler: Handler? = null
    private var captureThread: HandlerThread? = null

    @Volatile private var lastBitmap: Bitmap? = null
    @Volatile private var maxSide = 720
    @Volatile private var jpegQuality = 60
    @Volatile private var started = false
    private var wakeLock: PowerManager.WakeLock? = null

    private var pendingStart: MethodChannel.Result? = null

    @Volatile private var shizukuListenersAdded = false

    fun register() {
        projectionManager = activity.getSystemService(Service.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        channel.setMethodCallHandler(this)
        // Live banner updates as soon as the shell engine connects/disconnects.
        ShizukuControl.onStateChanged = { notifyShizukuStatus() }
        addShizukuListeners()
        // Eagerly bind at startup if we are already authorized.  This works
        // even when the non-sticky listener never fires because the Shizuku
        // binder was connected before this activity registered.
        try {
            if (ShizukuControl.canControl()) ShizukuControl.bind(activity)
        } catch (_: Throwable) {}
        notifyShizukuStatus()
    }

    private fun addShizukuListeners() {
        if (shizukuListenersAdded) return
        shizukuListenersAdded = true
        try {
            // Sticky variant immediately calls back if the Shizuku binder is
            // already available (the common case at app launch).
            Shizuku.addBinderReceivedListenerSticky(binderListener)
            Shizuku.addBinderDeadListener(binderListener)
            Shizuku.addRequestPermissionResultListener(permissionListener)
        } catch (_: Throwable) {}
    }

    private val binderListener = object : Shizuku.OnBinderReceivedListener, Shizuku.OnBinderDeadListener {
        override fun onBinderReceived() {
            if (ShizukuControl.canControl()) ShizukuControl.bind(activity)
            notifyShizukuStatus()
        }

        override fun onBinderDead() = notifyShizukuStatus()
    }

    private val permissionListener = object : Shizuku.OnRequestPermissionResultListener {
        override fun onRequestPermissionResult(requestCode: Int, grantResult: Int) {
            if (requestCode == ShizukuControl.REQUEST_CODE) {
                if (grantResult == PackageManager.PERMISSION_GRANTED && ShizukuControl.canControl()) {
                    ShizukuControl.bind(activity)
                }
                notifyShizukuStatus()
            }
        }
    }

    private fun notifyShizukuStatus() {
        try {
            channel.invokeMethod(
                "shizukuStatusChanged",
                mapOf(
                    "available" to ShizukuControl.available(),
                    "granted" to ShizukuControl.permissionGranted(),
                    "bound" to ShizukuControl.bound(),
                    "version" to ShizukuControl.version(),
                    "stuck" to ShizukuControl.stuckBinding(),
                    "attempts" to ShizukuControl.bindAttempts(),
                    "error" to ShizukuControl.lastBindError(),
                )
            )
        } catch (_: Throwable) {}
    }

    private fun notificationGranted(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return try {
            activity.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        } catch (_: Throwable) {
            false
        }
    }

    private fun batteryExempt(): Boolean {
        return try {
            val pm = activity.getSystemService(Service.POWER_SERVICE) as? PowerManager
            pm?.isIgnoringBatteryOptimizations(activity.packageName) ?: false
        } catch (_: Throwable) {
            false
        }
    }

    private fun canWriteSettings(): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.System.canWrite(activity) else true
    } catch (_: Throwable) {
        false
    }

    /** Forwarded from MainActivity for runtime-permission callbacks. */
    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode == REQUEST_NOTIFICATION_PERMISSION) {
            notifyPermissionsChanged()
        }
    }

    private fun notifyPermissionsChanged() {
        try {
            channel.invokeMethod("permissionChanged", null)
        } catch (_: Throwable) {}
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCapture" -> {
                val side = (call.argument<Number>("maxSide")?.toInt() ?: 720).coerceIn(240, 1600)
                val q = (call.argument<Number>("quality")?.toInt() ?: 60).coerceIn(10, 95)
                maxSide = side
                jpegQuality = q
                startCapture(result)
            }

            "captureFrame" -> captureFrame(result)
            "stopCapture" -> {
                stop()
                result.success(null)
            }

            "isCapturing" -> result.success(started)
            "requestBatteryBypass" -> {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = Uri.parse("package:${activity.packageName}")
                    activity.startActivity(intent)
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
            "shizukuStatus" -> {
                result.success(
                    mapOf(
                        "available" to ShizukuControl.available(),
                        "granted" to ShizukuControl.permissionGranted(),
                        "bound" to ShizukuControl.bound(),
                        "version" to ShizukuControl.version(),
                        "stuck" to ShizukuControl.stuckBinding(),
                        "attempts" to ShizukuControl.bindAttempts(),
                        "error" to ShizukuControl.lastBindError(),
                    )
                )
            }
            "requestShizukuPermission" -> {
                result.success(ShizukuControl.requestPermission())
            }
            "permissionStatus" -> {
                result.success(
                    mapOf(
                        "notifications" to notificationGranted(),
                        "battery" to batteryExempt(),
                        "shizukuAvailable" to ShizukuControl.available(),
                        "shizukuGranted" to ShizukuControl.permissionGranted(),
                        "shizukuBound" to ShizukuControl.bound(),
                        "accessibility" to ControlAccessibilityService.connected(),
                        "writeSettings" to canWriteSettings(),
                    )
                )
            }
            "requestNotificationPermission" -> {
                if (!notificationGranted() && Build.VERSION.SDK_INT >= 33) {
                    try {
                        activity.requestPermissions(
                            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                            REQUEST_NOTIFICATION_PERMISSION
                        )
                    } catch (_: Exception) {}
                }
                result.success(true)
            }
            "accessibilityStatus" -> {
                result.success(mapOf("enabled" to ControlAccessibilityService.connected()))
            }
            "openAccessibilitySettings" -> {
                result.success(try {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    activity.startActivity(intent)
                    true
                } catch (_: Exception) {
                    false
                })
            }
            "openWriteSettings" -> {
                result.success(try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                        intent.data = Uri.parse("package:${activity.packageName}")
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(intent)
                    }
                    true
                } catch (_: Exception) {
                    false
                })
            }
            "executeControl" -> executeControl(call, result)
            "listApps" -> result.success(listApps())
            "getAudio" -> result.success(getAudio())
            "setAudio" -> setAudio(call, result)
            "getBrightness" -> result.success(getBrightness())
            "setBrightness" -> setBrightness(call, result)
            "screenInfo" -> result.success(screenInfo())
            "getSystemMemory" -> result.success(systemMemory())
            "trimCaches" -> {
                val exit = if (ShizukuControl.canControl()) {
                    ShizukuControl.execute(activity, "pm trim-caches 1T")
                } else {
                    -2
                }
                result.success(
                    mapOf(
                        "ok" to (exit == 0),
                        "exit" to exit,
                        "mode" to if (exit == -2) "none" else "shizuku",
                        "detail" to if (exit == -2) "Needs Shizuku (shell) to free app caches" else null,
                    )
                )
            }
            "applyMemoryTweaks" -> {
                val maxCached = (call.argument<Number>("maxCached")?.toInt() ?: 8).coerceIn(0, 32)
                val exit = if (ShizukuControl.canControl()) {
                    ShizukuControl.execute(
                        activity,
                        "settings put global activity_manager_constants max_cached_processes $maxCached"
                    )
                } else {
                    -2
                }
                result.success(
                    mapOf(
                        "ok" to (exit == 0),
                        "exit" to exit,
                        "mode" to if (exit == -2) "none" else "shizuku",
                        "maxCached" to maxCached,
                        "detail" to if (exit == -2) "Needs Shizuku (shell) to apply this" else null,
                    )
                )
            }
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------------
    // Control injection
    // ---------------------------------------------------------------------

    private fun executeControl(call: MethodCall, result: MethodChannel.Result) {
        val action = call.argument<String>("action") ?: ""
        val x = call.argument<Number>("x")?.toDouble() ?: 0.5
        val y = call.argument<Number>("y")?.toDouble() ?: 0.5
        val x2 = call.argument<Number>("x2")?.toDouble()
        val y2 = call.argument<Number>("y2")?.toDouble()
        val duration = (call.argument<Number>("duration")?.toLong() ?: 300L)
        val keyCode = call.argument<Int>("keyCode")
        val keyName = call.argument<String>("key")
        val text = call.argument<String>("text") ?: ""
        val pkg = call.argument<String>("package") ?: ""
        val url = call.argument<String>("url") ?: ""
        val direction = call.argument<String>("direction") ?: "down"
        val stream = call.argument<String>("stream") ?: "music"
        val level = call.argument<Int>("level")

        val metrics = activity.resources.displayMetrics
        val w = metrics.widthPixels
        val h = metrics.heightPixels
        val px = (x * w).toInt()
        val py = (y * h).toInt()
        val px2 = ((x2 ?: x) * w).toInt()
        val py2 = ((y2 ?: y) * h).toInt()

        try {
            // ---- App-side actions (no elevation required) ----------------
            when (action) {
                "launch" -> {
                    result.success(launchApp(pkg))
                    return
                }
                "url", "open" -> {
                    result.success(openUrl(url))
                    return
                }
                "volume" -> {
                    val r = applyAudio(stream, level, direction)
                    result.success(r)
                    return
                }
                "wake" -> {
                    keepScreenOn(true)
                    val exit = if (ShizukuControl.canControl()) {
                        ShizukuControl.execute(activity, "input keyevent 224")
                    } else -1
                    result.success(mapOf("ok" to true, "exit" to exit, "mode" to if (exit == 0) "shizuku" else "app"))
                    return
                }
                "sleep" -> {
                    keepScreenOn(false)
                    if (ShizukuControl.canControl()) {
                        val exit = ShizukuControl.execute(activity, "input keyevent 26")
                        result.success(mapOf("ok" to (exit == 0), "exit" to exit, "mode" to "shizuku"))
                    } else {
                        result.success(mapOf("ok" to false, "exit" to -1, "mode" to "none"))
                    }
                    return
                }
            }

            // ---- Accessibility backend (gestures + global actions) -------
            if (ControlAccessibilityService.connected()) {
                val done = when (action) {
                    "tap" -> ControlAccessibilityService.tap(px.toFloat(), py.toFloat())
                    "doubleTap", "double_tap", "double" -> ControlAccessibilityService.doubleTap(px.toFloat(), py.toFloat())
                    "longPress", "long_press", "long" -> ControlAccessibilityService.longPress(px.toFloat(), py.toFloat(), duration.coerceAtLeast(700L))
                    "swipe" -> ControlAccessibilityService.swipe(px.toFloat(), py.toFloat(), px2.toFloat(), py2.toFloat(), duration)
                    "scroll" -> ControlAccessibilityService.swipe(
                        (0.5 * w).toFloat(), ((if (direction == "up") 0.7 else 0.3) * h).toFloat(),
                        (0.5 * w).toFloat(), ((if (direction == "up") 0.3 else 0.7) * h).toFloat(),
                        250
                    )
                    "key" -> handleGlobalKey(keyCode, keyName)
                    "text", "type" -> ControlAccessibilityService.setText(text)
                    "clearText" -> ControlAccessibilityService.clearText()
                    else -> ControlAccessibilityService.globalFor(action)?.let { ControlAccessibilityService.global(it) }
                        ?: false
                }
                if (done) {
                    result.success(mapOf("ok" to true, "exit" to 0, "mode" to "accessibility"))
                    return
                }
            }

            // ---- Shell backend (Shizuku / app process) -------------------
            val cmd = shellCommand(action, px, py, px2, py2, duration, keyCode, keyName, text, direction)
            if (cmd != null) {
                val mode: String
                val exit: Int
                if (ShizukuControl.canControl()) {
                    mode = "shizuku"
                    exit = ShizukuControl.execute(activity, cmd)
                } else {
                    mode = "app"
                    exit = try {
                        val p = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                        p.waitFor()
                        p.exitValue()
                    } catch (_: Exception) {
                        -1
                    }
                }
                result.success(mapOf("ok" to (exit == 0), "exit" to exit, "mode" to mode))
                return
            }

            result.success(mapOf("ok" to false, "exit" to -2, "mode" to "none", "detail" to "No backend for action '$action'"))
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "exit" to -1, "mode" to "error", "detail" to e.message))
        }
    }

    /** Map a key request onto a global action when possible. */
    private fun handleGlobalKey(keyCode: Int?, keyName: String?): Boolean {
        val name = keyName?.lowercase()
        val code = keyCode ?: when (name) {
            "home" -> 3
            "back" -> 4
            "recents", "appswitch", "app_switch" -> 187
            "menu" -> 82
            "power" -> 26
            "search" -> 84
            else -> -1
        }
        val globalAction = when (code) {
            3 -> ControlAccessibilityService.GLOBAL_HOME
            4 -> ControlAccessibilityService.GLOBAL_BACK
            187 -> ControlAccessibilityService.GLOBAL_RECENTS
            else -> null
        }
        return globalAction?.let { ControlAccessibilityService.global(it) } ?: false
    }

    private fun shellCommand(
        action: String, px: Int, py: Int, px2: Int, py2: Int, duration: Long,
        keyCode: Int?, keyName: String?, text: String, direction: String,
    ): String? = when (action) {
        "tap" -> "input tap $px $py"
        "doubleTap", "double_tap", "double" -> "input tap $px $py; sleep 0.12; input tap $px $py"
        "longPress", "long_press", "long" -> "input swipe $px $py $px $py ${duration.coerceAtLeast(700L)}"
        "swipe" -> "input swipe $px $py $px2 $py2 $duration"
        "scroll" -> {
            val cx = (0.5 * activity.resources.displayMetrics.widthPixels).toInt()
            val from = (if (direction == "up") 0.7 else 0.3) * activity.resources.displayMetrics.heightPixels
            val to = (if (direction == "up") 0.3 else 0.7) * activity.resources.displayMetrics.heightPixels
            "input swipe $cx ${from.toInt()} $cx ${to.toInt()} 280"
        }
        "key" -> when {
            keyName != null -> "input keyevent $keyName"
            keyCode != null -> "input keyevent $keyCode"
            else -> null
        }
        "text", "type" -> "input text '${text.replace("'", "'\\''")}'"
        "back" -> "input keyevent 4"
        "home" -> "input keyevent 3"
        "recents", "recent" -> "input keyevent 187"
        "notifications", "notification_shade", "statusbar" -> "cmd statusbar expand-notifications"
        "quick_settings", "quick", "quicksettings" -> "cmd statusbar expand-settings"
        "lock", "lock_screen" -> "input keyevent 26"
        else -> null
    }

    private fun launchApp(pkg: String): Map<String, Any?> {
        if (pkg.isBlank()) return mapOf("ok" to false, "exit" to -1, "mode" to "app", "detail" to "missing package")
        return try {
            val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
                mapOf("ok" to true, "exit" to 0, "mode" to "app")
            } else if (ShizukuControl.canControl()) {
                val exit = ShizukuControl.execute(activity, "monkey -p $pkg -c android.intent.category.LAUNCHER 1")
                mapOf("ok" to (exit == 0), "exit" to exit, "mode" to "shizuku")
            } else {
                mapOf("ok" to false, "exit" to -1, "mode" to "app", "detail" to "not launchable")
            }
        } catch (e: Exception) {
            mapOf("ok" to false, "exit" to -1, "mode" to "app", "detail" to e.message)
        }
    }

    private fun openUrl(url: String): Map<String, Any?> {
        if (url.isBlank()) return mapOf("ok" to false, "exit" to -1, "mode" to "app", "detail" to "missing url")
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            mapOf("ok" to true, "exit" to 0, "mode" to "app")
        } catch (e: Exception) {
            mapOf("ok" to false, "exit" to -1, "mode" to "app", "detail" to e.message)
        }
    }

    private fun keepScreenOn(on: Boolean) {
        try {
            activity.runOnUiThread {
                if (on) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        } catch (_: Throwable) {}
    }

    // ---------------------------------------------------------------------
    // Apps, audio, brightness, info
    // ---------------------------------------------------------------------

    private fun listApps(): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        try {
            val pm = activity.packageManager
            val launchable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledApplications(0)
            }
            for (app in launchable) {
                val launchIntent = pm.getLaunchIntentForPackage(app.packageName) ?: continue
                val label = try {
                    pm.getApplicationLabel(app).toString()
                } catch (_: Throwable) {
                    app.packageName
                }
                out.add(mapOf("package" to app.packageName, "label" to label, "launchable" to true))
            }
            out.sortBy { (it["label"] as? String ?: "").lowercase() }
        } catch (_: Throwable) {}
        return out
    }

    private fun streamId(name: String): Int = when (name.lowercase()) {
        "music", "media" -> AudioManager.STREAM_MUSIC
        "ring", "ringtone" -> AudioManager.STREAM_RING
        "alarm" -> AudioManager.STREAM_ALARM
        "notification", "notif" -> AudioManager.STREAM_NOTIFICATION
        "system" -> AudioManager.STREAM_SYSTEM
        "voice", "call" -> AudioManager.STREAM_VOICE_CALL
        else -> AudioManager.STREAM_MUSIC
    }

    private fun audioManager(): AudioManager? =
        activity.getSystemService(Service.AUDIO_SERVICE) as? AudioManager

    private fun getAudio(): Map<String, Any?> {
        val am = audioManager() ?: return mapOf("ok" to false)
        fun snapshot(stream: Int) = mapOf(
            "level" to am.getStreamVolume(stream),
            "max" to am.getStreamMaxVolume(stream),
            "muted" to (am.getStreamVolume(stream) == 0),
        )
        return mapOf(
            "ok" to true,
            "music" to snapshot(AudioManager.STREAM_MUSIC),
            "ring" to snapshot(AudioManager.STREAM_RING),
            "alarm" to snapshot(AudioManager.STREAM_ALARM),
            "notification" to snapshot(AudioManager.STREAM_NOTIFICATION),
            "system" to snapshot(AudioManager.STREAM_SYSTEM),
        )
    }

    private fun setAudio(call: MethodCall, result: MethodChannel.Result) {
        val r = applyAudio(
            call.argument<String>("stream") ?: "music",
            call.argument<Number>("level")?.toInt(),
            call.argument<String>("op") ?: "set",
        )
        result.success(r)
    }

    private fun applyAudio(streamName: String, level: Int?, op: String): Map<String, Any?> {
        val am = audioManager() ?: return mapOf("ok" to false, "detail" to "no audio manager")
        val stream = streamId(streamName)
        return try {
            when (op.lowercase()) {
                "up", "raise", "increase" -> am.adjustStreamVolume(stream, AudioManager.ADJUST_RAISE, AudioManager.FLAG_SHOW_UI)
                "down", "lower", "decrease" -> am.adjustStreamVolume(stream, AudioManager.ADJUST_LOWER, AudioManager.FLAG_SHOW_UI)
                "mute" -> am.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, AudioManager.FLAG_SHOW_UI)
                "unmute" -> am.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, AudioManager.FLAG_SHOW_UI)
                else -> {
                    val max = am.getStreamMaxVolume(stream)
                    val target = (level ?: (max / 2)).coerceIn(0, max)
                    am.setStreamVolume(stream, target, AudioManager.FLAG_SHOW_UI)
                }
            }
            mapOf(
                "ok" to true,
                "mode" to "app",
                "stream" to streamName,
                "level" to am.getStreamVolume(stream),
                "max" to am.getStreamMaxVolume(stream),
                "muted" to (am.getStreamVolume(stream) == 0),
            )
        } catch (e: Exception) {
            mapOf("ok" to false, "mode" to "app", "detail" to e.message)
        }
    }

    private fun getBrightness(): Map<String, Any?> {
        val system = try {
            Settings.System.getInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS)
        } catch (_: Throwable) {
            -1
        }
        val window = try {
            val attr = activity.window.attributes
            (attr.screenBrightness * 255).toInt()
        } catch (_: Throwable) {
            -1
        }
        return mapOf("ok" to true, "system" to system, "window" to window, "max" to 255, "canWrite" to canWriteSettings())
    }

    private fun setBrightness(call: MethodCall, result: MethodChannel.Result) {
        val level = (call.argument<Number>("level")?.toInt() ?: 128).coerceIn(0, 255)
        // Prefer the real system brightness (shell → WRITE_SETTINGS), fall back
        // to a window-only dim so the control always does *something*.
        if (ShizukuControl.canControl()) {
            val exit = ShizukuControl.execute(activity, "settings put system screen_brightness $level")
            if (exit == 0) {
                result.success(mapOf("ok" to true, "mode" to "shizuku", "level" to level))
                return
            }
        }
        if (canWriteSettings()) {
            val ok = try {
                Settings.System.putInt(activity.contentResolver, Settings.System.SCREEN_BRIGHTNESS, level)
            } catch (_: Throwable) {
                false
            }
            if (ok) {
                result.success(mapOf("ok" to true, "mode" to "settings", "level" to level))
                return
            }
        }
        try {
            activity.runOnUiThread {
                val attr = activity.window.attributes
                attr.screenBrightness = level / 255f
                activity.window.attributes = attr
            }
            result.success(mapOf("ok" to true, "mode" to "window", "level" to level))
        } catch (_: Exception) {
            result.success(mapOf("ok" to false, "mode" to "none", "detail" to "brightness unavailable"))
        }
    }

    private fun screenInfo(): Map<String, Any?> {
        val metrics = activity.resources.displayMetrics
        val rotation = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                activity.display?.rotation ?: 0
            } else {
                @Suppress("DEPRECATION")
                activity.windowManager.defaultDisplay.rotation
            }
        } catch (_: Throwable) {
            0
        }
        val version = try {
            activity.packageManager.getPackageInfo(activity.packageName, 0).versionName
        } catch (_: Throwable) {
            "?"
        }
        return mapOf(
            "width" to metrics.widthPixels,
            "height" to metrics.heightPixels,
            "density" to metrics.densityDpi,
            "rotation" to rotation,
            "sdk" to Build.VERSION.SDK_INT,
            "version" to version,
            "accessibility" to ControlAccessibilityService.connected(),
            "shizuku" to ShizukuControl.bound(),
        )
    }

    /**
     * Whole-device memory/swap snapshot read straight from /proc (world
     * readable), plus one-shot load. CrashGuard uses this to predict when
     * lmkd/ColorOS is about to kill Termux and trim caches first.
     */
    private fun systemMemory(): Map<String, Any?> {
        fun meminfoKb(): Map<String, Long> {
            val m = mutableMapOf<String, Long>()
            try {
                java.io.File("/proc/meminfo").readLines().forEach { line ->
                    val parts = line.split(":")
                    if (parts.size >= 2) {
                        val v = parts[1].trim().split(" ")[0].toLongOrNull()
                        if (v != null) m[parts[0]] = v
                    }
                }
            } catch (_: Throwable) {}
            return m
        }
        val kb = meminfoKb()
        val load1 = try {
            java.io.File("/proc/loadavg").readText().trim().split(" ")[0].toDoubleOrNull() ?: -1.0
        } catch (_: Throwable) { -1.0 }
        val uptimeS = try {
            java.io.File("/proc/uptime").readText().trim().split(" ")[0].toDoubleOrNull()?.toLong() ?: -1L
        } catch (_: Throwable) { -1L }
        return mapOf(
            "totalMB" to ((kb["MemTotal"] ?: 0L) / 1024L),
            "availableMB" to ((kb["MemAvailable"] ?: 0L) / 1024L),
            "swapTotalMB" to ((kb["SwapTotal"] ?: 0L) / 1024L),
            "swapFreeMB" to ((kb["SwapFree"] ?: 0L) / 1024L),
            "load1" to load1,
            "uptimeS" to uptimeS,
            "shizuku" to ShizukuControl.canControl(),
        )
    }

    // ---------------------------------------------------------------------
    // Screen capture
    // ---------------------------------------------------------------------

    private fun startCapture(result: MethodChannel.Result) {
        if (started) {
            result.success(true)
            return
        }
        val pm = projectionManager
        if (pm == null) {
            result.error("unavailable", "MediaProjection is not available on this device", null)
            return
        }
        pendingStart = result
        activity.startActivityForResult(pm.createScreenCaptureIntent(), REQUEST_CAPTURE)
    }

    fun onCaptureResult(resultCode: Int, data: Intent?) {
        val pending = pendingStart
        pendingStart = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            pending?.error("denied", "Screen capture permission denied", null)
            return
        }

        // Hand off to the foreground service: it creates the MediaProjection
        // AFTER startForeground(), which Android 14+ requires. We configure the
        // capture callback here so the projection arrives thread-safely.
        ProjectionService.setOnProjectionReady { projection, err ->
            if (projection == null) {
                pending?.error("failed", err ?: "Could not acquire media projection", null)
                return@setOnProjectionReady
            }
            try {
                mediaProjection = projection
                setupProjection(projection)
                started = true
                pending?.success(true)
            } catch (e: Exception) {
                stop()
                pending?.error("failed", "Failed to start screen capture: ${e.message}", null)
            }
        }

        val svc = Intent(activity, ProjectionService::class.java).apply {
            putExtra("extra_code", resultCode)
            putExtra("extra_data", data)
        }
        try {
            if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(svc)
            else activity.startService(svc)
        } catch (_: Exception) {
            ProjectionService.clearCallback()
            pending?.error("failed", "Could not start capture service", null)
        }
    }

    @android.annotation.SuppressLint("WrongConstant")
    private fun setupProjection(projection: MediaProjection) {
        // Acquire WakeLock to keep CPU alive during screen capture
        try {
            val pm = activity.getSystemService(Service.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "openbridge:capture"
            )?.apply { acquire(4 * 60 * 60 * 1000L) } // 4 hours max
        } catch (_: Exception) {}

        val metrics = activity.resources.displayMetrics
        val dispW = metrics.widthPixels
        val dispH = metrics.heightPixels
        val density = metrics.densityDpi

        // Scale capture resolution to maxSide to avoid OOM on high-DPI screens.
        // Full-res RGBA_8888 (e.g. 1080×2400) is ~10 MB per buffer; cutting to
        // ~720 px saves ~70 % of that and avoids the low-memory killer.
        val scale = maxSide.toFloat() / max(dispW, dispH).coerceAtLeast(1)
        val imgW = (dispW * scale).toInt().coerceAtLeast(1)
        val imgH = (dispH * scale).toInt().coerceAtLeast(1)

        captureThread = HandlerThread("openbridge-capture").also { it.start() }
        val thread = captureThread!!
        val loop = Handler(thread.looper)
        captureHandler = loop

        val reader = ImageReader.newInstance(imgW, imgH, PixelFormat.RGBA_8888, 1)
        imageReader = reader

        reader.setOnImageAvailableListener({ r ->
            val image: Image? = try {
                r.acquireLatestImage()
            } catch (_: Exception) {
                null
            }
            if (image == null) return@setOnImageAvailableListener
            try {
                val plane = image.planes[0]
                val buffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride = plane.rowStride
                val rowPadding = rowStride - pixelStride * imgW
                val padded = Bitmap.createBitmap(
                    imgW + rowPadding / pixelStride,
                    imgH,
                    Bitmap.Config.ARGB_8888
                )
                padded.copyPixelsFromBuffer(buffer)
                val cropped = Bitmap.createBitmap(padded, 0, 0, imgW, imgH)
                padded.recycle()
                lastBitmap?.recycle()
                lastBitmap = cropped
            } catch (_: Exception) {
                // A frame that failed to decode is safely dropped.
            } finally {
                image.close()
            }
        }, loop)

        // Register the callback BEFORE creating the virtual display: newer
        // Android versions require it for MediaProjection resource management.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stop()
                channel.invokeMethod("captureStopped", null)
            }
        }, loop)

        virtualDisplay = projection.createVirtualDisplay(
            "OpenBridgeCapture",
            imgW,
            imgH,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            loop
        )
    }

    private fun captureFrame(result: MethodChannel.Result) {
        val bmp = lastBitmap ?: run {
            result.success("")
            return
        }
        val scaled = scaleToFit(bmp, maxSide)
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, jpegQuality, out)
        if (scaled !== bmp) scaled.recycle()
        val b64 = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        result.success("data:image/jpeg;base64,$b64")
    }

    private fun scaleToFit(bmp: Bitmap, maxSide: Int): Bitmap {
        val w = bmp.width
        val h = bmp.height
        if (max(w, h) <= maxSide) return bmp
        val ratio = maxSide.toFloat() / max(w, h)
        val nw = (w * ratio).toInt().coerceAtLeast(1)
        val nh = (h * ratio).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bmp, nw, nh, true)
    }

    private fun stop() {
        started = false
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {}
        wakeLock = null
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {}
        virtualDisplay = null
        try {
            imageReader?.close()
        } catch (_: Exception) {}
        imageReader = null
        try {
            lastBitmap?.recycle()
        } catch (_: Exception) {}
        lastBitmap = null
        try {
            mediaProjection?.stop()
        } catch (_: Exception) {}
        mediaProjection = null
        try {
            captureThread?.quitSafely()
        } catch (_: Exception) {}
        captureThread = null
        captureHandler = null
        try {
            activity.stopService(Intent(activity, ProjectionService::class.java))
        } catch (_: Exception) {}
    }
}
