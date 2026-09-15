package com.elthondev.openbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION, required by
 * Android 14+ before MediaProjection can be used. It runs briefly while the
 * capture setup happens and then stops itself.
 */
class ProjectionService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureNotificationChannel()
        val notification = buildNotification()

        if (Build.VERSION.SDK_INT >= 29) {
            try {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } catch (_: Exception) {
                stopSelf()
                return START_NOT_STICKY
            }
        } else {
            @Suppress("DEPRECATION")
            try {
                startForeground(NOTIFICATION_ID, notification)
            } catch (_: Exception) {
                stopSelf()
                return START_NOT_STICKY
            }
        }

        // Capture (re)sets up its own thumbnail; we only hold the token.
        stopSelf()
        return START_NOT_STICKY
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
    }
}