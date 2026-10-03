package com.marina.marina.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
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
}
