package com.marina.marina.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.*
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.session.UserSessionManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@HiltViewModel
class AuthViewModel @Inject constructor(
    private val syncService: CloudflareSyncService,
    private val preferences: SyncPreferences,
    private val sessionManager: UserSessionManager
) : ViewModel() {

    private val _authState = MutableStateFlow<AuthState>(AuthState(isAuthenticated = false, isRestoring = true))
    val authState: StateFlow<AuthState> = _authState.asStateFlow()

    init {
        restoreSession()
    }

    private fun restoreSession() {
        viewModelScope.launch {
            val token = preferences.getAuthToken()
            val deviceId = preferences.getDeviceId()
            if (token != null && deviceId != null) {
                val user = AuthUser(
                    id = 0,
                    username = "admin",
                    fullName = "Admin",
                    userType = "admin",
                    permissions = listOf("all")
                )
                // Restored sessions start a fresh payment session (new UUID),
                // mirroring the Flutter Option-A contract.
                sessionManager.startSession(user)
                _authState.value = AuthState(
                    isAuthenticated = true,
                    currentUser = user,
                    rememberMe = true
                )
            } else {
                _authState.value = AuthState(isAuthenticated = false, isRestoring = false)
            }
        }
    }

    fun login(username: String, password: String) {
        _authState.value = _authState.value.copy(isRestoring = true, error = null)

        viewModelScope.launch {
            val result = syncService.login(username, password)
            result.onSuccess { token ->
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
                _authState.value = AuthState(
                    isAuthenticated = true,
                    currentUser = user,
                    rememberMe = true
                )
            }.onFailure { error ->
                _authState.value = AuthState(
                    isAuthenticated = false,
                    isRestoring = false,
                    error = error.message ?: "Login failed"
                )
            }
        }
    }

    fun logout() {
        sessionManager.endSession()
        preferences.saveAuthToken("")
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
