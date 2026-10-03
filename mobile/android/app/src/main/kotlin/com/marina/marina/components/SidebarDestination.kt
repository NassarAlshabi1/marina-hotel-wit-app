package com.marina.marina.components

import androidx.compose.ui.graphics.vector.ImageVector

/** One navigation entry in the side navigation. */
data class SidebarDestination(
    val label: String,
    val route: String,
    val icon: ImageVector
)

