package com.marina.marina.data.sync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.marina.marina.MainActivity
import com.marina.marina.R
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent

/** Visible, bounded data-sync service. Never restarts a completed task from a stale Intent. */
class SyncForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        val notifications = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "مزامنة البيانات", NotificationManager.IMPORTANCE_LOW
            ))
        }
        val openApp = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_sync_notification)
            .setContentTitle("جارٍ مزامنة البيانات")
            .setContentText("يمكنك التنقل بين الشاشات أو وضع التطبيق في الخلفية")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .build()
        try {
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0)
        } catch (error: RuntimeException) {
            cancelOwnedWork()
            stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY
    override fun onBind(intent: Intent?): IBinder? = null

    // Android 15 imposes a cumulative dataSync FGS time budget. Stop promptly,
    // report cancellation, and retain the existing cursor/outbox for later recovery.
    override fun onTimeout(startId: Int, fgsType: Int) {
        cancelOwnedWork()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun cancelOwnedWork() {
        EntryPointAccessors.fromApplication(applicationContext, SyncServiceEntryPoint::class.java)
            .runner().cancelForSystemStop()
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    @EntryPoint
    @InstallIn(SingletonComponent::class)
    interface SyncServiceEntryPoint {
        fun runner(): SyncOperationRunner
    }

    companion object {
        const val CHANNEL_ID = "active_data_sync"
        const val NOTIFICATION_ID = 2401
    }
}
