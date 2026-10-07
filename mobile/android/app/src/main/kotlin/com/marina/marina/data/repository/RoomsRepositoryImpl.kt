package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.data.sync.SyncEpochs
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.repository.RoomsRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

@Singleton
class RoomsRepositoryImpl @Inject constructor(
    private val roomsDao: RoomsDao,
    private val bookingsDao: BookingsDao,
    private val outboxRepository: OutboxRepository
) : RoomsRepository {

    override fun getAll(): Flow<List<Room>> =
        roomsDao.getAll().map { entities -> entities.map { it.toDomain() } }

    override suspend fun getAllOnce(): List<Room> =
        roomsDao.getAllOnce().map { it.toDomain() }

    override suspend fun insert(room: Room): Long {
        // ✅ (2026-10-06) الطوابع بالثواني — نظير `Time.nowEpoch()` في
        // `rooms_dao.dart:insertOne` (createdAt/updatedAt/lastModified = now).
        // الميلي ثانية كان يُفسد «آخر كتابة تفوز» في الاتجاهين (انظر SyncEpochs).
        val now = SyncEpochs.nowSeconds()
        val prepared = room.copy(
            localUuid = room.localUuid.ifBlank { UUID.randomUUID().toString() },
            createdAt = if (room.createdAt == 0L) now else room.createdAt,
            updatedAt = now
        )
        val id = roomsDao.insert(
            prepared.toEntity().copy(lastModified = now, lastModifiedEpoch = now)
        )
        outboxRepository.enqueueObject("rooms", "insert", prepared.localUuid, prepared)
        return id
    }

    override suspend fun update(room: Room) {
        // ✅ نظير `rooms_dao.dart:updateById`: updatedAt/lastModified = now(ثوانٍ)
        // و`version = existing.version + 1`. قبل الإصلاح: `last_modified` كان
        // يُكتب صفراً (لا يوجد في نموذج المجال أصلاً!) فيفوز صف الخادم الأقدم
        // على تعديلنا، و`updateStatus` كان يكتب ميلي ثانية فيُرفض الخادم للأبد.
        val now = SyncEpochs.nowSeconds()
        val existing = roomsDao.getById(room.id)
        val prepared = room.copy(updatedAt = now)
        roomsDao.update(
            prepared.toEntity().copy(
                // الهوية تبقى ثابتة حتى لو جاء النموذج بلا uuid (نفس عقد Dart).
                localUuid = prepared.localUuid.ifBlank { existing?.localUuid.orEmpty() },
                createdAt = if (prepared.createdAt == 0L) (existing?.createdAt ?: now) else prepared.createdAt,
                lastModified = now,
                lastModifiedEpoch = now,
                version = (existing?.version ?: prepared.version) + 1
            )
        )
        outboxRepository.enqueueObject("rooms", "update", prepared.localUuid, prepared)
    }

    override suspend fun softDelete(id: Long) {
        // Dart rooms_repository.dart l.149-186 — a room with an active booking
        // cannot be deleted (the guest is still living in it).
        val room = roomsDao.getById(id) ?: return
        val activeBooking = bookingsDao.getActiveBookingForRoom(room.roomNumber)
        if (activeBooking != null) {
            val guest = activeBooking.guestName.ifBlank { "غير معروف" }
            error("لا يمكن حذف الغرفة ${room.roomNumber}: يوجد حجز نشط (الضيف: $guest)")
        }
        // ✅ (2026-10-06) عقد Dart `rooms_dao.softDelete`: الطوابع بالثواني
        // **وإدراج عملية outbox** تحمل أعمدة القبورة (deleted_at/updated_at)
        // — قبل الإصلاح لم يكن الحذف يُرفع إطلاقاً فيبقى الصف حياً على D1
        // وعلى بقية الأجهزة (وهو من «الحذف لا ينتشر» في المزامنة).
        val now = SyncEpochs.nowSeconds()
        roomsDao.softDelete(id, deletedAt = now, updatedAt = now, lastModified = now)
        val prepared = room.toDomain().copy(deletedAt = now, updatedAt = now)
        outboxRepository.enqueueObject("rooms", "update", prepared.localUuid, prepared)
    }

    override suspend fun getByNumber(roomNumber: String): Room? =
        roomsDao.getByNumber(roomNumber)?.toDomain()

    override suspend fun updateStatus(id: Long, newStatus: String) {
        // ثوانٍ لا ميلي — كان هذا الموضع أخطر مصادر التسميم (أي نقرة على
        // شاشة الغرف تُقفل استقبال تحديثات الخادم لذلك الصف إلى الأبد).
        val now = SyncEpochs.nowSeconds()
        val room = roomsDao.getById(id) ?: return
        val prepared = room.toDomain().let { domain ->
            domain.copy(
                status = newStatus,
                updatedAt = now,
                // Keep localUuid stable: the entity row is updated in place.
                localUuid = domain.localUuid.ifBlank { java.util.UUID.randomUUID().toString() }
            )
        }
        roomsDao.updateStatus(id, newStatus, updatedAt = now, lastModified = now)
        outboxRepository.enqueueObject("rooms", "update", prepared.localUuid, prepared)
    }
}
