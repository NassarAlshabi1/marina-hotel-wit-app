package com.marina.marina.presentation.reports

import com.marina.marina.domain.model.Expense
import com.marina.marina.domain.model.SalaryWithdrawal
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SalaryMirrorReportTest {
    private val expense = Expense(
        id = 5, localUuid = "expense-a", employeeUuid = "employee-a", relatedId = 7,
        amount = 100.0, hotelDayKey = "2026-10-03", expenseType = "سلفة"
    )
    private val withdrawal = SalaryWithdrawal(
        employeeUuid = "employee-a", employeeId = 7, localUuid = "withdrawal-a",
        amount = 100.0, hotelDayKey = "2026-10-03", reason = "exp_5"
    )

    @Test
    fun equalEmployeeAmountDayAndNumericReferenceNeverHideIndependentEvents() {
        val other = withdrawal.copy(localUuid = "withdrawal-b")
        assertFalse(hasExplicitSalaryMirror(withdrawal, listOf(expense), listOf(withdrawal, other)))
        assertFalse(hasExplicitSalaryMirror(other, listOf(expense), listOf(withdrawal, other)))
    }

    @Test
    fun onlyUniqueConsistentExplicitSourceIsSuppressed() {
        val linked = withdrawal.copy(expenseUuid = expense.localUuid)
        assertTrue(hasExplicitSalaryMirror(linked, listOf(expense), listOf(linked)))
        assertFalse(hasExplicitSalaryMirror(linked.copy(amount = 200.0), listOf(expense), listOf(linked)))
        assertFalse(hasExplicitSalaryMirror(linked.copy(employeeUuid = "employee-b"), listOf(expense), listOf(linked)))
        assertFalse(hasExplicitSalaryMirror(linked, listOf(expense), listOf(linked, linked.copy(localUuid = "duplicate"))))
    }
}
