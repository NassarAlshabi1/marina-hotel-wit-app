package com.marinahotel.kotlin.domain.model

data class Guest(
    val id: Int = 0,
    val name: String,
    val idType: String,
    val idNumber: String,
    val phone: String,
    val nationality: String?,
    val createdAt: Long
)

data class Room(
    val number: String,
    val type: String,
    val price: Int,
    val status: RoomStatus = RoomStatus.VACANT
)

data class Booking(
    val id: Int = 0,
    val guestId: Int? = null,
    val roomNumber: String,
    val checkinDate: Long,
    val checkoutDate: Long? = null,
    val status: BookingStatus = BookingStatus.RESERVED,
    val notes: String? = null,
    val calculatedNights: Int = 1
)

data class Payment(
    val id: Int = 0,
    val bookingId: Int,
    val amount: Int,
    val paymentDate: Long,
    val paymentMethod: String,
    val notes: String? = null
)

data class BookingNote(
    val id: Int = 0,
    val bookingId: Int,
    val text: String,
    val alertType: AlertLevel = AlertLevel.MEDIUM,
    val alertUntil: Long? = null,
    val isActive: Boolean = true
)

data class Expense(
    val id: Int = 0,
    val expenseType: String,
    val description: String,
    val amount: Int,
    val date: Long,
    val relatedSupplierId: Int? = null
)

data class BookingSummary(
    val booking: Booking,
    val guest: Guest,
    val room: Room,
    val payments: List<Payment>
)

enum class RoomStatus(val value: String) {
    VACANT("شاغرة"),
    RESERVED("محجوزة"),
    MAINTENANCE("صيانة")
}

enum class BookingStatus(val value: String) {
    RESERVED("محجوزة"),
    COMPLETED("مكتملة"),
    CANCELLED("ملغاة")
}

enum class AlertLevel(val value: String) {
    HIGH("عالي"),
    MEDIUM("متوسط"),
    LOW("منخفض")
}
