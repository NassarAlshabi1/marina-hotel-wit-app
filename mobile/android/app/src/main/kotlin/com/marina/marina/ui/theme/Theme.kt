package com.marina.marina.ui.theme

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
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
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.a.a.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// ─────────────────────────────────────────────────────────────────────────────
// Legacy palette — kept for backward compatibility with the ported screens.
// New code should prefer MaterialTheme.colorScheme below.
// ─────────────────────────────────────────────────────────────────────────────

object MarinaPalette {
    // Reference: feat/cloudflare-sync-execution@78c17381 mobile/lib/utils/theme.dart.
    // Legacy names retained to avoid changing screen contracts; values follow MarketKy.
    val Ocean = Color(0xFF242476)
    val OceanDeep = Color(0xFF0A0E2F)
    val OceanNight = Color(0xFF0F172A)
    val OceanMid = Color(0xFF3D3D9E)
    val OceanSoft = Color(0xFFEAEAF2)
    val Brass = Color(0xFFFABA3E)
    val BrassSoft = Color(0xFFFFF3DC)
    val Canvas = Color(0xFFF8F8FC)
    val Paper = Color(0xFFFFFFFF)
    val Ink = Color(0xFF0A0E2F)
    val Muted = Color(0xFF6C6F8F)
    val Neutral = Color(0xFF8495A5)
    val NeutralSoft = Color(0xFFEAEAF2)
    val Line = Color(0xFFD3D3E4)
    val LineSoft = Color(0xFFEAEAF2)
    val Success = Color(0xFF2E7D5B)
    val SuccessDeep = Color(0xFF1D5844)
    val SuccessSoft = Color(0xFFE1F1E8)
    val Warning = Color(0xFF875918)
    val WarningDeep = Color(0xFF704910)
    val WarningSoft = Color(0xFFFAEED8)
    val Danger = Color(0xFFAF3E49)
    val DangerDeep = Color(0xFF852C36)
    val DangerSoft = Color(0xFFFBE7E9)
    val Info = Color(0xFF242476)
    val InfoSoft = Color(0xFFEAEAF2)
    val Violet = Color(0xFF71617E)
    val VioletSoft = Color(0xFFEEEAF1)
    val Slate = Color(0xFF52686B)
    val Walnut = Color(0xFF705B43)
    val WhatsApp = Color(0xFF25D366)
    val WhatsAppDeep = Color(0xFF0E6B3B)
}

/** Dynamic compatibility aliases so legacy screens follow light and dark themes. */
object AppColors {
    /** Deep brand accents reserved for filled controls with white labels. */
    val PrimaryActionColor: Color = MarinaPalette.Ocean
    val SuccessActionColor: Color = MarinaPalette.Success
    val WarningActionColor: Color = MarinaPalette.Warning
    val DangerActionColor: Color = MarinaPalette.Danger

    val PrimaryColor: Color
        @Composable get() = MaterialTheme.colorScheme.primary
    val PrimaryDark: Color
        @Composable get() = MaterialTheme.colorScheme.primaryContainer
    val PrimaryLight: Color
        @Composable get() = MaterialTheme.colorScheme.primaryContainer
    val Secondary: Color
        @Composable get() = MaterialTheme.colorScheme.onSurface
    val AccentColor: Color = MarinaPalette.Brass
    val BackgroundColor: Color
        @Composable get() = MaterialTheme.colorScheme.background
    val SurfaceColor: Color
        @Composable get() = MaterialTheme.colorScheme.surface
    val SuccessColor: Color
        @Composable get() = MaterialTheme.colorScheme.tertiary
    val SuccessContainerColor: Color
        @Composable get() = MaterialTheme.colorScheme.tertiaryContainer
    val DangerContainerColor: Color
        @Composable get() = MaterialTheme.colorScheme.errorContainer
    val WarningContainerColor: Color
        @Composable get() = MaterialTheme.colorScheme.secondaryContainer
    val InfoContainerColor: Color
        @Composable get() = MaterialTheme.colorScheme.primaryContainer
    val DangerColor: Color
        @Composable get() = MaterialTheme.colorScheme.error
    val WarningColor: Color
        @Composable get() = if (MaterialTheme.colorScheme.background.luminance() > 0.5f) {
            MarinaPalette.Warning // Gold remains decorative; small warning text needs contrast.
        } else MaterialTheme.colorScheme.secondary
    val InfoColor: Color
        @Composable get() = MaterialTheme.colorScheme.primary
    val TextPrimary: Color
        @Composable get() = MaterialTheme.colorScheme.onSurface
    val TextSecondary: Color
        @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
    val LightGray: Color
        @Composable get() = MaterialTheme.colorScheme.surfaceVariant
    val MediumGray: Color
        @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
    val DarkGray: Color
        @Composable get() = MaterialTheme.colorScheme.onSurface
    val CardBackground: Color
        @Composable get() = MaterialTheme.colorScheme.surface
    val DividerColor: Color
        @Composable get() = MaterialTheme.colorScheme.outlineVariant
    val SidebarColor: Color
        @Composable get() = MaterialTheme.colorScheme.primaryContainer
    val SidebarAccent: Color
        @Composable get() = MaterialTheme.colorScheme.primary
    val AccentSoft: Color
        @Composable get() = MaterialTheme.colorScheme.secondaryContainer
}

