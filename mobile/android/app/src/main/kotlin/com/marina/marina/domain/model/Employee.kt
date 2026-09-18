package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/** Pure business model for an employee — no Room/Gson/Android persistence concerns. */
@Parcelize
data class Employee(
    val id: Long = 0,
    val name: String = "",
    val basicSalary: Double = 0.0,
    val position: String = "-employed",
    val phone: String = "",
    val hireDate: String = "",
    val status: String = "",
    val terminationDate: String? = null,
    val terminationReason: String? = null,
    val employeeID: String? = null,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable
