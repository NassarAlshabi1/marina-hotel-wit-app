package com.marina.marina.domain.util

import com.marina.marina.domain.model.Employee
import com.marina.marina.domain.model.Expense
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SalaryEntitlementCalculatorTest {
    @Test
    fun employeeUuidIsAuthoritativeAndNumericIdIsLegacyOnly() {
        val employee = Employee(
            id = 7,
            name = "Employee",
            basicSalary = 100_000.0,
            hireDate = "2020-01-01",
            localUuid = "ABCDEF01-2345-6789-ABCD-0123456789AB"
        )
        val expenses = listOf(
            Expense(expenseType = "سلفة", relatedId = 99, employeeUuid = "abcdef0123456789abcd0123456789ab", amount = 10.0),
            Expense(expenseType = "سلفة", relatedId = 7, employeeUuid = "another-employee-uuid", amount = 100.0),
            Expense(expenseType = "سلفة", relatedId = 7, employeeUuid = null, amount = 20.0)
        )

        val result = SalaryEntitlementCalculator.calculateEmployeeEntitlement(
            employee = employee,
            expenses = expenses,
            nowMillis = 1_790_000_000_000L
        )

        assertEquals(30.0, result.totalAdvances, 0.0)
    }
}
