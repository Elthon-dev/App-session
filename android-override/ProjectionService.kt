package com.elthondev.openbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder

/**
 * Foreground service with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION.
 *
 * Android 10+ requires a foreground service of this type to be ACTIVE before
 * MediaProjectionManager.getMediaProjection() may be called, and Android 14+
 * throws a SecurityException otherwise. Creating the projection here, after
 * startForeground(), guarantees correct ordering. The service stays alive for
 * the duration of the capture and is stopped by the capture channel.
 */
class ProjectionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel()
        if (!startForegroundSafely()) return START_NOT_STICKY

        val code = intent?.getIntExtra(EXTRA_CODE, -1) ?: -1
        val data = extractData(intent)
        if (code != -1 && data != null) {
            val pm =
                getSystemService(Service.MEDIA_PROJECTION_SERVICE) as? MediaProjectionManager
            val projection: MediaProjection? = try {
                pm?.getMediaProjection(code, data)
            } catch (_: Exception) {
                null
            }
            val cb = callback
            callback = null
            if (cb != null) cb(projection)
        }

        return START_STICKY
    }

    private fun startForegroundSafely(): Boolean {
        val notification = buildNotification()
        return try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    @Suppress("DEPRECATION")
    private fun extractData(intent: Intent?): Intent? {
        if (intent == null) return null
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        } else {
            intent.getParcelableExtra(EXTRA_DATA)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Screen sharing",
            NotificationManager.IMPORTANCE_LOW
        )
        channel.setShowBadge(false)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("OpenBridge")
            .setContentText("Sharing your screen with Opencode")
            .setSmallIcon(R.drawable.ic_stat_openbridge)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "openbridge-capture"
        private const val NOTIFICATION_ID = 7007
        private const val EXTRA_CODE = "extra_code"
        private const val EXTRA_DATA = "extra_data"

        @Volatile
        private var callback: ((MediaProjection?) -> Unit)? = null

        /** Set by the capture channel before starting this service. */
        fun setOnProjectionReady(cb: (MediaProjection?) -> Unit) {
            callback = cb
        }

        fun clearCallback() {
            callback = null
        }
    }
}