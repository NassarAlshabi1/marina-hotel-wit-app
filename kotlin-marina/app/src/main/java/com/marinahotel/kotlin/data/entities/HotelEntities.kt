package com.marinahotel.kotlin.data.entities

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

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
    val price: Double,

    @ColumnInfo(name = "status")
    val status: String = "شاغرة"
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
    val guestIdIssueDate: String?,

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
    val guestCreatedAt: String,

    @ColumnInfo(name = "room_number")
    val roomNumber: String,

    @ColumnInfo(name = "checkin_date")
    val checkinDate: String,

    @ColumnInfo(name = "checkout_date")
    val checkoutDate: String?,

    @ColumnInfo(name = "status")
    val status: String,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "expected_nights", defaultValue = "1")
    val expectedNights: Int = 1,

    @ColumnInfo(name = "actual_checkout")
    val actualCheckout: String?,

    @ColumnInfo(name = "calculated_nights", defaultValue = "1")
    val calculatedNights: Int = 1,

    @ColumnInfo(name = "last_calculation")
    val lastCalculation: String
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
    val alertType: String = "medium",

    @ColumnInfo(name = "alert_until")
    val alertUntil: String?,

    @ColumnInfo(name = "is_active", defaultValue = "1")
    val isActive: Boolean = true,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

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
    val date: String,

    @ColumnInfo(name = "opening_balance")
    val openingBalance: Double,

    @ColumnInfo(name = "closing_balance")
    val closingBalance: Double?,

    @ColumnInfo(name = "total_income")
    val totalIncome: Double,

    @ColumnInfo(name = "total_expense")
    val totalExpense: Double,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "created_by")
    val createdBy: Int?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "status")
    val status: String = "open"
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
    ],
    indices = [Index("register_id")]
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
    val transactionTime: String,

    @ColumnInfo(name = "created_by")
    val createdBy: Int?,

    @ColumnInfo(name = "created_at")
    val createdAt: String
)

@Entity(tableName = "employees")
data class EmployeeEntity(
    @PrimaryKey(autoGenerate = true)
    @ColumnInfo(name = "id")
    val id: Int = 0,

    @ColumnInfo(name = "name")
    val name: String,

    @ColumnInfo(name = "basic_salary")
    val basicSalary: Double,

    @ColumnInfo(name = "status")
    val status: String = "active"
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
    val amount: Double,

    @ColumnInfo(name = "date")
    val date: String,

    @ColumnInfo(name = "cash_transaction_id")
    val cashTransactionId: Int?,

    @ColumnInfo(name = "created_by")
    val createdBy: Int?,

    @ColumnInfo(name = "created_at")
    val createdAt: String
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
    ],
    indices = [Index("expense_id")]
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
    val createdAt: String
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
    val createdAt: String
)

@Entity(
    tableName = "payment",
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
    @ColumnInfo(name = "payment_id")
    val paymentId: Int = 0,

    @ColumnInfo(name = "booking_id")
    val bookingId: Int,

    @ColumnInfo(name = "amount")
    val amount: Int,

    @ColumnInfo(name = "payment_date")
    val paymentDate: String,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "payment_method")
    val paymentMethod: String,

    @ColumnInfo(name = "revenue_type")
    val revenueType: String = "room",

    @ColumnInfo(name = "cash_transaction_id")
    val cashTransactionId: Int?,

    @ColumnInfo(name = "room_number")
    val roomNumber: String?
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
    val userType: String = "employee",

    @ColumnInfo(name = "is_active", defaultValue = "1")
    val isActive: Boolean = true,

    @ColumnInfo(name = "last_login")
    val lastLogin: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "updated_at")
    val updatedAt: String,

    @ColumnInfo(name = "failed_login_attempts", defaultValue = "0")
    val failedLoginAttempts: Int = 0,

    @ColumnInfo(name = "locked_until")
    val lockedUntil: String?,

    @ColumnInfo(name = "password_reset_token")
    val passwordResetToken: String?,

    @ColumnInfo(name = "password_reset_expires")
    val passwordResetExpires: String?
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
    val createdAt: String
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
    val amount: Double,

    @ColumnInfo(name = "date")
    val date: String,

    @ColumnInfo(name = "notes")
    val notes: String?,

    @ColumnInfo(name = "created_at")
    val createdAt: String,

    @ColumnInfo(name = "withdrawal_type")
    val withdrawalType: String = "cash"
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
    val createdAt: String
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
    val attemptTime: String
)
