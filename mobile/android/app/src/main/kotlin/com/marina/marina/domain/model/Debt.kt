package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Pure business model for a debt — no Room/Gson/Android persistence concerns. */
@Parcelize
data class Debt(
    val id: Long = 0,
    val bookingLocalId: Long? = null,
    val guestName: String = "",
    val guestPhone: String? = null,
    val checkinDate: String = "",
    val checkoutDate: String = "",
    val dateRecorded: String = "",
    val debtReason: String = "",
    val totalAmount: Double = 0.0,
    val paidAmount: Double = 0.0,
    val remainingAmount: Double = 0.0,
    val paymentDate: String = "",
    val isSettled: Boolean = false,
    val note: String? = null,
    /** رهن (pledge) — Dart debts_list l.522-549 renders the pledge box. */
    val pledge: String? = null,
    val pledgeType: String? = null,
    val hotelDayOpened: String? = null,
    val hotelDayClosed: String? = null,
    val isFromAutoFix: Boolean = false,
    val settlementConfirmed: Boolean = false,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable
