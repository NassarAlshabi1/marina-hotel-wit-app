package com.marina.marina.domain.repository

import com.marina.marina.domain.model.Room
import kotlinx.coroutines.flow.Flow

interface RoomsRepository {
    fun getAll(): Flow<List<Room>>

    /** لقطة واحدة — للرسوم الحسابية في لوحة التقارير (نظير db.select(db.rooms).get()). */
    suspend fun getAllOnce(): List<Room>
    suspend fun insert(room: Room): Long
    suspend fun update(room: Room)
    suspend fun softDelete(id: Long)
    suspend fun getByNumber(roomNumber: String): Room?

    /** Targeted status update (e.g. "تحويل إلى صيانة" from the Dashboard). */
    suspend fun updateStatus(id: Long, newStatus: String)
}
