package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Pure business model for a booking — no Room/Gson/Android persistence concerns. */
@Parcelize
data class Booking(
    val id: Long = 0,
    val serverBookingId: Int? = null,
    val roomNumber: String = "",
    val guestName: String = "",
    val guestPhone: String = "",
    val guestIdType: String = "بطاقة شخصية",
    val guestIdNumber: String = "",
    val guestIdIssueDate: String? = null,
    val guestIdIssuePlace: String? = null,
    val guestNationality: String = "",
    val guestEmail: String? = null,
    val guestAddress: String? = null,
    val checkinDate: String = "",
    val checkoutDate: String? = null,
    val actualCheckout: String? = null,
    val status: String = "",
    val notes: String? = null,
    val discount: Double = 0.0,
    val discountType: String = "per_night",
    val discountStartDate: String? = null,
    val expectedNights: Int = 1,
    val calculatedNights: Int = 1,
    val totalNightsCached: Int = 0,
    val isOverdue: Boolean = false,
    val needsCheckoutReview: Boolean = false,
    val totalDueCached: Double = 0.0,
    val totalPaidCached: Double = 0.0,
    val remainingBalanceCached: Double = 0.0,
    val isFullyPaid: Boolean = false,
    val hotelDayCheckin: String? = null,
    val hotelDayCheckout: String? = null,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable
