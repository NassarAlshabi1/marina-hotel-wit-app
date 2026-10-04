package com.marina.marina.data.backup

import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class RestoreFixReportTest {
    @Test
    fun failedRepairPreventsFollowingSuccessNotification() {
        for (details in listOf(null, "database unavailable")) {
            var notified = false
            try {
                RestoreFixReport(false, 0, 0, 0, details).requireSuccess()
                notified = true
                fail("Expected failed repair to stop success path")
            } catch (error: IllegalStateException) {
                assertTrue(error.message.orEmpty().contains("فشل الإصلاح"))
                assertTrue(error.message.orEmpty().contains(details ?: "سبب غير معروف"))
            }
            assertTrue(!notified)
        }
    }

    @Test
    fun successfulRepairAllowsSuccessPath() {
        RestoreFixReport(true, 1, 1, 1).requireSuccess()
    }
}
