package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class PaymentVoid(
    val id: Long = 0,
    val originalPaymentUuid: String = "",
    val originalPaymentId: Long = 0,
    val bookingUuid: String = "",
    val voidedAmount: Long = 0,
    val voidReason: String = "",
    val voidedBy: String = "",
    val voidedAt: Long = 0,
    val voidedAtIso: String = "",
    val hotelDayKey: String = "",
    val reversalPaymentUuid: String? = null,
    val approvedBy: String? = null,
    val note: String? = null,
    val localUuid: String = ""
) : Parcelable
