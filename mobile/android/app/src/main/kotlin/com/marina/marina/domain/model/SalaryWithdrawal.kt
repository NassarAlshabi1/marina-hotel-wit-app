package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

/**
 * A salary withdrawal / advance / deduction recorded against an employee.
 * Mirrors the Flutter `salary_withdrawals` table.
 */
@Parcelize
data class SalaryWithdrawal(
    val id: Long = 0,
    val employeeId: Long = 0,
    val employeeUuid: String? = null,
    val employeeName: String = "",
    val amount: Double = 0.0,
    val withdrawDate: Long = 0,
    val hotelDayKey: String? = null,
    val withdrawalType: String = "سحب راتب", // سلفة / سحب راتب / خصم
    val reason: String? = null,
    val description: String? = null,
    val localUuid: String = "",
    val serverId: Int? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
    val deletedAt: Long? = null,
    val version: Int = 1
) : Parcelable
