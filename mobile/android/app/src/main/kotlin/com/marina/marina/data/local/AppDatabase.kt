package com.marina.marina.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.marina.marina.data.local.dao.AuditLogsDao
import com.marina.marina.data.local.dao.BlacklistEntriesDao
import com.marina.marina.data.local.dao.BookingNightsDao
import com.marina.marina.data.local.dao.BookingPriceAdjustmentsDao
import com.marina.marina.data.local.dao.CashTransactionsDao
import com.marina.marina.data.local.dao.GuestInfosDao
import com.marina.marina.data.local.dao.HotelDayLedgerDao
import com.marina.marina.data.local.dao.PaymentVoidsDao
import com.marina.marina.data.local.dao.PriceAdjustmentsDao
import com.marina.marina.data.local.dao.SalaryCarryOverLogsDao
import com.marina.marina.data.local.dao.SalaryCyclesDao
import com.marina.marina.data.local.dao.SalaryPaymentsDao
import com.marina.marina.data.local.dao.BookingNotesDao
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.local.dao.InventoryDao
import com.marina.marina.data.local.dao.OutboxDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.local.dao.SalaryWithdrawalsDao
import com.marina.marina.data.local.dao.ShiftNotesDao
import com.marina.marina.data.local.entity.AuditLogEntity
import com.marina.marina.data.local.entity.BlacklistEntryEntity
import com.marina.marina.data.local.entity.BookingNightEntity
import com.marina.marina.data.local.entity.BookingPriceAdjustmentEntity
import com.marina.marina.data.local.entity.GuestInfoEntity
import com.marina.marina.data.local.entity.HotelDayLedgerEntity
import com.marina.marina.data.local.entity.PaymentVoidEntity
import com.marina.marina.data.local.entity.PriceAdjustmentEntity
import com.marina.marina.data.local.entity.SalaryCarryOverLogEntity
import com.marina.marina.data.local.entity.SalaryCycleEntity
import com.marina.marina.data.local.entity.SalaryPaymentEntity
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.BookingNoteEntity
import com.marina.marina.data.local.entity.CashTransactionEntity
import com.marina.marina.data.local.entity.DebtEntity
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.ExpenseEntity
import com.marina.marina.data.local.entity.InventoryItemEntity
import com.marina.marina.data.local.entity.InventoryTransactionEntity
import com.marina.marina.data.local.entity.OutboxEntity
import com.marina.marina.data.local.entity.PaymentEntity
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.local.entity.SalaryWithdrawalEntity
import com.marina.marina.data.local.entity.ShiftNoteEntity
import com.marina.marina.data.local.entity.SyncStateEntity

@Database(
    entities = [
        RoomEntity::class,
        BookingEntity::class,
        BookingNoteEntity::class,
        EmployeeEntity::class,
        ExpenseEntity::class,
        CashTransactionEntity::class,
        PaymentEntity::class,
        DebtEntity::class,
        ShiftNoteEntity::class,
        OutboxEntity::class,
        SyncStateEntity::class,
        InventoryItemEntity::class,
        InventoryTransactionEntity::class,
        SalaryWithdrawalEntity::class,
        BookingNightEntity::class,
        HotelDayLedgerEntity::class,
        PriceAdjustmentEntity::class,
        BookingPriceAdjustmentEntity::class,
        PaymentVoidEntity::class,
        GuestInfoEntity::class,
        SalaryCycleEntity::class,
        SalaryPaymentEntity::class,
        SalaryCarryOverLogEntity::class,
        BlacklistEntryEntity::class,
        AuditLogEntity::class
    ],
    version = 69,
    exportSchema = true
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun roomsDao(): RoomsDao
    abstract fun bookingsDao(): BookingsDao
    abstract fun paymentsDao(): PaymentsDao
    abstract fun employeesDao(): EmployeesDao
    abstract fun expensesDao(): ExpensesDao
    abstract fun debtsDao(): DebtsDao
    abstract fun bookingNotesDao(): BookingNotesDao
    abstract fun shiftNotesDao(): ShiftNotesDao
    abstract fun outboxDao(): OutboxDao
    abstract fun inventoryDao(): InventoryDao
    abstract fun salaryWithdrawalsDao(): SalaryWithdrawalsDao
    abstract fun bookingNightsDao(): BookingNightsDao
    abstract fun hotelDayLedgerDao(): HotelDayLedgerDao
    abstract fun priceAdjustmentsDao(): PriceAdjustmentsDao
    abstract fun bookingPriceAdjustmentsDao(): BookingPriceAdjustmentsDao
    abstract fun paymentVoidsDao(): PaymentVoidsDao
    abstract fun guestInfosDao(): GuestInfosDao
    abstract fun salaryCyclesDao(): SalaryCyclesDao
    abstract fun salaryPaymentsDao(): SalaryPaymentsDao
    abstract fun salaryCarryOverLogsDao(): SalaryCarryOverLogsDao
    abstract fun blacklistEntriesDao(): BlacklistEntriesDao
    abstract fun auditLogsDao(): AuditLogsDao
    abstract fun cashTransactionsDao(): CashTransactionsDao

    companion object {
        const val DATABASE_NAME = "marina_hotel.db"
        const val SCHEMA_VERSION = 69
    }
}
