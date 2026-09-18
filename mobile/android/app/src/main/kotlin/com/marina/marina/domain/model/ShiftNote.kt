package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Pure business model for a shift handover note — no Room/Gson/Android persistence concerns. */
@Parcelize
data class ShiftNote(
    val id: Long = 0,
    val title: String = "",
    val content: String = "",
    val priority: String = "medium",
    val shiftType: String = "all",
    val isRead: Boolean = false,
    val expiresAt: String? = null,
    val createdBy: String = "user",
    val localUuid: String = "",
    val createdAt: Long = 0
) : Parcelable
