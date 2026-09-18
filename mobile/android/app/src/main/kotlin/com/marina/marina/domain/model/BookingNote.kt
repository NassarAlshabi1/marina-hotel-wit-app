package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Pure business model for a booking note/alert — no Room/Gson/Android persistence concerns. */
@Parcelize
data class BookingNote(
    val id: Long = 0,
    val bookingId: Long = 0,
    val noteText: String = "",
    val alertType: String = "",
    val alertUntil: String? = null,
    val isActive: Boolean = true,
    val localUuid: String = "",
    val createdAt: Long = 0,
    val updatedAt: Long = 0
) : Parcelable
