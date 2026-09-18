package com.marina.marina.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

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

val AppTypography = Typography(
    headlineLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W700,
        fontSize = 32.sp,
        color = AppColors.TextPrimary
    ),
    headlineMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W700,
        fontSize = 28.sp,
        color = AppColors.TextPrimary
    ),
    headlineSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W700,
        fontSize = 24.sp,
        color = AppColors.TextPrimary
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 20.sp,
        color = AppColors.TextPrimary
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 16.sp,
        color = AppColors.TextPrimary
    ),
    titleSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 14.sp,
        color = AppColors.TextPrimary
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        color = AppColors.TextPrimary
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        color = AppColors.TextPrimary
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        color = AppColors.TextSecondary
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.W600,
        fontSize = 14.sp,
        color = AppColors.TextPrimary
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        color = AppColors.TextSecondary
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Normal,
        fontSize = 11.sp,
        color = AppColors.TextSecondary
    )
)

val AppShapes = RoundedCornerShape(8.dp)

@Composable
fun MarinaTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    val colors = if (darkTheme) {
        darkColorScheme(
            primary = AppColors.PrimaryDark,
            secondary = AppColors.AccentColor,
            background = Color(0xFF0A0E2F),
            surface = Color(0xFF11142B),
            error = Color(0xFFF25555),
            onPrimary = Color.White,
            onSecondary = AppColors.Secondary,
            onBackground = Color(0xFFE8E8F0),
            onSurface = Color(0xFFE8E8F0)
        )
    } else {
        lightColorScheme(
            primary = AppColors.PrimaryColor,
            secondary = AppColors.AccentColor,
            background = AppColors.BackgroundColor,
            surface = AppColors.SurfaceColor,
            error = AppColors.DangerColor,
            onPrimary = Color.White,
            onSecondary = AppColors.Secondary,
            onBackground = AppColors.TextPrimary,
            onSurface = AppColors.TextPrimary
        )
    }

    MaterialTheme(
        colorScheme = colors,
        typography = AppTypography,
        shapes = MaterialTheme.shapes.copy(
            medium = RoundedCornerShape(12.dp)
        ),
        content = content
    )
}