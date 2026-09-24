package com.marina.marina.data.auth

import com.google.gson.Gson
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

    private val gson = Gson()

    override suspend fun login(username: String, password: String, rememberMe: Boolean): Result<AuthUser> {
        // ✅ (2026-09-24) حفظ تفضيل «تذكرني» — نفس عقد Dart (login_screen.dart
        // → authProvider.login(…, rememberMe:)) — يقرر استعادة الجلسة لاحقاً.
        preferences.setRememberMe(rememberMe)

        // Built-in administrator: admin/admin unlocks the app locally.
        // Checked BEFORE the network so the login screen works offline
        // and never depends on Worker availability.
        if (LocalAdminAuth.matches(username, password)) {
            return Result.success(startLocalAdminSession(username))
        }

        val tokenResult = syncService.login(username, password)
        return tokenResult.fold(
            onSuccess = { token ->
                val deviceId = ensureDeviceId()
                // Dart auth_local_store.dart l.355-412 — the Worker response
                // carries the REAL user metadata (id / username / role). The
                // role drives RBAC: 'admin' -> permissions ['all']; every other
                // role keeps its own (restricted) permission set.
                val workerUser = syncService.lastLoginUser
                val role = workerUser?.role?.trim()?.lowercase() ?: "employee"
                val user = AuthUser(
                    id = workerUser?.id?.toLongOrNull()?.toInt() ?: 1,
                    username = workerUser?.username?.trim() ?: username.trim(),
                    fullName = workerUser?.username?.trim() ?: username.trim(),
                    userType = role,
                    permissions = if (role == "admin" || role.isEmpty()) listOf("all") else emptyList()
                )
                persistUser(user)
                sessionManager.startSession(user)
                Result.success(user)
            },
            onFailure = { Result.failure(it) }
        )
    }

    override suspend fun restoreSession(): AuthUser? {
        // ✅ «تذكرني» غير مفعّل = لا استعادة للجلسة (نفس Dart).
        if (!preferences.getRememberMe()) return null
        val token = preferences.getAuthToken()
        val deviceId = preferences.getDeviceId()
        // An empty token is what logout() leaves behind — treating it as
        // "session present" would resurrect a signed-out session, so an
        // empty token (or missing device id) means signed out.
        if (token.isNullOrEmpty() || deviceId == null) return null
        // Restore the REAL logged-in identity (Dart restores the stored user
        // object — never a hardcoded 'admin').
        val stored = preferences.getCurrentUserJson()
        val user = if (!stored.isNullOrBlank()) {
            try { gson.fromJson(stored, AuthUser::class.java) } catch (_: Exception) { null }
        } else null
        val restored = user ?: AuthUser(
            id = 1,
            username = "admin",
            fullName = "Admin",
            userType = "admin",
            permissions = listOf("all")
        )
        sessionManager.startSession(restored)
        return restored
    }

    override fun logout() {
        sessionManager.endSession()
        preferences.saveAuthToken("")
        preferences.clearCurrentUser()
    }

    private fun persistUser(user: AuthUser) {
        try {
            preferences.saveCurrentUserJson(gson.toJson(user))
        } catch (_: Exception) {
            // Persistence is best-effort; the in-memory session still works.
        }
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
        persistUser(user)
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
