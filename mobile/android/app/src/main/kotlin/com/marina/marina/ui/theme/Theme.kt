package com.marina.marina.ui.theme

import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// ─────────────────────────────────────────────────────────────────────────────
// Legacy palette — kept for backward compatibility with the ported screens.
// New code should prefer MaterialTheme.colorScheme below.
// ─────────────────────────────────────────────────────────────────────────────

object AppColors {
    val PrimaryColor = Color(0xFF242476)
    val PrimaryDark = Color(0xFF3D3D9E)
    val PrimaryLight = Color(0xFFEAEAF2)
    val Secondary = Color(0xFF0A0E2F)
    val AccentColor = Color(0xFFFABA3E)
    val BackgroundColor = Color(0xFFF8F8FC)
    val SurfaceColor = Color(0xFFFFFFFF)
    val SuccessColor = Color(0xFF2E7D5B)
    val DangerColor = Color(0xFFE5484D)
    val WarningColor = Color(0xFFFABA3E)
    val InfoColor = Color(0xFF242476)
    val TextPrimary = Color(0xFF0A0E2F)
    val TextSecondary = Color(0xFF6C6F8F)
    val LightGray = Color(0xFFEAEAF2)
    val MediumGray = Color(0xFF6C6F8F)
    val DarkGray = Color(0xFF0A0E2F)
    val CardBackground = Color(0xFFFFFFFF)
    val DividerColor = Color(0xFFD3D3E4)
    val SidebarColor = Color(0xFF0A0E2F)
    val SidebarAccent = Color(0xFF242476)
    val AccentSoft = Color(0xFFFFF3DC)
}

// ─────────────────────────────────────────────────────────────────────────────
// Marina Brand — full Material3 color schemes (serenity-style structure):
// proper container colors, surface variants and error containers for both
// light and dark, built on the original navy + gold brand identity.
// ─────────────────────────────────────────────────────────────────────────────

/** Light scheme — navy primary with gold secondary on a soft ivory surface. */
val MarinaLightColorScheme = lightColorScheme(
    primary = Color(0xFF242476),
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = Color(0xFFEAEAF2),
    onPrimaryContainer = Color(0xFF0A0E2F),
    secondary = Color(0xFFFABA3E),
    onSecondary = Color(0xFF0A0E2F),
    secondaryContainer = Color(0xFFFFF3DC),
    onSecondaryContainer = Color(0xFF3D2E00),
    tertiary = Color(0xFF2E7D5B),
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = Color(0xFFDFF2E9),
    onTertiaryContainer = Color(0xFF0E3324),
    surface = Color(0xFFFFFFFF),
    onSurface = Color(0xFF0A0E2F),
    surfaceVariant = Color(0xFFEAEAF2),
    onSurfaceVariant = Color(0xFF6C6F8F),
    surfaceTint = Color(0xFF242476),
    inverseSurface = Color(0xFF2A2A3C),
    inverseOnSurface = Color(0xFFF4F4F8),
    inversePrimary = Color(0xFFBFC2FF),
    outline = Color(0xFFD3D3E4),
    outlineVariant = Color(0xFFE6E6F0),
    background = Color(0xFFF8F8FC),
    onBackground = Color(0xFF0A0E2F),
    error = Color(0xFFE5484D),
    onError = Color(0xFFFFFFFF),
    errorContainer = Color(0xFFFCE8E8),
    onErrorContainer = Color(0xFF5C1A1D),
    scrim = Color(0xFF000000)
)

/** Dark scheme — inverted navy surfaces, softened gold accents. */
val MarinaDarkColorScheme = darkColorScheme(
    primary = Color(0xFFBFC2FF),
    onPrimary = Color(0xFF101044),
    primaryContainer = Color(0xFF3D3D9E),
    onPrimaryContainer = Color(0xFFEAEAF2),
    secondary = Color(0xFFFABA3E),
    onSecondary = Color(0xFF241A00),
    secondaryContainer = Color(0xFF5A4508),
    onSecondaryContainer = Color(0xFFFFF3DC),
    tertiary = Color(0xFF8FD4AE),
    onTertiary = Color(0xFF0E3324),
    tertiaryContainer = Color(0xFF1F4A36),
    onTertiaryContainer = Color(0xFFDFF2E9),
    surface = Color(0xFF11142B),
    onSurface = Color(0xFFE8E8F0),
    surfaceVariant = Color(0xFF2A2A3C),
    onSurfaceVariant = Color(0xFFB9BBD0),
    surfaceTint = Color(0xFFBFC2FF),
    inverseSurface = Color(0xFFF4F4F8),
    inverseOnSurface = Color(0xFF2A2A3C),
    inversePrimary = Color(0xFF242476),
    outline = Color(0xFF4A4A5E),
    outlineVariant = Color(0xFF333348),
    background = Color(0xFF0A0E2F),
    onBackground = Color(0xFFE8E8F0),
    error = Color(0xFFF25555),
    onError = Color(0xFF2A0D0E),
    errorContainer = Color(0xFF5C1A1D),
    onErrorContainer = Color(0xFFFCE8E8),
    scrim = Color(0xFF000000)
)

