package com.marina.marina.presentation.dashboard

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FinancialStats derivation tests — the Dashboard "المتبقي / عجز" card
 * contract: balance = payments − expenses, deficit styling below zero.
 */
class FinancialStatsTest {

    @Test
    fun `balance is payments minus expenses`() {
        val stats = FinancialStats(todayPayments = 1000.0, todayExpenses = 250.0)
        assertEquals(750.0, stats.balance, 0.001)
        assertFalse(stats.isDeficit)
    }

    @Test
    fun `zero balance is not a deficit`() {
        val stats = FinancialStats(todayPayments = 500.0, todayExpenses = 500.0)
        assertEquals(0.0, stats.balance, 0.001)
        assertFalse(stats.isDeficit)
    }

    @Test
    fun `negative balance is a deficit`() {
        val stats = FinancialStats(todayPayments = 200.0, todayExpenses = 800.0)
        assertEquals(-600.0, stats.balance, 0.001)
        assertTrue(stats.isDeficit)
    }

    @Test
    fun `currency formatting matches dart NumberFormat hash comma zero`() {
        assertEquals("1,250", formatCurrency(1250.0))
        assertEquals("0", formatCurrency(0.0))
        assertEquals("1,000,000", formatCurrency(1000000.0))
        assertEquals("999", formatCurrency(999.4))
        // Rounding follows HALF_EVEN like Dart's NumberFormat('#,##0').
        assertEquals("1,000", formatCurrency(999.5))
    }
}
