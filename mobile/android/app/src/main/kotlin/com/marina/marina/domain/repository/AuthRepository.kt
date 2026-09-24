package com.marina.marina.domain.repository

import com.marina.marina.domain.model.AuthUser

interface AuthRepository {
    /**
     * @param rememberMe نظير rememberMe في Dart (login_screen.dart): عند
     * false لا تُستعاد الجلسة عند الإقلاع التالي (تسجيل دخول كل مرة).
     */
    suspend fun login(username: String, password: String, rememberMe: Boolean = true): Result<AuthUser>
    suspend fun restoreSession(): AuthUser?
    fun logout()
}
