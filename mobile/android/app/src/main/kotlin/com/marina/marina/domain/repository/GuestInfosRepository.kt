package com.marina.marina.domain.repository

import com.marina.marina.domain.model.GuestInfo
import kotlinx.coroutines.flow.Flow

interface GuestInfosRepository {
    fun getAll(): Flow<List<GuestInfo>>
    fun search(query: String): Flow<List<GuestInfo>>
    suspend fun getByRoom(roomNumber: String): List<GuestInfo>
    suspend fun getById(id: Long): GuestInfo?
    suspend fun insert(guest: GuestInfo): Long
    suspend fun update(guest: GuestInfo)
    suspend fun softDelete(id: Long)
}
