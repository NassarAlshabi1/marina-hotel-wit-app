package com.marina.marina.domain.repository

import com.marina.marina.domain.model.ShiftNote
import kotlinx.coroutines.flow.Flow

interface ShiftNotesRepository {
    fun getAll(): Flow<List<ShiftNote>>
    fun getUnread(): Flow<List<ShiftNote>>
    suspend fun insert(note: ShiftNote): Long
    suspend fun update(note: ShiftNote)
    suspend fun markRead(id: Long)
    suspend fun delete(id: Long)
}