// ─────────────────────────────────────────────────────────────────────────────
// MarketKy reference — indigo, soft lavender borders and navy surfaces.
// ─────────────────────────────────────────────────────────────────────────────

val MarinaLightColorScheme = lightColorScheme(
    primary = MarinaPalette.Ocean,
    onPrimary = Color(0xFFFFFFFF),
    primaryContainer = MarinaPalette.OceanSoft,
    onPrimaryContainer = MarinaPalette.OceanDeep,
    secondary = MarinaPalette.Brass,
    onSecondary = MarinaPalette.Ink,
    secondaryContainer = MarinaPalette.BrassSoft,
    onSecondaryContainer = Color(0xFF45351A),
    tertiary = MarinaPalette.Success,
    onTertiary = Color(0xFFFFFFFF),
    tertiaryContainer = MarinaPalette.SuccessSoft,
    onTertiaryContainer = Color(0xFF183F31),
    surface = MarinaPalette.Paper,
    onSurface = MarinaPalette.Ink,
    surfaceVariant = MarinaPalette.LineSoft,
    onSurfaceVariant = MarinaPalette.Muted,
    surfaceTint = MarinaPalette.Ocean,
    inverseSurface = MarinaPalette.Ink,
    inverseOnSurface = MarinaPalette.Canvas,
    inversePrimary = Color(0xFFBDBDFF),
    outline = Color(0xFF787890),
    outlineVariant = MarinaPalette.Line,
    background = MarinaPalette.Canvas,
    onBackground = MarinaPalette.Ink,
    error = MarinaPalette.Danger,
    onError = Color(0xFFFFFFFF),
    errorContainer = MarinaPalette.DangerSoft,
    onErrorContainer = Color(0xFF5C2522),
    scrim = Color(0xFF000000)
)

val MarinaDarkColorScheme = darkColorScheme(
    primary = Color(0xFFBDBDFF),
    onPrimary = MarinaPalette.OceanDeep,
    primaryContainer = Color(0xFF29295C),
    onPrimaryContainer = Color(0xFFEAEAF2),
    secondary = MarinaPalette.Brass,
    onSecondary = Color(0xFF32250D),
    secondaryContainer = Color(0xFF5A4727),
    onSecondaryContainer = Color(0xFFFFF3DC),
    tertiary = Color(0xFF9BD0B1),
    onTertiary = Color(0xFF15392D),
    tertiaryContainer = Color(0xFF204B3B),
    onTertiaryContainer = Color(0xFFE1F1E8),
    surface = Color(0xFF11142B),
    onSurface = Color(0xFFE8E8F0),
    surfaceVariant = Color(0xFF20233C),
    onSurfaceVariant = Color(0xFFAAAAD0),
    surfaceTint = Color(0xFFBDBDFF),
    inverseSurface = Color(0xFFE8E8F0),
    inverseOnSurface = Color(0xFF20233C),
    inversePrimary = MarinaPalette.Ocean,
    outline = Color(0xFF8A8AA8),
    outlineVariant = Color(0xFF2A2D4A),
    background = Color(0xFF0A0E2F),
    onBackground = Color(0xFFE8E8F0),
    error = Color(0xFFFFB4AA),
    onError = Color(0xFF5C2522),
    errorContainer = Color(0xFF7A3935),
    onErrorContainer = Color(0xFFFFDAD4),
    scrim = Color(0xFF000000)
)

