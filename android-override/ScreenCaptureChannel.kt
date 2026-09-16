package com.elthondev.openbridge

import android.app.Activity
import android.app.Service
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.PowerManager
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import kotlin.math.max

/**
 * Bridges MediaProjection screen capture to Dart over the `openbridge/screen`
 * MethodChannel. Frames are captured on a dedicated HandlerThread, scaled to a
 * max side, JPEG-compressed and returned as base64 data URLs on demand.
 */
class ScreenCaptureChannel(
    private val engine: FlutterEngine,
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "openbridge/screen"
        const val REQUEST_CAPTURE = 92451
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
        addShizukuListeners()
    }

    private fun addShizukuListeners() {
        if (shizukuListenersAdded) return
        shizukuListenersAdded = true
        try {
            Shizuku.addBinderReceivedListener(binderListener)
            Shizuku.addBinderDeadListener(binderListener)
            Shizuku.addRequestPermissionResultListener(permissionListener)
        } catch (_: Throwable) {}
    }

    private val binderListener = object : Shizuku.OnBinderReceivedListener, Shizuku.OnBinderDeadListener {
        override fun onBinderReceived() = notifyShizukuStatus()
        override fun onBinderDead() = notifyShizukuStatus()
    }

    private val permissionListener = object : Shizuku.OnRequestPermissionResultListener {
        override fun onRequestPermissionResult(requestCode: Int, grantResult: Int) {
            if (requestCode == ShizukuControl.REQUEST_CODE) notifyShizukuStatus()
        }
    }

    private fun notifyShizukuStatus() {
        try {
            channel.invokeMethod(
                "shizukuStatusChanged",
                mapOf(
                    "available" to ShizukuControl.available(),
                    "granted" to ShizukuControl.permissionGranted(),
                )
            )
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
                    val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = android.net.Uri.parse("package:${activity.packageName}")
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
                    )
                )
            }
            "requestShizukuPermission" -> {
                result.success(ShizukuControl.requestPermission())
            }
            "executeControl" -> {
                val action = call.argument<String>("action") ?: ""
                val x = call.argument<Number>("x")?.toDouble() ?: 0.5
                val y = call.argument<Number>("y")?.toDouble() ?: 0.5
                val x2 = call.argument<Number>("x2")?.toDouble()
                val y2 = call.argument<Number>("y2")?.toDouble()
                val metrics = activity.resources.displayMetrics
                val px = (x * metrics.widthPixels).toInt()
                val py = (y * metrics.heightPixels).toInt()
                try {
                    val cmd = when (action) {
                        "tap" -> "input tap $px $py"
                        "swipe" -> {
                            val px2 = ((x2 ?: x) * metrics.widthPixels).toInt()
                            val py2 = ((y2 ?: y) * metrics.heightPixels).toInt()
                            "input swipe $px $py $px2 $py2 300"
                        }
                        "key" -> "input keyevent ${call.argument<Int>("keyCode") ?: 4}"
                        "text" -> "input text '${call.argument<String>("text") ?: ""}'"
                        else -> null
                    }
                    if (cmd == null) {
                        result.success(false)
                        return
                    }
                    if (ShizukuControl.canControl()) {
                        ShizukuControl.execute(cmd)
                    } else {
                        try {
                            Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
                        } catch (_: Exception) {
                            result.success(false)
                            return
                        }
                    }
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

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