// ─────────────────────────────────────────────────────────────────────────────
// Typography — serenity-inspired: display weights breathe (thin/normal),
// body text keeps a comfortable 24sp line height for Arabic readability.
// ─────────────────────────────────────────────────────────────────────────────

val AppTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Thin,
        fontSize = 57.sp,
        lineHeight = 64.sp,
        letterSpacing = (-0.25).sp,
        color = AppColors.TextPrimary
    ),
    headlineLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W700,
        fontSize = 32.sp,
        lineHeight = 40.sp,
        color = AppColors.TextPrimary
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W700,
        fontSize = 28.sp,
        lineHeight = 36.sp,
        color = AppColors.TextPrimary
    ),
    headlineSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W700,
        fontSize = 24.sp,
        lineHeight = 32.sp,
        color = AppColors.TextPrimary
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 20.sp,
        lineHeight = 28.sp,
        color = AppColors.TextPrimary
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        color = AppColors.TextPrimary
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        color = AppColors.TextPrimary
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.5.sp,
        color = AppColors.TextPrimary
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        color = AppColors.TextPrimary
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        color = AppColors.TextSecondary
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        color = AppColors.TextPrimary
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        color = AppColors.TextSecondary
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.5.sp,
        color = AppColors.TextSecondary
    )
)

// ─────────────────────────────────────────────────────────────────────────────
// Shapes — serenity's soft, calming corner radii (12 / 16 / 24 dp).
// ─────────────────────────────────────────────────────────────────────────────

val MarinaShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(32.dp)
)

val AppShapes = RoundedCornerShape(12.dp)

// ─────────────────────────────────────────────────────────────────────────────
// Theme entry point
// ─────────────────────────────────────────────────────────────────────────────

/**
 * ✅ (2026-09-24) تفضيل الوضع الداكن — نظير themeSettingsProvider في Dart
 * (settings_screen.dart): مفتاح 'المظهر الداكن' في حوار إعدادات التطبيق
 * يتحكم بثيم كل الشاشات عبر [MarinaTheme] الافتراضي.
 */
object ThemePrefs {
    private const val PREFS_NAME = "marina_theme_prefs"
    private const val KEY_DARK_MODE = "dark_mode"

    private val _isDark = MutableStateFlow(false)

    /** الوضع الداكن الحالي (يُحمّل من التفضيلات عند أول استخدام). */
    val isDark: StateFlow<Boolean> = _isDark.asStateFlow()

    /** قراءة القيمة المحفوظة وتحديث الحالة — تُستدعى عند أول تركيب. */
    fun load(context: Context): Boolean {
        val value = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_DARK_MODE, false)
        _isDark.value = value
        return value
    }

    /** حفظ القيمة وبثّها فوراً لكل الشاشات. */
    fun setDark(context: Context, dark: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_DARK_MODE, dark).apply()
        _isDark.value = dark
    }
}

/** مصدر الوضع: تفضيل المستخدم إن وُجد وإلا إعداد النظام (نفس Dart). */
@Composable
private fun rememberThemeSetting(): Boolean {
    val context = LocalContext.current
    var dark by remember { mutableStateOf(ThemePrefs.isDark.value) }
    LaunchedEffect(context) {
        dark = ThemePrefs.load(context)
        ThemePrefs.isDark.collect { dark = it }
    }
    return dark
}

@Composable
fun MarinaTheme(
    darkTheme: Boolean = rememberThemeSetting(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) MarinaDarkColorScheme else MarinaLightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        shapes = MarinaShapes,
        content = content
    )
}