// ─────────────────────────────────────────────────────────────────────────────
// Typography — bundled Tajawal for every Material role; Arabic tracking stays natural,
// body text keeps a comfortable 24sp line height for Arabic readability.
// ─────────────────────────────────────────────────────────────────────────────

// Regular/Bold are byte-identical to reference mobile/assets/fonts. Flutter's
// pubspec declares these as assets, not a fonts family; runtime rendering there
// cannot be inferred from the fontFamily string alone. Android registers them.
/** Bundled Tajawal: regular, medium, bold; version chips intentionally use monospace. */
val TajawalFamily = FontFamily(
    Font(R.font.tajawal_regular, FontWeight.Normal),
    Font(R.font.tajawal_medium, FontWeight.Medium),
    Font(R.font.tajawal_bold, FontWeight.Bold)
)

val AppTypography = Typography(
    displayLarge = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 57.sp,
        lineHeight = 64.sp,
        letterSpacing = (-0.25).sp,
        color = Color.Unspecified
    ),
    displayMedium = TextStyle(fontFamily = TajawalFamily, fontSize = 45.sp, lineHeight = 52.sp),
    displaySmall = TextStyle(fontFamily = TajawalFamily, fontSize = 36.sp, lineHeight = 44.sp),
    headlineLarge = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.W700,
        fontSize = 32.sp,
        lineHeight = 40.sp,
        color = Color.Unspecified
    ),
    headlineMedium = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.W700,
        fontSize = 28.sp,
        lineHeight = 36.sp,
        color = Color.Unspecified
    ),
    headlineSmall = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.W700,
        fontSize = 24.sp,
        lineHeight = 32.sp,
        color = Color.Unspecified
    ),
    titleLarge = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.W700,
        fontSize = 18.sp,
        lineHeight = 26.sp,
        color = Color.Unspecified
    ),
    titleMedium = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.W600,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        color = Color.Unspecified
    ),
    titleSmall = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.W600,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        color = Color.Unspecified
    ),
    bodyLarge = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 24.sp,
        letterSpacing = 0.sp,
        color = Color.Unspecified
    ),
    bodyMedium = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        color = Color.Unspecified
    ),
    bodySmall = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        color = Color.Unspecified
    ),
    labelLarge = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.W600,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        color = Color.Unspecified
    ),
    labelMedium = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
        color = Color.Unspecified
    ),
    labelSmall = TextStyle(
        fontFamily = TajawalFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 11.sp,
        lineHeight = 16.sp,
        letterSpacing = 0.sp,
        color = Color.Unspecified
    )
)

// ─────────────────────────────────────────────────────────────────────────────
// Reference radii: controls 8dp, cards 12dp, dashboard panels 16dp.
// ─────────────────────────────────────────────────────────────────────────────

val MarinaShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(24.dp)
)

val AppShapes = MarinaShapes.medium

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
    fun load(context: Context, systemDark: Boolean): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val value = if (prefs.contains(KEY_DARK_MODE)) {
            prefs.getBoolean(KEY_DARK_MODE, systemDark)
        } else {
            systemDark
        }
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

/** Resolve the hosting Activity through Compose's possible context wrappers. */
private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** مصدر الوضع: تفضيل المستخدم إن وُجد وإلا إعداد النظام (نفس Dart). */
@Composable
private fun rememberThemeSetting(): Boolean {
    val context = LocalContext.current
    val systemDark = isSystemInDarkTheme()
    var dark by remember { mutableStateOf(systemDark) }
    LaunchedEffect(context, systemDark) {
        dark = ThemePrefs.load(context, systemDark)
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
    val view = LocalView.current

    SideEffect {
        val window = view.context.findActivity()?.window
        if (window != null) {
            val systemBarColor = colorScheme.background.toArgb()
            window.statusBarColor = systemBarColor
            window.navigationBarColor = systemBarColor
            val insetsController = WindowCompat.getInsetsController(window, view)
            insetsController.isAppearanceLightStatusBars = !darkTheme
            insetsController.isAppearanceLightNavigationBars = !darkTheme
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        shapes = MarinaShapes,
        content = content
    )
}
