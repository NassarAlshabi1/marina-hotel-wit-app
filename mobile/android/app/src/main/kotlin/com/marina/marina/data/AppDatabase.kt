package com.marina.marina.data

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [
        Room::class,
        Booking::class,
        BookingNote::class,
        Employee::class,
        Expense::class,
        CashTransaction::class,
        Payment::class,
        Debt::class,
        ShiftNote::class,
        Outbox::class,
        SyncState::class
    ],
    version = 67,
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

    companion object {
        const val DATABASE_NAME = "marina_hotel.db"
        const val SCHEMA_VERSION = 67
    }
}