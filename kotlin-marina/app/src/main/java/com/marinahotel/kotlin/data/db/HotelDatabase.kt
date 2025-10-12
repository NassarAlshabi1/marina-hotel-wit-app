package com.marinahotel.kotlin.data.db

import androidx.room.Database
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.entities.BookingNoteEntity
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
    version = 1,
    exportSchema = true
)
@TypeConverters(AppTypeConverters::class)
abstract class HotelDatabase : RoomDatabase() {
    abstract fun roomDao(): RoomDao
    abstract fun bookingDao(): BookingDao
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
}
