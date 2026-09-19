package com.marina.marina.di

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
}
