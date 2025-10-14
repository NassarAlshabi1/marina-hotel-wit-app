package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.BookingDao
import com.marinahotel.kotlin.data.db.ExpenseDao
import com.marinahotel.kotlin.data.db.RoomDao
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map

class DashboardRepository(
    private val roomDao: RoomDao,
    private val bookingDao: BookingDao,
    private val expenseDao: ExpenseDao
) {
    data class Stats(
        val totalRooms: Int,
        val availableRooms: Int,
        val bookedRooms: Int,
        val occupancyPercent: Int
    )

    fun stats(): Flow<Stats> {
        val totalRooms = roomDao.flowAll().map { it.size }
        val booked = bookingDao.flowCountByStatus("محجوزة")
        return combine(totalRooms, booked) { total, bookedCount ->
            val available = (total - bookedCount).coerceAtLeast(0)
            val occupancy = if (total > 0) (bookedCount * 100 / total) else 0
            Stats(total, available, bookedCount, occupancy)
        }
    }
}