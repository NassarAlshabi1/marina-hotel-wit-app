package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Pure business model for a hotel room — no Room/Gson/Android persistence concerns. */
@Parcelize
data class Room(
    val id: Long = 0,
    val roomNumber: String = "",
    val type: String = "",
    val price: Double = 0.0,
    val status: String = "",
    val imageUrl: String? = null,
    val cleaningStatus: String = "clean",
    val lastCleanedHotelDay: String? = null,
    val lastOccupiedHotelDay: String? = null,
    val requiresMaintenance: Boolean = false,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable
