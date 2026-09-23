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
     * Dart `AuthUser.canPerform(module, action)` (auth_local_store.dart
     * l.87-154): admins pass everything; otherwise the permission list must
     * contain `all`, the bare module, or the `module.action` key.
     */
    fun canPerform(module: String, action: String): Boolean {
        if (isAdmin) return true
        if (permissions.contains("all")) return true
        if (permissions.contains(module)) return true
        return permissions.contains("$module.$action")
    }

    /** Dart `canAccessModule` — visibility gate for whole screens. */
    fun canAccessModule(module: String): Boolean =
        isAdmin || permissions.contains("all") || permissions.any { it == module || it.startsWith("$module.") }
}
