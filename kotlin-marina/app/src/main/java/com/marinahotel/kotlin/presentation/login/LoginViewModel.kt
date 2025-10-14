package com.marinahotel.kotlin.presentation.login

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.R
import com.marinahotel.kotlin.data.repository.HotelRepository
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class LoginViewModel(
    private val repository: HotelRepository
) : ViewModel() {

    private val _uiState = MutableStateFlow(LoginUiState())
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<LoginEvent>()
    val events: SharedFlow<LoginEvent> = _events.asSharedFlow()

    fun onUsernameChanged(value: String) {
        _uiState.update { it.copy(username = value.trim(), errorMessageRes = null) }
    }

    fun onPasswordChanged(value: String) {
        _uiState.update { it.copy(password = value.trim(), errorMessageRes = null) }
    }

    fun submit() {
        val current = _uiState.value
        if (current.username.isBlank() || current.password.isBlank()) {
            _uiState.update { it.copy(errorMessageRes = LoginError.RequiredFields.messageRes) }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessageRes = null) }
            val success = repository.authenticate(current.username, current.password)
            if (success) {
                _uiState.update { it.copy(isLoading = false, password = "") }
                _events.emit(LoginEvent.NavigateToDashboard)
            } else {
                _uiState.update { it.copy(isLoading = false, errorMessageRes = LoginError.InvalidCredentials.messageRes) }
            }
        }
    }

    sealed class LoginEvent {
        object NavigateToDashboard : LoginEvent()
    }

    enum class LoginError(@StringRes val messageRes: Int) {
        RequiredFields(R.string.error_required_credentials),
        InvalidCredentials(R.string.error_invalid_credentials)
    }
}

data class LoginUiState(
    val username: String = "",
    val password: String = "",
    val isLoading: Boolean = false,
    @StringRes val errorMessageRes: Int? = null
)
