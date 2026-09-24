package com.marina.marina.domain.usecase.auth

import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.repository.AuthRepository
import javax.inject.Inject

class LoginUseCase @Inject constructor(
    private val authRepository: AuthRepository
) {
    suspend operator fun invoke(
        username: String,
        password: String,
        rememberMe: Boolean = true
    ): Result<AuthUser> =
        authRepository.login(username.trim(), password, rememberMe)
}

class RestoreSessionUseCase @Inject constructor(
    private val authRepository: AuthRepository
) {
    suspend operator fun invoke(): AuthUser? = authRepository.restoreSession()
}

class LogoutUseCase @Inject constructor(
    private val authRepository: AuthRepository
) {
    operator fun invoke() = authRepository.logout()
}
