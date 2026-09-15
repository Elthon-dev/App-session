package com.elthondev.openbridge

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.Base64
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.io.ByteArrayOutputStream

@CapacitorPlugin
class ScreenCapturePlugin : Plugin() {

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection: MediaProjection? = null
    private var imageReader: ImageReader? = null
    private var virtualDisplay: VirtualDisplay? = null

    private var width = 720
    private var height = 1280
    private var density = 160
    private var running = false

    private val handler = Handler(Looper.getMainLooper())
    private var lastBitmap: Bitmap? = null
    private var pendingCall: PluginCall? = null

    override fun load() {
        projectionManager = activity?.getSystemService(Context.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
    }

    @PluginMethod
    fun startCapture(call: PluginCall) {
        if (running) {
            call.resolve()
            return
        }
        width = call.getInt("width", 720)
        height = call.getInt("height", 1280)
        density = context?.resources?.displayMetrics?.densityDpi ?: 160
        pendingCall = call

        val intent = projectionManager?.createScreenCaptureIntent()
        if (intent == null) {
            call.reject("Screen capture not available on this device")
            return
        }
        activity?.startActivityForResult(intent, CAPTURE_REQUEST)
    }

    override fun handleOnActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.handleOnActivityResult(requestCode, resultCode, data)
        if (requestCode != CAPTURE_REQUEST) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            pendingCall?.reject("Screen capture permission denied")
            pendingCall = null
            return
        }

        val projection = projectionManager?.getMediaProjection(resultCode, data)
        if (projection == null) {
            pendingCall?.reject("Failed to acquire media projection")
            pendingCall = null
            return
        }

        mediaProjection = projection
        setupProjection(projection)
        running = true
        pendingCall?.resolve(JSObject().put("started", true))
        pendingCall = null
    }

    @SuppressLint("WrongConstant")
    private fun setupProjection(projection: MediaProjection) {
        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 3)
        virtualDisplay = projection.createVirtualDisplay(
            "OpenBridgeCapture",
            width, height, density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            handler
        )

        imageReader?.setOnImageAvailableListener({ reader ->
            val image: Image? = reader.acquireLatestImage()
            if (image != null) {
                try {
                    val plane = image.planes[0]
                    val buffer = plane.buffer
                    val pixelStride = plane.pixelStride
                    val rowStride = plane.rowStride
                    val rowPadding = rowStride - pixelStride * width
                    val temp = Bitmap.createBitmap(width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888)
                    temp.copyPixelsFromBuffer(buffer)
                    lastBitmap?.recycle()
                    lastBitmap = Bitmap.createBitmap(temp, 0, 0, width, height)
                    temp.recycle()
                } finally {
                    image.close()
                }
            }
        }, handler)
    }

    @PluginMethod
    fun captureFrame(call: PluginCall) {
        val bmp = lastBitmap
        if (bmp == null) {
            call.reject("No frame available yet")
            return
        }
        val quality = call.getInt("quality", 40)
        val output = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, quality, output)
        val encoded = Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
        val ret = JSObject()
        ret.put("data", "data:image/jpeg;base64,$encoded")
        call.resolve(ret)
    }

    @PluginMethod
    fun stopCapture(call: PluginCall) {
        teardown()
        call.resolve()
    }

    private fun teardown() {
        running = false
        lastBitmap?.recycle()
        lastBitmap = null
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null
    }

    override fun handleOnDestroy() {
        teardown()
        super.handleOnDestroy()
    }

    companion object {
        private const val CAPTURE_REQUEST = 10451
    }
}