package com.marina.marina.domain.model

/**
 * One row of the "other users' receipts for the current hotel day" card.
 *
 * Ported 1:1 from the Flutter app's `PaymentUserHotelDaySummary`
 * (`lib/services/repositories/payments_repository.dart`). Rows are grouped
 * by a stable receiver identity — cloud id when present, otherwise the
 * legacy per-device numeric id — and ordered by total amount descending.
 */
data class PaymentUserHotelDaySummary(
    val userId: Long?,
    val userName: String,
    val totalAmount: Double,
    val paymentCount: Int
)
