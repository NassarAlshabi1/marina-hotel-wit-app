package com.marina.marina.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.marina.marina.data.local.dao.BookingNotesDao
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.local.dao.OutboxDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.local.dao.ShiftNotesDao
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.BookingNoteEntity
import com.marina.marina.data.local.entity.CashTransactionEntity
import com.marina.marina.data.local.entity.DebtEntity
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.ExpenseEntity
import com.marina.marina.data.local.entity.OutboxEntity
import com.marina.marina.data.local.entity.PaymentEntity
import com.marina.marina.data.local.entity.RoomEntity
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
        SyncStateEntity::class
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
