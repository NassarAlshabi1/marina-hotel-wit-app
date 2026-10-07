package com.marina.marina.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.mapper.toDomain
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.CloudflareWorkerApi
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.sync.SyncEpochs
import com.marina.marina.di.EncryptedSharedPreferencesManager
import com.marina.marina.domain.model.BlacklistEntry
import com.marina.marina.domain.model.CashTransaction
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.model.ExpenseKind
import com.marina.marina.domain.model.GuestInfo
import com.marina.marina.domain.model.InventoryItem
import com.marina.marina.domain.model.Payment
import com.marina.marina.domain.model.SalaryCycle
import com.marina.marina.domain.model.SalaryPayment
import com.marina.marina.domain.model.SalaryWithdrawal
import com.marina.marina.domain.model.ShiftNote
import com.marina.marina.domain.util.HotelTimeEngine
import java.lang.reflect.Proxy
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * عقد **الكتابة المحلية** في المستودعات الثلاثة عشر المتبقية — نظير Dart
 * `Time.nowEpoch()` (ثوانٍ) في كل مسارات `insertOne`/`updateById`/`softDelete`
 * (`mobile/lib/services/daos/…dart` في فرع `feat/cloudflare-sync-execution`).
 *
 * ثلاتة عقود يقفلها هذا الملف لكل مستودع:
 *  1. **الوحدة**: `updated_at` / `last_modified` / `deleted_at` بالثواني لا
 *     بالميلي — نظير §5 من `docs/android-epoch-unit-parity.md`.
 *  2. **`last_modified` مكتوب فعلاً** (لم يكن يُكتب إطلاقاً: نموذج المجال لا
 *     يحمله ⇒ كان يبقى صفراً). الأثر المقيس: قرار «آخر كتابة تفوز» يقارن
 *     `remote >= existing.lastModified`، فمع صفر يفوز **أي** صف خادمي — ولو
 *     أقدم — ويطمس تعديلنا المحلي صامتاً (نفس العطل B في وثيقة الوحدة).
 *  3. **`version+1`** في التحديث — نظير `version: Value(existing.version + 1)`
 *     في Dart، وهو كاسر التعادل في الـ Worker عند تساوي `updated_at`.
 *
 * و**حقول الأعمال تبقى بالميلي** حيث يعتمد عليها العرض/الاستعلام:
 * `expenses.date` و`payments.payment_date` (نصوص ISO مبنية على `Date(millis)`)،
 * `inventory_transactions.transaction_time` (يُغذّى من `created_at` عند الاستيعاب
 * عبر `normalizeEpochMillis` ×1000)، و`salary_withdrawals.withdraw_date`
 * (يعرض بـ`Date(millis)` ويُفلتر بنطاق ميلي في التقارير). أما `voided_at`
 * فبالثواني عمداً — لأن Dart يختمه بـ`nowEpoch` (`payment_void_service.dart:90`).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class RepositoryEpochParityTest {

    private lateinit var db: AppDatabase
    private lateinit var registry: SyncIngestorRegistry
    private lateinit var outbox: OutboxRepository

    @Before
    fun openInMemoryDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("marina_secure_prefs", Context.MODE_PRIVATE)
            .edit().clear().commit()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        registry = newRegistry()
        outbox = outboxRepository()
    }

    @After
    fun closeDatabase() {
        db.close()
    }

    private fun newRegistry() = SyncIngestorRegistry(
        db = db, roomsDao = db.roomsDao(), bookingsDao = db.bookingsDao(),
        paymentsDao = db.paymentsDao(), expensesDao = db.expensesDao(), employeesDao = db.employeesDao(),
        debtsDao = db.debtsDao(), bookingNotesDao = db.bookingNotesDao(), bookingNightsDao = db.bookingNightsDao(),
        bookingPriceAdjustmentsDao = db.bookingPriceAdjustmentsDao(), guestInfosDao = db.guestInfosDao(),
        shiftNotesDao = db.shiftNotesDao(), salaryCyclesDao = db.salaryCyclesDao(),
        salaryPaymentsDao = db.salaryPaymentsDao(), salaryWithdrawalsDao = db.salaryWithdrawalsDao(),
        salaryCarryOverLogsDao = db.salaryCarryOverLogsDao(), appUsersDao = db.appUsersDao(),
        devicesDao = db.devicesDao(), cashTransactionsDao = db.cashTransactionsDao(),
        auditLogsDao = db.auditLogsDao(), paymentVoidsDao = db.paymentVoidsDao(),
        priceAdjustmentsDao = db.priceAdjustmentsDao(), inventoryDao = db.inventoryDao(),
        blacklistEntriesDao = db.blacklistEntriesDao()
    )

    private fun outboxRepository(): OutboxRepository {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val syncPreferences = SyncPreferences(EncryptedSharedPreferencesManager(context))
        val workerApi = Proxy.newProxyInstance(
            CloudflareWorkerApi::class.java.classLoader,
            arrayOf(CloudflareWorkerApi::class.java)
        ) { _, method, _ ->
            throw AssertionError("Unexpected network call in repository epoch test: ${method.name}")
        } as CloudflareWorkerApi
        val syncService = CloudflareSyncService(
            api = workerApi,
            config = CloudflareConfig(context),
            preferences = syncPreferences
        )
        return OutboxRepository(
            outboxDao = db.outboxDao(),
            syncService = syncService,
            preferences = syncPreferences,
            syncIngestorRegistry = registry
        )
    }

    // ─── مساعدات القياس ───────────────────────────────────────────────────────

    /** ثوانٍ شرعية: من 2001 حتى العتبة (2e9 = 2033+) — نفس تحقق اختبار الوحدة. */
    private fun isSeconds(value: Long): Boolean =
        value in 1_000_000_000L..SyncEpochs.MILLIS_THRESHOLD

    private fun assertSeconds(label: String, value: Long) {
        assertTrue("$label يجب أن يكون ثوانٍ لا ميلي: $value", isSeconds(value))
    }

    private fun assertMillis(label: String, value: Long) {
        assertTrue("$label يجب أن يبقى بالميلي: $value", value > SyncEpochs.MILLIS_THRESHOLD)
    }

    private fun blacklist() = BlacklistRepositoryImpl(db.blacklistEntriesDao(), outbox)
    private fun cash() = CashRepositoryImpl(db.cashTransactionsDao(), outbox)
    private fun debts() = DebtsRepositoryImpl(db.debtsDao(), outbox)
    private fun employees() = EmployeesRepositoryImpl(db.employeesDao(), outbox)
    private fun guestInfos() = GuestInfosRepositoryImpl(db.guestInfosDao(), outbox)
    private fun shiftNotes() = ShiftNotesRepositoryImpl(db.shiftNotesDao(), outbox)
    private fun inventory() = InventoryRepositoryImpl(db.inventoryDao(), outbox)

    private fun withdrawals() = SalaryWithdrawalsRepositoryImpl(
        db, db.expensesDao(), db.salaryWithdrawalsDao(), db.employeesDao(), outbox
    )

    private fun expenses() = ExpensesRepositoryImpl(db, withdrawals(), db.expensesDao(), db.employeesDao(), outbox)

    private fun salaries() = SalaryRepositoryImpl(
        db.employeesDao(), db.salaryCyclesDao(), db.salaryPaymentsDao(), db.salaryCarryOverLogsDao(), outbox
    )

    // ─── 1) القائمة البسيطة: إدراج/تحديث/حذف ناعم ────────────────────────────

    @Test
    fun blacklistInsertUpdateSoftDeleteStampSecondsAndBumpVersion() = runBlocking {
        val repo = blacklist()
        val id = repo.insert(BlacklistEntry(name = "ضيف أ", reason = "اختبار"))
        val inserted = requireNotNull(db.blacklistEntriesDao().getById(id))
        assertSeconds("blacklist.insert.last_modified", inserted.lastModified)
        assertSeconds("blacklist.insert.updated_at", inserted.updatedAt)
        assertEquals(1, inserted.version)

        repo.update(inserted.toDomain().copy(name = "ضيف ب"))
        val updated = requireNotNull(db.blacklistEntriesDao().getById(id))
        assertSeconds("blacklist.update.last_modified", updated.lastModified)
        assertEquals("version+1 في التحديث", 2, updated.version)
        assertEquals("ضيف ب", updated.name)

        repo.softDelete(id)
        val deleted = requireNotNull(db.blacklistEntriesDao().getById(id))
        assertSeconds("blacklist.softDelete.deleted_at", requireNotNull(deleted.deletedAt))
        assertSeconds("blacklist.softDelete.last_modified", deleted.lastModified)
    }

    @Test
    fun cashInsertAndSoftDeleteStampSeconds() = runBlocking {
        val repo = cash()
        val id = repo.insert(CashTransaction(transactionType = "in", amount = 100.0, transactionTime = "2026-10-07 10:00"))
        val entity = requireNotNull(db.cashTransactionsDao().getById(id))
        assertSeconds("cash.insert.created_at", entity.createdAt)
        assertSeconds("cash.insert.last_modified", entity.lastModified)

        repo.softDelete(id)
        val deleted = requireNotNull(db.cashTransactionsDao().getById(id))
        assertSeconds("cash.softDelete.deleted_at", requireNotNull(deleted.deletedAt))
        assertSeconds("cash.softDelete.last_modified", deleted.lastModified)
    }

    @Test
    fun debtsInsertUpdateSettleAndSoftDeleteStampSeconds() = runBlocking {
        val repo = debts()
        val id = repo.insert(Debt(guestName = "ضيف مدين", totalAmount = 500.0, remainingAmount = 500.0))
        val inserted = requireNotNull(db.debtsDao().getById(id))
        assertSeconds("debts.insert.last_modified", inserted.lastModified)

        repo.update(inserted.toDomain().copy(note = "ملاحظة"))
        val updated = requireNotNull(db.debtsDao().getById(id))
        assertSeconds("debts.update.last_modified", updated.lastModified)
        assertEquals(2, updated.version)

        repo.markSettled(id, paidAmount = 500.0)
        val settled = requireNotNull(db.debtsDao().getById(id))
        assertSeconds("debts.markSettled.last_modified", settled.lastModified)
        assertEquals("markSettled يرفع النسخة (عقد update)", 3, settled.version)
        assertEquals(1, settled.isSettled)

        repo.softDelete(id)
        val deleted = requireNotNull(db.debtsDao().getById(id))
        assertSeconds("debts.softDelete.last_modified", deleted.lastModified)
    }

    @Test
    fun employeesInsertUpdateTerminateReactivateSoftDeleteStampSeconds() = runBlocking {
        val repo = employees()
        val id = repo.insert(Employee(name = "موظف أ", basicSalary = 1000.0, position = "موظف"))
        val inserted = requireNotNull(db.employeesDao().getById(id))
        assertSeconds("employees.insert.last_modified", inserted.lastModified)

        repo.update(inserted.toDomain().copy(phone = "777000111"))
        val updated = requireNotNull(db.employeesDao().getById(id))
        assertSeconds("employees.update.last_modified", updated.lastModified)
        assertEquals(2, updated.version)

        repo.terminate(id, "مفصول", "2026-10-07", "سبب")
        val terminated = requireNotNull(db.employeesDao().getById(id))
        assertSeconds("employees.terminate.last_modified", terminated.lastModified)
        assertEquals(3, terminated.version)

        repo.reactivate(id)
        val reactivated = requireNotNull(db.employeesDao().getById(id))
        assertSeconds("employees.reactivate.last_modified", reactivated.lastModified)
        assertEquals(4, reactivated.version)

        repo.softDelete(id)
        // getById يستثني المحذوف ناعمياً (deleted_at IS NULL) — نقرأ بالمتغيّر الشامل.
        val deleted = requireNotNull(db.employeesDao().getByIdIncludingDeleted(id))
        assertSeconds("employees.softDelete.deleted_at", requireNotNull(deleted.deletedAt))
        assertSeconds("employees.softDelete.last_modified", deleted.lastModified)
    }

    @Test
    fun guestInfosInsertUpdateSoftDeleteStampSeconds() = runBlocking {
        val repo = guestInfos()
        val id = repo.insert(GuestInfo(roomNumber = "G-1", guestName = "ضيف أ"))
        val inserted = requireNotNull(db.guestInfosDao().getById(id))
        assertSeconds("guest_infos.insert.last_modified", inserted.lastModified)

        repo.update(inserted.toDomain().copy(nationality = "يمني"))
        val updated = requireNotNull(db.guestInfosDao().getById(id))
        assertSeconds("guest_infos.update.last_modified", updated.lastModified)
        assertEquals(2, updated.version)

        repo.softDelete(id)
        val deleted = requireNotNull(db.guestInfosDao().getById(id))
        assertSeconds("guest_infos.softDelete.last_modified", deleted.lastModified)
    }

    @Test
    fun shiftNotesInsertUpdateMarkReadDeleteStampSeconds() = runBlocking {
        val repo = shiftNotes()
        val id = repo.insert(ShiftNote(title = "ملاحظة", content = "نص"))
        val inserted = requireNotNull(db.shiftNotesDao().getById(id))
        assertSeconds("shift_notes.insert.last_modified", inserted.lastModified)

        repo.update(inserted.toDomain().copy(content = "نص مُحرَّر"))
        val updated = requireNotNull(db.shiftNotesDao().getById(id))
        assertSeconds("shift_notes.update.last_modified", updated.lastModified)
        assertEquals(2, updated.version)

        repo.markRead(id)
        val read = requireNotNull(db.shiftNotesDao().getById(id))
        assertSeconds("shift_notes.markRead.last_modified", read.lastModified)
        assertEquals(3, read.version)

        repo.delete(id)
        val deleted = requireNotNull(db.shiftNotesDao().getById(id))
        assertSeconds("shift_notes.delete.deleted_at", requireNotNull(deleted.deletedAt))
        assertSeconds("shift_notes.delete.last_modified", deleted.lastModified)
    }

    // ─── 2) المال: حقول الأعمال بالميلي والطوابع بالثواني ─────────────────────

    @Test
    fun expensesKeepIsoBusinessDateInMillisWhileSyncFieldsAreSeconds() = runBlocking {
        val repo = expenses()
        val before = System.currentTimeMillis()
        val id = repo.insert(Expense(expenseType = "منوعات", amount = 250.0, description = "كهرباء", expenseKind = ExpenseKind.NORMAL))
        val inserted = requireNotNull(db.expensesDao().getById(id))
        assertSeconds("expenses.insert.updated_at", inserted.updatedAt)
        assertSeconds("expenses.insert.last_modified", inserted.lastModified)

        // `date` نص ISO مبني على `HotelTimeEngine.formatIso(millisNow)` — لو خُتم
        // بالثواني لظهر 1970. يُقاس بتحليله ومقارنته بزمن التنفيذ.
        val parsed = HotelTimeEngine.parseDate(inserted.date)
        assertNotNull("expenses.date يجب أن يكون ISO قابلاً للتحليل: ${inserted.date}", parsed)
        assertTrue(
            "expenses.date يجب أن يطابق زمن الآن (لا 1970): ${inserted.date}",
            requireNotNull(parsed) >= before - 60_000L
        )

        repo.update(inserted.toDomain().copy(amount = 300.0))
        val updated = requireNotNull(db.expensesDao().getById(id))
        assertSeconds("expenses.update.last_modified", updated.lastModified)
        assertEquals(2, updated.version)

        repo.softDelete(id)
        // getById يستثني المحذوف ناعمياً؛ `getByLocalUuid` يقرأ الصف كما هو.
        val deleted = requireNotNull(db.expensesDao().getByLocalUuid(updated.localUuid))
        assertSeconds("expenses.softDelete.last_modified", deleted.lastModified)
    }

    @Test
    fun paymentsInsertVoidAndSoftDeleteStampSecondsWhilePaymentDateStaysMillis() = runBlocking {
        val derivedRefresh = BookingDerivedRefreshService(
            db, db.bookingsDao(), db.roomsDao(), db.paymentsDao(), db.bookingNightsDao()
        )
        val bookings = BookingsRepositoryImpl(db, db.bookingsDao(), outbox, derivedRefresh)
        val payments = PaymentsRepositoryImpl(db.paymentsDao(), db.paymentVoidsDao(), outbox, db, bookings)
        val before = System.currentTimeMillis()
        val id = payments.insert(Payment(amount = 400.0, paymentMethod = "نقدي", revenueType = "room"))
        val inserted = requireNotNull(db.paymentsDao().getById(id))
        assertSeconds("payments.insert.updated_at", inserted.updatedAt)
        assertSeconds("payments.insert.last_modified", inserted.lastModified)
        val parsedDate = HotelTimeEngine.parseDate(inserted.paymentDate)
        assertTrue(
            "payments.payment_date يجب أن يطابق زمن الآن: ${inserted.paymentDate}",
            parsedDate != null && parsedDate >= before - 60_000L
        )

        payments.void(id, voidedBy = "مدير", voidReason = "خطأ إدخال")
        val voided = requireNotNull(db.paymentsDao().getByLocalUuid(inserted.localUuid))
        assertSeconds("payments.void.updated_at", voided.updatedAt)
        assertSeconds("payments.void.last_modified", voided.lastModified)
        // Dart: `voidedAt: drift.Value(nowEpoch)` ثوانٍ (payment_void_service.dart l.161).
        assertSeconds("payments.void.voided_at", requireNotNull(voided.voidedAt))
        assertEquals(2, voided.version)

        payments.softDelete(id)
        val deleted = requireNotNull(db.paymentsDao().getByLocalUuid(inserted.localUuid))
        assertSeconds("payments.softDelete.last_modified", deleted.lastModified)
    }

    @Test
    fun inventoryTransactionTimeStaysMillisWhileSyncFieldsAreSeconds() = runBlocking {
        val repo = inventory()
        val itemId = repo.addItem(InventoryItem(name = "ورق طباعة", unit = "رزمة"))
        val item = requireNotNull(db.inventoryDao().getItemById(itemId))
        assertSeconds("inventory_items.insert.last_modified", item.lastModified)

        // الحركة أولاً (recordMovement يقرأ الصنف بـgetItemById الذي يستثني المحذوف).
        val result = repo.recordMovement(itemId, type = "in", quantity = 10.0, note = "شراء")
        assertTrue("recordMovement فشل: ${result.exceptionOrNull()}", result.isSuccess)
        val tx = requireNotNull(db.inventoryDao().getTransactionsForItem(itemId).first().firstOrNull())
        // `transaction_time` عمود محلي بحت (لا مقابل على السلك/Drift) ويُفلتر
        // بنطاق **ميلي** في تقارير المخزون؛ يُغذّى على السلك من `created_at`
        // بالثواني ثم ×1000 عبر `SyncWireFields.millisTargets` ⇒ يبقى بالميلي
        // في الكتابة المحلية أيضاً (وحدة موحّدة على المسارين).
        assertMillis("inventory_transactions.transaction_time", tx.transactionTime)
        assertSeconds("inventory_transactions.created_at", tx.createdAt)
        assertSeconds("inventory_transactions.last_modified", tx.lastModified)

        // الفجوة المكتشفة في هذه الجولة: الصنف نفسه كان يُكتب بـ`updated_at`
        // بالميلي بلا `last_modified` ولا `version+1` ولا رفع — فتغيير الرصيد
        // لا يصل السحابة. صار نظير Dart (`inventory_repository.dart` l.133-157).
        val itemAfter = requireNotNull(db.inventoryDao().getItemById(itemId))
        assertSeconds("inventory_items.movement.updated_at", itemAfter.updatedAt)
        assertSeconds("inventory_items.movement.last_modified", itemAfter.lastModified)
        assertEquals("الحركة ترفع نسخة الصنف", 2, itemAfter.version)
        assertEquals(12.0, itemAfter.currentQuantity, 0.0)
        val pendingOps = db.outboxDao().getPendingPrimary().first().map { "${it.entity}:${it.op}" }
        assertTrue("يجب رفع تحديث الصنف مع الحركة: $pendingOps", pendingOps.contains("inventory_items:update"))
        assertTrue("يجب رفع الحركة نفسها: $pendingOps", pendingOps.contains("inventory_transactions:insert"))

        repo.softDeleteItem(itemId)
        val softDeleted = requireNotNull(db.inventoryDao().listAllIncludingDeleted().firstOrNull { it.id == itemId })
        assertSeconds("inventory_items.softDelete.last_modified", softDeleted.lastModified)
        assertSeconds("inventory_items.softDelete.deleted_at", requireNotNull(softDeleted.deletedAt))
    }

    /**
     * عطل مُكتشف بالتشغيل (CI `37696941360`): تمرير **كيان Room** إلى
     * `enqueueObject` كان يرمي `declares multiple JSON fields named 'id'`
     * (Gson مقابل ظلّ حقول `BaseSyncEntity`) ⇒ `recordMovement` يفشل كاملاً
     * وحركات المخزون لا تُرفع. الآن التسلسل واعٍ بظلّ الحقول، والحمولة تحمل
     * أسماء السلك (`movement_type`) بعد `SyncWireFields.toWire`.
     */
    @Test
    fun entityPayloadSerializesWithWireNamesInsteadOfThrowing() = runBlocking {
        val repo = inventory()
        val itemId = repo.addItem(InventoryItem(name = "صنف تسلسل", unit = "قطعة"))
        val movement = repo.recordMovement(itemId, type = "out", quantity = 2.0, note = "صرف")
        assertTrue("recordMovement فشل: ${movement.exceptionOrNull()}", movement.isSuccess)

        val row = db.outboxDao().getPendingPrimary().first()
            .single { it.entity == "inventory_transactions" }
        val json = com.google.gson.JsonParser.parseString(row.payload).asJsonObject
        // الاسم السلكي (يراه الخادم) والاسم المحلي (يُفلتر عنده) — كلاهما موجود.
        assertEquals("out", json["movement_type"].asString)
        assertEquals("out", json["transaction_type"].asString)
        // حقول المزامنة الأساسية تُسلسَل مرة واحدة من حقل الصنف لا من ظلّه.
        assertTrue("الطابع يجب أن يكون ثوانٍ", json["last_modified"].asLong in 1_000_000_000L..SyncEpochs.MILLIS_THRESHOLD)
        assertTrue("local_uuid مطلوب في الحمولة", json["local_uuid"].asString.isNotBlank())
        assertTrue("created_at مطلوب (يغذّي transaction_time على الأجهزة الأخرى)", json.has("created_at"))
    }

    // ─── 3) الرواتب: دورة/دفعة/ترحيل/سحب ────────────────────────────────────

    @Test
    fun salaryCyclePaymentCarryOverAndWithdrawalStampSeconds() = runBlocking {
        val employeeId = employees().insert(Employee(name = "موظف رواتب", basicSalary = 2000.0, position = "موظف"))
        val salaryRepo = salaries()

        val cycleId = salaryRepo.insertCycle(
            SalaryCycle(employeeId = employeeId, cycleKey = "2026-10", expectedAmount = 2000L, actualPaid = 0L)
        )
        val cycle = requireNotNull(db.salaryCyclesDao().getById(cycleId))
        assertSeconds("salary_cycles.insert.last_modified", cycle.lastModified)

        salaryRepo.updateCycle(cycle.toDomain().copy(actualPaid = 500L))
        val updatedCycle = requireNotNull(db.salaryCyclesDao().getById(cycleId))
        assertSeconds("salary_cycles.update.last_modified", updatedCycle.lastModified)
        assertEquals(2, updatedCycle.version)

        val paymentId = salaryRepo.insertPayment(SalaryPayment(cycleId = cycleId, amount = 300L))
        val payment = requireNotNull(db.salaryPaymentsDao().getById(paymentId))
        assertSeconds("salary_payments.insert.last_modified", payment.lastModified)

        val logId = salaryRepo.carryOver(employeeId, 100.0, "2026-09", "2026-10", "ترحيل", null)
        val log = requireNotNull(db.salaryCarryOverLogsDao().getById(logId))
        assertSeconds("salary_carry_over_logs.insert.last_modified", log.lastModified)
        // `carried_at` بالثواني أيضاً — Dart: `Time.nowEpoch()` (salary_carry_over_logs_adapter l.72).
        assertSeconds("salary_carry_over_logs.carried_at", log.carriedAt)

        val employee = requireNotNull(db.employeesDao().getById(employeeId))
        val withdrawalId = withdrawals().insert(
            SalaryWithdrawal(employeeId = employeeId, employeeUuid = employee.localUuid, amount = 150.0, withdrawalType = "سحب راتب")
        )
        val withdrawal = requireNotNull(db.salaryWithdrawalsDao().getAllOnce().firstOrNull { it.id == withdrawalId })
        assertSeconds("salary_withdrawals.insert.last_modified", withdrawal.lastModified)
        // `withdraw_date` يبقى بالميلي: يُعرض بـ`Date(millis)` ويُفلتر بنطاق ميلي
        // في التقارير، ويُغذّى بالميلي عند الاستيعاب (×1000).
        assertMillis("salary_withdrawals.withdraw_date", withdrawal.withdrawDate)
    }
}
