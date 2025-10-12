package com.marinahotel.kotlin.data.repository

import com.marinahotel.kotlin.data.db.RoomDao
import com.marinahotel.kotlin.data.entities.RoomEntity
import kotlinx.coroutines.flow.Flow

class RoomsRepository(private val roomDao: RoomDao) {
    fun flowAllRooms(): Flow<List<RoomEntity>> = roomDao.flowAll()
    fun flowRoomsByStatus(status: String): Flow<List<RoomEntity>> = roomDao.flowByStatus(status)

    suspend fun getAll(): List<RoomEntity> = roomDao.getAll()
    suspend fun getByStatus(status: String): List<RoomEntity> = roomDao.getByStatus(status)

    suspend fun saveRoom(entity: RoomEntity) {
        roomDao.insert(entity)
    }

    suspend fun updateRoom(entity: RoomEntity) {
        roomDao.update(entity)
    }
}