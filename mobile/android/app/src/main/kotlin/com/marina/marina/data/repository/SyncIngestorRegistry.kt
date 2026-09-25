package com.marina.marina.data.repository

import androidx.room.withTransaction
import com.google.gson.ExclusionStrategy
import com.google.gson.FieldAttributes
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.AppUsersDao
import com.marina.marina.data.local.dao.AuditLogsDao
import com.marina.marina.data.local.dao.BlacklistEntriesDao
import com.marina.marina.data.local.dao.BookingNightsDao
import com.marina.marina.data.local.dao.BookingNotesDao
import com.marina.marina.data.local.dao.BookingPriceAdjustmentsDao
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.CashTransactionsDao
import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.local.dao.DevicesDao
import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.local.dao.GuestInfosDao
import com.marina.marina.data.local.dao.InventoryDao
import com.marina.marina.data.local.dao.PaymentVoidsDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.local.dao.PriceAdjustmentsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.local.dao.SalaryCarryOverLogsDao
import com.marina.marina.data.local.dao.SalaryCyclesDao
import com.marina.marina.data.local.dao.SalaryPaymentsDao
import com.marina.marina.data.local.dao.SalaryWithdrawalsDao
import com.marina.marina.data.local.dao.ShiftNotesDao
import com.marina.marina.data.local.entity.BaseSyncEntity
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ✅ (2026-09-25) محرك استيعاب سجلات السحب — أُعيدت كتابته على العقد
 * الدارتي الكامل (cloudflare_sync_manager.dart — الجذري الثالث
 * 2026-09-09 + سجل الانتظار 2026-09-15):
 *
 * 1. **تعلّم ظلّ هوية الخادم**: كل صف واصل يحمل `id` (AUTOINCREMENT
 *    خادمي) — يُخزن في عمود `server_id` المحلي فيصير سجلَّ ترجمة
 *    دائماً «D1 id → صف محلي» داخل البيانات نفسها (عمود server_id
 *    الواصل من D1 إرثي وNULL غالباً — لم يكن يُتعلم إطلاقاً).
 *
 * 2. **ترجمة FK عند التطبيق** (تكافؤ _fkRules + IdResolver):
 *    مؤشرات الأبناء الرقمية على السلك (booking_local_id/employee_id/
 *    cycle_id/item_id) تحمل فضاء id الجهاز الدافع — كتابتها كما هي
 *    محلياً تربط الابن بأب **خاطئ** (تصادم autoIncrement بين الأجهزة).
 *    سلّم الحل: uuid-cache (3 صيغ) → الرجل الإرثية (server_booking_id)
 *    → ظلّ server_id → ما لم يُحلّ يُؤجَّل لإعادة المحاولة بعد اكتمال
 *    الصفحات (الآب قد يصل في صفحة لاحقة). **لا يُستخدم id الخام من
 *    جهاز بعيد أبداً** («bookingLocalId=5 على جهاز A ≠ جهاز B»).
 *
 * 3. **الدمج بالمفتاح الطبيعي** لليالي الحجز (booking_local_id,
 *    hotel_day_key — عقد _naturalUniqueKeys): صف بـ local_uuid جديد
 *    بنفس الليلة = نسخة مكررة منطقياً تُدمج LWW بدل صف ثانٍ.
 *
 * 4. **الصفحة كلها في معاملة واحدة** — 7,300 commit → ~18 (تسريع
 *     السحب الكامل 2026-09-22 في Dart).
 *
 * 5. **آخر-كتابة-تفوز** بمقارنة last_modified؛ التعادل للقادم من
 *    الخادم (حسم التعارض خادمياً). الحذفيات تُستوعب ناعمياً.
 *
 * hotel_day_ledger مستبعد عمداً (تأكيد المالك: جدول محلي-فقط — خطة D8).
 */

