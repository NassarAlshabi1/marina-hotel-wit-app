package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Pure business model for an inventory item — no Room/Gson persistence concerns. */
@Parcelize
data class InventoryItem(
    val id: Long = 0,
    val name: String = "",
    val unit: String = "قطعة",
    val category: String? = null,
    val currentQuantity: Double = 0.0,
    val minimumQuantity: Double = 0.0,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable {
    val isLowStock: Boolean get() = currentQuantity <= minimumQuantity
}

/** A single inventory movement (in / out / adjustment). */
@Parcelize
data class InventoryTransaction(
    val id: Long = 0,
    val itemId: Long = 0,
    val transactionType: String = "", // "in" | "out" | "adjustment"
    val quantity: Double = 0.0,
    val balanceAfter: Double = 0.0,
    val note: String? = null,
    val transactionTime: Long = 0,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable
