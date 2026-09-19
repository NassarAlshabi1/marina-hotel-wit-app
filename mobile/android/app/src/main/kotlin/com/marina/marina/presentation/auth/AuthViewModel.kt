package com.marina.marina.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.usecase.auth.LoginUseCase
import com.marina.marina.domain.usecase.auth.LogoutUseCase
import com.marina.marina.domain.usecase.auth.RestoreSessionUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val loginUseCase: LoginUseCase,
    private val restoreSessionUseCase: RestoreSessionUseCase,
    private val logoutUseCase: LogoutUseCase
) : ViewModel() {

    private val _authState = MutableStateFlow(AuthState(isAuthenticated = false, isRestoring = true))
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    init {
        restoreSession()
    }

    private fun restoreSession() {
        viewModelScope.launch {
            val user = restoreSessionUseCase()
            _authState.value = if (user != null) {
                AuthState(isAuthenticated = true, currentUser = user, rememberMe = true)
            } else {
                AuthState(isAuthenticated = false, isRestoring = false)
            }
        }
    }

    fun login(username: String, password: String) {
        _authState.value = _authState.value.copy(isRestoring = true, error = null)

        viewModelScope.launch {
            loginUseCase(username, password)
                .onSuccess { user ->
                    _authState.value = AuthState(
                        isAuthenticated = true,
                        currentUser = user,
                        rememberMe = true
                    )
                }
                .onFailure { error ->
                    _authState.value = AuthState(
                        isAuthenticated = false,
                        isRestoring = false,
                        error = error.message ?: "Login failed"
                    )
                }
        }
    }

    fun logout() {
        logoutUseCase()
        _authState.value = AuthState(isAuthenticated = false, isRestoring = false)
    }
}

data class AuthState(
    val isAuthenticated: Boolean = false,
    val isRestoring: Boolean = false,
    val currentUser: AuthUser? = null,
    val rememberMe: Boolean = false,
    val error: String? = null
)
