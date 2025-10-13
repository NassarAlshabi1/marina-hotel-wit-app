package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.BookingDao
import com.marinahotel.kotlin.data.db.BookingWithGuest
import com.marinahotel.kotlin.data.db.GuestDao
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.entities.GuestEntity
import kotlinx.coroutines.flow.Flow

class BookingRepository(
    private val bookingDao: BookingDao,
    private val guestDao: GuestDao
) {
    suspend fun getBookingDraftById(id: Int): BookingDraft? {
        val result = bookingDao.getWithGuestById(id) ?: return null
        return result.toDraft()
    }

    fun flowAllBookingsWithGuests(): Flow<List<BookingWithGuest>> = bookingDao.flowAllWithGuest()

    fun flowAllGuests(): Flow<List<GuestEntity>> = guestDao.flowAll()

    fun flowCountByStatus(status: String): Flow<Int> = bookingDao.flowCountByStatus(status)

    suspend fun saveBooking(draft: BookingDraft): Int {
        val existingGuest = draft.guestId?.let { guestDao.getById(it) } ?: guestDao.findByPhone(draft.guestPhone)
        val guestId = existingGuest?.guestId ?: 0
        val guestCreatedAt = existingGuest?.createdAt ?: draft.guestCreatedAt
        val guestEntity = GuestEntity(
            guestId = guestId,
            guestName = draft.guestName,
            guestIdType = draft.guestIdType,
            guestIdNumber = draft.guestIdNumber,
            guestIdIssueDate = draft.guestIdIssueDate,
            guestIdIssuePlace = draft.guestIdIssuePlace,
            guestPhone = draft.guestPhone,
            guestNationality = draft.guestNationality,
            guestEmail = draft.guestEmail,
            guestAddress = draft.guestAddress,
            createdAt = guestCreatedAt
        )
        val persistedGuestId = guestDao.insert(guestEntity).toInt().takeIf { guestId == 0 } ?: guestId

        val bookingEntity = BookingEntity(
            bookingId = draft.bookingId,
            guestId = persistedGuestId,
            roomNumber = draft.roomNumber,
            checkinDate = draft.checkinDate,
            checkoutDate = draft.checkoutDate,
            status = draft.status,
            notes = draft.notes,
            createdAt = draft.createdAt,
            expectedNights = draft.expectedNights,
            actualCheckout = draft.actualCheckout,
            calculatedNights = draft.calculatedNights,
            lastCalculation = draft.lastCalculation
        )

        return if (draft.bookingId == 0) {
            bookingDao.insert(bookingEntity).toInt()
        } else {
            val updated = bookingDao.update(bookingEntity)
            if (updated == 0) {
                bookingDao.insert(bookingEntity).toInt()
            } else {
                draft.bookingId
            }
        }
    }

    private fun BookingWithGuest.toDraft(): BookingDraft {
        return BookingDraft(
            bookingId = booking.bookingId,
            guestId = guest.guestId,
            guestName = guest.guestName,
            guestIdType = guest.guestIdType,
            guestIdNumber = guest.guestIdNumber,
            guestIdIssueDate = guest.guestIdIssueDate,
            guestIdIssuePlace = guest.guestIdIssuePlace,
            guestPhone = guest.guestPhone.orEmpty(),
            guestNationality = guest.guestNationality,
            guestEmail = guest.guestEmail,
            guestAddress = guest.guestAddress,
            guestCreatedAt = guest.createdAt,
            roomNumber = booking.roomNumber,
            checkinDate = booking.checkinDate,
            checkoutDate = booking.checkoutDate,
            status = booking.status,
            notes = booking.notes,
            createdAt = booking.createdAt,
            expectedNights = booking.expectedNights,
            actualCheckout = booking.actualCheckout,
            calculatedNights = booking.calculatedNights,
            lastCalculation = booking.lastCalculation
        )
    }
}

data class BookingDraft(
    val bookingId: Int = 0,
    val guestId: Int? = null,
    val guestName: String,
    val guestIdType: String?,
    val guestIdNumber: String?,
    val guestIdIssueDate: String?,
    val guestIdIssuePlace: String?,
    val guestPhone: String,
    val guestNationality: String?,
    val guestEmail: String?,
    val guestAddress: String?,
    val guestCreatedAt: String,
    val roomNumber: String,
    val checkinDate: String,
    val checkoutDate: String?,
    val status: String,
    val notes: String?,
    val createdAt: String,
    val expectedNights: Int,
    val actualCheckout: String?,
    val calculatedNights: Int,
    val lastCalculation: String
)
