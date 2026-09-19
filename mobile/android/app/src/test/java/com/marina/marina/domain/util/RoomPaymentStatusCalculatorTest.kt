package com.marina.marina.domain.util

import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.model.RoomWithPaymentStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * RoomPaymentStatusCalculator tests — the Dashboard room-board lateness
 * contract, ported from the Flutter `room_payment_status_provider`
 * expectations. Every alert window is exercised with an injected hour.
 */
class RoomPaymentStatusCalculatorTest {

    private fun room(number: String, status: String = "شاغرة") =
        Room(id = number.toLong(), roomNumber = number, type = "مزدوجة", price = 250.0, status = status)

    private fun booking(
        roomNumber: String,
        status: String = "نشط",
        remaining: Double = 500.0
    ) = Booking(id = 1, roomNumber = roomNumber, guestName = "ضيف", status = status, remainingBalanceCached = remaining)

    // -------------------------------------------------------------------------
    // Color/status derivation
    // -------------------------------------------------------------------------

    @Test
    fun `vacant room is green and displays شاغرة`() {
        val result = RoomPaymentStatusCalculator.calculate(listOf(room("101")), emptyList(), hour = 15)
        assertEquals("شاغرة", result.single().displayStatus)
        assertEquals(RoomWithPaymentStatus.VacantColor, result.single().roomColor)
        assertNull(result.single().activeBooking)
    }

    @Test
    fun `room with active booking is red and displays محجوزة`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")),
            listOf(booking("101")),
            hour = 15
        )
        assertEquals("محجوزة", result.single().displayStatus)
        assertEquals(RoomWithPaymentStatus.OccupiedColor, result.single().roomColor)
        assertNotNull(result.single().activeBooking)
    }

    @Test
    fun `maintenance has the highest color priority`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101", status = "صيانة")),
            listOf(booking("101")),
            hour = 15
        )
        assertEquals("صيانة", result.single().displayStatus)
        assertEquals(RoomWithPaymentStatus.MaintenanceColor, result.single().roomColor)
    }

    @Test
    fun `stale room status is overridden by live booking presence`() {
        // room.status says vacant but a live booking exists → red (occupied).
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101", status = "شاغرة")),
            listOf(booking("101")),
            hour = 15
        )
        assertEquals("محجوزة", result.single().displayStatus)
        assertEquals(RoomWithPaymentStatus.OccupiedColor, result.single().roomColor)
    }

    // -------------------------------------------------------------------------
    // Lateness windows (the financial alert contract)
    // -------------------------------------------------------------------------

    @Test
    fun `hour 22 with remaining balance is early warning`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")), listOf(booking("101")), hour = 22
        ).single()
        assertTrue(result.isLatePayment)
        assertFalse(result.isPaymentOverdue)
        assertTrue(result.hasLatePaymentIndicator)
    }

    @Test
    fun `hour 23 with remaining balance is actual overdue`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")), listOf(booking("101")), hour = 23
        ).single()
        assertTrue(result.isPaymentOverdue)
        assertFalse(result.isLatePayment)
        assertTrue(result.hasLatePaymentIndicator)
    }

    @Test
    fun `hour 3 (early morning) is still overdue`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")), listOf(booking("101")), hour = 3
        ).single()
        assertTrue(result.isPaymentOverdue)
    }

    @Test
    fun `hour 5 exits the overdue window`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")), listOf(booking("101")), hour = 5
        ).single()
        assertFalse(result.isPaymentOverdue)
        assertFalse(result.isLatePayment)
    }

    @Test
    fun `no lateness outside alert windows even with balance`() {
        for (hour in 5..21) {
            val result = RoomPaymentStatusCalculator.calculate(
                listOf(room("101")), listOf(booking("101")), hour = hour
            ).single()
            assertFalse("hour $hour must not be late", result.isLatePayment)
            assertFalse("hour $hour must not be overdue", result.isPaymentOverdue)
        }
    }

    @Test
    fun `fully paid booking never flags lateness`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")),
            listOf(booking("101", remaining = 0.0)),
            hour = 23
        ).single()
        assertFalse(result.isPaymentOverdue)
        assertFalse(result.isLatePayment)
    }

    @Test
    fun `rounded sub-half balance counts as paid`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")),
            listOf(booking("101", remaining = 0.4)),
            hour = 23
        ).single()
        // round(0.4) = 0 → no remaining balance → no lateness flag.
        assertFalse(result.isPaymentOverdue)
    }

    @Test
    fun `inactive booking does not occupy the room`() {
        val result = RoomPaymentStatusCalculator.calculate(
            listOf(room("101")),
            listOf(booking("101", status = "مغادرة")),
            hour = 15
        ).single()
        assertEquals("شاغرة", result.displayStatus)
        assertNull(result.activeBooking)
    }
}
