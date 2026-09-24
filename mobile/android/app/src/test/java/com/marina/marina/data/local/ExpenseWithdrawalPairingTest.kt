package com.marina.marina.data.local

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.marina.marina.data.local.dao.SalaryWithdrawalsDao
import com.marina.marina.domain.util.ExpenseReasonMatcher
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * عقد الاقتران بين مصروف الرواتب والسحب المقترن — شبكة انحدار لعلّة تكرار
 * تقرير المصروفات (2026-09-25):
 *
 * عند تعديل مبلغ مصروف راتب من شاشة المصروفات، كانت إزالة تكرار التقرير
 * تعتمد على مطابقة المبلغ فتفشل بعد التعديل فيظهر السحب يتيماً كمصفوف ثانٍ.
 * الإصلاح يزامن السحب المقترن عبر مرجع exp_<expenseId> — وهذا الاختبار يثبّت:
 *
 *  1. [ExpenseReasonMatcher.matchesExpenseRef] — exp_5 لا تطابق exp_50
 *     (negative lookahead — مرآة expense_reason_matcher.dart).
 *  2. [SalaryWithdrawalsDao.getByReasonLike] — SQL يعيد المرشحين الواسعين
 *     ثم يضيّقهم المطابِق، بعكس المطابقة التامة القديمة التي كانت تفوّت
 *     السجلات ذات النص الإضافي.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ExpenseWithdrawalPairingTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: SalaryWithdrawalsDao

    @Before
    fun openInMemoryDatabase() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        db = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        dao = db.salaryWithdrawalsDao()
    }

    @After
    fun closeDatabase() {
        db.close()
    }

    // ─── 1) مطابِق المرجع — عقد expense_reason_matcher.dart ───

    @Test
    fun matcherMatchesExactRefAndRefInsideFreeText() {
        assertTrue(ExpenseReasonMatcher.matchesExpenseRef("exp_5", 5L))
        assertTrue(ExpenseReasonMatcher.matchesExpenseRef("سلفة exp_5 لتغطية مصاريف", 5L))
        assertTrue(ExpenseReasonMatcher.matchesExpenseRef("direct_note exp_5", 5L))
    }

    @Test
    fun matcherDoesNotMatchLongerIds() {
        // الجوهر: exp_5 يجب ألا تلتقط exp_50/exp_51/exp_500.
        assertFalse(ExpenseReasonMatcher.matchesExpenseRef("exp_50", 5L))
        assertFalse(ExpenseReasonMatcher.matchesExpenseRef("exp_51", 5L))
        assertFalse(ExpenseReasonMatcher.matchesExpenseRef("exp_500", 5L))
        // والعكس صحيح.
        assertTrue(ExpenseReasonMatcher.matchesExpenseRef("exp_50", 50L))
    }

    @Test
    fun matcherRejectsNullAndUnrelatedReasons() {
        assertFalse(ExpenseReasonMatcher.matchesExpenseRef(null, 5L))
        assertFalse(ExpenseReasonMatcher.matchesExpenseRef("", 5L))
        assertFalse(ExpenseReasonMatcher.matchesExpenseRef("direct_withdrawal_1727", 5L))
        assertFalse(ExpenseReasonMatcher.matchesExpenseRef("سلفة شهرية", 5L))
    }

    // ─── 2) استعلام DAO الواسع + التضييق — التغطية النهائية للعقد ───

    @Test
    fun getByReasonLikeReturnsCandidatesAndMatcherNarrowsThem() = runBlocking {
        val now = System.currentTimeMillis()
        fun withdrawal(reason: String?, employeeId: Long) =
            com.marina.marina.data.local.entity.SalaryWithdrawalEntity(
                employeeId = employeeId,
                amount = 1000.0,
                withdrawDate = now,
                hotelDayKey = "2026-09-25",
                withdrawalType = "سحب راتب",
                reason = reason,
                localUuid = "uuid-$reason-${employeeId}"
            )

        dao.insert(withdrawal("exp_5", 1L))
        dao.insert(withdrawal("exp_50", 2L))
        dao.insert(withdrawal("exp_5 ملاحظة قديمة", 1L))
        dao.insert(withdrawal("direct_withdrawal_1727", 3L))
        dao.insert(withdrawal(null, 4L))

        // المرشحون الواسعون (LIKE) — سجلات عادية فقط (المحذوف ناعمياً مستبعد).
        val candidates = dao.getByReasonLike("exp_5")
        assertEquals(3, candidates.size)

        // التضييق بالمطابِق: مرجع المصروف 5 فقط.
        val paired = candidates.filter { ExpenseReasonMatcher.matchesExpenseRef(it.reason, 5L) }
        assertEquals(2, paired.size)
        assertTrue(paired.all { it.reason!!.startsWith("exp_5") && !it.reason!!.startsWith("exp_50") })

        // مرجع المصروف 50 يلتقط سجله وحده.
        val paired50 = dao.getByReasonLike("exp_50")
            .filter { ExpenseReasonMatcher.matchesExpenseRef(it.reason, 50L) }
        assertEquals(1, paired50.size)
        assertEquals("exp_50", paired50.first().reason)
    }

    @Test
    fun softDeletedPairedWithdrawalsLeaveTheLikeQuery() = runBlocking {
        val now = System.currentTimeMillis()
        val id = dao.insert(
            com.marina.marina.data.local.entity.SalaryWithdrawalEntity(
                employeeId = 1L,
                amount = 500.0,
                withdrawDate = now,
                hotelDayKey = "2026-09-25",
                withdrawalType = "سلفة",
                reason = "exp_7",
                localUuid = "uuid-softdel"
            )
        )

        assertEquals(1, dao.getByReasonLike("exp_7").size)

        // عقد deleteByExpenseId: الحذف الناعم يُخرج السجل من نطاق الاقتران
        // (كل الاستعلامات النشطة تفلتر deleted_at IS NULL).
        dao.softDelete(id, now, now)
        assertEquals(0, dao.getByReasonLike("exp_7").size)
    }
}
