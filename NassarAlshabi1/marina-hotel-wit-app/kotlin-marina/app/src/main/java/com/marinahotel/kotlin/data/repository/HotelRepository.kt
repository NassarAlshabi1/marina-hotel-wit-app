package com.marinahotel.kotlin.data.repository

import androidx.room.withTransaction
import com.marinahotel.kotlin.data.db.BookingDao
import com.marinahotel.kotlin.data.db.BookingNoteDao
import com.marinahotel.kotlin.data.db.ExpenseDao
import com.marinahotel.kotlin.data.db.GuestDao
import com.marinahotel.kotlin.data.db.HotelDatabase
import com.marinahotel.kotlin.data.db.PaymentDao
import com.marinahotel.kotlin.data.db.ReportingDao
import com.marinahotel.kotlin.data.db.RoomDao
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.mappers.toDomain
import com.marinahotel.kotlin.data.mappers.toEntity
import com.marinahotel.kotlin.data.mappers.toSummary
import com.marinahotel.kotlin.domain.model.AlertLevel
import com.marinahotel.kotlin.domain.model.Booking
import com.marinahotel.kotlin.domain.model.BookingNote
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.BookingSummary
import com.marinahotel.kotlin.domain.model.Expense
import com.marinahotel.kotlin.domain.model.Guest
import com.marinahotel.kotlin.domain.model.Payment
import com.marinahotel.kotlin.domain.model.Room
import com.marinahotel.kotlin.domain.model.RoomStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlin.math.max

