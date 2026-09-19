package com.marina.marina.di

import com.marina.marina.data.ai.AiAssistantRepositoryImpl
import com.marina.marina.data.auth.AuthRepositoryImpl
import com.marina.marina.data.repository.BlacklistRepositoryImpl
import com.marina.marina.data.repository.SyncManager
import com.marina.marina.data.repository.BookingNightsRepositoryImpl
import com.marina.marina.data.repository.CashRepositoryImpl
import com.marina.marina.data.repository.GuestInfosRepositoryImpl
import com.marina.marina.data.repository.PaymentVoidsRepositoryImpl
import com.marina.marina.data.repository.SalaryRepositoryImpl
import com.marina.marina.domain.repository.AiAssistantRepository
import com.marina.marina.domain.repository.AuthRepository
import com.marina.marina.domain.repository.BlacklistRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.repository.BookingNightsRepository
import com.marina.marina.domain.repository.CashRepository
import com.marina.marina.domain.repository.GuestInfosRepository
import com.marina.marina.domain.repository.PaymentVoidsRepository
import com.marina.marina.domain.repository.SalaryRepository
import com.marina.marina.data.repository.BookingsRepositoryImpl
import com.marina.marina.data.repository.DebtsRepositoryImpl
import com.marina.marina.data.repository.EmployeesRepositoryImpl
import com.marina.marina.data.repository.ExpensesRepositoryImpl
import com.marina.marina.data.repository.InventoryRepositoryImpl
import com.marina.marina.data.repository.PaymentsRepositoryImpl
import com.marina.marina.data.repository.RoomsRepositoryImpl
import com.marina.marina.data.repository.SalaryWithdrawalsRepositoryImpl
import com.marina.marina.data.repository.ShiftNotesRepositoryImpl
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.EmployeesRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.InventoryRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SalaryWithdrawalsRepository
import com.marina.marina.domain.repository.ShiftNotesRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * Binds the domain-layer repository interfaces to their data-layer
 * implementations, so ViewModels can depend on [com.marina.marina.domain.repository]
 * abstractions instead of reaching into the data layer directly.
 */
@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindRoomsRepository(impl: RoomsRepositoryImpl): RoomsRepository

    @Binds
    @Singleton
    abstract fun bindBookingsRepository(impl: BookingsRepositoryImpl): BookingsRepository

    @Binds
    @Singleton
    abstract fun bindPaymentsRepository(impl: PaymentsRepositoryImpl): PaymentsRepository

    @Binds
    @Singleton
    abstract fun bindEmployeesRepository(impl: EmployeesRepositoryImpl): EmployeesRepository

    @Binds
    @Singleton
    abstract fun bindExpensesRepository(impl: ExpensesRepositoryImpl): ExpensesRepository

    @Binds
    @Singleton
    abstract fun bindDebtsRepository(impl: DebtsRepositoryImpl): DebtsRepository

    @Binds
    @Singleton
    abstract fun bindShiftNotesRepository(impl: ShiftNotesRepositoryImpl): ShiftNotesRepository

    @Binds
    @Singleton
    abstract fun bindInventoryRepository(impl: InventoryRepositoryImpl): InventoryRepository

    @Binds
    @Singleton
    abstract fun bindSalaryWithdrawalsRepository(impl: SalaryWithdrawalsRepositoryImpl): SalaryWithdrawalsRepository

    @Binds
    @Singleton
    abstract fun bindBlacklistRepository(impl: BlacklistRepositoryImpl): BlacklistRepository

    @Binds
    @Singleton
    abstract fun bindCashRepository(impl: CashRepositoryImpl): CashRepository

    @Binds
    @Singleton
    abstract fun bindGuestInfosRepository(impl: GuestInfosRepositoryImpl): GuestInfosRepository

    @Binds
    @Singleton
    abstract fun bindSalaryRepository(impl: SalaryRepositoryImpl): SalaryRepository

    @Binds
    @Singleton
    abstract fun bindPaymentVoidsRepository(impl: PaymentVoidsRepositoryImpl): PaymentVoidsRepository

    @Binds
    @Singleton
    abstract fun bindBookingNightsRepository(impl: BookingNightsRepositoryImpl): BookingNightsRepository

    @Binds
    @Singleton
    abstract fun bindSyncRepository(impl: SyncManager): SyncRepository

    @Binds
    @Singleton
    abstract fun bindAuthRepository(impl: AuthRepositoryImpl): AuthRepository

    @Binds
    @Singleton
    abstract fun bindAiAssistantRepository(impl: AiAssistantRepositoryImpl): AiAssistantRepository
}