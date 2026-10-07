package com.marina.marina.data.sync

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * سياسات سلامة السحب — عتبات مطابقة حرفياً لـ Flutter
 * (`CloudflareSyncManager.maxSanePullCursorFuture = 2e9`،
 * `maxCursorAheadOfServerSec = سنة`) وبوابة مسح الحذفيات نفسها.
 */
class PullSanityPolicyTest {

    @Test
    fun storedCursorAboveFixedBoundIsPoisoned() {
        assertTrue(evaluateStoredCursor(2_000_000_001L).mustReset)
        assertTrue(evaluateStoredCursor(99_999_999_999L).mustReset)
        assertTrue(evaluateStoredCursor(100_000_000_000L).mustReset)
        assertFalse(evaluateStoredCursor(2_000_000_000L).mustReset)
        assertFalse(evaluateStoredCursor(1_800_000_000L).mustReset)
        assertFalse(evaluateStoredCursor(0L).mustReset)
        assertFalse(evaluateStoredCursor(123L).mustReset)
    }

    @Test
    fun serverCursorBeyondOneYearAheadOfServerTimeIsRejected() {
        val now = 1_800_000_000L
        val margin = MAX_PULL_CURSOR_AHEAD_OF_SERVER_SEC
        assertTrue(isServerCursorRejected(now + margin + 1, now))
        assertTrue(isServerCursorRejected(9_999_999_999L, now))
        // الحد نفسه مسموح (المقارنة صارمة) — انحراف ساعة الجهاز سنة كاملة.
        assertFalse(isServerCursorRejected(now + margin, now))
        assertFalse(isServerCursorRejected(now + 60, now))
        // Worker قديم بلا server_time: لا حكم ديناميكي — طبقة التثبيت تحكم.
        assertFalse(isServerCursorRejected(9_999_999_999L, null))
    }

    @Test
    fun installGuardUsesTheSameFixedBound() {
        assertTrue(isPendingCursorSafeToInstall(2_000_000_000L))
        assertTrue(isPendingCursorSafeToInstall(1_800_000_000L))
        assertFalse(isPendingCursorSafeToInstall(2_000_000_001L))
        assertFalse(isPendingCursorSafeToInstall(9_999_999_999L))
    }

    @Test
    fun sweepGateRequiresAnEstablishedDeviceAndAnOpenFlag() {
        // تثبيت جديد (cursor=0 ولم يكتمل full sync) → لا مسح: سحبه الكامل يجلب الحذفيات.
        assertFalse(tombstoneSweepDue(sweepDone = false, storedCursor = 0L, fullSyncComplete = false))
        // جهاز قائم بمؤشر محفوظ → المسح واجب مرة واحدة.
        assertTrue(tombstoneSweepDue(sweepDone = false, storedCursor = 123L, fullSyncComplete = false))
        // اكتمل full sync سابقاً ثم صُفّر المؤشر (استعادة) → يبقى واجباً.
        assertTrue(tombstoneSweepDue(sweepDone = false, storedCursor = 0L, fullSyncComplete = true))
        // العلم مضبوط → لا إعادة أبداً.
        assertFalse(tombstoneSweepDue(sweepDone = true, storedCursor = 123L, fullSyncComplete = true))
    }
}
