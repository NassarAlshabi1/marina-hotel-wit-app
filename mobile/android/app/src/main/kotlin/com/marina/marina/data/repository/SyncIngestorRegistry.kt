package com.marina.marina.data.repository

import androidx.room.withTransaction
import com.google.gson.ExclusionStrategy
import com.google.gson.FieldAttributes
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.annotations.SerializedName
import com.google.gson.reflect.TypeToken
import com.marina.marina.data.local.entity.PendingSyncLinkEntity
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
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.ExpenseEntity
import com.marina.marina.data.local.entity.SalaryCarryOverLogEntity
import com.marina.marina.data.local.entity.SalaryCycleEntity
import com.marina.marina.data.local.entity.SalaryPaymentEntity
import com.marina.marina.data.local.entity.SalaryWithdrawalEntity
import com.marina.marina.domain.util.HotelTimeEngine
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
 *    UUID هو المرجع الحاسم (بصيغته المعيارية/المضغوطة وبلا حساسية لحالة
 *    الأحرف)، وتُقبل رجل server_id الإرثية فقط إذا غاب UUID تماماً؛ لا
 *    fallback عند فشل UUID ولا تخمين عند تعدد النتائج. غير المحلول يُؤجَّل
 *    أو يبقى NULL للعلاقة الاختيارية. **لا يُستخدم id الخام من جهاز بعيد
 *    أبداً** («employeeId=5 على جهاز A ≠ جهاز B»).
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

