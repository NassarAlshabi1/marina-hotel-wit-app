package com.marina.marina.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.size
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
import com.marina.marina.ui.theme.ReferenceLayout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp

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
    colors: TopAppBarColors = TopAppBarDefaults.topAppBarColors(
        containerColor = MaterialTheme.colorScheme.surface,
        scrolledContainerColor = MaterialTheme.colorScheme.primaryContainer,
        titleContentColor = MaterialTheme.colorScheme.onSurface,
        navigationIconContentColor = MaterialTheme.colorScheme.primary,
        actionIconContentColor = MaterialTheme.colorScheme.primary
    ),
    scrollBehavior: TopAppBarScrollBehavior? = null
) {
    val dividerColor = MaterialTheme.colorScheme.outlineVariant
    val wideLayout = LocalConfiguration.current.screenWidthDp.dp >= ReferenceLayout.SidebarBreakpoint
    TopAppBar(
        title = title,
        modifier = modifier.drawWithContent {
            drawContent()
            if (!wideLayout) return@drawWithContent
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

/** Plain AppScaffold-style toolbar action; explicit custom fills remain supported. */
@Composable
fun MarinaToolbarActionButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    containerColor: Color = Color.Transparent,
    contentColor: Color = if (containerColor == Color.Transparent) LocalContentColor.current else Color.White,
    content: @Composable () -> Unit
) {
    val scheme = MaterialTheme.colorScheme
    val shape = MaterialTheme.shapes.small
    val actualContainer = if (enabled) containerColor else Color.Transparent
    val actualContent = if (enabled) contentColor else scheme.onSurface.copy(alpha = 0.38f)
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .size(48.dp)
            .clip(shape)
            .background(actualContainer)
    ) {
        CompositionLocalProvider(LocalContentColor provides actualContent) {
            content()
        }
    }
}

/** Plain, RTL-aware icon control matching Flutter AppScaffold. */
@Composable
fun MarinaToolbarIconButton(
    imageVector: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    val scheme = MaterialTheme.colorScheme
    val iconColor = if (enabled) LocalContentColor.current else scheme.onSurface.copy(alpha = 0.38f)
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier
            .size(48.dp)
    ) {
        Icon(
            imageVector = imageVector,
            contentDescription = contentDescription,
            tint = iconColor,
            modifier = Modifier.size(22.dp)
        )
    }
}

/** AutoMirrored back arrow follows the app's RTL direction. */
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
