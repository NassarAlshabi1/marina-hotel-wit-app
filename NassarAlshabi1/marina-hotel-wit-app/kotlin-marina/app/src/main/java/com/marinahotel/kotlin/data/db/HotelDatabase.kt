package com.marinahotel.kotlin.data.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.marinahotel.kotlin.data.entities.BookingEntity
import com.marinahotel.kotlin.data.entities.BookingNoteEntity
import com.marinahotel.kotlin.data.entities.ExpenseEntity
import com.marinahotel.kotlin.data.entities.GuestEntity
import com.marinahotel.kotlin.data.entities.PaymentEntity
import com.marinahotel.kotlin.data.entities.RoomEntity

@Database(
    entities = [
        GuestEntity::class,
        RoomEntity::class,
        BookingEntity::class,
        PaymentEntity::class,
        BookingNoteEntity::class,
        ExpenseEntity::class
    ],
    version = 1,
    exportSchema = true
)
@TypeConverters(AppTypeConverters::class)
abstract class HotelDatabase : RoomDatabase() {

    abstract fun guestDao(): GuestDao
    abstract fun roomDao(): RoomDao
    abstract fun bookingDao(): BookingDao
    abstract fun paymentDao(): PaymentDao
    abstract fun bookingNoteDao(): BookingNoteDao
    abstract fun expenseDao(): ExpenseDao
    abstract fun reportingDao(): ReportingDao

    companion object {
        @Volatile
        private var INSTANCE: HotelDatabase? = null

        fun getInstance(context: Context): HotelDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    HotelDatabase::class.java,
                    "hotel_database"
                )
                    .fallbackToDestructiveMigration()
                    .build()
                    .also { INSTANCE = it }
            }
        }
    }
}
