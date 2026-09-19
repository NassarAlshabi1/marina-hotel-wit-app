package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class BookingNight(
    val id: Long = 0,
    val bookingLocalId: Long = 0,
    val hotelDayKey: String = "",
    val nightStart: String = "",
    val nightEnd: String = "",
    val nightlyRate: Double = 0.0,
    val sequence: Int = 0,
    val baseRate: Double = 0.0,
    val adjustment: Double = 0.0,
    val finalRate: Double = 0.0,
    val localUuid: String = ""
) : Parcelable

@Parcelize
data class BookingPriceAdjustment(
    val id: Long = 0,
    val bookingLocalUuid: String = "",
    val bookingLocalId: Long? = null,
    val roomNumber: String? = null,
    val amount: Double = 0.0,
    val effectiveHotelDay: String = "",
    val endHotelDay: String? = null,
    val isActive: Boolean = true,
    val reason: String? = null,
    val localUuid: String = ""
) : Parcelable

@Parcelize
data class HotelDayLedger(
    val id: Long = 0,
    val hotelDayKey: String = "",
    val totalIncome: Double = 0.0,
    val totalExpenses: Double = 0.0,
    val pendingBalances: Double = 0.0,
    val occupancyRate: Double = 0.0,
    val status: String = "draft",
    val localUuid: String = ""
) : Parcelable
