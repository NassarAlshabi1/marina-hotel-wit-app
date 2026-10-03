package com.marina.marina.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ThemeContrastTest {
    private fun contrast(a: Color, b: Color): Double {
        val light = maxOf(a.luminance(), b.luminance()).toDouble()
        val dark = minOf(a.luminance(), b.luminance()).toDouble()
        return (light + 0.05) / (dark + 0.05)
    }

    @Test
    fun semanticTextRemainsReadableInBothThemes() {
        for (scheme in listOf(MarinaLightColorScheme, MarinaDarkColorScheme)) {
            val pairs = listOf(
                "body" to (scheme.onSurface to scheme.surface),
                "secondary text" to (scheme.onSurfaceVariant to scheme.surface),
                "background" to (scheme.onBackground to scheme.background),
                "primary" to (scheme.onPrimary to scheme.primary),
                "primary container" to (scheme.onPrimaryContainer to scheme.primaryContainer),
                "secondary" to (scheme.onSecondary to scheme.secondary),
                "success" to (scheme.onTertiary to scheme.tertiary),
                "error" to (scheme.onError to scheme.error)
            )
            pairs.forEach { (name, pair) ->
                val ratio = contrast(pair.first, pair.second)
                assertTrue("$name contrast is $ratio, expected at least 4.5:1", ratio >= 4.5)
            }
            assertTrue("Input outlines need 3:1 contrast", contrast(scheme.outline, scheme.surface) >= 3.0)
        }
    }

    @Test
    fun filledActionColorsSupportExistingWhiteLabels() {
        for (background in listOf(AppColors.PrimaryActionColor, AppColors.SuccessActionColor,
            AppColors.WarningActionColor, AppColors.DangerActionColor)) {
            assertTrue("White action label lost contrast", contrast(Color.White, background) >= 4.5)
        }
    }
    @Test
    fun referencePaletteAndLayoutMeasurementsRemainStable() {
        // Flutter reference 78c17381: utils/theme.dart, admin_layout/sidebar,
        // and report_page_scaffold.dart. Prevent accidental coastal-style drift.
        assertEquals(Color(0xFF242476), MarinaLightColorScheme.primary)
        assertEquals(Color(0xFFF8F8FC), MarinaLightColorScheme.background)
        assertEquals(Color(0xFFD3D3E4), MarinaLightColorScheme.outlineVariant)
        assertEquals(Color(0xFFEAEAF2), MarinaLightColorScheme.primaryContainer)
        assertEquals(Color(0xFF0A0E2F), MarinaLightColorScheme.onSurface)
        assertEquals(Color(0xFF11142B), MarinaDarkColorScheme.surface)
        assertEquals(Color(0xFF2A2D4A), MarinaDarkColorScheme.outlineVariant)
        assertEquals(280.dp, ReferenceLayout.SidebarWidth)
        assertEquals(768.dp, ReferenceLayout.SidebarBreakpoint)
        assertEquals(8.dp, ReferenceLayout.ReportSectionGap)
        val size = Size(100f, 100f)
        val density = Density(1f)
        assertEquals(8f, MarinaShapes.small.topStart.toPx(size, density), 0.001f)
        assertEquals(12f, MarinaShapes.medium.topStart.toPx(size, density), 0.001f)
        assertEquals(16f, MarinaShapes.large.topStart.toPx(size, density), 0.001f)
        for (direction in listOf(LayoutDirection.Ltr, LayoutDirection.Rtl)) {
            assertEquals(8.dp, ReferenceLayout.ReportPadding.calculateLeftPadding(direction))
            assertEquals(8.dp, ReferenceLayout.ReportPadding.calculateRightPadding(direction))
        }
        assertEquals(6.dp, ReferenceLayout.ReportPadding.calculateTopPadding())
        assertEquals(6.dp, ReferenceLayout.ReportPadding.calculateBottomPadding())
    }

}
