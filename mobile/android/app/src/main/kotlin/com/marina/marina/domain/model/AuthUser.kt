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
}
