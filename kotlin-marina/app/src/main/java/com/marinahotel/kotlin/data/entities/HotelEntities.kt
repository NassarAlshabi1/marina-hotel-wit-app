package com.marinahotel.kotlin.data.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime

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
    val price: BigDecimal,

    @ColumnInfo(name = "status")
    val status: String
)

@Entity(
    tableName = "bookings",
    foreignKeys = [
        ForeignKey(
            entity = RoomEntity::class,
            parentColumns = ["room_number"],
            childColumns = ["room_number"],
            onUpdate = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("status"),
        Index("room_number"),
        Index("guest_name"),
        Index("checkin_date"),
        Index("guest_phone"),
        Index("created_at")
    ]
)
data class BookingEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "booking_id")
    val bookingId: Int = 0,

    @ColumnInfo(name = "guest_id")
    val guestId: Int?,

    @ColumnInfo(name = "guest_name")
    val guestName: String,

    @ColumnInfo(name = "guest_id_type")
    val guestIdType: String,

    @ColumnInfo(name = "guest_id_number")
    val guestIdNumber: String,

    @ColumnInfo(name = "guest_id_issue_date")
    val guestIdIssueDate: LocalDate?,

    @ColumnInfo(name = "guest_id_issue_place")
    val guestIdIssuePlace: String?,

    @ColumnInfo(name = "guest_phone")
    val guestPhone: String,

    @ColumnInfo(name = "guest_nationality")
    val guestNationality: String?,

    @ColumnInfo(name = "guest_email")
    val guestEmail: String?,

    @ColumnInfo(name = "guest_address")
    val guestAddress: String?,

    @ColumnInfo(name = "guest_created_at")
    val guestCreatedAt: Instant,

    @ColumnInfo(name = "room_number")
    val roomNumber: String,

    @ColumnInfo(name = "checkin_date")
    val checkinDate: LocalDateTime,

    @ColumnInfo(name = "checkout_date")
    val checkoutDate: LocalDateTime?,

    @ColumnInfo(name = "status")
    val status: String,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant,

    @ColumnInfo(name = "expected_nights", defaultValue = "1")
    val expectedNights: Int = 1,

    @ColumnInfo(name = "actual_checkout")
    val actualCheckout: LocalDateTime?,

    @ColumnInfo(name = "calculated_nights", defaultValue = "1")
    val calculatedNights: Int = 1,

    @ColumnInfo(name = "last_calculation")
    val lastCalculation: Instant
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
    ]
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
    val alertType: String,

    @ColumnInfo(name = "alert_until")
    val alertUntil: LocalDateTime?,

    @ColumnInfo(name = "is_active", defaultValue = "1")
    val isActive: Boolean = true,

    @ColumnInfo(name = "created_at")
    val createdAt: LocalDateTime,

    @ColumnInfo(name = "created_by")
    val createdBy: String?
)

@Entity(
    tableName = "cash_register",
    indices = [Index(value = ["date"], unique = true)]
)
data class CashRegisterEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "date")
    val date: LocalDate,

    @ColumnInfo(name = "opening_balance")
    val openingBalance: BigDecimal,

    @ColumnInfo(name = "closing_balance")
    val closingBalance: BigDecimal?,

    @ColumnInfo(name = "total_income")
    val totalIncome: BigDecimal,

    @ColumnInfo(name = "total_expense")
    val totalExpense: BigDecimal,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "created_by")
    val createdBy: Int?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant,

    @ColumnInfo(name = "updated_at")
    val updatedAt: Instant,

    @ColumnInfo(name = "status")
    val status: String
)

@Entity(
    tableName = "cash_transactions",
    foreignKeys = [
        ForeignKey(
            entity = CashRegisterEntity::class,
            parentColumns = ["id"],
            childColumns = ["register_id"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class CashTransactionEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "register_id")
    val registerId: Int,

    @ColumnInfo(name = "transaction_type")
    val transactionType: String,

    @ColumnInfo(name = "amount")
    val amount: Int,

    @ColumnInfo(name = "reference_type")
    val referenceType: String,

    @ColumnInfo(name = "reference_id")
    val referenceId: Int?,

    @ColumnInfo(name = "description")
    val description: String?,

    @ColumnInfo(name = "transaction_time")
    val transactionTime: LocalDateTime,

    @ColumnInfo(name = "created_by")
    val createdBy: Int?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant
)

@Entity(tableName = "employees")
data class EmployeeEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "basic_salary")
    val basicSalary: BigDecimal,

    @ColumnInfo(name = "status")
    val status: String
)

@Entity(
    tableName = "expenses",
    indices = [Index("date")],
    foreignKeys = [
        ForeignKey(
            entity = CashTransactionEntity::class,
            parentColumns = ["id"],
            childColumns = ["cash_transaction_id"],
            onDelete = ForeignKey.SET_NULL
        )
    ]
)
data class ExpenseEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "expense_type")
    val expenseType: String,

    @ColumnInfo(name = "related_id")
    val relatedId: Int?,

    @ColumnInfo(name = "description")
    val description: String,

    @ColumnInfo(name = "amount")
    val amount: BigDecimal,

    @ColumnInfo(name = "date")
    val date: LocalDate,

    @ColumnInfo(name = "cash_transaction_id")
    val cashTransactionId: Int?,

    @ColumnInfo(name = "created_by")
    val createdBy: Int?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant
)

