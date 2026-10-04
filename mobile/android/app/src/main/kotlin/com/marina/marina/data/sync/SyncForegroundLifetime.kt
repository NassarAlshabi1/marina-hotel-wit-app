package com.marina.marina.data.sync

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

/** Reference counted across settings preflight and its nested manager operation. */
@Singleton
class SyncForegroundLifetime @Inject constructor(@ApplicationContext private val context: Context) {
    private var users = 0

    @Synchronized
    fun acquire(): AutoCloseable {
        if (users == 0) {
            // Do not silently run unprotected if Android refuses a background start.
            ContextCompat.startForegroundService(context, Intent(context, SyncForegroundService::class.java))
        }
        users++
        val released = AtomicBoolean(false)
        return AutoCloseable {
            if (released.compareAndSet(false, true)) release()
        }
    }

    @Synchronized
    private fun release() {
        users--
        if (users == 0) context.stopService(Intent(context, SyncForegroundService::class.java))
    }
}
