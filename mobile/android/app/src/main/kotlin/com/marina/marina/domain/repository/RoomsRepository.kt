package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Room
import kotlinx.coroutines.flow.Flow

interface RoomsRepository {
    fun getAll(): Flow<List<Room>>
    suspend fun insert(room: Room): Long
    suspend fun update(room: Room)
    suspend fun softDelete(id: Long)
    suspend fun getByNumber(roomNumber: String): Room?
}
