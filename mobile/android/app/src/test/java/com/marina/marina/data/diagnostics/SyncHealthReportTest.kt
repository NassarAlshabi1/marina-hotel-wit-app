package com.marina.marina.data.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Test

class SyncHealthReportTest {
    private val empty = SyncHealthReport(0, 0, 0, 0, 0, null, emptyMap(), emptyMap(), 0, 1)

    @Test fun referenceThresholdsAndBoundaryValues() {
        assertEquals(SyncHealthLevel.HEALTHY, empty.level)
        assertEquals(SyncHealthLevel.OK, empty.copy(processing = 1).level)
        assertEquals(SyncHealthLevel.OK, empty.copy(pending = 100, oldestAgeMs = 600_000).level)
        assertEquals(SyncHealthLevel.WARNING, empty.copy(pending = 101).level)
        assertEquals(SyncHealthLevel.WARNING, empty.copy(failed = 6).level)
        assertEquals(SyncHealthLevel.ERROR, empty.copy(failed = 21).level)
        assertEquals(SyncHealthLevel.ERROR, empty.copy(pending = 1, oldestAgeMs = 600_001).level)
        assertEquals(SyncHealthLevel.WARNING, empty.copy(stuck = 10).level)
        assertEquals(SyncHealthLevel.CRITICAL, empty.copy(stuck = 11).level)
        assertEquals(SyncHealthLevel.CRITICAL, empty.copy(fkViolations = 1).level)
    }
}
