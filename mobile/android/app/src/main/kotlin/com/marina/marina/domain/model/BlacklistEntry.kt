package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class BlacklistEntry(
    val id: Long = 0,
    val name: String = "",
    val nationality: String? = null,
    val nationalId: String? = null,
    val phone: String? = null,
    val reason: String? = null,
    val notes: String? = null,
    val reportedBy: String = "police",
    val active: Boolean = true,
    val localUuid: String = "",
    val createdAt: Long = 0,
    val updatedAt: Long = 0
) : Parcelable
