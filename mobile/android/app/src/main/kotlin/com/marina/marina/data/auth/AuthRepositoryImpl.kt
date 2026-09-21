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
        // Built-in administrator: admin/admin unlocks the app locally.
        // Checked BEFORE the network so the login screen works offline
        // and never depends on Worker availability.
        if (LocalAdminAuth.matches(username, password)) {
            return Result.success(startLocalAdminSession(username))
        }

        val tokenResult = syncService.login(username, password)
        return tokenResult.fold(
            onSuccess = {
                val deviceId = ensureDeviceId()
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
        // An empty token is what logout() leaves behind — treating it as
        // "session present" would resurrect a signed-out session, so an
        // empty token (or missing device id) means signed out.
        if (token.isNullOrEmpty() || deviceId == null) return null
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

    private fun startLocalAdminSession(username: String): AuthUser {
        preferences.saveAuthToken(LocalAdminAuth.LOCAL_ADMIN_TOKEN)
        ensureDeviceId()
        val user = AuthUser(
            id = 1,
            username = username.trim().ifEmpty { LocalAdminAuth.ADMIN_USERNAME },
            fullName = "Admin",
            userType = "admin",
            permissions = listOf("all")
        )
        sessionManager.startSession(user)
        return user
    }

    private fun ensureDeviceId(): String {
        val existing = preferences.getDeviceId()
        if (existing != null) return existing
        val deviceId = "cf_dev_${System.currentTimeMillis()}"
        preferences.saveDeviceId(deviceId)
        return deviceId
    }
}
