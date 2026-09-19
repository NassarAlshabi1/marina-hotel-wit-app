package com.marina.marina.data.auth

import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.repository.AuthRepository
import com.marina.marina.domain.session.UserSessionManager
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepositoryImpl @Inject constructor(
    private val syncService: CloudflareSyncService,
    private val preferences: SyncPreferences,
    private val sessionManager: UserSessionManager
) : AuthRepository {

    override suspend fun login(username: String, password: String): Result<AuthUser> {
        val tokenResult = syncService.login(username, password)
        return tokenResult.fold(
            onSuccess = {
                val deviceId = preferences.getDeviceId() ?: "cf_dev_${System.currentTimeMillis()}"
                preferences.saveDeviceId(deviceId)
                val user = AuthUser(
                    id = 1,
                    username = username,
                    fullName = username,
                    userType = "admin",
                    permissions = listOf("all")
                )
                sessionManager.startSession(user)
                Result.success(user)
            },
            onFailure = { Result.failure(it) }
        )
    }

    override suspend fun restoreSession(): AuthUser? {
        val token = preferences.getAuthToken()
        val deviceId = preferences.getDeviceId()
        if (token == null || deviceId == null) return null
        val user = AuthUser(
            id = 0,
            username = "admin",
            fullName = "Admin",
            userType = "admin",
            permissions = listOf("all")
        )
        sessionManager.startSession(user)
        return user
    }

    override fun logout() {
        sessionManager.endSession()
        preferences.saveAuthToken("")
    }
}
