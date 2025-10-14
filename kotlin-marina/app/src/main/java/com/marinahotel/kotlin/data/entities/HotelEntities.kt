package com.marinahotel.kotlin.data.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "guests",
    indices = [Index(value = ["guest_phone"], unique = true)]
)
data class GuestEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "guest_id")
    val guestId: Int = 0,

    @ColumnInfo(name = "guest_name")
    val guestName: String,

    @ColumnInfo(name = "guest_id_type")
    val guestIdType: String,

    @ColumnInfo(name = "guest_id_number")
    val guestIdNumber: String,

    @ColumnInfo(name = "guest_phone")
    val guestPhone: String,

    @ColumnInfo(name = "guest_nationality")
    val guestNationality: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: Long
)

@Entity(
    tableName = "rooms",
    indices = [Index(value = ["status"])]
)
data class RoomEntity(
    @PrimaryKey
    @ColumnInfo(name = "room_number")
    val roomNumber: String,

    @ColumnInfo(name = "type")
    val type: String,

    @ColumnInfo(name = "price")
    val price: Int,

    @ColumnInfo(name = "status")
    val status: String = "شاغرة"
)

@Entity(
    tableName = "bookings",
    foreignKeys = [
        ForeignKey(
            entity = GuestEntity::class,
            parentColumns = ["guest_id"],
            childColumns = ["guest_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = RoomEntity::class,
            parentColumns = ["room_number"],
            childColumns = ["room_number"],
            onDelete = ForeignKey.RESTRICT
        )
    ],
    indices = [
        Index("guest_id"),
        Index("room_number"),
        Index("status"),
        Index("checkin_date")
    ]
)
data class BookingEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "booking_id")
    val bookingId: Int = 0,

    @ColumnInfo(name = "guest_id")
    val guestId: Int,

    @ColumnInfo(name = "room_number")
    val roomNumber: String,

    @ColumnInfo(name = "checkin_date")
    val checkinDate: Long,

    @ColumnInfo(name = "checkout_date")
    val checkoutDate: Long?,

    @ColumnInfo(name = "status")
    val status: String,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "calculated_nights", defaultValue = "1")
    val calculatedNights: Int = 1
)

@Entity(
    tableName = "payments",
    foreignKeys = [
        ForeignKey(
            entity = BookingEntity::class,
            parentColumns = ["booking_id"],
            childColumns = ["booking_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("booking_id"),
        Index("payment_date")
    ]
)
data class PaymentEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "payment_id")
    val paymentId: Int = 0,

    @ColumnInfo(name = "booking_id")
    val bookingId: Int,

    @ColumnInfo(name = "amount")
    val amount: Int,

    @ColumnInfo(name = "payment_date")
    val paymentDate: Long,

    @ColumnInfo(name = "payment_method")
    val paymentMethod: String,

    @ColumnInfo(name = "notes")
    val notes: String?
)

@Entity(
    tableName = "booking_notes",
    foreignKeys = [
        ForeignKey(
            entity = BookingEntity::class,
            parentColumns = ["booking_id"],
            childColumns = ["booking_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("booking_id")]
)
data class BookingNoteEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "note_id")
    val noteId: Int = 0,

    @ColumnInfo(name = "booking_id")
    val bookingId: Int,

    @ColumnInfo(name = "note_text")
    val noteText: String,

    @ColumnInfo(name = "alert_type")
    val alertType: String = "متوسط",

    @ColumnInfo(name = "alert_until")
    val alertUntil: Long?,

    @ColumnInfo(name = "is_active", defaultValue = "1")
    val isActive: Boolean = true
)

@Entity(
    tableName = "expenses",
    indices = [Index("date")]
)
data class ExpenseEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "expense_id")
    val expenseId: Int = 0,

    @ColumnInfo(name = "expense_type")
    val expenseType: String,

    @ColumnInfo(name = "description")
    val description: String,

    @ColumnInfo(name = "amount")
    val amount: Int,

    @ColumnInfo(name = "date")
    val date: Long,

    @ColumnInfo(name = "related_supplier_id")
    val relatedSupplierId: Int?
)