class HotelRepository(
    private val database: HotelDatabase,
    private val guestDao: GuestDao,
    private val roomDao: RoomDao,
    private val bookingDao: BookingDao,
    private val paymentDao: PaymentDao,
    private val bookingNoteDao: BookingNoteDao,
    private val expenseDao: ExpenseDao,
    private val reportingDao: ReportingDao
) {

    suspend fun authenticate(username: String, password: String): Boolean {
        val validUsers = mapOf(
            "admin" to "admin123",
            "reception" to "reception123"
        )
        return validUsers[username] == password
    }

    fun observeGuests(): Flow<List<Guest>> = guestDao.observeGuests().map { guests ->
        guests.map { it.toDomain() }
    }

    suspend fun findGuestByPhone(phone: String): Guest? = guestDao.findGuestByPhone(phone)?.toDomain()

    fun observeRooms(): Flow<List<Room>> = roomDao.observeRooms().map { rooms ->
        rooms.map { it.toDomain() }
    }

    fun observeRoomsByStatus(status: RoomStatus): Flow<List<Room>> =
        roomDao.observeRoomsByStatus(status.value).map { rooms -> rooms.map { it.toDomain() } }

    fun observeAvailableRooms(): Flow<List<Room>> =
        roomDao.observeAvailableRooms().map { rooms -> rooms.map { it.toDomain() } }

    fun observeBookings(): Flow<List<BookingSummary>> =
        bookingDao.observeBookingsWithDetails().map { list -> list.map { it.toSummary() } }

    fun observeBookingDetails(bookingId: Int): Flow<BookingSummary?> =
        bookingDao.observeBookingDetails(bookingId).map { it?.toSummary() }

    fun observeBookingsByStatus(status: BookingStatus): Flow<List<BookingSummary>> =
        reportingDao.observeBookingsByStatus(status.value).map { list -> list.map { it.toSummary() } }

    fun observeBookingCountByStatus(status: BookingStatus): Flow<Int> =
        bookingDao.observeBookingCountByStatus(status.value)

    fun observePayments(bookingId: Int): Flow<List<Payment>> =
        paymentDao.observePaymentsByBooking(bookingId).map { items -> items.map { it.toDomain() } }

    fun observePaymentsBetween(from: Long, to: Long): Flow<List<Payment>> =
        paymentDao.observePaymentsBetween(from, to).map { items -> items.map { it.toDomain() } }

    fun observeTotalPaidForBooking(bookingId: Int): Flow<Int> =
        paymentDao.observeTotalPaidForBooking(bookingId).map { it ?: 0 }

    fun observeNotesForBooking(bookingId: Int): Flow<List<BookingNote>> =
        bookingNoteDao.observeNotesForBooking(bookingId).map { notes -> notes.map { it.toDomain() } }

    fun observeActiveAlerts(): Flow<List<BookingNote>> =
        bookingNoteDao.observeActiveNotes().map { notes -> notes.map { it.toDomain() } }

    fun observeExpenses(): Flow<List<Expense>> =
        expenseDao.observeExpenses().map { expenses -> expenses.map { it.toDomain() } }

    fun observeExpensesBetween(from: Long, to: Long): Flow<List<Expense>> =
        expenseDao.observeExpensesBetween(from, to).map { expenses -> expenses.map { it.toDomain() } }

    fun observeExpenseTotalBetween(from: Long, to: Long): Flow<Int> =
        expenseDao.observeExpenseTotalBetween(from, to).map { it ?: 0 }

    suspend fun createBooking(guest: Guest, booking: Booking): Int {
        val now = System.currentTimeMillis()
        val guestToPersist = if (guest.createdAt == 0L) guest.copy(createdAt = now) else guest
        return database.withTransaction {
            validateRoomIsVacant(booking.roomNumber)

            val existingGuest = guestDao.findGuestByPhone(guestToPersist.phone)
            val resolvedGuestId = existingGuest?.guestId
                ?: guestDao.insert(guestToPersist.toEntity()).toInt()

            val bookingId = bookingDao.insert(booking.toEntity(resolvedGuestId)).toInt()
            roomDao.updateRoomStatus(booking.roomNumber, RoomStatus.RESERVED.value)
            bookingId
        }
    }

    suspend fun updateBooking(guest: Guest, booking: Booking) {
        database.withTransaction {
            val guestId = upsertGuestInternal(guest)
            val current = bookingDao.getBookingById(booking.id)
                ?: throw IllegalArgumentException("Booking ${booking.id} not found")
            if (current.roomNumber != booking.roomNumber) {
                validateRoomIsVacant(booking.roomNumber)
                roomDao.updateRoomStatus(current.roomNumber, RoomStatus.VACANT.value)
                roomDao.updateRoomStatus(booking.roomNumber, RoomStatus.RESERVED.value)
            }
            bookingDao.update(booking.toEntity(guestId))
        }
    }

    private suspend fun upsertGuestInternal(guest: Guest): Int {
        val entity = guest.toEntity()
        return if (entity.guestId == 0) {
            guestDao.insert(entity).toInt()
        } else {
            guestDao.update(entity)
            entity.guestId
        }
    }

    suspend fun cancelBooking(bookingId: Int) {
        database.withTransaction {
            val booking = bookingDao.getBookingById(bookingId) ?: return@withTransaction
            bookingDao.update(booking.copy(status = BookingStatus.CANCELLED.value))
            roomDao.updateRoomStatus(booking.roomNumber, RoomStatus.VACANT.value)
        }
    }

    suspend fun checkOut(bookingId: Int, checkoutTimestamp: Long = System.currentTimeMillis()) {
        database.withTransaction {
            val booking = bookingDao.getBookingById(bookingId)
                ?: throw IllegalArgumentException("Booking $bookingId not found")

            val nights = computeNights(booking.checkinDate, checkoutTimestamp)
            val updated = BookingEntity(
                bookingId = booking.bookingId,
                guestId = booking.guestId,
                roomNumber = booking.roomNumber,
                checkinDate = booking.checkinDate,
                checkoutDate = checkoutTimestamp,
                status = BookingStatus.COMPLETED.value,
                notes = booking.notes,
                calculatedNights = nights
            )
            bookingDao.update(updated)
            roomDao.updateRoomStatus(booking.roomNumber, RoomStatus.VACANT.value)
        }
    }

    suspend fun addPayment(payment: Payment): Int =
        paymentDao.insert(payment.toEntity()).toInt()

    suspend fun updatePayment(payment: Payment) {
        paymentDao.update(payment.toEntity())
    }

    suspend fun deletePayment(payment: Payment) {
        paymentDao.delete(payment.toEntity())
    }

    suspend fun addBookingNote(note: BookingNote): Int =
        bookingNoteDao.insert(note.toEntity()).toInt()

    suspend fun updateBookingNote(note: BookingNote) {
        bookingNoteDao.update(note.toEntity())
    }

    suspend fun deleteBookingNote(note: BookingNote) {
        bookingNoteDao.delete(note.toEntity())
    }

    suspend fun addExpense(expense: Expense): Int =
        expenseDao.insert(expense.toEntity()).toInt()

    suspend fun updateExpense(expense: Expense) {
        expenseDao.update(expense.toEntity())
    }

    suspend fun deleteExpense(expense: Expense) {
        expenseDao.delete(expense.toEntity())
    }

    suspend fun updateRoom(room: Room) {
        roomDao.update(room.toEntity())
    }

    suspend fun saveRoom(room: Room) {
        roomDao.insert(room.toEntity())
    }

    private suspend fun validateRoomIsVacant(roomNumber: String) {
        val room = roomDao.getRoom(roomNumber) ?: throw IllegalArgumentException("Room $roomNumber not found")
        if (room.status != RoomStatus.VACANT.value) {
            throw IllegalStateException("Room $roomNumber is not available")
        }
    }

    private fun computeNights(checkin: Long, checkout: Long): Int {
        val millisPerNight = 86_400_000L
        val diff = max(0L, checkout - checkin)
        val nights = (diff / millisPerNight).toInt()
        return max(1, nights)
    }

    suspend fun setRoomStatus(roomNumber: String, status: RoomStatus) {
        roomDao.updateRoomStatus(roomNumber, status.value)
    }

    suspend fun getRoom(roomNumber: String): Room? = roomDao.getRoom(roomNumber)?.toDomain()

    suspend fun getBooking(id: Int): Booking? = bookingDao.getBookingById(id)?.toDomain()

    suspend fun upsertGuest(guest: Guest): Int = upsertGuestInternal(guest)

    fun observeAlertsByLevel(level: AlertLevel): Flow<List<BookingNote>> =
        bookingNoteDao.observeActiveNotes().map { notes ->
            notes.filter { it.alertType == level.value }.map { it.toDomain() }
        }
}
