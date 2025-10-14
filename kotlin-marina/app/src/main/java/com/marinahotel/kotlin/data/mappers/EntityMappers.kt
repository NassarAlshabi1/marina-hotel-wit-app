package com.marinahotel.kotlin.data.mappers

import com.marinahotel.kotlin.data.db.BookingDetails
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.entities.BookingNoteEntity
import com.marinahotel.kotlin.data.entities.ExpenseEntity
import com.marinahotel.kotlin.data.entities.GuestEntity
import com.marinahotel.kotlin.data.entities.PaymentEntity
import com.marinahotel.kotlin.data.entities.RoomEntity
import com.marinahotel.kotlin.domain.model.AlertLevel
import com.marinahotel.kotlin.domain.model.Booking
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.BookingSummary
import com.marinahotel.kotlin.domain.model.BookingNote
import com.marinahotel.kotlin.domain.model.Expense
import com.marinahotel.kotlin.domain.model.Guest
import com.marinahotel.kotlin.domain.model.Payment
import com.marinahotel.kotlin.domain.model.Room
import com.marinahotel.kotlin.domain.model.RoomStatus

fun GuestEntity.toDomain(): Guest = Guest(
    id = guestId,
    name = guestName,
    idType = guestIdType,
    idNumber = guestIdNumber,
    phone = guestPhone,
    nationality = guestNationality,
    createdAt = createdAt
)

fun Guest.toEntity(): GuestEntity = GuestEntity(
    guestId = id,
    guestName = name,
    guestIdType = idType,
    guestIdNumber = idNumber,
    guestPhone = phone,
    guestNationality = nationality,
    createdAt = createdAt
)

fun RoomEntity.toDomain(): Room = Room(
    number = roomNumber,
    type = type,
    price = price,
    status = RoomStatus.values().firstOrNull { it.value == status } ?: RoomStatus.VACANT
)

fun Room.toEntity(): RoomEntity = RoomEntity(
    roomNumber = number,
    type = type,
    price = price,
    status = status.value
)

fun BookingEntity.toDomain(): Booking = Booking(
    id = bookingId,
    guestId = guestId,
    roomNumber = roomNumber,
    checkinDate = checkinDate,
    checkoutDate = checkoutDate,
    status = BookingStatus.values().firstOrNull { it.value == status } ?: BookingStatus.RESERVED,
    notes = notes,
    calculatedNights = calculatedNights
)

fun Booking.toEntity(resolvedGuestId: Int): BookingEntity = BookingEntity(
    bookingId = id,
    guestId = resolvedGuestId,
    roomNumber = roomNumber,
    checkinDate = checkinDate,
    checkoutDate = checkoutDate,
    status = status.value,
    notes = notes,
    calculatedNights = calculatedNights
)

fun PaymentEntity.toDomain(): Payment = Payment(
    id = paymentId,
    bookingId = bookingId,
    amount = amount,
    paymentDate = paymentDate,
    paymentMethod = paymentMethod,
    notes = notes
)

fun Payment.toEntity(): PaymentEntity = PaymentEntity(
    paymentId = id,
    bookingId = bookingId,
    amount = amount,
    paymentDate = paymentDate,
    paymentMethod = paymentMethod,
    notes = notes
)

fun BookingNoteEntity.toDomain(): BookingNote = BookingNote(
    id = noteId,
    bookingId = bookingId,
    text = noteText,
    alertType = AlertLevel.values().firstOrNull { it.value == alertType } ?: AlertLevel.MEDIUM,
    alertUntil = alertUntil,
    isActive = isActive
)

fun BookingNote.toEntity(): BookingNoteEntity = BookingNoteEntity(
    noteId = id,
    bookingId = bookingId,
    noteText = text,
    alertType = alertType.value,
    alertUntil = alertUntil,
    isActive = isActive
)

fun ExpenseEntity.toDomain(): Expense = Expense(
    id = expenseId,
    expenseType = expenseType,
    description = description,
    amount = amount,
    date = date,
    relatedSupplierId = relatedSupplierId
)

fun Expense.toEntity(): ExpenseEntity = ExpenseEntity(
    expenseId = id,
    expenseType = expenseType,
    description = description,
    amount = amount,
    date = date,
    relatedSupplierId = relatedSupplierId
)

fun BookingDetails.toSummary(): BookingSummary = BookingSummary(
    booking = booking.toDomain(),
    guest = guest.toDomain(),
    room = room.toDomain(),
    payments = payments.map { it.toDomain() }
)
