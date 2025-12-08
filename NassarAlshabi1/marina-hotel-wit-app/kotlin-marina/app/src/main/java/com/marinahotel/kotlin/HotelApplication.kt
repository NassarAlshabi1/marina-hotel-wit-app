package com.marinahotel.kotlin

import android.app.Application
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.HotelRepository
import com.marinahotel.kotlin.data.work.OccupancyRefreshWorker
import java.util.concurrent.TimeUnit

class HotelApplication : Application() {

    val database: HotelDatabase by lazy { HotelDatabase.getInstance(this) }

    val repository: HotelRepository by lazy {
        HotelRepository(
            database = database,
            guestDao = database.guestDao(),
            roomDao = database.roomDao(),
            bookingDao = database.bookingDao(),
            paymentDao = database.paymentDao(),
            bookingNoteDao = database.bookingNoteDao(),
            expenseDao = database.expenseDao(),
            reportingDao = database.reportingDao()
        )
    }

    override fun onCreate() {
        super.onCreate()
        scheduleOccupancyRefreshWork()
    }

    private fun scheduleOccupancyRefreshWork() {
        val constraints = Constraints.Builder()
            .setRequiresBatteryNotLow(true)
            .build()

        val workRequest = PeriodicWorkRequestBuilder<OccupancyRefreshWorker>(1, TimeUnit.DAYS)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            "occupancy_refresh",
            ExistingPeriodicWorkPolicy.KEEP,
            workRequest
        )
    }
}
