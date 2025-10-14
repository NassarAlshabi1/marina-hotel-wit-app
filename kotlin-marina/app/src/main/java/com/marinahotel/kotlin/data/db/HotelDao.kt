package com.marinahotel.kotlin.data.db

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Update
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.entities.BookingNoteEntity
import com.marinahotel.kotlin.data.entities.ExpenseEntity
import com.marinahotel.kotlin.data.entities.GuestEntity
import com.marinahotel.kotlin.data.entities.PaymentEntity
import com.marinahotel.kotlin.data.entities.RoomEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface GuestDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(guest: GuestEntity): Long

    @Update
    suspend fun update(guest: GuestEntity): Int

    @Delete
    suspend fun delete(guest: GuestEntity): Int

    @Query("SELECT * FROM guests WHERE guest_id = :guestId LIMIT 1")
    suspend fun getGuestById(guestId: Int): GuestEntity?

    @Query("SELECT * FROM guests WHERE guest_phone = :phone LIMIT 1")
    suspend fun findGuestByPhone(phone: String): GuestEntity?

    @Query("SELECT * FROM guests ORDER BY guest_name")
    fun observeGuests(): Flow<List<GuestEntity>>
}

@Dao
interface RoomDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(room: RoomEntity)

    @Update
    suspend fun update(room: RoomEntity): Int

    @Delete
    suspend fun delete(room: RoomEntity): Int

    @Query("SELECT * FROM rooms WHERE room_number = :roomNumber LIMIT 1")
    suspend fun getRoom(roomNumber: String): RoomEntity?

    @Query("SELECT * FROM rooms ORDER BY room_number")
    fun observeRooms(): Flow<List<RoomEntity>>

    @Query("SELECT * FROM rooms WHERE status = :status ORDER BY room_number")
    fun observeRoomsByStatus(status: String): Flow<List<RoomEntity>>

    @Query("SELECT * FROM rooms WHERE status = 'شاغرة' ORDER BY room_number")
    fun observeAvailableRooms(): Flow<List<RoomEntity>>

    @Query("UPDATE rooms SET status = :status WHERE room_number = :roomNumber")
    suspend fun updateRoomStatus(roomNumber: String, status: String): Int
}

@Dao
interface BookingDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(booking: BookingEntity): Long

    @Update
    suspend fun update(booking: BookingEntity): Int

    @Delete
    suspend fun delete(booking: BookingEntity): Int

    @Query("SELECT * FROM bookings WHERE booking_id = :bookingId LIMIT 1")
    suspend fun getBookingById(bookingId: Int): BookingEntity?

    @Transaction
    @Query("SELECT * FROM bookings WHERE booking_id = :bookingId LIMIT 1")
    fun observeBookingWithGuest(bookingId: Int): Flow<BookingWithGuest?>

    @Transaction
    @Query("SELECT * FROM bookings WHERE booking_id = :bookingId LIMIT 1")
    fun observeBookingWithPayments(bookingId: Int): Flow<BookingWithPayments?>

    @Transaction
    @Query("SELECT * FROM bookings ORDER BY checkin_date DESC")
    fun observeBookingsWithGuest(): Flow<List<BookingWithGuest>>

    @Transaction
    @Query("SELECT * FROM bookings ORDER BY checkin_date DESC")
    fun observeBookingsWithDetails(): Flow<List<BookingDetails>>

    @Transaction
    @Query("SELECT * FROM bookings WHERE booking_id = :bookingId LIMIT 1")
    fun observeBookingDetails(bookingId: Int): Flow<BookingDetails?>

    @Query("SELECT COUNT(*) FROM bookings WHERE status = :status")
    fun observeBookingCountByStatus(status: String): Flow<Int>

    @Query("SELECT * FROM bookings WHERE status = :status AND checkout_date IS NOT NULL AND checkout_date < :timestamp")
    suspend fun getBookingsPastCheckout(status: String, timestamp: Long): List<BookingEntity>
}

@Dao
interface PaymentDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(payment: PaymentEntity): Long

    @Update
    suspend fun update(payment: PaymentEntity): Int

    @Delete
    suspend fun delete(payment: PaymentEntity): Int

    @Query("SELECT * FROM payments WHERE booking_id = :bookingId ORDER BY payment_date DESC")
    fun observePaymentsByBooking(bookingId: Int): Flow<List<PaymentEntity>>

    @Query("SELECT SUM(amount) FROM payments WHERE booking_id = :bookingId")
    fun observeTotalPaidForBooking(bookingId: Int): Flow<Int?>

    @Query("SELECT * FROM payments WHERE payment_date BETWEEN :from AND :to ORDER BY payment_date")
    fun observePaymentsBetween(from: Long, to: Long): Flow<List<PaymentEntity>>
}

@Dao
interface BookingNoteDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(note: BookingNoteEntity): Long

    @Update
    suspend fun update(note: BookingNoteEntity): Int

    @Delete
    suspend fun delete(note: BookingNoteEntity): Int

    @Query("SELECT * FROM booking_notes WHERE booking_id = :bookingId ORDER BY note_id DESC")
    fun observeNotesForBooking(bookingId: Int): Flow<List<BookingNoteEntity>>

    @Query("SELECT * FROM booking_notes WHERE is_active = 1 ORDER BY note_id DESC")
    fun observeActiveNotes(): Flow<List<BookingNoteEntity>>
}

@Dao
interface ExpenseDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(expense: ExpenseEntity): Long

    @Update
    suspend fun update(expense: ExpenseEntity): Int

    @Delete
    suspend fun delete(expense: ExpenseEntity): Int

    @Query("SELECT * FROM expenses ORDER BY date DESC")
    fun observeExpenses(): Flow<List<ExpenseEntity>>

    @Query("SELECT * FROM expenses WHERE date BETWEEN :from AND :to ORDER BY date DESC")
    fun observeExpensesBetween(from: Long, to: Long): Flow<List<ExpenseEntity>>

    @Query("SELECT SUM(amount) FROM expenses WHERE date BETWEEN :from AND :to")
    fun observeExpenseTotalBetween(from: Long, to: Long): Flow<Int?>
}

@Dao
interface ReportingDao {
    @Transaction
    @Query("SELECT * FROM bookings WHERE status = :status ORDER BY checkin_date DESC")
    fun observeBookingsByStatus(status: String): Flow<List<BookingDetails>>
}

data class BookingWithGuest(
    @androidx.room.Embedded
    val booking: BookingEntity,
    @androidx.room.Relation(
        parentColumn = "guest_id",
        entityColumn = "guest_id"
    )
    val guest: GuestEntity
)

data class BookingWithPayments(
    @androidx.room.Embedded
    val booking: BookingEntity,
    @androidx.room.Relation(
        parentColumn = "booking_id",
        entityColumn = "booking_id"
    )
    val payments: List<PaymentEntity>
)

data class BookingDetails(
    @androidx.room.Embedded
    val booking: BookingEntity,
    @androidx.room.Relation(
        parentColumn = "guest_id",
        entityColumn = "guest_id"
    )
    val guest: GuestEntity,
    @androidx.room.Relation(
        parentColumn = "room_number",
        entityColumn = "room_number"
    )
    val room: RoomEntity,
    @androidx.room.Relation(
        parentColumn = "booking_id",
        entityColumn = "booking_id"
    )
    val payments: List<PaymentEntity>
)
