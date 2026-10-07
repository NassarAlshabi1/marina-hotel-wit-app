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

    /**
     * إعادة ضبط إشغال **كل** الغرف من الحجوزات النشطة — نظير Dart
     * `RoomsRepository.refreshAllRoomOccupancy` (rooms_repository.dart l.221-258).
     *
     * @param originIsServer مطابق لدالة Dart: عند `true` تُحدَّث الحالة محلياً
     *   بلا إدراج outbox (المصدر الخادم يملك الطابع)، وهو مسار غير مستدعى اليوم
     *   في Dart نفسه (كلا موضعي النداء يمرّران الافتراضي `false`).
     */
    suspend fun refreshAllRoomOccupancy(originIsServer: Boolean = false)

    /** Targeted status update (e.g. "تحويل إلى صيانة" from the Dashboard). */
    suspend fun updateStatus(id: Long, newStatus: String)
}
