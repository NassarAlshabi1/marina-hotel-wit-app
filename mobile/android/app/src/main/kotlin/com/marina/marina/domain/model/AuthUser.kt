package com.marina.marina.domain.model

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class AuthUser(
    val id: Int = 0,
    val username: String = "",
    val fullName: String = "",
    val userType: String = "",
    val cloudUserId: String? = null,
    val permissions: List<String> = emptyList()
) : Parcelable {
    val name: String get() = if (fullName.isNotEmpty()) fullName else username
    val isAdmin: Boolean get() = userType == "admin" || permissions.contains("all")

    /**
     * Dart `AuthLocalStore.isManagerialRole` + `AuthUser.canManageRecords`:
     * تعديل/حذف السجلات الموجودة (وإلغاء الدفعات) مقيّد بالدور —
     * admin أو manager أو supervisor أو صلاحية 'all'.
     */
    val canManageRecords: Boolean
        get() = userType == "admin" || userType == "manager" ||
            userType == "supervisor" || permissions.contains("all")

    /** إلغاء الدفعات (void) — نفس قيد canManageRecords. */
    val canVoidPayments: Boolean get() = canManageRecords

    /**
     * Dart `AuthUser.canPerform(module, action)` — القاعدة المحدّثة:
     * view/create متاحان لكل مستخدم يملك دخول الوحدة، بينما
     * update/delete يتطلبان دوراً إدارياً (canManageRecords).
     */
    fun canPerform(module: String, action: String): Boolean {
        if (isAdmin) return true
        val canEnter = permissions.contains(module) ||
            permissions.any { it.startsWith("$module.") }
        if (!canEnter) return false
        if (action == "view" || action == "create") return true
        return canManageRecords
    }

    /** Dart `canAccessModule` — visibility gate for whole screens. */
    fun canAccessModule(module: String): Boolean =
        isAdmin || permissions.contains("all") || permissions.any { it == module || it.startsWith("$module.") }
}
