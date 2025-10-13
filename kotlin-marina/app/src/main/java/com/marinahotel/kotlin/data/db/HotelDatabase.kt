package com.marinahotel.kotlin.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.marinahotel.kotlin.data.entities.BookingEntity
import kotlin.jvm.Volatile
import com.marinahotel.kotlin.data.entities.BookingNoteEntity
import com.marinahotel.kotlin.data.entities.GuestEntity
import com.marinahotel.kotlin.data.entities.CashRegisterEntity
import com.marinahotel.kotlin.data.entities.CashTransactionEntity
import com.marinahotel.kotlin.data.entities.EmployeeEntity
import com.marinahotel.kotlin.data.entities.ExpenseEntity
import com.marinahotel.kotlin.data.entities.ExpenseLogEntity
import com.marinahotel.kotlin.data.entities.FailedLoginEntity
import com.marinahotel.kotlin.data.entities.InvoiceEntity
import com.marinahotel.kotlin.data.entities.PaymentEntity
import com.marinahotel.kotlin.data.entities.PermissionEntity
import com.marinahotel.kotlin.data.entities.RoomEntity
import com.marinahotel.kotlin.data.entities.SalaryWithdrawalEntity
import com.marinahotel.kotlin.data.entities.SupplierEntity
import com.marinahotel.kotlin.data.entities.UserActivityLogEntity
import com.marinahotel.kotlin.data.entities.UserEntity
import com.marinahotel.kotlin.data.entities.UserPermissionEntity

@Database(
    entities = [
        RoomEntity::class,
        BookingEntity::class,
        GuestEntity::class,
        BookingNoteEntity::class,
        CashRegisterEntity::class,
        CashTransactionEntity::class,
        EmployeeEntity::class,
        ExpenseEntity::class,
        ExpenseLogEntity::class,
        InvoiceEntity::class,
        PaymentEntity::class,
        UserEntity::class,
        PermissionEntity::class,
        UserPermissionEntity::class,
        SalaryWithdrawalEntity::class,
        SupplierEntity::class,
        UserActivityLogEntity::class,
        FailedLoginEntity::class
    ],
    version = 2,
    exportSchema = true
)
@TypeConverters(AppTypeConverters::class)
abstract class HotelDatabase : RoomDatabase() {
    abstract fun roomDao(): RoomDao
    abstract fun bookingDao(): BookingDao
    abstract fun guestDao(): GuestDao
    abstract fun bookingNoteDao(): BookingNoteDao
    abstract fun userDao(): UserDao
    abstract fun permissionDao(): PermissionDao
    abstract fun userPermissionDao(): UserPermissionDao
    abstract fun paymentDao(): PaymentDao
    abstract fun cashRegisterDao(): CashRegisterDao
    abstract fun cashTransactionDao(): CashTransactionDao
    abstract fun expenseDao(): ExpenseDao
    abstract fun expenseLogDao(): ExpenseLogDao
    abstract fun employeeDao(): EmployeeDao
    abstract fun salaryWithdrawalDao(): SalaryWithdrawalDao
    abstract fun supplierDao(): SupplierDao
    abstract fun invoiceDao(): InvoiceDao
    abstract fun userActivityLogDao(): UserActivityLogDao
    abstract fun failedLoginDao(): FailedLoginDao

    companion object {
        @Volatile
        private var INSTANCE: HotelDatabase? = null

        fun getInstance(context: Context): HotelDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    HotelDatabase::class.java,
                    "hotel_db"
                ).addMigrations(MIGRATION_1_2)
                    .build()
                    .also { INSTANCE = it }
            }
        }

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(database: SupportSQLiteDatabase) {
                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `guests` (
                        `guest_id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `guest_name` TEXT NOT NULL,
                        `guest_id_type` TEXT,
                        `guest_id_number` TEXT,
                        `guest_id_issue_date` TEXT,
                        `guest_id_issue_place` TEXT,
                        `guest_phone` TEXT,
                        `guest_nationality` TEXT,
                        `guest_email` TEXT,
                        `guest_address` TEXT,
                        `created_at` TEXT NOT NULL
                    )
                    """.trimIndent()
                )

                database.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `bookings_new` (
                        `booking_id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                        `guest_id` INTEGER NOT NULL,
                        `room_number` TEXT NOT NULL,
                        `checkin_date` TEXT NOT NULL,
                        `checkout_date` TEXT,
                        `status` TEXT NOT NULL,
                        `notes` TEXT,
                        `created_at` TEXT NOT NULL,
                        `expected_nights` INTEGER NOT NULL DEFAULT 1,
                        `actual_checkout` TEXT,
                        `calculated_nights` INTEGER NOT NULL DEFAULT 1,
                        `last_calculation` TEXT NOT NULL,
                        FOREIGN KEY(`guest_id`) REFERENCES `guests`(`guest_id`) ON UPDATE CASCADE ON DELETE RESTRICT,
                        FOREIGN KEY(`room_number`) REFERENCES `rooms`(`room_number`) ON UPDATE CASCADE
                    )
                    """.trimIndent()
                )

                database.execSQL(
                    """
                    INSERT INTO guests (
                        guest_id,
                        guest_name,
                        guest_id_type,
                        guest_id_number,
                        guest_id_issue_date,
                        guest_id_issue_place,
                        guest_phone,
                        guest_nationality,
                        guest_email,
                        guest_address,
                        created_at
                    )
                    SELECT
                        booking_id,
                        guest_name,
                        guest_id_type,
                        guest_id_number,
                        guest_id_issue_date,
                        guest_id_issue_place,
                        guest_phone,
                        guest_nationality,
                        guest_email,
                        guest_address,
                        COALESCE(guest_created_at, created_at)
                    FROM bookings
                    """.trimIndent()
                )

                database.execSQL(
                    """
                    INSERT INTO bookings_new (
                        booking_id,
                        guest_id,
                        room_number,
                        checkin_date,
                        checkout_date,
                        status,
                        notes,
                        created_at,
                        expected_nights,
                        actual_checkout,
                        calculated_nights,
                        last_calculation
                    )
                    SELECT
                        booking_id,
                        booking_id,
                        room_number,
                        checkin_date,
                        checkout_date,
                        status,
                        notes,
                        created_at,
                        expected_nights,
                        actual_checkout,
                        calculated_nights,
                        last_calculation
                    FROM bookings
                    """.trimIndent()
                )

                database.execSQL("DROP TABLE bookings")
                database.execSQL("ALTER TABLE bookings_new RENAME TO bookings")

                database.execSQL("CREATE INDEX IF NOT EXISTS index_guests_guest_name ON guests(guest_name)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_guests_guest_phone ON guests(guest_phone)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_bookings_status ON bookings(status)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_bookings_room_number ON bookings(room_number)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_bookings_guest_id ON bookings(guest_id)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_bookings_checkin_date ON bookings(checkin_date)")
                database.execSQL("CREATE INDEX IF NOT EXISTS index_bookings_created_at ON bookings(created_at)")
            }
        }
    }
}
