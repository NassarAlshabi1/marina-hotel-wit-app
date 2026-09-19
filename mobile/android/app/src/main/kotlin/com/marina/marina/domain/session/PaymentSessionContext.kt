package com.marina.marina.domain.session

import java.util.UUID

/**
 * Payment-session context that new payments are attributed to.
 *
 * Ported 1:1 from the Flutter app's `lib/services/payment_session_context.dart`.
 *
 * This is NOT a standalone shifts table; it represents the current login
 * session (Option A as agreed in the Flutter app). The [sessionUuid] is
 * regenerated on every login/restore.
 */
object PaymentSessionContext {

    var userId: Long? = null
        private set

    var userName: String? = null
        private set

    var sessionUuid: String? = null
        private set

    var cloudUserId: String? = null
        private set

    var startedAt: Long? = null
        private set

    val isActive: Boolean
        get() = userId != null && sessionUuid != null

    fun start(
        userId: Long,
        userName: String,
        sessionUuid: String? = null,
        cloudUserId: String? = null,
        startedAt: Long? = null
    ) {
        this.userId = userId
        this.userName = userName
        this.sessionUuid = sessionUuid ?: UUID.randomUUID().toString()
        this.cloudUserId = cloudUserId
        this.startedAt = startedAt ?: System.currentTimeMillis()
    }

    fun clear() {
        userId = null
        userName = null
        sessionUuid = null
        cloudUserId = null
        startedAt = null
    }
}
