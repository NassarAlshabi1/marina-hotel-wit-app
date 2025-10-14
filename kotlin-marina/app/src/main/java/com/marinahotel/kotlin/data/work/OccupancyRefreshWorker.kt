package com.marinahotel.kotlin.data.work

import android.content.Context
import androidx.room.withTransaction
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.marinahotel.kotlin.data.db.HotelDatabase
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.math.max

class OccupancyRefreshWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    private val locale = Locale("ar")
    private val dateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy", locale)
    private val timestampFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm", locale)

    override suspend fun doWork(): Result = try {
        val database = HotelDatabase.getInstance(applicationContext)
        val bookingDao = database.bookingDao()
        val roomDao = database.roomDao()
        val today = LocalDate.now()

        val reservedBookings = bookingDao.getByStatus(STATUS_RESERVED)
        val overdueBookings = reservedBookings.filter { booking ->
            val checkout = booking.checkoutDate?.let(::parseDate)
            checkout != null && checkout.isBefore(today)
        }

        if (overdueBookings.isEmpty()) {
            Result.success()
        } else {
            database.withTransaction {
                overdueBookings.forEach { booking ->
                    val originalCheckout = booking.checkoutDate?.let(::parseDate)
                    val effectiveCheckout = originalCheckout ?: today
                    val checkinDate = parseDate(booking.checkinDate) ?: effectiveCheckout
                    val nights = computeNights(checkinDate, effectiveCheckout)
                    val formattedCheckout = formatDate(effectiveCheckout)
                    val updated = booking.copy(
                        status = STATUS_COMPLETED,
                        checkoutDate = formattedCheckout,
                        actualCheckout = formattedCheckout,
                        calculatedNights = nights,
                        lastCalculation = formatTimestamp(LocalDateTime.now())
                    )
                    bookingDao.update(updated)
                    roomDao.updateStatus(booking.roomNumber, STATUS_VACANT)
                }
            }
            Result.success()
        }
    } catch (exception: Exception) {
        Result.retry()
    }

    private fun parseDate(value: String): LocalDate? = try {
        LocalDate.parse(value, dateFormatter)
    } catch (ex: DateTimeParseException) {
        null
    }

    private fun formatDate(date: LocalDate): String = date.format(dateFormatter)

    private fun formatTimestamp(dateTime: LocalDateTime): String = dateTime.format(timestampFormatter)

    private fun computeNights(checkin: LocalDate, checkout: LocalDate): Int {
        val diff = ChronoUnit.DAYS.between(checkin, checkout).toInt()
        return max(1, diff)
    }

    companion object {
        private const val STATUS_RESERVED = "محجوزة"
        private const val STATUS_COMPLETED = "مكتملة"
        private const val STATUS_VACANT = "شاغرة"
    }
}
