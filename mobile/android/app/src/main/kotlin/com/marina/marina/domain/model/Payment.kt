package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

enum class PaymentMethod(val displayName: String, val displayNameAr: String) {
    CASH("Cash", "نقدي"),
    CARD("Card", "بطاقة ائتمانية"),
    TRANSFER("Transfer", "تحويل بنكي"),
    CHECK("Check", "شيك"),
    INSTALLMENT("Installment", "تقسيط");

    companion object {
        fun fromString(name: String): PaymentMethod =
            values().find { it.name == name } ?: CASH
    }
}

enum class PaymentStatus(val displayName: String, val displayNameAr: String) {
    PENDING("Pending", "في الانتظار"),
    COMPLETED("Completed", "مكتمل"),
    FAILED("Failed", "فشل"),
    REFUNDED("Refunded", "مسترد");

    companion object {
        fun fromString(name: String): PaymentStatus =
            values().find { it.name == name } ?: PENDING
    }
}

/** Pure business model for a payment — no Room/Gson/Android persistence concerns. */
@Parcelize
data class Payment(
    val id: Long = 0,
    val bookingLocalId: Long? = null,
    val roomNumber: String? = null,
    val amount: Double = 0.0,
    val paymentDate: String = "",
    val paymentMethod: String = "",
    val revenueType: String = "",
    val notes: String? = null,
    val referenceNumber: String? = null,
    val hotelDayKey: String? = null,
    val isPendingBalance: Boolean = false,
    val isVoided: Boolean = false,
    val voidedAt: Long? = null,
    val voidedBy: String? = null,
    val voidReason: String? = null,
    val receivedByName: String? = null,
    val receivedByUserId: Long? = null,
    val receivedSessionUuid: String? = null,
    val receivedByCloudId: String? = null,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable
