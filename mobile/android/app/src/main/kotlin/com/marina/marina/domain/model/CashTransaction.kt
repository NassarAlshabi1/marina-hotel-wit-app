package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class CashTransaction(
    val id: Long = 0,
    val registerId: Long? = null,
    val transactionType: String = "",
    val amount: Double = 0.0,
    val referenceType: String? = null,
    val referenceId: Long? = null,
    val description: String? = null,
    val transactionTime: String = "",
    val createdBy: Long? = null,
    val localUuid: String = "",
    val createdAt: Long = 0,
    val updatedAt: Long = 0
) : Parcelable