/** نتيجة تطبيق سجل واحد. */
private sealed interface ApplyOutcome {
    data object Applied : ApplyOutcome
    data object Skipped : ApplyOutcome
    data object Deferred : ApplyOutcome
    data class Failed(val error: String) : ApplyOutcome
}

/** سجل مؤجل — فشلت ترجمة آبائه في هذه الصفحة (تُعاد بعد اكتمال الصفحات). */
data class DeferredRecord(val entity: String, val record: Map<String, Any>)

/** تقرير تطبيق صفحة كاملة (تكافؤ PullApplyReport في Dart). */
data class PullApplyReport(
    val applied: Int,
    val skipped: Int,
    val failed: Int,
    val firstError: String?,
    val deferred: List<DeferredRecord>
) {
    val hasFailures: Boolean get() = failed > 0
    val hasDeferred: Boolean get() = deferred.isNotEmpty()
}

@Singleton
class SyncIngestorRegistry @Inject constructor(
    private val db: AppDatabase,
    private val roomsDao: RoomsDao,
    private val bookingsDao: BookingsDao,
    private val paymentsDao: PaymentsDao,
    private val expensesDao: ExpensesDao,
    private val employeesDao: EmployeesDao,
    private val debtsDao: DebtsDao,
    private val bookingNotesDao: BookingNotesDao,
    private val bookingNightsDao: BookingNightsDao,
    private val bookingPriceAdjustmentsDao: BookingPriceAdjustmentsDao,
    private val guestInfosDao: GuestInfosDao,
    private val shiftNotesDao: ShiftNotesDao,
    private val salaryCyclesDao: SalaryCyclesDao,
    private val salaryPaymentsDao: SalaryPaymentsDao,
    private val salaryWithdrawalsDao: SalaryWithdrawalsDao,
    private val salaryCarryOverLogsDao: SalaryCarryOverLogsDao,
    private val appUsersDao: AppUsersDao,
    private val devicesDao: DevicesDao,
    private val cashTransactionsDao: CashTransactionsDao,
    private val auditLogsDao: AuditLogsDao,
    private val paymentVoidsDao: PaymentVoidsDao,
    private val priceAdjustmentsDao: PriceAdjustmentsDao,
    private val inventoryDao: InventoryDao,
    private val blacklistEntriesDao: BlacklistEntriesDao
) {
    /**
     * ✅ (2026-09-25) Gson لكل صنف كيان — الإصلاح الجذري لموت الاستيعاب:
     * الكيانات تعيد إعلان حقول BaseSyncEntity (id، وبعضها local_uuid مثل
     * PaymentEntity) لتعليقها بـ@PrimaryKey/@ColumnInfo — Gson يفشل
     * «declares multiple JSON fields named 'id'» على كل سجل، وكان
     * catch(_: Exception) القديم يبتلع ذلك صمتاً فلا يصل صفّ واحد إلى
     * Room إطلاقاً. الاستراتيجية: الحقل المورّث يُتجاهل عندما يعيد
     * الصنف الفعلي إعلانه (الفرعي هو المصدر المرجعي).
     */
    private val gsonCache = java.util.concurrent.ConcurrentHashMap<Class<*>, Gson>()

    private fun gsonFor(clazz: Class<*>): Gson = gsonCache.getOrPut(clazz) {
        val ownNames = clazz.declaredFields.map { it.name }.toSet()
        val strategy = object : ExclusionStrategy {
            override fun shouldSkipField(f: FieldAttributes): Boolean =
                f.declaringClass != clazz && f.name in ownNames

            override fun shouldSkipClass(c: Class<*>): Boolean = false
        }
        GsonBuilder()
            .addDeserializationExclusionStrategy(strategy)
            .addSerializationExclusionStrategy(strategy)
            .create()
    }

    // ─── واجهات عامة ────────────────────────────────────────────

    /**
     * استيعاب صفحة كاملة داخل معاملة Room واحدة (ذريّة الأداء — ليس
     * ذريّة الدلالة: فشل SQL لسجل يُحصى ولا يُجهض الصفحة، عقد Dart).
     *
     * @return تقرير [PullApplyReport] — المؤجّلون يُعادون من المستدعي
     *   بعد اكتمال كل الصفحات (الآباء المتأخرون).
     */
    suspend fun ingestPage(records: List<Map<String, Any>>): PullApplyReport {
        var applied = 0
        var skipped = 0
        var failed = 0
        var firstError: String? = null
        val deferred = mutableListOf<DeferredRecord>()

        db.withTransaction {
            for (record in records) {
                when (val outcome = applyRecord(record)) {
                    is ApplyOutcome.Applied -> applied++
                    is ApplyOutcome.Skipped -> skipped++
                    is ApplyOutcome.Deferred -> deferred += DeferredRecord(
                        entity = record["_entity"] as? String ?: "unknown",
                        record = record
                    )
                    is ApplyOutcome.Failed -> {
                        failed++
                        if (firstError == null) firstError = outcome.error
                    }
                }
            }
        }
        return PullApplyReport(applied, skipped, failed, firstError, deferred)
    }

    /** سجل استيعاب واحد (توافق الاستدعاءات القديمة) — بلا معاملة صفحة. */
    suspend fun ingest(record: Map<String, Any>): Boolean =
        applyRecord(record) is ApplyOutcome.Applied

    // ─── تطبيق سجل واحد ─────────────────────────────────────────

    private suspend fun applyRecord(record: Map<String, Any>): ApplyOutcome {
        val entity = record["_entity"] as? String ?: return ApplyOutcome.Skipped

        // نسخة قابلة للتعديل: يُزال _entity (ليس عموداً محلياً) ويُتعلم
        // الظل (server_id := id الخادمي AUTOINCREMENT — الرجل الأولى في
        // ترجمة الأبناء لاحقاً).
        val mapped = record.toMutableMap()
        mapped.remove("_entity")
        (record["id"] as? Number)?.let { mapped["server_id"] = it.toLong() }
        applyBaseDefaults(mapped)

        // ─── ترجمة FK (سلّم Dart: uuid → إرثي → ظلّ → تأجيل) ───
        when (entity) {
            "booking_nights" -> {
                // NOT NULL + uuid-cache على السلك — لا حلّ = تأجيل.
                val resolved = resolveBookingId(
                    uuid = asString(mapped["booking_uuid_cache"])
                ) ?: return ApplyOutcome.Deferred
                mapped["booking_local_id"] = resolved
            }
            "payments" -> {
                // nullable=true — لا حلّ يُطبَّق بـ NULL (عقد _fkRules).
                val resolved = resolveBookingId(
                    uuid = asString(mapped["booking_uuid_cache"]),
                    legacyServerId = asLong(mapped["server_booking_id"])
                )
                if (resolved != null) mapped["booking_local_id"] = resolved
                else mapped.remove("booking_local_id")
                // nullWhenUnresolvable=true — مؤشر صندوق ثانوي بلا مفتاح
                // عالمي على السلك: «تعذّرت الترجمة → NULL ولا يُعطَّل السحب».
                mapped.remove("cash_transaction_local_id")
            }
            "booking_notes" -> {
                // NOT NULL، لا uuid-cache على السلك — الرجل الإرثية فقط
                // (فضاء Appwrite) ثم التأجيل (عقد Dart الحرفي).
                val resolved = resolveBookingId(
                    uuid = null,
                    legacyServerId = asLong(mapped["booking_id"])
                ) ?: return ApplyOutcome.Deferred
                mapped["booking_id"] = resolved
            }
            "booking_price_adjustments" -> {
                // رجلان: booking_local_uuid مفتاح طبيعي ثم booking_uuid
                // (تكافؤ قاعدتَي Dart لهذا الجدول) — nullable=true.
                val resolvedAdj = resolveBookingByLocalUuid(
                    asString(mapped["booking_local_uuid"])
                ) ?: resolveBookingId(uuid = asString(mapped["booking_uuid"]))
                if (resolvedAdj != null) mapped["booking_local_id"] = resolvedAdj
                else mapped.remove("booking_local_id")
            }
            "salary_cycles" -> {
                val resolved = resolveEmployeeId(
                    uuid = asString(mapped["employee_uuid"]),
                    rawId = asLong(mapped["employee_id"])
                ) ?: return ApplyOutcome.Deferred
                mapped["employee_id"] = resolved
            }
            "salary_payments" -> {
                val resolved = resolveSalaryCycleId(
                    uuid = asString(mapped["cycle_uuid"]),
                    rawId = asLong(mapped["cycle_id"])
                ) ?: return ApplyOutcome.Deferred
                mapped["cycle_id"] = resolved
            }
            "salary_withdrawals" -> {
                val resolved = resolveEmployeeId(
                    uuid = asString(mapped["employee_uuid"]),
                    rawId = asLong(mapped["employee_id"])
                ) ?: return ApplyOutcome.Deferred
                mapped["employee_id"] = resolved
            }
            "salary_carry_over_logs" -> {
                val resolved = resolveEmployeeId(
                    uuid = asString(mapped["employee_uuid"]),
                    rawId = asLong(mapped["employee_id"])
                ) ?: return ApplyOutcome.Deferred
                mapped["employee_id"] = resolved
            }
            "inventory_transactions" -> {
                val resolved = resolveItemId(
                    uuid = asString(mapped["item_local_uuid"]),
                    rawId = asLong(mapped["item_id"])
                ) ?: return ApplyOutcome.Deferred
                mapped["item_id"] = resolved
            }
        }

        // ─── تسلسل + LWW ───
        return try {
            val clazz = entityClass(entity) ?: return ApplyOutcome.Skipped
            val entityGson = gsonFor(clazz)
            @Suppress("UNCHECKED_CAST")
            val remote = entityGson.fromJson(entityGson.toJson(mapped), clazz) as? BaseSyncEntity
                ?: return ApplyOutcome.Skipped
            if (remote.localUuid.isBlank()) return ApplyOutcome.Skipped
            val remoteLastModified = (record["last_modified"] as? Number)?.toLong() ?: 0L

            val existing = fetchExisting(entity, remote.localUuid)
                ?: fetchByNaturalKey(entity, remote)

            when {
                existing == null -> {
                    store(entity, remote)
                    ApplyOutcome.Applied
                }
                remoteLastModified >= existing.lastModified -> {
                    // استبدال الصف المحلي نفسه (REPLACE بذات المفتاح).
                    store(entity, remote.copyWithId(existing.id))
                    ApplyOutcome.Applied
                }
                // المحلي أحدث (تعديل محلي لم يُرفع بعد) — نحتفظ به.
                else -> ApplyOutcome.Skipped
            }
        } catch (e: Exception) {
            ApplyOutcome.Failed("${entity}: ${e.message ?: e.javaClass.simpleName}")
        }
    }

    /**
     * ✅ (2026-09-25) تحصين انحراف المخطط: حقول العمود الفقري المشترك
     * (BaseSyncEntity) غير القابلة للنل تُعبأ بقيمها الافتراضية عند
     * غيابها عن الصف الواصل — صف قديم في D1 أُضيف عمود بعده أو جدول
     * يفتقد عموداً لا يُفشل الاستيعاب كله (فلسفة Dart: «الصف يُطبَّق»).
     * الحقول الخاصة بالكيان تبقى صارمة — نقصها يعني انحرافاً حقيقياً
     * يجب أن يظهر كفشل مرئي لا صمت.
     */
    private fun applyBaseDefaults(mapped: MutableMap<String, Any>) {
        mapped.putIfAbsent("created_at", 0L)
        mapped.putIfAbsent("updated_at", 0L)
        mapped.putIfAbsent("last_modified", 0L)
        mapped.putIfAbsent("created_at_epoch", 0L)
        mapped.putIfAbsent("last_modified_epoch", 0L)
        mapped.putIfAbsent("version", 1)
        mapped.putIfAbsent("origin", "local")
        mapped.putIfAbsent("vector_clock", "{}")
        mapped.putIfAbsent("device_id", "")
        mapped.putIfAbsent("sync_timestamp", 0L)
    }

    /** الجلب بـ local_uuid — ثم بالمفتاح الطبيعي لليالي (دمج 398 ليلة). */
    private suspend fun fetchExisting(entity: String, localUuid: String): BaseSyncEntity? =
        when (entity) {
            "rooms" -> roomsDao.getByLocalUuid(localUuid)
            "bookings" -> bookingsDao.getByLocalUuid(localUuid)
            "payments" -> paymentsDao.getByLocalUuid(localUuid)
            "expenses" -> expensesDao.getByLocalUuid(localUuid)
            "employees" -> employeesDao.getByLocalUuid(localUuid)
            "debts" -> debtsDao.getByLocalUuid(localUuid)
            "booking_notes" -> bookingNotesDao.getByLocalUuid(localUuid)
            "booking_nights" -> bookingNightsDao.getByLocalUuid(localUuid)
            "booking_price_adjustments" -> bookingPriceAdjustmentsDao.getByLocalUuid(localUuid)
            "guest_infos" -> guestInfosDao.getByLocalUuid(localUuid)
            "shift_notes" -> shiftNotesDao.getByLocalUuid(localUuid)
            "salary_cycles" -> salaryCyclesDao.getByLocalUuid(localUuid)
            "salary_payments" -> salaryPaymentsDao.getByLocalUuid(localUuid)
            "salary_withdrawals" -> salaryWithdrawalsDao.getByLocalUuid(localUuid)
            "salary_carry_over_logs" -> salaryCarryOverLogsDao.getByLocalUuid(localUuid)
            "app_users" -> appUsersDao.getByLocalUuid(localUuid)
            "devices" -> devicesDao.getByLocalUuid(localUuid)
            "cash_transactions" -> cashTransactionsDao.getByLocalUuid(localUuid)
            "audit_logs" -> auditLogsDao.getByLocalUuid(localUuid)
            "payment_voids" -> paymentVoidsDao.getByLocalUuid(localUuid)
            "price_adjustments" -> priceAdjustmentsDao.getByLocalUuid(localUuid)
            "inventory_items" -> inventoryDao.getItemByLocalUuid(localUuid)
            "inventory_transactions" -> inventoryDao.getTransactionByLocalUuid(localUuid)
            "blacklist" -> blacklistEntriesDao.getByLocalUuid(localUuid)
            else -> null
        }

    /** المفتاح الطبيعي الوحيد المتزامن: ليلة الحجز (Dart _naturalUniqueKeys). */
    private suspend fun fetchByNaturalKey(
        entity: String,
        remote: BaseSyncEntity
    ): BaseSyncEntity? {
        if (entity != "booking_nights") return null
        val night = remote as? com.marina.marina.data.local.entity.BookingNightEntity
            ?: return null
        return bookingNightsDao.getByNaturalKey(night.bookingLocalId, night.hotelDayKey)
    }

    private suspend fun store(entity: String, value: BaseSyncEntity) {
        when (entity) {
            "rooms" -> roomsDao.insert(value as com.marina.marina.data.local.entity.RoomEntity)
            "bookings" -> bookingsDao.insert(value as com.marina.marina.data.local.entity.BookingEntity)
            "payments" -> paymentsDao.insert(value as com.marina.marina.data.local.entity.PaymentEntity)
            "expenses" -> expensesDao.insert(value as com.marina.marina.data.local.entity.ExpenseEntity)
            "employees" -> employeesDao.insert(value as com.marina.marina.data.local.entity.EmployeeEntity)
            "debts" -> debtsDao.insert(value as com.marina.marina.data.local.entity.DebtEntity)
            "booking_notes" -> bookingNotesDao.insert(value as com.marina.marina.data.local.entity.BookingNoteEntity)
            "booking_nights" -> bookingNightsDao.insert(value as com.marina.marina.data.local.entity.BookingNightEntity)
            "booking_price_adjustments" -> bookingPriceAdjustmentsDao.insert(value as com.marina.marina.data.local.entity.BookingPriceAdjustmentEntity)
            "guest_infos" -> guestInfosDao.insert(value as com.marina.marina.data.local.entity.GuestInfoEntity)
            "shift_notes" -> shiftNotesDao.insert(value as com.marina.marina.data.local.entity.ShiftNoteEntity)
            "salary_cycles" -> salaryCyclesDao.insert(value as com.marina.marina.data.local.entity.SalaryCycleEntity)
            "salary_payments" -> salaryPaymentsDao.insert(value as com.marina.marina.data.local.entity.SalaryPaymentEntity)
            "salary_withdrawals" -> salaryWithdrawalsDao.insert(value as com.marina.marina.data.local.entity.SalaryWithdrawalEntity)
            "salary_carry_over_logs" -> salaryCarryOverLogsDao.insert(value as com.marina.marina.data.local.entity.SalaryCarryOverLogEntity)
            "app_users" -> appUsersDao.insert(value as com.marina.marina.data.local.entity.AppUserEntity)
            "devices" -> devicesDao.insert(value as com.marina.marina.data.local.entity.DeviceInfoEntity)
            "cash_transactions" -> cashTransactionsDao.insert(value as com.marina.marina.data.local.entity.CashTransactionEntity)
            "audit_logs" -> auditLogsDao.insert(value as com.marina.marina.data.local.entity.AuditLogEntity)
            "payment_voids" -> paymentVoidsDao.insert(value as com.marina.marina.data.local.entity.PaymentVoidEntity)
            "price_adjustments" -> priceAdjustmentsDao.insert(value as com.marina.marina.data.local.entity.PriceAdjustmentEntity)
            "inventory_items" -> inventoryDao.insertItem(value as com.marina.marina.data.local.entity.InventoryItemEntity)
            "inventory_transactions" -> inventoryDao.insertTransaction(value as com.marina.marina.data.local.entity.InventoryTransactionEntity)
            "blacklist" -> blacklistEntriesDao.insert(value as com.marina.marina.data.local.entity.BlacklistEntryEntity)
        }
    }

    // ─── محلّلات الهوية (تكافؤ IdResolver في Dart) ──────────────

    /**
     * حلّ مرجع حجز → id محلي. السلّم: uuid (3 صيغ) → الرجل الإرثية
     * (فضاء Appwrite عبر server_booking_id للحجز). **لا id خام من
     * جهاز بعيد أبداً** — يربط الابن بحجز خاطئ (تعليق Dart الحرج).
     */
    private suspend fun resolveBookingId(
        uuid: String?,
        legacyServerId: Long? = null
    ): Long? {
        uuid?.takeIf { it.isNotEmpty() }?.let { candidate ->
            bookingsDao.getByLocalUuid(candidate)?.let { return it.id }
            normalizeUuid(candidate)?.takeIf { it != candidate }?.let { dashed ->
                bookingsDao.getByLocalUuid(dashed)?.let { return it.id }
            }
            stripDashes(candidate).takeIf { it != candidate && it.length == 32 }?.let { stripped ->
                bookingsDao.getByLocalUuid(stripped)?.let { return it.id }
            }
        }
        legacyServerId?.let { legacy ->
            bookingsDao.getByServerBookingIdIncludingDeleted(legacy)?.let { return it.id }
        }
        return null
    }

    /** المفتاح الطبيعي للتعديلات: booking_local_uuid → حجز (3 صيغ). */
    private suspend fun resolveBookingByLocalUuid(uuid: String?): Long? {
        val candidate = uuid?.takeIf { it.isNotEmpty() } ?: return null
        bookingsDao.getByLocalUuid(candidate)?.let { return it.id }
        normalizeUuid(candidate)?.takeIf { it != candidate }?.let { dashed ->
            bookingsDao.getByLocalUuid(dashed)?.let { return it.id }
        }
        stripDashes(candidate).takeIf { it != candidate && it.length == 32 }?.let { stripped ->
            bookingsDao.getByLocalUuid(stripped)?.let { return it.id }
        }
        return null
    }

    /**
     * حلّ مرجع موظف → id محلي: uuid (3 صيغ) → ظلّ server_id (حسم
     * الازدواج: النشط أولاً ثم الأصغر id — عقد Dart).
     */
    private suspend fun resolveEmployeeId(uuid: String?, rawId: Long?): Long? {
        uuid?.takeIf { it.isNotEmpty() }?.let { candidate ->
            employeesDao.getByLocalUuid(candidate)?.let { return it.id }
            normalizeUuid(candidate)?.takeIf { it != candidate }?.let { dashed ->
                employeesDao.getByLocalUuid(dashed)?.let { return it.id }
            }
            stripDashes(candidate).takeIf { it != candidate && it.length == 32 }?.let { stripped ->
                employeesDao.getByLocalUuid(stripped)?.let { return it.id }
            }
        }
        rawId?.let { raw ->
            employeesDao.getByServerIdIncludingDeleted(raw)?.let { return it.id }
        }
        return null
    }

    /** حلّ مرجع دورة راتب: cycle_uuid (3 صيغ) → ظلّ server_id. */
    private suspend fun resolveSalaryCycleId(uuid: String?, rawId: Long?): Long? {
        uuid?.takeIf { it.isNotEmpty() }?.let { candidate ->
            salaryCyclesDao.getByLocalUuid(candidate)?.let { return it.id }
            normalizeUuid(candidate)?.takeIf { it != candidate }?.let { dashed ->
                salaryCyclesDao.getByLocalUuid(dashed)?.let { return it.id }
            }
            stripDashes(candidate).takeIf { it != candidate && it.length == 32 }?.let { stripped ->
                salaryCyclesDao.getByLocalUuid(stripped)?.let { return it.id }
            }
        }
        rawId?.let { raw ->
            salaryCyclesDao.getByServerIdIncludingDeleted(raw)?.let { return it.id }
        }
        return null
    }

    /** حلّ مرجع صنف مخزون: item_local_uuid (3 صيغ) → ظلّ server_id. */
    private suspend fun resolveItemId(uuid: String?, rawId: Long?): Long? {
        uuid?.takeIf { it.isNotEmpty() }?.let { candidate ->
            inventoryDao.getItemByLocalUuid(candidate)?.let { return it.id }
            normalizeUuid(candidate)?.takeIf { it != candidate }?.let { dashed ->
                inventoryDao.getItemByLocalUuid(dashed)?.let { return it.id }
            }
            stripDashes(candidate).takeIf { it != candidate && it.length == 32 }?.let { stripped ->
                inventoryDao.getItemByLocalUuid(stripped)?.let { return it.id }
            }
        }
        rawId?.let { raw ->
            inventoryDao.getItemByServerIdIncludingDeleted(raw)?.let { return it.id }
        }
        return null
    }

    // ─── أدوات UUID (تكافؤ normalizeUuid/stripDashes في Dart) ───

    /** 32 خانة سداسية عشري بلا شرطات → الصيغة المعيارية المشرطة. */
    private fun normalizeUuid(raw: String): String? {
        val trimmed = raw.trim().lowercase()
        if (trimmed.length != 32) return null
        if (trimmed.any { it !in '0'..'9' && it !in 'a'..'f' }) return null
        return buildString {
            append(trimmed, 0, 8); append('-')
            append(trimmed, 8, 12); append('-')
            append(trimmed, 12, 16); append('-')
            append(trimmed, 16, 20); append('-')
            append(trimmed, 20, 32)
        }
    }

    private fun stripDashes(raw: String): String = raw.replace("-", "").lowercase()

    // ─── أدوات قراءة آمنة من الخريطة ────────────────────────────

    private fun asString(value: Any?): String? = (value as? String)?.takeIf { it.isNotBlank() }

    private fun asLong(value: Any?): Long? = when (value) {
        is Number -> value.toLong()
        is String -> value.toLongOrNull()
        else -> null
    }

    /** نسخ الكيان مع استبدال id — Gson round-trip بديل آمن عن copy(). */
    @Suppress("UNCHECKED_CAST")
    private fun <T : BaseSyncEntity> T.copyWithId(newId: Long): T {
        val entityGson = gsonFor(this.javaClass)
        val json = entityGson.toJson(this)
        val map = entityGson.fromJson<Map<String, Any>>(json, Map::class.java)
            .toMutableMap()
        map["id"] = newId
        return entityGson.fromJson(entityGson.toJson(map), this.javaClass) as T
    }

    /** خريطة الكيان → صنف الـ Room المطابق (مرآة جدول D1). */
    private fun entityClass(entity: String): Class<*>? = when (entity) {
        "rooms" -> com.marina.marina.data.local.entity.RoomEntity::class.java
        "bookings" -> com.marina.marina.data.local.entity.BookingEntity::class.java
        "payments" -> com.marina.marina.data.local.entity.PaymentEntity::class.java
        "expenses" -> com.marina.marina.data.local.entity.ExpenseEntity::class.java
        "employees" -> com.marina.marina.data.local.entity.EmployeeEntity::class.java
        "debts" -> com.marina.marina.data.local.entity.DebtEntity::class.java
        "booking_notes" -> com.marina.marina.data.local.entity.BookingNoteEntity::class.java
        "booking_nights" -> com.marina.marina.data.local.entity.BookingNightEntity::class.java
        "booking_price_adjustments" -> com.marina.marina.data.local.entity.BookingPriceAdjustmentEntity::class.java
        "guest_infos" -> com.marina.marina.data.local.entity.GuestInfoEntity::class.java
        "shift_notes" -> com.marina.marina.data.local.entity.ShiftNoteEntity::class.java
        "salary_cycles" -> com.marina.marina.data.local.entity.SalaryCycleEntity::class.java
        "salary_payments" -> com.marina.marina.data.local.entity.SalaryPaymentEntity::class.java
        "salary_withdrawals" -> com.marina.marina.data.local.entity.SalaryWithdrawalEntity::class.java
        "salary_carry_over_logs" -> com.marina.marina.data.local.entity.SalaryCarryOverLogEntity::class.java
        "app_users" -> com.marina.marina.data.local.entity.AppUserEntity::class.java
        "devices" -> com.marina.marina.data.local.entity.DeviceInfoEntity::class.java
        "cash_transactions" -> com.marina.marina.data.local.entity.CashTransactionEntity::class.java
        "audit_logs" -> com.marina.marina.data.local.entity.AuditLogEntity::class.java
        "payment_voids" -> com.marina.marina.data.local.entity.PaymentVoidEntity::class.java
        "price_adjustments" -> com.marina.marina.data.local.entity.PriceAdjustmentEntity::class.java
        "inventory_items" -> com.marina.marina.data.local.entity.InventoryItemEntity::class.java
        "inventory_transactions" -> com.marina.marina.data.local.entity.InventoryTransactionEntity::class.java
        "blacklist" -> com.marina.marina.data.local.entity.BlacklistEntryEntity::class.java
        else -> null
    }
}
