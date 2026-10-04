package com.marina.marina.di

import android.content.Context
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.marina.marina.data.local.AppDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    /** Add stable UUID references for salary-payment cycles and carry-over employees. */
    val MIGRATION_70_71 = object : Migration(70, 71) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE salary_payments ADD COLUMN cycle_uuid TEXT")
            db.execSQL("ALTER TABLE salary_carry_over_logs ADD COLUMN employee_uuid TEXT")
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_salary_payments_cycle_uuid " +
                    "ON salary_payments(cycle_uuid)"
            )
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS idx_salary_carryover_employee_uuid " +
                    "ON salary_carry_over_logs(employee_uuid)"
            )
        }
    }

    val MIGRATION_71_72 = object : Migration(71, 72) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE salary_withdrawals ADD COLUMN expense_uuid TEXT")
            db.execSQL("CREATE INDEX IF NOT EXISTS idx_salary_wd_expense_uuid ON salary_withdrawals(expense_uuid)")
            db.execSQL("CREATE TABLE IF NOT EXISTS pending_sync_links (entity TEXT NOT NULL, localUuid TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(entity, localUuid))")
        }
    }

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context.applicationContext,
            AppDatabase::class.java,
            AppDatabase.DATABASE_NAME
        )
            .addMigrations(MIGRATION_70_71, MIGRATION_71_72)
            // Unknown historical versions fail closed; never erase financial data/Outbox.
            .build()
    }

    @Provides
    @Singleton
    fun provideRoomsDao(db: AppDatabase) = db.roomsDao()

    @Provides
    @Singleton
    fun provideBookingsDao(db: AppDatabase) = db.bookingsDao()

    @Provides
    @Singleton
    fun providePaymentsDao(db: AppDatabase) = db.paymentsDao()

    @Provides
    @Singleton
    fun provideEmployeesDao(db: AppDatabase) = db.employeesDao()

    @Provides
    @Singleton
    fun provideExpensesDao(db: AppDatabase) = db.expensesDao()

    @Provides
    @Singleton
    fun provideDebtsDao(db: AppDatabase) = db.debtsDao()

    @Provides
    @Singleton
    fun provideBookingNotesDao(db: AppDatabase) = db.bookingNotesDao()

    @Provides
    @Singleton
    fun provideShiftNotesDao(db: AppDatabase) = db.shiftNotesDao()

    @Provides
    @Singleton
    fun provideOutboxDao(db: AppDatabase) = db.outboxDao()

    @Provides
    @Singleton
    fun provideInventoryDao(db: AppDatabase) = db.inventoryDao()

    @Provides
    @Singleton
    fun provideSalaryWithdrawalsDao(db: AppDatabase) = db.salaryWithdrawalsDao()

    @Provides
    @Singleton
    fun provideBookingNightsDao(db: AppDatabase) = db.bookingNightsDao()

    @Provides
    @Singleton
    fun provideHotelDayLedgerDao(db: AppDatabase) = db.hotelDayLedgerDao()

    @Provides
    @Singleton
    fun providePriceAdjustmentsDao(db: AppDatabase) = db.priceAdjustmentsDao()

    @Provides
    @Singleton
    fun provideBookingPriceAdjustmentsDao(db: AppDatabase) = db.bookingPriceAdjustmentsDao()

    @Provides
    @Singleton
    fun providePaymentVoidsDao(db: AppDatabase) = db.paymentVoidsDao()

    @Provides
    @Singleton
    fun provideGuestInfosDao(db: AppDatabase) = db.guestInfosDao()

    @Provides
    @Singleton
    fun provideSalaryCyclesDao(db: AppDatabase) = db.salaryCyclesDao()

    @Provides
    @Singleton
    fun provideSalaryPaymentsDao(db: AppDatabase) = db.salaryPaymentsDao()

    @Provides
    @Singleton
    fun provideSalaryCarryOverLogsDao(db: AppDatabase) = db.salaryCarryOverLogsDao()

    @Provides
    @Singleton
    fun provideBlacklistEntriesDao(db: AppDatabase) = db.blacklistEntriesDao()

    @Provides
    @Singleton
    fun provideAuditLogsDao(db: AppDatabase) = db.auditLogsDao()

    @Provides
    @Singleton
    fun provideCashTransactionsDao(db: AppDatabase) = db.cashTransactionsDao()

    @Provides
    @Singleton
    fun provideAutoFixRunsDao(db: AppDatabase) = db.autoFixRunsDao()

    @Provides
    @Singleton
    fun provideIntegrityViolationsDao(db: AppDatabase) = db.integrityViolationsDao()

    @Provides
    @Singleton
    fun provideAppSessionsDao(db: AppDatabase) = db.appSessionsDao()

    @Provides
    @Singleton
    fun provideRestoreFixLogDao(db: AppDatabase) = db.restoreFixLogDao()

    @Provides
    @Singleton
    fun provideSyncQueueDao(db: AppDatabase) = db.syncQueueDao()

    @Provides
    @Singleton
    fun provideSyncLogDao(db: AppDatabase) = db.syncLogDao()

    @Provides
    @Singleton
    fun provideSyncConflictsDao(db: AppDatabase) = db.syncConflictsDao()

    @Provides
    @Singleton
    fun provideAncestorCacheDao(db: AppDatabase) = db.ancestorCacheDao()

    @Provides
    @Singleton
    fun provideSyncRemoteMetaDao(db: AppDatabase) = db.syncRemoteMetaDao()

    @Provides
    @Singleton
    fun provideAppUsersDao(db: AppDatabase) = db.appUsersDao()

    @Provides
    @Singleton
    fun provideDevicesDao(db: AppDatabase) = db.devicesDao()
}
