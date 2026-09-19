package com.marina.marina.data.mapper

import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.BookingNoteEntity
import com.marina.marina.data.local.entity.DebtEntity
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.ExpenseEntity
import com.marina.marina.data.local.entity.PaymentEntity
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.local.entity.ShiftNoteEntity
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.BookingNote
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.model.ShiftNote

/**
 * Entity <-> domain-model mappers. These are the only place Room's
 * [com.marina.marina.data.local.entity] types are allowed to turn into the
 * plain Kotlin models the domain/presentation layers work with, and back.
 */

fun RoomEntity.toDomain(): Room = Room(
    id = id,
    roomNumber = roomNumber,
    type = type,
    price = price,
    status = status,
    imageUrl = imageUrl,
    cleaningStatus = cleaningStatus,
    lastCleanedHotelDay = lastCleanedHotelDay,
    lastOccupiedHotelDay = lastOccupiedHotelDay,
    requiresMaintenance = requiresMaintenance,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun Room.toEntity(): RoomEntity = RoomEntity(
    id = id,
    roomNumber = roomNumber,
    type = type,
    price = price,
    status = status,
    imageUrl = imageUrl,
    cleaningStatus = cleaningStatus,
    lastCleanedHotelDay = lastCleanedHotelDay,
    lastOccupiedHotelDay = lastOccupiedHotelDay,
    requiresMaintenance = requiresMaintenance,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun BookingEntity.toDomain(): Booking = Booking(
    id = id,
    serverBookingId = serverBookingId,
    roomNumber = roomNumber,
    guestName = guestName,
    guestPhone = guestPhone,
    guestIdType = guestIdType,
    guestIdNumber = guestIdNumber,
    guestIdIssueDate = guestIdIssueDate,
    guestIdIssuePlace = guestIdIssuePlace,
    guestNationality = guestNationality,
    guestEmail = guestEmail,
    guestAddress = guestAddress,
    checkinDate = checkinDate,
    checkoutDate = checkoutDate,
    actualCheckout = actualCheckout,
    status = status,
    notes = notes,
    discount = discount,
    discountType = discountType,
    discountStartDate = discountStartDate,
    expectedNights = expectedNights,
    calculatedNights = calculatedNights,
    totalNightsCached = totalNightsCached,
    isOverdue = isOverdue,
    needsCheckoutReview = needsCheckoutReview,
    totalDueCached = totalDueCached,
    totalPaidCached = totalPaidCached,
    remainingBalanceCached = remainingBalanceCached,
    isFullyPaid = isFullyPaid,
    hotelDayCheckin = hotelDayCheckin,
    hotelDayCheckout = hotelDayCheckout,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun Booking.toEntity(): BookingEntity = BookingEntity(
    id = id,
    serverBookingId = serverBookingId,
    roomNumber = roomNumber,
    guestName = guestName,
    guestPhone = guestPhone,
    guestIdType = guestIdType,
    guestIdNumber = guestIdNumber,
    guestIdIssueDate = guestIdIssueDate,
    guestIdIssuePlace = guestIdIssuePlace,
    guestNationality = guestNationality,
    guestEmail = guestEmail,
    guestAddress = guestAddress,
    checkinDate = checkinDate,
    checkoutDate = checkoutDate,
    actualCheckout = actualCheckout,
    status = status,
    notes = notes,
    discount = discount,
    discountType = discountType,
    discountStartDate = discountStartDate,
    expectedNights = expectedNights,
    calculatedNights = calculatedNights,
    totalNightsCached = totalNightsCached,
    isOverdue = isOverdue,
    needsCheckoutReview = needsCheckoutReview,
    totalDueCached = totalDueCached,
    totalPaidCached = totalPaidCached,
    remainingBalanceCached = remainingBalanceCached,
    isFullyPaid = isFullyPaid,
    hotelDayCheckin = hotelDayCheckin,
    hotelDayCheckout = hotelDayCheckout,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun PaymentEntity.toDomain(): Payment = Payment(
    id = id,
    bookingLocalId = bookingLocalId,
    roomNumber = roomNumber,
    amount = amount,
    paymentDate = paymentDate,
    paymentMethod = paymentMethod,
    revenueType = revenueType,
    notes = notes,
    referenceNumber = referenceNumber,
    hotelDayKey = hotelDayKey,
    isPendingBalance = isPendingBalance,
    isVoided = isVoided,
    voidedAt = voidedAt,
    voidedBy = voidedBy,
    voidReason = voidReason,
    receivedByName = receivedByName,
    receivedByUserId = receivedByUserId,
    receivedSessionUuid = receivedSessionUuid,
    receivedByCloudId = receivedByCloudId,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun Payment.toEntity(): PaymentEntity = PaymentEntity(
    id = id,
    bookingLocalId = bookingLocalId,
    roomNumber = roomNumber,
    amount = amount,
    paymentDate = paymentDate,
    paymentMethod = paymentMethod,
    revenueType = revenueType,
    notes = notes,
    referenceNumber = referenceNumber,
    hotelDayKey = hotelDayKey,
    isPendingBalance = isPendingBalance,
    isVoided = isVoided,
    voidedAt = voidedAt,
    voidedBy = voidedBy,
    voidReason = voidReason,
    receivedByName = receivedByName,
    receivedByUserId = receivedByUserId,
    receivedSessionUuid = receivedSessionUuid,
    receivedByCloudId = receivedByCloudId,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun EmployeeEntity.toDomain(): Employee = Employee(
    id = id,
    name = name,
    basicSalary = basicSalary,
    position = position,
    phone = phone,
    hireDate = hireDate,
    status = status,
    terminationDate = terminationDate,
    terminationReason = terminationReason,
    employeeID = employeeID,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun Employee.toEntity(): EmployeeEntity = EmployeeEntity(
    id = id,
    name = name,
    basicSalary = basicSalary,
    position = position,
    phone = phone,
    hireDate = hireDate,
    status = status,
    terminationDate = terminationDate,
    terminationReason = terminationReason,
    employeeID = employeeID,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun ExpenseEntity.toDomain(): Expense = Expense(
    id = id,
    expenseType = expenseType,
    relatedId = relatedId,
    description = description,
    amount = amount,
    date = date,
    hotelDayKey = hotelDayKey,
    categoryUuid = categoryUuid,
    isAutoGenerated = isAutoGenerated,
    employeeUuid = employeeUuid,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun Expense.toEntity(): ExpenseEntity = ExpenseEntity(
    id = id,
    expenseType = expenseType,
    relatedId = relatedId,
    description = description,
    amount = amount,
    date = date,
    hotelDayKey = hotelDayKey,
    categoryUuid = categoryUuid,
    isAutoGenerated = isAutoGenerated,
    employeeUuid = employeeUuid,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun DebtEntity.toDomain(): Debt = Debt(
    id = id,
    bookingLocalId = bookingLocalId,
    guestName = guestName,
    guestPhone = guestPhone,
    checkinDate = checkinDate,
    checkoutDate = checkoutDate,
    dateRecorded = dateRecorded,
    debtReason = debtReason,
    totalAmount = totalAmount,
    paidAmount = paidAmount,
    remainingAmount = remainingAmount,
    paymentDate = paymentDate,
    isSettled = isSettled == 1,
    note = note,
    hotelDayOpened = hotelDayOpened,
    hotelDayClosed = hotelDayClosed,
    isFromAutoFix = isFromAutoFix,
    settlementConfirmed = settlementConfirmed,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun Debt.toEntity(): DebtEntity = DebtEntity(
    id = id,
    bookingLocalId = bookingLocalId,
    guestName = guestName,
    guestPhone = guestPhone,
    checkinDate = checkinDate,
    checkoutDate = checkoutDate,
    dateRecorded = dateRecorded,
    debtReason = debtReason,
    totalAmount = totalAmount,
    paidAmount = paidAmount,
    remainingAmount = remainingAmount,
    paymentDate = paymentDate,
    isSettled = if (isSettled) 1 else 0,
    note = note,
    hotelDayOpened = hotelDayOpened,
    hotelDayClosed = hotelDayClosed,
    isFromAutoFix = isFromAutoFix,
    settlementConfirmed = settlementConfirmed,
    localUuid = localUuid,
    serverId = serverId,
    createdAt = createdAt,
    updatedAt = updatedAt,
    deletedAt = deletedAt,
    version = version
)

fun BookingNoteEntity.toDomain(): BookingNote = BookingNote(
    id = id,
    bookingId = bookingId,
    noteText = noteText,
    alertType = alertType,
    alertUntil = alertUntil,
    isActive = isActive == 1,
    localUuid = localUuid,
    createdAt = createdAt,
    updatedAt = updatedAt
)

fun BookingNote.toEntity(): BookingNoteEntity = BookingNoteEntity(
    id = id,
    bookingId = bookingId,
    noteText = noteText,
    alertType = alertType,
    alertUntil = alertUntil,
    isActive = if (isActive) 1 else 0,
    localUuid = localUuid,
    createdAt = createdAt,
    updatedAt = updatedAt
)

fun ShiftNoteEntity.toDomain(): ShiftNote = ShiftNote(
    id = id,
    title = title,
    content = content,
    priority = priority,
    shiftType = shiftType,
    isRead = isRead == 1,
    expiresAt = expiresAt,
    createdBy = createdBy,
    localUuid = localUuid,
    createdAt = createdAt
)

fun ShiftNote.toEntity(): ShiftNoteEntity = ShiftNoteEntity(
    id = id,
    title = title,
    content = content,
    priority = priority,
    shiftType = shiftType,
    isRead = if (isRead) 1 else 0,
    expiresAt = expiresAt,
    createdBy = createdBy,
    localUuid = localUuid,
    createdAt = createdAt
)
