package com.marina.marina.data.repository

import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.mapper.toEntity
import com.marina.marina.data.sync.SyncEpochs
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.util.StatusUtils
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

    /**
     * إعادة ضبط إشغال **كل** الغرف من الحجوزات النشطة — منقول حرفياً من Dart
     * `RoomsRepository.refreshAllRoomOccupancy` (rooms_repository.dart l.221-258):
     *
     * 1. مجموعة أرقام الغرف التي لها حجز **غير محذوف ناعمياً** و**نشط**
     *    (`status IN activeBookingStatuses` الخام في SQL — نظير `selectOnly`).
     * 2. لكل غرفة غير محذوفة:
     *    - `shouldBeOccupied && !isRoomOccupied` ⇒ «محجوزة»
     *    - `!shouldBeOccupied && !isRoomAvailable` ⇒ «شاغرة»
     *    - غير ذلك: تُترك كما هي (لا كتابة بلا داعٍ).
     *
     * **المقايضة الموثّقة (نفس سلوك Dart بالحرف)**: الغرفة التي حالتها «صيانة»
     * ليست «مشغولة» ولا «متاحة»، فتُعاد إلى «شاغرة» عند عدم وجود حجز نشط —
     * هذه بالضبط سلوك الدالة في المرجع، ونُقلت كما هي بدل «تحسينها» محلياً
     * حتى لا يفترق الطرفان (انظر `docs/android-pull-parity-flutter.md`).
     *
     * الفرق البنيوي الوحيد: Dart يُحدّث بـ`updateByRoomNumber` لكل غرفة على حدة
     * (معاملة مستقلة لكل غرفة)، ونحن نُعيد استخدام [update] نفسه — نفس الطوابع
     * (ثوانٍ) ونفس `version+1` ونفس إدراج الـoutbox.
     */
    override suspend fun refreshAllRoomOccupancy(originIsServer: Boolean) {
        val occupiedRoomNumbers = bookingsDao.listActivelyOccupiedRoomNumbers().toSet()
        val rooms = roomsDao.getAllOnce()
        for (room in rooms) {
            val shouldBeOccupied = occupiedRoomNumbers.contains(room.roomNumber)
            val isCurrentlyOccupied = StatusUtils.isRoomOccupied(room.status)
            val isCurrentlyAvailable = StatusUtils.isRoomAvailable(room.status)
            val target = StatusUtils.roomStatusForOccupancy(shouldBeOccupied)
            if (shouldBeOccupied && !isCurrentlyOccupied) {
                persistOccupancy(room, target, originIsServer)
            } else if (!shouldBeOccupied && !isCurrentlyAvailable) {
                persistOccupancy(room, target, originIsServer)
            }
        }
    }

    /**
     * كتابة حالة إشغال واحدة — نظير `rooms_dao.dart:updateByNumber`
     * (`updateByNumber` l.138-175): `updatedAt = now(ثوانٍ)`،
     * `lastModified = now`، `version = existing.version + 1`، وإدراج عملية
     * outbox **إلا** عند `originIsServer = true` (فما جاء من الخادم لا يُعاد
     * رفعه).
     *
     * ⚠️ دقّة نظير: في Dart يُحفظ الطابع الوارد **فقط** إذا مرّره المنادي صراحةً
     * (`originIsServer && data.lastModified.present`) — و`refreshAllRoomOccupancy`
     * **لا تمرّره** (l.246/253)، فالفرعان يختمان `last_modified = now` سواءً
     * `originIsServer` صحيحاً أو خاطئاً. كان فرعنا يترك طابع الصف كما هو (صفراً
     * في صف جديد) ⇒ تلويث `last_modified` بصفر. أُصلح ليطابق المرجع.
     */
    private suspend fun persistOccupancy(
        room: RoomEntity,
        status: String,
        originIsServer: Boolean
    ) {
        val now = SyncEpochs.nowSeconds()
        if (originIsServer) {
            roomsDao.update(
                room.copy(
                    status = status,
                    updatedAt = now,
                    lastModified = now,
                    lastModifiedEpoch = now,
                    version = room.version + 1
                )
            )
            return
        }
        val domain = room.toDomain().copy(
            status = status,
            updatedAt = now,
            localUuid = room.localUuid.ifBlank { UUID.randomUUID().toString() }
        )
        roomsDao.updateStatus(room.id, status, updatedAt = now, lastModified = now)
        outboxRepository.enqueueObject("rooms", "update", domain.localUuid, domain)
    }

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