@Entity(
    tableName = "expense_logs",
    foreignKeys = [
        ForeignKey(
            entity = ExpenseEntity::class,
            parentColumns = ["id"],
            childColumns = ["expense_id"],
            onDelete = ForeignKey.CASCADE
        )
    ]
)
data class ExpenseLogEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "expense_id")
    val expenseId: Int,

    @ColumnInfo(name = "action")
    val action: String,

    @ColumnInfo(name = "details")
    val details: String?,

    @ColumnInfo(name = "user_id")
    val userId: Int?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant
)

@Entity(tableName = "invoices")
data class InvoiceEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "booking_id")
    val bookingId: Int?,

    @ColumnInfo(name = "No_room")
    val noRoom: Int,

    @ColumnInfo(name = "amount")
    val amount: Int,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant
)

@Entity(
    tableName = "payments",
    foreignKeys = [
        ForeignKey(
            entity = BookingEntity::class,
            parentColumns = ["booking_id"],
            childColumns = ["booking_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = CashTransactionEntity::class,
            parentColumns = ["id"],
            childColumns = ["cash_transaction_id"],
            onDelete = ForeignKey.SET_NULL
        ),
        ForeignKey(
            entity = RoomEntity::class,
            parentColumns = ["room_number"],
            childColumns = ["room_number"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [
        Index("booking_id"),
        Index("room_number"),
        Index("payment_method"),
        Index("revenue_type"),
        Index("payment_date")
    ]
)
data class PaymentEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "booking_id")
    val bookingId: Int?,

    @ColumnInfo(name = "cash_transaction_id")
    val cashTransactionId: Int?,

    @ColumnInfo(name = "room_number")
    val roomNumber: String?,

    @ColumnInfo(name = "amount")
    val amount: BigDecimal,

    @ColumnInfo(name = "payment_method")
    val paymentMethod: String,

    @ColumnInfo(name = "revenue_type")
    val revenueType: String?,

    @ColumnInfo(name = "payment_date")
    val paymentDate: LocalDateTime,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant,

    @ColumnInfo(name = "created_by")
    val createdBy: Int?
)

@Entity(
    tableName = "users",
    indices = [Index(value = ["username"], unique = true)]
)
data class UserEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "user_id")
    val userId: Int = 0,

    @ColumnInfo(name = "username")
    val username: String,

    @ColumnInfo(name = "password")
    val password: String,

    @ColumnInfo(name = "password_hash")
    val passwordHash: String?,

    @ColumnInfo(name = "full_name")
    val fullName: String,

    @ColumnInfo(name = "email")
    val email: String?,

    @ColumnInfo(name = "phone")
    val phone: String?,

    @ColumnInfo(name = "user_type")
    val userType: String,

    @ColumnInfo(name = "is_active", defaultValue = "1")
    val isActive: Boolean = true,

    @ColumnInfo(name = "last_login")
    val lastLogin: LocalDateTime?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant,

    @ColumnInfo(name = "updated_at")
    val updatedAt: Instant,

    @ColumnInfo(name = "failed_login_attempts", defaultValue = "0")
    val failedLoginAttempts: Int = 0,

    @ColumnInfo(name = "locked_until")
    val lockedUntil: LocalDateTime?,

    @ColumnInfo(name = "password_reset_token")
    val passwordResetToken: String?,

    @ColumnInfo(name = "password_reset_expires")
    val passwordResetExpires: Instant?
)

@Entity(
    tableName = "permissions",
    indices = [Index(value = ["permission_code"], unique = true)]
)
data class PermissionEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "permission_id")
    val permissionId: Int = 0,

    @ColumnInfo(name = "permission_name")
    val permissionName: String,

    @ColumnInfo(name = "permission_description")
    val permissionDescription: String,

    @ColumnInfo(name = "permission_code")
    val permissionCode: String
)

@Entity(
    tableName = "user_permissions",
    primaryKeys = ["user_id", "permission_id"],
    foreignKeys = [
        ForeignKey(
            entity = UserEntity::class,
            parentColumns = ["user_id"],
            childColumns = ["user_id"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = PermissionEntity::class,
            parentColumns = ["permission_id"],
            childColumns = ["permission_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index("permission_id")
    ]
)
data class UserPermissionEntity(
    @ColumnInfo(name = "user_id")
    val userId: Int,

    @ColumnInfo(name = "permission_id")
    val permissionId: Int,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant
)

@Entity(
    tableName = "salary_withdrawals",
    foreignKeys = [
        ForeignKey(
            entity = EmployeeEntity::class,
            parentColumns = ["id"],
            childColumns = ["employee_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("employee_id")]
)
data class SalaryWithdrawalEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "employee_id")
    val employeeId: Int,

    @ColumnInfo(name = "amount")
    val amount: BigDecimal,

    @ColumnInfo(name = "date")
    val date: LocalDate,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant,

    @ColumnInfo(name = "withdrawal_type")
    val withdrawalType: String
)

@Entity(tableName = "suppliers")
data class SupplierEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "name")
    val name: String
)

@Entity(
    tableName = "user_activity_log",
    foreignKeys = [
        ForeignKey(
            entity = UserEntity::class,
            parentColumns = ["user_id"],
            childColumns = ["user_id"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [Index("user_id")]
)
data class UserActivityLogEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "user_id")
    val userId: Int?,

    @ColumnInfo(name = "action")
    val action: String?,

    @ColumnInfo(name = "details")
    val details: String?,

    @ColumnInfo(name = "ip_address")
    val ipAddress: String?,

    @ColumnInfo(name = "user_agent")
    val userAgent: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: Instant
)

@Entity(tableName = "failed_logins")
data class FailedLoginEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "username")
    val username: String?,

    @ColumnInfo(name = "ip_address")
    val ipAddress: String?,

    @ColumnInfo(name = "attempt_time")
    val attemptTime: Instant
)
