package com.elthondev.openbridge

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var screenCapture: ScreenCaptureChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        screenCapture = ScreenCaptureChannel(flutterEngine, this).also { it.register() }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == ScreenCaptureChannel.REQUEST_CAPTURE) {
            screenCapture?.onCaptureResult(resultCode, data)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == ScreenCaptureChannel.REQUEST_NOTIFICATION_PERMISSION) {
            screenCapture?.onRequestPermissionsResult(requestCode, grantResults)
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}