package com.marina.marina.presentation.settings.backup

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.marina.marina.ui.theme.AppColors

object BackupUi {
    /** ألوان متوافقة مع السمة الحالية، مع الإبقاء على ثوابت المسافات القديمة. */
    val backupColor: Color
        @Composable get() = AppColors.SuccessColor
    val grey100: Color
        @Composable get() = AppColors.LightGray
    val grey400: Color
        @Composable get() = AppColors.TextSecondary
    val grey500: Color
        @Composable get() = AppColors.TextSecondary
    val grey600: Color
        @Composable get() = AppColors.TextSecondary
    val grey700: Color
        @Composable get() = AppColors.TextPrimary
    const val spacingSM = 8
    const val spacingMD = 16
    const val spacingLG = 24
    const val radiusMD = 8
    const val radiusLG = 12
    const val iconSizeMD = 24
}
