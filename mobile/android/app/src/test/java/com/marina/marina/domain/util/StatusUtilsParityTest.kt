package com.marina.marina.domain.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * تكافؤ `StatusUtils` مع المرجع الدارتي (`mobile/lib/utils/status_utils.dart`
 * في فرع `feat/cloudflare-sync-execution`) — الفجوة الموثّقة في
 * `docs/android-epoch-unit-parity.md` §5: `isRoomOccupied` في Dart يستثني
 * «مكتمل/completed/checked_out/checked out» **صراحةً** قبل فحص مجموعة المشغولة.
 *
 * ملاحظة صدق: المجموعة نفسها عندنا مطابقة حرفياً لمجموعة Dart، وهذه القيم
 * الأربع ليست فيها، فالسلوك الفعلي كان متطابقاً؛ لكن الاستبعاد صار الآن
 * بنيوياً (لا ينقلب المعنى لو أُضيف للمجموعة يوماً)، وهذا الملف يمنع أي
 * انحراف مستقبلي في أيٍّ من المجموعتين.
 */
class StatusUtilsParityTest {

    /** حرفياً من `status_utils.dart` l.14-24 (بعد التطبيع trim+lowercase). */
    private val dartOccupiedRoomStatuses = listOf(
        "محجوزة", "محجوز", "مشغولة", "occupied", "محجوز temporarily",
        "نشط", "active", "مؤقت", "provisional"
    )

    /** حرفياً من `status_utils.dart` l.4-12. */
    private val dartAvailableRoomStatuses = listOf(
        "شاغرة", "شاغره", "متاحة", "متاح", "available", "vacant", "empty"
    )

    /** حرفياً من `status_utils.dart` l.57-62. */
    private val dartMaintenanceRoomStatuses = listOf(
        "صيانة", "maintenance", "under_maintenance", "under maintenance"
    )

    /** حرفياً من `status_utils.dart` l.26-36 (قائمة SQL الخام). */
    private val dartActiveBookingStatuses = listOf(
        "محجوزة", "محجوز", "نشط", "active", "confirmed", "قيد الحجز",
        "in_progress", "مؤقت", "provisional"
    )

    /** الاستبعاد الصريح في `isRoomOccupied` (l.105-110). */
    private val dartCompletedStatuses = listOf(
        "مكتمل", "مكتملة", "completed", "checked_out", "checked out"
    )

    @Test
    fun occupiedSetMatchesDartExactly() {
        for (status in dartOccupiedRoomStatuses) {
            assertTrue("يجب أن تُعدّ مشغولة كما في Dart: $status", StatusUtils.isRoomOccupied(status))
        }
        // الاختلافات في المسافات وحالة الأحرف تُطبَّع (trim+lowercase).
        assertTrue(StatusUtils.isRoomOccupied("  محجوزة  "))
        assertTrue(StatusUtils.isRoomOccupied("ACTIVE"))
    }

    @Test
    fun completedStatusesAreNeverOccupied() {
        for (status in dartCompletedStatuses) {
            assertFalse("Dart يستثنيها صراحةً: $status", StatusUtils.isRoomOccupied(status))
            // التطبيع نفسه (trim + lowercase) يُطبَّق قبل الاستبعاد.
            assertFalse("التطبيع: $status", StatusUtils.isRoomOccupied("  ${status.uppercase()}  "))
        }
    }

    @Test
    fun availableAndMaintenanceSetsMatchDart() {
        for (status in dartAvailableRoomStatuses) {
            assertTrue("متاحة في Dart: $status", StatusUtils.isRoomAvailable(status))
            assertFalse("ليست مشغولة في Dart: $status", StatusUtils.isRoomOccupied(status))
        }
        for (status in dartMaintenanceRoomStatuses) {
            assertTrue("صيانة في Dart: $status", StatusUtils.isRoomUnderMaintenance(status))
            // الصيانة ليست مشغولة ولا متاحة — أساس سلوك refreshAllRoomOccupancy.
            assertFalse(StatusUtils.isRoomOccupied(status))
            assertFalse(StatusUtils.isRoomAvailable(status))
        }
    }

    @Test
    fun activeBookingStatusesMatchDartIncludingSqlRawList() {
        for (status in dartActiveBookingStatuses) {
            assertTrue("حجز نشط في Dart: $status", StatusUtils.isBookingActive(status))
        }
        // عكس القائمة: مكتمل/ملغي ليستا نشطتين.
        assertFalse(StatusUtils.isBookingActive("مكتمل"))
        assertFalse(StatusUtils.isBookingActive("ملغي"))
        assertFalse(StatusUtils.isBookingActive("cancelled"))
    }

    @Test
    fun roomStatusForOccupancyMatchesDartDefaults() {
        assertEquals("محجوزة", StatusUtils.roomStatusForOccupancy(true))
        assertEquals("شاغرة", StatusUtils.roomStatusForOccupancy(false))
    }
}
