package com.marina.marina.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarColors
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.TopAppBarScrollBehavior
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.marina.marina.ui.theme.AppColors

/**
 * Consistent Marina app bar: Material colors stay theme-aware and a fine
 * outline divider gives every screen header the same crisp lower frame.
 */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun MarinaTopAppBar(
    title: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    navigationIcon: @Composable () -> Unit = {},
    actions: @Composable RowScope.() -> Unit = {},
    colors: TopAppBarColors = TopAppBarDefaults.topAppBarColors(),
    scrollBehavior: TopAppBarScrollBehavior? = null
) {
    val dividerColor = MaterialTheme.colorScheme.outlineVariant
    TopAppBar(
        title = title,
        modifier = modifier.drawWithContent {
            drawContent()
            val lineWidth = 1.dp.toPx()
            val y = size.height - lineWidth / 2f
            drawLine(
                color = dividerColor,
                start = Offset(0f, y),
                end = Offset(size.width, y),
                strokeWidth = lineWidth
            )
        },
        navigationIcon = navigationIcon,
        actions = actions,
        colors = colors,
        scrollBehavior = scrollBehavior
    )
}

/** Shared framed control for navigation and app-bar actions. */
@Composable
fun MarinaToolbarActionButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    containerColor: Color = AppColors.PrimaryActionColor,
    contentColor: Color = Color.White,
    content: @Composable () -> Unit
) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(13.dp)
    val actualContainer = if (enabled) containerColor else scheme.surfaceVariant
    val actualContent = if (enabled) contentColor else scheme.onSurface.copy(alpha = 0.38f)
    val borderColor = if (enabled) contentColor.copy(alpha = 0.35f) else scheme.outlineVariant
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .size(44.dp)
            .clip(shape)
            .background(actualContainer)
            .border(BorderStroke(1.dp, borderColor), shape)
    ) {
        CompositionLocalProvider(LocalContentColor provides actualContent) {
            content()
        }
    }
}

/** Framed, RTL-aware icon control used by back and navigation buttons. */
@Composable
fun MarinaToolbarIconButton(
    imageVector: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    val scheme = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(13.dp)
    val iconColor = if (enabled) scheme.onPrimaryContainer else scheme.onSurface.copy(alpha = 0.38f)
    val containerColor = if (enabled) scheme.primaryContainer else scheme.surfaceVariant
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .size(44.dp)
            .clip(shape)
            .background(containerColor)
            .border(BorderStroke(1.dp, scheme.outlineVariant), shape)
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = contentDescription,
            tint = iconColor,
            modifier = Modifier.size(22.dp)
        )
    }
}

/** Standard framed back arrow; AutoMirrored follows the app's RTL direction. */
@Composable
fun MarinaBackButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    MarinaToolbarIconButton(
        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
        contentDescription = "رجوع",
        onClick = onClick,
        modifier = modifier,
        enabled = enabled
    )
}
