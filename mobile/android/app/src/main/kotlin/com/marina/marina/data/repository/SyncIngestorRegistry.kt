package com.marina.marina.data.repository

import com.google.gson.Gson
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
 * ✅ (2026-09-24) محرك استيعاب سجلات السحب — يوجّه كل سجل بعلامة `_entity`
 * (يضيفها الخادم لكل سجل في pullChanges) إلى الجدول المحلي الصحيح ويطبّق
 * آخر-كتابة-تفوز بمقارنة last_modified (تكافؤ ingestRecord القديم لكن
 * لكل الكيانات المتزامنة بدل 6 فقط).
 *
 * الحذف: السجلات المحذوفة تحمل deleted_at من الخادم — تُستوعب كصفوف
 * محذوفة ناعماً (الاستعلامات النشطة تفلتر deleted_at IS NULL)، أي أن
 * tombstone الواصل من جهاز آخر يُطبع محلياً كما يجب.
 *
 * hotel_day_ledger مستبعد عمداً (تأكيد المالك 2026-09-05: «جدول محلي لا
 * أريد أن يتم مزامنته») — محلي-فقط بالتصميم (خطة D8).
 */
@Singleton
class SyncIngestorRegistry @Inject constructor(
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
    private val gson = Gson()

    /** سجل استيعاب واحد: سجل → upsert محلي. يعيد false عند كيان غير مدعوم. */
    suspend fun ingest(record: Map<String, Any>): Boolean {
        val entity = record["_entity"] as? String ?: return false
        val remoteLastModified = (record["last_modified"] as? Number)?.toLong() ?: 0L
        return when (entity) {
            "rooms" -> upsert<com.marina.marina.data.local.entity.RoomEntity>(
                record, remoteLastModified,
                fetch = { roomsDao.getByLocalUuid(it) },
                store = { roomsDao.insert(it) }
            )
            "bookings" -> upsert<com.marina.marina.data.local.entity.BookingEntity>(
                record, remoteLastModified,
                fetch = { bookingsDao.getByLocalUuid(it) },
                store = { bookingsDao.insert(it) }
            )
            "payments" -> upsert<com.marina.marina.data.local.entity.PaymentEntity>(
                record, remoteLastModified,
                fetch = { paymentsDao.getByLocalUuid(it) },
                store = { paymentsDao.insert(it) }
            )
            "expenses" -> upsert<com.marina.marina.data.local.entity.ExpenseEntity>(
                record, remoteLastModified,
                fetch = { expensesDao.getByLocalUuid(it) },
                store = { expensesDao.insert(it) }
            )
            "employees" -> upsert<com.marina.marina.data.local.entity.EmployeeEntity>(
                record, remoteLastModified,
                fetch = { employeesDao.getByLocalUuid(it) },
                store = { employeesDao.insert(it) }
            )
            "debts" -> upsert<com.marina.marina.data.local.entity.DebtEntity>(
                record, remoteLastModified,
                fetch = { debtsDao.getByLocalUuid(it) },
                store = { debtsDao.insert(it) }
            )
            "booking_notes" -> upsert<com.marina.marina.data.local.entity.BookingNoteEntity>(
                record, remoteLastModified,
                fetch = { bookingNotesDao.getByLocalUuid(it) },
                store = { bookingNotesDao.insert(it) }
            )
            "booking_nights" -> upsert<com.marina.marina.data.local.entity.BookingNightEntity>(
                record, remoteLastModified,
                fetch = { bookingNightsDao.getByLocalUuid(it) },
                store = { bookingNightsDao.insert(it) }
            )
            "booking_price_adjustments" -> upsert<com.marina.marina.data.local.entity.BookingPriceAdjustmentEntity>(
                record, remoteLastModified,
                fetch = { bookingPriceAdjustmentsDao.getByLocalUuid(it) },
                store = { bookingPriceAdjustmentsDao.insert(it) }
            )
            "guest_infos" -> upsert<com.marina.marina.data.local.entity.GuestInfoEntity>(
                record, remoteLastModified,
                fetch = { guestInfosDao.getByLocalUuid(it) },
                store = { guestInfosDao.insert(it) }
            )
            "shift_notes" -> upsert<com.marina.marina.data.local.entity.ShiftNoteEntity>(
                record, remoteLastModified,
                fetch = { shiftNotesDao.getByLocalUuid(it) },
                store = { shiftNotesDao.insert(it) }
            )
            "salary_cycles" -> upsert<com.marina.marina.data.local.entity.SalaryCycleEntity>(
                record, remoteLastModified,
                fetch = { salaryCyclesDao.getByLocalUuid(it) },
                store = { salaryCyclesDao.insert(it) }
            )
            "salary_payments" -> upsert<com.marina.marina.data.local.entity.SalaryPaymentEntity>(
                record, remoteLastModified,
                fetch = { salaryPaymentsDao.getByLocalUuid(it) },
                store = { salaryPaymentsDao.insert(it) }
            )
            "salary_withdrawals" -> upsert<com.marina.marina.data.local.entity.SalaryWithdrawalEntity>(
                record, remoteLastModified,
                fetch = { salaryWithdrawalsDao.getByLocalUuid(it) },
                store = { salaryWithdrawalsDao.insert(it) }
            )
            "salary_carry_over_logs" -> upsert<com.marina.marina.data.local.entity.SalaryCarryOverLogEntity>(
                record, remoteLastModified,
                fetch = { salaryCarryOverLogsDao.getByLocalUuid(it) },
                store = { salaryCarryOverLogsDao.insert(it) }
            )
            "app_users" -> upsert<com.marina.marina.data.local.entity.AppUserEntity>(
                record, remoteLastModified,
                fetch = { appUsersDao.getByLocalUuid(it) },
                store = { appUsersDao.insert(it) }
            )
            "devices" -> upsert<com.marina.marina.data.local.entity.DeviceInfoEntity>(
                record, remoteLastModified,
                fetch = { devicesDao.getByLocalUuid(it) },
                store = { devicesDao.insert(it) }
            )
            "cash_transactions" -> upsert<com.marina.marina.data.local.entity.CashTransactionEntity>(
                record, remoteLastModified,
                fetch = { cashTransactionsDao.getByLocalUuid(it) },
                store = { cashTransactionsDao.insert(it) }
            )
            "audit_logs" -> upsert<com.marina.marina.data.local.entity.AuditLogEntity>(
                record, remoteLastModified,
                fetch = { auditLogsDao.getByLocalUuid(it) },
                store = { auditLogsDao.insert(it) }
            )
            "payment_voids" -> upsert<com.marina.marina.data.local.entity.PaymentVoidEntity>(
                record, remoteLastModified,
                fetch = { paymentVoidsDao.getByLocalUuid(it) },
                store = { paymentVoidsDao.insert(it) }
            )
            "price_adjustments" -> upsert<com.marina.marina.data.local.entity.PriceAdjustmentEntity>(
                record, remoteLastModified,
                fetch = { priceAdjustmentsDao.getByLocalUuid(it) },
                store = { priceAdjustmentsDao.insert(it) }
            )
            "inventory_items" -> upsert<com.marina.marina.data.local.entity.InventoryItemEntity>(
                record, remoteLastModified,
                fetch = { inventoryDao.getItemByLocalUuid(it) },
                store = { inventoryDao.insertItem(it) }
            )
            "inventory_transactions" -> upsert<com.marina.marina.data.local.entity.InventoryTransactionEntity>(
                record, remoteLastModified,
                fetch = { inventoryDao.getTransactionByLocalUuid(it) },
                store = { inventoryDao.insertTransaction(it) }
            )
            "blacklist" -> upsert<com.marina.marina.data.local.entity.BlacklistEntryEntity>(
                record, remoteLastModified,
                fetch = { blacklistEntriesDao.getByLocalUuid(it) },
                store = { blacklistEntriesDao.insert(it) }
            )
            else -> false
        }
    }

    /**
     * Upsert عام: إدخال عند الغياب، أو استبدال عند تفوق البعيد محلياً
     * (last_modified >= المحلي — نفس دلالة ingestRecord السابقة:
     * التعادل يذهب للقادم من الخادم لأن الخادم حسم التعارض مسبقاً).
     */
    private suspend fun <T : BaseSyncEntity> upsert(
        record: Map<String, Any>,
        remoteLastModified: Long,
        fetch: suspend (String) -> T?,
        store: suspend (T) -> Unit
    ): Boolean {
        return try {
            @Suppress("UNCHECKED_CAST")
            val clazz = entityClass(record["_entity"] as String) ?: return false
            val remote = gson.fromJson(gson.toJson(record), clazz) as? T ?: return false
            if (remote.localUuid.isBlank()) return false
            val existing = fetch(remote.localUuid)
            when {
                existing == null -> store(remote)
                remoteLastModified >= existing.lastModified -> {
                    // copy(id=…) يستبدل الصف المحلي نفسه (REPLACE بذات المفتاح).
                    store(remote.copyWithId(existing.id))
                }
                // المحلي أحدث (تعديل محلي لم يُرفع بعد) — نحتفظ به؛ الدفع
                // سيرفعه لاحقاً والخادم يحسم.
                else -> Unit
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /** نسخ الكيان مع استبدال id — data class copy عبر الانعكاس المباشر. */
    @Suppress("UNCHECKED_CAST")
    private fun <T : BaseSyncEntity> T.copyWithId(newId: Long): T {
        // BaseSyncEntity.id مُعلن open val — البُناة الفعلية للكيانات تحمله
        // كمعامل بُناء أول؛ نستخدم Gson round-trip بديلاً آمناً عن copy()
        // غير المتاح عبر التعميم (T ليس reified هنا).
        val json = gson.toJson(this)
        val map = gson.fromJson<Map<String, Any>>(json, Map::class.java)
            .toMutableMap()
        map["id"] = newId
        @Suppress("UNCHECKED_CAST")
        val result = gson.fromJson(gson.toJson(map), this.javaClass) as T
        return result
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
