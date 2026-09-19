package com.marina.marina.domain.session

import com.marina.marina.domain.model.AuthUser
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Holds the authenticated user for the whole process and mirrors it into
 * the [PaymentSessionContext] so every payment recorded during the session
 * is attributed to the logged-in user (Flutter Option A: the session IS the
 * login session).
 *
 * The [AuthViewModel] starts/ends the session here; feature ViewModels
 * (Dashboard, Payments...) observe [currentUser] without reaching into
 * auth internals.
 */
@Singleton
class UserSessionManager @Inject constructor() {

    private val _currentUser = MutableStateFlow<AuthUser?>(null)
    val currentUser: StateFlow<AuthUser?> = _currentUser.asStateFlow()

    val isSessionActive: Boolean
        get() = PaymentSessionContext.isActive

    /** Session start instant (login time), null when no session is active. */
    val sessionStartedAt: Long?
        get() = PaymentSessionContext.startedAt

    fun startSession(user: AuthUser) {
        _currentUser.value = user
        PaymentSessionContext.start(
            userId = user.id.toLong(),
            userName = user.name,
            cloudUserId = user.cloudUserId
        )
    }

    fun endSession() {
        _currentUser.value = null
        PaymentSessionContext.clear()
    }
}
