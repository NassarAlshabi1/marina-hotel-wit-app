package com.marina.marina.di

import android.content.Context
import androidx.room.Room
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

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): AppDatabase {
        return Room.databaseBuilder(
            context.applicationContext,
            AppDatabase::class.java,
            AppDatabase.DATABASE_NAME
        )
            .fallbackToDestructiveMigration()
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
}