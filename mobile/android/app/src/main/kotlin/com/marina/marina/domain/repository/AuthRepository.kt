package com.marina.marina.domain.repository

import com.marina.marina.domain.model.AuthUser

interface AuthRepository {
    suspend fun login(username: String, password: String): Result<AuthUser>
    suspend fun restoreSession(): AuthUser?
    fun logout()
}
