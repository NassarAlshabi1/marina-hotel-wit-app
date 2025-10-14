package com.marinahotel.kotlin

import android.app.Application
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.repository.BookingRepository
import com.marinahotel.kotlin.data.repository.DashboardRepository
import com.marinahotel.kotlin.data.repository.EmployeesRepository
import com.marinahotel.kotlin.data.repository.ExpensesRepository
import com.marinahotel.kotlin.data.repository.NotesRepository
import com.marinahotel.kotlin.data.repository.PaymentsRepository
import com.marinahotel.kotlin.data.repository.RoomsRepository
import com.marinahotel.kotlin.data.work.OccupancyRefreshWorker
import java.util.concurrent.TimeUnit

class HotelApplication : Application() {

    val database: HotelDatabase by lazy { HotelDatabase.getInstance(this) }

    val bookingRepository: BookingRepository by lazy {
        BookingRepository(
            bookingDao = database.bookingDao(),
            guestDao = database.guestDao()
        )
    }

    val roomsRepository: RoomsRepository by lazy { RoomsRepository(database.roomDao()) }

    val paymentsRepository: PaymentsRepository by lazy { PaymentsRepository(database.paymentDao()) }

    val notesRepository: NotesRepository by lazy { NotesRepository(database.bookingNoteDao()) }

    val expensesRepository: ExpensesRepository by lazy {
        ExpensesRepository(
            expenseDao = database.expenseDao(),
            expenseLogDao = database.expenseLogDao()
        )
    }

    val employeesRepository: EmployeesRepository by lazy {
        EmployeesRepository(database.employeeDao())
    }

    val dashboardRepository: DashboardRepository by lazy {
        DashboardRepository(
            roomDao = database.roomDao(),
            bookingDao = database.bookingDao(),
            expenseDao = database.expenseDao()
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
            WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            workRequest
        )
    }

    companion object {
        private const val WORK_NAME = "occupancy_refresh"
    }
}