/** Keep the Android Int version contract aligned with the Worker sanitizer. */
private const val MAX_SANE_SYNC_VERSION = 1_000_000
private val EMPLOYEE_EXPENSE_TYPES = setOf(
    "رواتب", "سحب راتب", "سحب من الراتب", "سلفة", "خصم راتب", "خصم من الراتب", "خصم", "غياب", "employee"
)

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
    private val booleanWireFieldsCache = java.util.concurrent.ConcurrentHashMap<Class<*>, Set<String>>()

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

    /** D1/SQLite booleans arrive over both sync transports as INTEGER 0/1. */
    private fun normalizeBooleanWireFields(mapped: MutableMap<String, Any>, clazz: Class<*>) {
        val fieldNames = booleanWireFieldsCache.getOrPut(clazz) {
            generateSequence(clazz) { it.superclass }
                .takeWhile { it != Any::class.java }
                .flatMap { it.declaredFields.asSequence() }
                .filter { field ->
                    field.type == Boolean::class.javaPrimitiveType ||
                        field.type == Boolean::class.javaObjectType
                }
                .map { field ->
                    field.getAnnotation(SerializedName::class.java)?.value ?: field.name
                }
                .toSet()
        }

        fieldNames.forEach { name ->
            val wireValue = mapped[name] ?: return@forEach
            val booleanValue = when (wireValue) {
                is Boolean -> wireValue
                is Number -> wireValue.toDouble() != 0.0
                is String -> when (val normalized = wireValue.trim().lowercase()) {
                    "true" -> true
                    "false" -> false
                    else -> normalized.toDoubleOrNull()?.let { it != 0.0 }
                }
                else -> null
            }
            if (booleanValue != null) mapped[name] = booleanValue
        }
    }

    /**
     * D1 can contain legacy `version` values polluted by old bulk migrations
     * (for example 1e12). Gson cannot deserialize those into the app's Int
     * field. Match the Worker policy: values outside the sane range reset to 1.
     */
    private fun normalizeSyncVersionWireField(mapped: MutableMap<String, Any>) {
        if (!mapped.containsKey("version")) return
        val rawVersion = mapped["version"]
        val numericVersion = when (rawVersion) {
            is Number -> rawVersion.toDouble()
            is String -> rawVersion.trim().toDoubleOrNull()
            else -> null
        }
        val saneVersion = numericVersion?.takeIf {
            it.isFinite() &&
                it >= 0.0 &&
                it <= MAX_SANE_SYNC_VERSION.toDouble() &&
                it % 1.0 == 0.0
        }
        mapped["version"] = saneVersion?.toInt() ?: 1
    }

    /**
     * D1 stores `salary_withdrawals.withdraw_date` as TEXT (usually yyyy-MM-dd),
     * while the local Room entity stores epoch milliseconds. Normalize at the
     * wire boundary before Gson attempts to coerce the date string to Long.
     */
    private suspend fun normalizeSalaryWithdrawalFields(mapped: MutableMap<String, Any>) {
        val rawDate = mapped["withdraw_date"]
            ?: throw IllegalArgumentException("salary_withdrawals.withdraw_date is missing")
        val withdrawDateMillis = when (rawDate) {
            is Number -> normalizeEpochMillis(rawDate.toLong())
            is String -> {
                val raw = rawDate.trim()
                val numeric = raw.toLongOrNull()
                if (numeric != null) {
                    normalizeEpochMillis(numeric)
                } else {
                    HotelTimeEngine.parseDate(raw)
                }
            }
            else -> null
        } ?: throw IllegalArgumentException(
            "salary_withdrawals.withdraw_date has an unsupported date format"
        )
        mapped["withdraw_date"] = withdrawDateMillis

        // `employee_name` is a local display snapshot and is not present in
        // every deployed Worker schema. Never let its absence turn an otherwise
        // valid salary row into a NOT NULL insert failure.
        val remoteName = (mapped["employee_name"] as? String)?.trim().orEmpty()
        if (remoteName.isEmpty()) {
            val employeeUuid = asString(mapped["employee_uuid"])
            val employee = employeeUuid?.let { employeesDao.getByLocalUuid(it) }
                ?: asLong(mapped["employee_id"])?.let { employeesDao.getByIdIncludingDeleted(it) }
            mapped["employee_name"] = employee?.name.orEmpty()
        }
    }

    private fun normalizeEpochMillis(value: Long): Long =
        if (value in -99_999_999_999L..99_999_999_999L) value * 1_000L else value

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
                val entity = record["_entity"] as? String ?: "unknown"
                val uuid = record["local_uuid"] as? String ?: ""
                val outcome = applyRecord(record)
                if (outcome is ApplyOutcome.Deferred) {
                    require(uuid.isNotBlank()) { "Deferred row has no local_uuid" }
                    db.pendingSyncLinksDao().put(PendingSyncLinkEntity(entity, uuid, Gson().toJson(record)))
                } else if (outcome is ApplyOutcome.Applied || outcome is ApplyOutcome.Skipped) {
                    db.pendingSyncLinksDao().remove(entity, uuid)
                }
                when (outcome) {
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

    /** Retry across process restarts; parent/child chains may require more than one pass. */
    suspend fun retryPendingLinks(): PullApplyReport {
        var total = 0
        while (true) {
            val pending = db.pendingSyncLinksDao().getAll()
            if (pending.isEmpty()) return PullApplyReport(total, 0, 0, null, emptyList())
            val type = object : TypeToken<Map<String, Any>>() {}.type
            val report = ingestPage(pending.map { Gson().fromJson<Map<String, Any>>(it.payload, type) })
            total += report.applied
            if (report.hasFailures || report.applied == 0) return report.copy(applied = total)
        }
    }

    suspend fun clearPendingLinksForEpochReset() = db.pendingSyncLinksDao().clear()

    /** سجل استيعاب واحد (توافق الاستدعاءات القديمة) — بلا معاملة صفحة. */
    suspend fun ingest(record: Map<String, Any>): Boolean =
        ingestPage(listOf(record)).applied == 1

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
        val existingForLink = if (
            entity in setOf("expenses", "salary_cycles", "salary_payments", "salary_withdrawals", "salary_carry_over_logs")
        ) {
            asString(mapped["local_uuid"])?.trim()?.takeIf { it.isNotEmpty() }?.let { fetchExisting(entity, it) }
        } else {
            null
        }

        // ─── ترجمة FK (UUID أولاً؛ أي fallback عددي فريد فقط) ───
        when (entity) {
            "booking_nights" -> {
                // Prefer the stable parent UUID; legacy server_booking_id is
                // only a compatibility fallback. Never trust the sender's
                // device-local booking_local_id as a local Room id.
                val resolved = resolveBookingId(
                    uuid = asString(mapped["booking_uuid_cache"]),
                    legacyServerId = asLong(mapped["server_booking_id"])
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
            "expenses" -> {
                val existing = existingForLink as? ExpenseEntity
                val incomingUuid = asString(mapped["employee_uuid"])?.trim()?.takeIf { it.isNotEmpty() }
                val explicitUnlink =
                    mapped["employee_link_cleared"] == true ||
                        asLong(mapped["employee_link_cleared"]) == 1L ||
                        mapped["clear_employee_link"] == true ||
                        asLong(mapped["clear_employee_link"]) == 1L
                mapped.remove("employee_link_cleared")
                mapped.remove("clear_employee_link")
                when {
                    explicitUnlink -> {
                        mapped.remove("employee_uuid")
                        mapped.remove("related_id")
                    }
                    incomingUuid != null -> {
                        val employee = resolveEmployee(uuid = incomingUuid, rawId = null)
                        if (employee != null) {
                            mapped["employee_uuid"] = employee.localUuid
                            mapped["related_id"] = employee.id
                        } else {
                            // Preserve the incoming identity in the durable inbox, not the old employee.
                            return ApplyOutcome.Deferred
                        }
                    }
                    existing != null -> preserveExpenseEmployeeLink(mapped, existing)
                    asString(mapped["expense_type"])?.trim()?.lowercase()?.let { it in EMPLOYEE_EXPENSE_TYPES } == true -> {
                        mapped.remove("employee_uuid")
                        mapped.remove("related_id")
                    }
                    else -> Unit
                }
            }
            "salary_cycles" -> {
                val existing = existingForLink as? SalaryCycleEntity
                if (!mapEmployeeReference(
                        mapped = mapped,
                        uuidKey = "employee_uuid",
                        idKey = "employee_id",
                        rawId = asLong(mapped["employee_id"]),
                        existingId = existing?.employeeId,
                        existingUuid = existing?.employeeUuid
                    )
                ) return ApplyOutcome.Deferred
            }
            "salary_payments" -> {
                val existing = existingForLink as? SalaryPaymentEntity
                val incomingCycleUuid = asString(mapped["cycle_uuid"])?.trim()?.takeIf { it.isNotEmpty() }
                if (incomingCycleUuid == null && existing != null) {
                    mapped["cycle_id"] = existing.cycleId
                    existing.cycleUuid?.let { mapped["cycle_uuid"] = it } ?: mapped.remove("cycle_uuid")
                    existing.employeeUuid?.let { mapped["employee_uuid"] = it } ?: mapped.remove("employee_uuid")
                } else {
                    val cycle = resolveSalaryCycle(
                        uuid = incomingCycleUuid,
                        rawId = if (incomingCycleUuid == null) asLong(mapped["cycle_id"]) else null
                    ) ?: return ApplyOutcome.Deferred
                    val suppliedEmployeeUuid = asString(mapped["employee_uuid"])?.trim()?.takeIf { it.isNotEmpty() }
                    val cycleEmployeeUuid = cycle.employeeUuid?.trim()?.takeIf { it.isNotEmpty() }
                    if (
                        suppliedEmployeeUuid != null && cycleEmployeeUuid != null &&
                        uuidComparable(suppliedEmployeeUuid) != uuidComparable(cycleEmployeeUuid)
                    ) {
                        return ApplyOutcome.Failed("salary_payments.employee_uuid does not match cycle_uuid")
                    }
                    mapped["cycle_id"] = cycle.id
                    mapped["cycle_uuid"] = cycle.localUuid
                    when {
                        cycleEmployeeUuid != null -> mapped["employee_uuid"] = cycleEmployeeUuid
                        suppliedEmployeeUuid != null -> {
                            val employee = resolveEmployee(uuid = suppliedEmployeeUuid, rawId = null)
                                ?: return ApplyOutcome.Deferred
                            mapped["employee_uuid"] = employee.localUuid
                        }
                        else -> mapped.remove("employee_uuid")
                    }
                }
            }
            "salary_withdrawals" -> {
                val existing = existingForLink as? SalaryWithdrawalEntity
                if (asString(mapped["expense_uuid"]).isNullOrBlank()) {
                    existing?.expenseUuid?.let { mapped["expense_uuid"] = it }
                }
                if (!mapEmployeeReference(
                        mapped = mapped,
                        uuidKey = "employee_uuid",
                        idKey = "employee_id",
                        rawId = asLong(mapped["employee_id"]),
                        existingId = existing?.employeeId,
                        existingUuid = existing?.employeeUuid
                    )
                ) return ApplyOutcome.Deferred
            }
            "salary_carry_over_logs" -> {
                val existing = existingForLink as? SalaryCarryOverLogEntity
                if (!mapEmployeeReference(
                        mapped = mapped,
                        uuidKey = "employee_uuid",
                        idKey = "employee_id",
                        rawId = asLong(mapped["employee_id"]),
                        existingId = existing?.employeeId,
                        existingUuid = existing?.employeeUuid
                    )
                ) return ApplyOutcome.Deferred
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
            normalizeBooleanWireFields(mapped, clazz)
            normalizeSyncVersionWireField(mapped)
            if (entity == "salary_withdrawals") normalizeSalaryWithdrawalFields(mapped)
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
                remote.deletedAt != null -> {
                    // A tombstone is a terminal server decision. Apply only
                    // its sync fields so a stale remote snapshot cannot also
                    // overwrite newer local business data.
                    applyRemoteTombstone(
                        entity = entity,
                        localId = existing.id,
                        deletedAt = requireNotNull(remote.deletedAt),
                        updatedAt = remote.updatedAt
                    )
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

    /** Apply only deletion metadata, preserving newer local business fields. */
    private fun applyRemoteTombstone(
        entity: String,
        localId: Long,
        deletedAt: Long,
        updatedAt: Long
    ) {
        val table = localTableName(entity)
            ?: throw IllegalArgumentException("No local table for tombstoned entity: $entity")
        db.openHelper.writableDatabase.execSQL(
            "UPDATE $table SET deleted_at = ?, updated_at = ?, last_modified = ? WHERE id = ?",
            arrayOf<Any?>(deletedAt, updatedAt, updatedAt, localId)
        )
    }

    /**
     * Immediately mirror the server's delete-wins push disposition locally.
     * The following pull remains authoritative and can refresh the exact
     * server timestamp; this prevents a stale edited row from staying visible
     * when the user selected push-only.
     */
    suspend fun tombstoneLocalRecord(entity: String, localUuid: String): Boolean {
        val canonicalEntity = if (entity == "blacklist_entries") "blacklist" else entity
        val existing = fetchExisting(canonicalEntity, localUuid) ?: return false
        if (existing.deletedAt != null) return true
        val table = localTableName(canonicalEntity) ?: return false
        val now = System.currentTimeMillis() / 1_000L
        db.withTransaction {
            db.openHelper.writableDatabase.execSQL(
                "UPDATE $table SET deleted_at = ?, updated_at = ?, last_modified = ? WHERE id = ?",
                arrayOf<Any?>(now, now, now, existing.id)
            )
        }
        return true
    }

    /** Local table mapping is explicit so dynamic SQL never uses wire input. */
    private fun localTableName(entity: String): String? = when (entity) {
        "rooms" -> "rooms"
        "bookings" -> "bookings"
        "payments" -> "payments"
        "expenses" -> "expenses"
        "employees" -> "employees"
        "debts" -> "debts"
        "booking_notes" -> "booking_notes"
        "booking_nights" -> "booking_nights"
        "booking_price_adjustments" -> "booking_price_adjustments"
        "guest_infos" -> "guest_infos"
        "shift_notes" -> "shift_notes"
        "salary_cycles" -> "salary_cycles"
        "salary_payments" -> "salary_payments"
        "salary_withdrawals" -> "salary_withdrawals"
        "salary_carry_over_logs" -> "salary_carry_over_logs"
        "app_users" -> "app_users"
        "devices" -> "devices"
        "cash_transactions" -> "cash_transactions"
        "audit_logs" -> "audit_logs"
        "payment_voids" -> "payment_voids"
        "price_adjustments" -> "price_adjustments"
        "inventory_items" -> "inventory_items"
        "inventory_transactions" -> "inventory_transactions"
        "blacklist", "blacklist_entries" -> "blacklist_entries"
        else -> null
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

    /** UUID is authoritative; a legacy server_booking_id is considered only when UUID is absent. */
    private suspend fun resolveBookingId(
        uuid: String?,
        legacyServerId: Long? = null
    ): Long? {
        val candidate = uuid?.trim()?.takeIf { it.isNotEmpty() }
        if (candidate != null) {
            val forms = linkedSetOf(candidate)
            val dashless = stripDashes(candidate)
            if (dashless.length == 32) {
                forms.add(dashless)
                normalizeUuid(dashless)?.let(forms::add)
            }
            return forms.flatMap { bookingsDao.getByLocalUuidCandidates(it) }
                .distinctBy { it.id }
                .singleOrNull()
                ?.id
        }
        val legacy = legacyServerId ?: return null
        return bookingsDao.getByServerBookingIdCandidates(legacy).singleOrNull()?.id
    }

    /** Natural-key resolver for booking_local_uuid; ambiguous variants are rejected. */
    private suspend fun resolveBookingByLocalUuid(uuid: String?): Long? {
        val candidate = uuid?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val forms = linkedSetOf(candidate)
        val dashless = stripDashes(candidate)
        if (dashless.length == 32) {
            forms.add(dashless)
            normalizeUuid(dashless)?.let(forms::add)
        }
        return forms.flatMap { bookingsDao.getByLocalUuidCandidates(it) }
            .distinctBy { it.id }
            .singleOrNull()
            ?.id
    }

    /** UUID wins absolutely; only UUID-absent legacy rows may use a unique server_id shadow. */
    private suspend fun resolveEmployee(uuid: String?, rawId: Long?): EmployeeEntity? {
        val candidate = uuid?.trim()?.takeIf { it.isNotEmpty() }
        if (candidate != null) {
            val forms = linkedSetOf(candidate)
            val dashless = stripDashes(candidate)
            if (dashless.length == 32) {
                forms.add(dashless)
                normalizeUuid(dashless)?.let(forms::add)
            }
            val matches = forms.flatMap { employeesDao.getByLocalUuidCandidates(it) }
                .distinctBy { it.id }
            return matches.singleOrNull()
        }
        val legacyId = rawId ?: return null
        return employeesDao.getByServerIdCandidates(legacyId).singleOrNull()
    }

    /** UUID wins absolutely; duplicates or unresolved UUIDs are never guessed. */
    private suspend fun resolveSalaryCycle(uuid: String?, rawId: Long?): SalaryCycleEntity? {
        val candidate = uuid?.trim()?.takeIf { it.isNotEmpty() }
        if (candidate != null) {
            val forms = linkedSetOf(candidate)
            val dashless = stripDashes(candidate)
            if (dashless.length == 32) {
                forms.add(dashless)
                normalizeUuid(dashless)?.let(forms::add)
            }
            val matches = forms.flatMap { salaryCyclesDao.getByLocalUuidCandidates(it) }
                .distinctBy { it.id }
            return matches.singleOrNull()
        }
        val legacyId = rawId ?: return null
        return salaryCyclesDao.getByServerIdCandidates(legacyId).singleOrNull()
    }

    /** A link already stored locally survives UUID-absent snapshots unchanged. */
    private suspend fun mapEmployeeReference(
        mapped: MutableMap<String, Any>,
        uuidKey: String,
        idKey: String,
        rawId: Long?,
        existingId: Long?,
        existingUuid: String?
    ): Boolean {
        val incomingUuid = asString(mapped[uuidKey])?.trim()?.takeIf { it.isNotEmpty() }
        if (incomingUuid != null) {
            val employee = resolveEmployee(uuid = incomingUuid, rawId = null) ?: return false
            mapped[uuidKey] = employee.localUuid
            mapped[idKey] = employee.id
            return true
        }

        if (existingId != null) {
            mapped[idKey] = existingId
            existingUuid?.takeIf { it.isNotBlank() }?.let { mapped[uuidKey] = it } ?: mapped.remove(uuidKey)
            return true
        }

        val employee = resolveEmployee(uuid = null, rawId = rawId) ?: return false
        mapped[uuidKey] = employee.localUuid
        mapped[idKey] = employee.id
        return true
    }

    private fun preserveExpenseEmployeeLink(mapped: MutableMap<String, Any>, existing: ExpenseEntity) {
        existing.employeeUuid?.takeIf { it.isNotBlank() }?.let { mapped["employee_uuid"] = it }
            ?: mapped.remove("employee_uuid")
        existing.relatedId?.let { mapped["related_id"] = it } ?: mapped.remove("related_id")
    }

    private fun uuidComparable(value: String): String =
        value.trim().replace("-", "").lowercase()

    /** UUID is authoritative; a unique server_id shadow is legacy-only. */
    private suspend fun resolveItemId(uuid: String?, rawId: Long?): Long? {
        val candidate = uuid?.trim()?.takeIf { it.isNotEmpty() }
        if (candidate != null) {
            val forms = linkedSetOf(candidate)
            val dashless = stripDashes(candidate)
            if (dashless.length == 32) {
                forms.add(dashless)
                normalizeUuid(dashless)?.let(forms::add)
            }
            return forms.flatMap { inventoryDao.getItemByLocalUuidCandidates(it) }
                .distinctBy { it.id }
                .singleOrNull()
                ?.id
        }
        val legacyId = rawId ?: return null
        return inventoryDao.getItemByServerIdCandidates(legacyId).singleOrNull()?.id
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
