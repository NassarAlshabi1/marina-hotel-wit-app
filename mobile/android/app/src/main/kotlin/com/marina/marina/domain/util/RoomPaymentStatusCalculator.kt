package com.marina.marina.domain.util

import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.model.RoomWithPaymentStatus

/**
 * Pure derivation of per-room payment-lateness state — ported 1:1 from the
 * Flutter `roomsWithPaymentStatusProvider` compute kernel:
 *
 * - An active booking with a remaining balance flags the room.
 * - 22:00–22:59 → early warning (`isLatePayment`, orange strip).
 * - 23:00–04:59 → actual overdue (`isPaymentOverdue`, dark red).
 *
 * The hour is injected so unit tests can verify every window deterministically.
 */
object RoomPaymentStatusCalculator {

    fun calculate(
        rooms: List<Room>,
        bookings: List<Booking>,
        hour: Int
    ): List<RoomWithPaymentStatus> {
        // O(1) lookup map instead of O(R×B) scans (Flutter optimization).
        val bookingByRoom = HashMap<String, Booking>()
        for (booking in bookings) {
            if (StatusUtils.isBookingActive(booking.status)) {
                bookingByRoom[booking.roomNumber] = booking
            }
        }

        return rooms.map { room ->
            val activeBooking = bookingByRoom[room.roomNumber]
            var isPaymentOverdue = false
            var isLatePayment = false

            if (activeBooking != null) {
                val hasRemainingBalance = kotlin.math.round(activeBooking.remainingBalanceCached) > 0.0
                if (hasRemainingBalance) {
                    if (hour >= 22 && hour < 23) isLatePayment = true
                    if (hour >= 23 || hour < 5) isPaymentOverdue = true
                }
            }

            RoomWithPaymentStatus(
                room = room,
                isPaymentOverdue = isPaymentOverdue,
                isLatePayment = isLatePayment,
                activeBooking = activeBooking
            )
        }
    }
}
