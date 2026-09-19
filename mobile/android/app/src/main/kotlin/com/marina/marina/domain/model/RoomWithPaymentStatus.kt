package com.marina.marina.domain.model

import androidx.compose.ui.graphics.Color

/**
 * Domain model pairing a room with its payment-overdue state.
 *
 * Ported 1:1 from the Flutter app's `RoomWithPaymentStatus`
 * (`lib/providers/room_payment_status_provider.dart`). Color derivation
 * lives here so both the Dashboard and the Rooms screens agree on the
 * visual semantics of each room state.
 *
 * @property isPaymentOverdue Actual overdue phase (23:00 – 05:00) with a
 * remaining balance: the whole button turns dark red with a thick border.
 * @property isLatePayment Early-warning phase (22:00 – 23:00) with a
 * remaining balance: part of the button turns orange as an alert strip.
 * @property activeBooking The live booking bound to this room, if any.
 * Occupancy is derived from this instead of the stored `room.status`,
 * which may be stale after a sync.
 */
data class RoomWithPaymentStatus(
    val room: Room,
    val isPaymentOverdue: Boolean = false,
    val isLatePayment: Boolean = false,
    val activeBooking: Booking? = null
) {

    /** Whether the room has an actual active booking. */
    val hasActiveBooking: Boolean get() = activeBooking != null

    /** Whether the partial orange indicator should be shown. */
    val hasLatePaymentIndicator: Boolean
        get() = isLatePayment || isPaymentOverdue

    /**
     * The room tile color. Maintenance has the highest priority, then an
     * actual active booking (red), otherwise vacant (green).
     */
    val roomColor: Color
        get() = when {
            com.marina.marina.domain.util.StatusUtils.isRoomUnderMaintenance(room.status) ->
                MaintenanceColor
            hasActiveBooking -> OccupiedColor
            else -> VacantColor
        }

    /** The user-facing status, derived from the live booking. */
    val displayStatus: String
        get() = when {
            com.marina.marina.domain.util.StatusUtils.isRoomUnderMaintenance(room.status) ->
                "صيانة"
            hasActiveBooking -> "محجوزة"
            else -> "شاغرة"
        }

    companion object {
        /** محجوزة — occupied red (Material red 600 ≈ 0xFFE53935). */
        val OccupiedColor: Color = Color(0xFFE53935)

        /** شاغرة — vacant green (Material green 600 ≈ 0xFF43A047). */
        val VacantColor: Color = Color(0xFF43A047)

        /** صيانة — maintenance orange (Material orange 600 ≈ 0xFFFB8C00). */
        val MaintenanceColor: Color = Color(0xFFFB8C00)

        /** متأخر 23:00 — overdue dark red (Material red 800 ≈ 0xFFC62828). */
        val OverdueColor: Color = Color(0xFFC62828)

        /** Overdue tile border — Material red 900 ≈ 0xFFB71C1C. */
        val OverdueDark: Color = Color(0xFFB71C1C)

        /** تنبيه 22:00 strip — alert orange (Material orange 500 ≈ 0xFFF57C00). */
        val LatePaymentColor: Color = Color(0xFFF57C00)

        /** Unregistered room fallback (Material grey 400 ≈ 0xFFBDBDBD). */
        val UnregisteredColor: Color = Color(0xFFBDBDBD)
    }
}
