package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class GuestInfo(
    val id: Long = 0,
    val roomNumber: String = "",
    val guestName: String = "",
    val nationality: String = "",
    val idNumber: String = "",
    val idType: String = "بطاقة شخصية",
    val issueDate: String? = null,
    val issuePlace: String? = null,
    val governorate: String? = null,
    val notes: String? = null,
    val guestPhone: String? = null,
    val localUuid: String = "",
    val createdAt: Long = 0,
    val updatedAt: Long = 0
) : Parcelable
