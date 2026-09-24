package com.marina.marina.domain.util

/**
 * مطابقة مرجع المصروف في نص reason لسحب الراتب — مرآة 1:1 لملف
 * Flutter `mobile/lib/utils/expense_reason_matcher.dart`.
 *
 * يستخدم تعبيراً نمطياً مع negative lookahead يمنع `exp_1` من مطابقة
 * `exp_10` أو `exp_100` — العقد الذي تعتمد عليه إزالة تكرار تقرير
 * المصروفات بين جدولي expenses و salary_withdrawals.
 */
object ExpenseReasonMatcher {

    /** true عندما يحمل reason مرجع exp_<expenseId> الحرفي (وليس بامتداد رقمي أطول). */
    fun matchesExpenseRef(reason: String?, expenseId: Long): Boolean {
        if (reason == null) return false
        return Regex("exp_$expenseId(?!\\d)").containsMatchIn(reason)
    }
}
