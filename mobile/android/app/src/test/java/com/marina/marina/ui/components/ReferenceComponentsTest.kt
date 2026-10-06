package com.marina.marina.ui.components

import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import com.marina.marina.domain.model.RoomWithPaymentStatus
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.ui.theme.TajawalFamily
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@OptIn(ExperimentalCoroutinesApi::class)
class ReferenceComponentsTest {
    @Test fun everyMaterialTextRoleUsesBundledTajawal() {
        with(AppTypography) {
            listOf(displayLarge, displayMedium, displaySmall, headlineLarge, headlineMedium,
                headlineSmall, titleLarge, titleMedium, titleSmall, bodyLarge, bodyMedium,
                bodySmall, labelLarge, labelMedium, labelSmall).forEach {
                assertEquals(TajawalFamily, it.fontFamily)
            }
        }
    }

    @Test fun referenceSnackbarTimingIsNotTheMaterialShortLongDefault() {
        assertEquals(3_000L, MarinaSnackbarVisuals("تم", MarinaSnackbarType.SUCCESS).timeoutMillis)
        assertEquals(4_000L, MarinaSnackbarVisuals("فشل", MarinaSnackbarType.ERROR).timeoutMillis)
        assertEquals(2_000L, MarinaSnackbarVisuals("تمت المزامنة", type = null,
            floating = false, timeoutOverrideMillis = 2_000L).timeoutMillis)
        assertEquals(Long.MAX_VALUE, MarinaSnackbarVisuals("انتظار",
            requestedDuration = SnackbarDuration.Indefinite).timeoutMillis)
        assertEquals(Long.MAX_VALUE, MarinaSnackbarVisuals("إجراء", actionLabel = "تراجع").timeoutMillis)
        assertNull(MarinaSnackbarVisuals("نص فقط").icon)
        assertEquals(SnackbarDuration.Indefinite, MarinaSnackbarVisuals("تم").duration)
    }

    @Test fun typedSnackbarsKeepReadableWhiteText() {
        MarinaSnackbarType.entries.forEach {
            val ratio = 1.05 / (snackbarContainer(it).luminance() + 0.05)
            assertTrue("$it contrast $ratio", ratio >= 4.5)
        }
    }

    @Test fun roomStatusPaletteMatchesFlutterNotTheOldOceanPalette() {
        assertEquals(Color(0xFFE53935), RoomWithPaymentStatus.OccupiedColor)
        assertEquals(Color(0xFF43A047), RoomWithPaymentStatus.VacantColor)
        assertEquals(Color(0xFFFB8C00), RoomWithPaymentStatus.MaintenanceColor)
        assertEquals(Color(0xFFFF9800), RoomWithPaymentStatus.LatePaymentColor)
        assertEquals(Color(0xFFC62828), RoomWithPaymentStatus.OverdueColor)
        assertEquals(Color(0xFFB71C1C), RoomWithPaymentStatus.OverdueDark)
    }

    @Test fun actionAndDismissSignalsReachSuspendedCallers() = runTest {
        val host = SnackbarHostState()
        val action = async { host.showSnackbar(MarinaSnackbarVisuals("اختبار", actionLabel = "فتح")) }
        runCurrent()
        host.currentSnackbarData!!.performAction()
        assertEquals(SnackbarResult.ActionPerformed, action.await())
        val dismissed = async { host.showSnackbar(MarinaSnackbarVisuals("اختبار", withDismissAction = true)) }
        runCurrent()
        host.currentSnackbarData!!.dismiss()
        assertEquals(SnackbarResult.Dismissed, dismissed.await())
        assertNull(host.currentSnackbarData)
    }

    @Test fun helperReplacesOldMessageInsteadOfQueueingIt() = runTest {
        val host = SnackbarHostState()
        val first = showMarinaSnackbar(host, "قديم")
        runCurrent()
        val second = showMarinaSnackbar(host, "جديد")
        runCurrent()
        assertTrue(first.isCompleted)
        assertEquals("جديد", host.currentSnackbarData!!.visuals.message)
        host.currentSnackbarData!!.dismiss()
        second.join()
    }
}
