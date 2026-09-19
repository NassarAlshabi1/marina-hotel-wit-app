package com.marina.marina.domain.session

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PaymentSessionContext tests — the shift-receipts attribution contract
 * (Option A: the session IS the login session). Every payment recorded
 * during a session carries its identity; clearing it de-attributes.
 */
class PaymentSessionContextTest {

    @Test
    fun `inactive by default`() {
        PaymentSessionContext.clear()
        assertFalse(PaymentSessionContext.isActive)
        assertNull(PaymentSessionContext.userId)
        assertNull(PaymentSessionContext.sessionUuid)
    }

    @Test
    fun `start stamps identity and generates session uuid`() {
        PaymentSessionContext.start(userId = 7, userName = "أحمد")
        assertTrue(PaymentSessionContext.isActive)
        assertEquals(7L, PaymentSessionContext.userId)
        assertEquals("أحمد", PaymentSessionContext.userName)
        assertTrue(PaymentSessionContext.sessionUuid!!.isNotBlank())
        assertTrue(PaymentSessionContext.startedAt!! > 0)
        PaymentSessionContext.clear()
    }

    @Test
    fun `each start regenerates the session uuid`() {
        PaymentSessionContext.start(userId = 1, userName = "a", sessionUuid = null)
        val first = PaymentSessionContext.sessionUuid
        PaymentSessionContext.start(userId = 1, userName = "a")
        val second = PaymentSessionContext.sessionUuid
        assertNotEquals(first, second)
        PaymentSessionContext.clear()
    }

    @Test
    fun `explicit session uuid is preserved`() {
        PaymentSessionContext.start(userId = 3, userName = "b", sessionUuid = "fixed-uuid")
        assertEquals("fixed-uuid", PaymentSessionContext.sessionUuid)
        PaymentSessionContext.clear()
    }

    @Test
    fun `clear wipes all identity fields`() {
        PaymentSessionContext.start(userId = 9, userName = "c", cloudUserId = "cloud-9")
        PaymentSessionContext.clear()
        assertFalse(PaymentSessionContext.isActive)
        assertNull(PaymentSessionContext.userId)
        assertNull(PaymentSessionContext.userName)
        assertNull(PaymentSessionContext.sessionUuid)
        assertNull(PaymentSessionContext.cloudUserId)
        assertNull(PaymentSessionContext.startedAt)
    }

    @Test
    fun `user session manager mirrors the context`() {
        val manager = UserSessionManager()
        assertFalse(manager.isSessionActive)
        val user = com.marina.marina.domain.model.AuthUser(
            id = 5,
            username = "admin",
            fullName = "المدير العام",
            userType = "admin"
        )
        manager.startSession(user)
        assertTrue(manager.isSessionActive)
        assertEquals(5L, PaymentSessionContext.userId)
        assertEquals("المدير العام", PaymentSessionContext.userName)
        assertEquals(user, manager.currentUser.value)
        assertTrue(manager.currentUser.value!!.isAdmin)
        manager.endSession()
        assertFalse(manager.isSessionActive)
        assertNull(manager.currentUser.value)
    }
}
