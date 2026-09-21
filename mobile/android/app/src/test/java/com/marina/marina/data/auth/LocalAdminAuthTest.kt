package com.marina.marina.data.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * LocalAdminAuth tests — the login screen's built-in administrator rule.
 *
 * Contract: `admin` / `admin` (username trimmed, password exact) unlocks
 * the app locally with no network round-trip; anything else falls through
 * to the remote Worker login flow.
 */
class LocalAdminAuthTest {

    @Test
    fun `admin admin matches`() {
        assertTrue(LocalAdminAuth.matches("admin", "admin"))
    }

    @Test
    fun `username is trimmed before matching`() {
        assertTrue(LocalAdminAuth.matches("  admin  ", "admin"))
    }

    @Test
    fun `wrong password does not match`() {
        assertFalse(LocalAdminAuth.matches("admin", "Admin"))
        assertFalse(LocalAdminAuth.matches("admin", "admin "))
        assertFalse(LocalAdminAuth.matches("admin", "1234"))
        assertFalse(LocalAdminAuth.matches("admin", ""))
    }

    @Test
    fun `other usernames do not match`() {
        assertFalse(LocalAdminAuth.matches("Admin", "admin")) // username is case-sensitive
        assertFalse(LocalAdminAuth.matches("manager", "admin"))
        assertFalse(LocalAdminAuth.matches("", "admin"))
    }

    @Test
    fun `local admin token is recognized`() {
        assertTrue(LocalAdminAuth.isLocalAdminToken(LocalAdminAuth.LOCAL_ADMIN_TOKEN))
        assertFalse(LocalAdminAuth.isLocalAdminToken(null))
        assertFalse(LocalAdminAuth.isLocalAdminToken(""))
        assertFalse(LocalAdminAuth.isLocalAdminToken("eyJhbGciOiJIUzI1NiJ9.worker.jwt"))
    }

    @Test
    fun `documented credentials are stable`() {
        assertEquals("admin", LocalAdminAuth.ADMIN_USERNAME)
        assertEquals("admin", LocalAdminAuth.ADMIN_PASSWORD)
    }
}
