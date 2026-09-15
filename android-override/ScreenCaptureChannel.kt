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
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
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

    private var pendingStart: MethodChannel.Result? = null

    fun register() {
        projectionManager = activity.getSystemService(Service.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
        channel.setMethodCallHandler(this)
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

        // Android 14+ requires a mediaProjection foreground service before
        // getMediaProjection is allowed to succeed.
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                val svc = Intent(activity, ProjectionService::class.java)
                if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(svc)
                else activity.startService(svc)
            } catch (_: Exception) {}
        }

        val pm = projectionManager
        if (pm == null) {
            pending?.error("unavailable", "MediaProjection is not available on this device", null)
            return
        }
        val projection = pm.getMediaProjection(resultCode, data)
        if (projection == null) {
            pending?.error("failed", "Could not acquire media projection", null)
            return
        }

        mediaProjection = projection
        setupProjection(projection)
        started = true
        pending?.success(true)
    }

    @android.annotation.SuppressLint("WrongConstant")
    private fun setupProjection(projection: MediaProjection) {
        val metrics = activity.resources.displayMetrics
        val dispW = metrics.widthPixels
        val dispH = metrics.heightPixels
        val density = metrics.densityDpi

        captureThread = HandlerThread("openbridge-capture").also { it.start() }
        val thread = captureThread!!
        val loop = Handler(thread.looper)
        captureHandler = loop

        val reader = ImageReader.newInstance(dispW, dispH, PixelFormat.RGBA_8888, 2)
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
                val rowPadding = rowStride - pixelStride * dispW
                val padded = Bitmap.createBitmap(
                    dispW + rowPadding / pixelStride,
                    dispH,
                    Bitmap.Config.ARGB_8888
                )
                padded.copyPixelsFromBuffer(buffer)
                val cropped = Bitmap.createBitmap(padded, 0, 0, dispW, dispH)
                padded.recycle()
                lastBitmap?.recycle()
                lastBitmap = cropped
            } catch (_: Exception) {
                // A frame that failed to decode is safely dropped.
            } finally {
                image.close()
            }
        }, loop)

        virtualDisplay = projection.createVirtualDisplay(
            "OpenBridgeCapture",
            dispW,
            dispH,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            loop
        )

        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                stop()
                channel.invokeMethod("captureStopped", null)
            }
        }, loop)

        // Tell the foreground service it can tear itself down now.
        try {
            activity.stopService(Intent(activity, ProjectionService::class.java))
        } catch (_: Exception) {}
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
    }
}