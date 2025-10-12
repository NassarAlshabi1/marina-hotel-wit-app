package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.BookingDao
import com.marinahotel.kotlin.data.entities.BookingEntity
import kotlinx.coroutines.flow.Flow

class BookingRepository(private val bookingDao: BookingDao) {
    suspend fun getBookingById(id: Int): BookingEntity? = bookingDao.getById(id)

    suspend fun getAllBookings(): List<BookingEntity> = bookingDao.getAll()

    fun flowAllBookings(): Flow<List<BookingEntity>> = bookingDao.flowAll()

    fun flowDistinctGuests(): Flow<List<String>> = bookingDao.flowDistinctGuests()

    fun flowCountByStatus(status: String): Flow<Int> = bookingDao.flowCountByStatus(status)

    suspend fun saveBooking(entity: BookingEntity): Int {
        return if (entity.bookingId == 0) {
            bookingDao.insert(entity).toInt()
        } else {
            val updated = bookingDao.update(entity)
            if (updated == 0) {
                bookingDao.insert(entity).toInt()
            } else {
                entity.bookingId
            }
        }
    }
}
