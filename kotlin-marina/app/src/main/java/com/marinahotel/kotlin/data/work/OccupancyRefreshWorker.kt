package com.marinahotel.kotlin.data.work

import android.content.Context
import androidx.room.withTransaction
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.RoomStatus
import kotlin.math.max

class OccupancyRefreshWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    override suspend fun doWork(): Result = try {
        val database = HotelDatabase.getInstance(applicationContext)
        val bookingDao = database.bookingDao()
        val roomDao = database.roomDao()
        val now = System.currentTimeMillis()

        val overdueBookings = bookingDao.getBookingsPastCheckout(BookingStatus.RESERVED.value, now)

        if (overdueBookings.isEmpty()) {
            Result.success()
        } else {
            database.withTransaction {
                overdueBookings.forEach { booking ->
                    val checkout = booking.checkoutDate ?: now
                    val nights = computeNights(booking.checkinDate, checkout)
                    bookingDao.update(
                        booking.copy(
                            status = BookingStatus.COMPLETED.value,
                            checkoutDate = checkout,
                            calculatedNights = nights
                        )
                    )
                    roomDao.updateRoomStatus(booking.roomNumber, RoomStatus.VACANT.value)
                }
            }
            Result.success()
        }
    } catch (exception: Exception) {
        Result.retry()
    }

    private fun computeNights(checkin: Long, checkout: Long): Int {
        val millisPerNight = 86_400_000L
        val diff = max(0L, checkout - checkin)
        val nights = (diff / millisPerNight).toInt()
        return max(1, nights)
    }
}
