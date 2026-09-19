package com.marina.marina.components

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.Color
import com.marina.marina.ui.theme.AppColors
import com.marina.marina.ui.theme.AppTypography
import com.marina.marina.navigation.Screen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminSidebar(
    currentRoute: String?,
    onRouteSelected: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        color = Color(0xFF0A0E2F),
        modifier = modifier
    ) {
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .width(250.dp)
                .padding(vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                text = "فندق مارينا",
                style = AppTypography.headlineSmall,
                color = Color(0xFFFFF3DC),
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp)
            )
            HorizontalDivider(color = Color(0xFF3D3D9E))

            SidebarItem(
                label = "لوحة التحكم",
                route = Screen.Dashboard.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "الغرف",
                route = Screen.Rooms.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "الحجز",
                route = Screen.Bookings.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "المدفوعات",
                route = Screen.Payments.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "الديون",
                route = Screen.Debts.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "ال موظفون",
                route = Screen.Employees.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "المصروفات",
                route = Screen.Expenses.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "القائمة السوداء",
                route = Screen.Blacklist.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "الملاحظات",
                route = Screen.Notes.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
            SidebarItem(
                label = "الإعدادات",
                route = Screen.Settings.route,
                currentRoute = currentRoute,
                onRouteSelected = onRouteSelected
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SidebarItem(
    label: String,
    route: String,
    currentRoute: String?,
    onRouteSelected: (String) -> Unit
) {
    val selected = currentRoute == route
    NavigationDrawerItem(
        label = {
            Text(
                text = label,
                style = AppTypography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        },
        selected = selected,
        onClick = { onRouteSelected(route) },
        modifier = Modifier.padding(horizontal = 8.dp),
        colors = NavigationDrawerItemDefaults.colors(
            selectedContainerColor = Color(0xFF3D3D9E),
            selectedTextColor = Color(0xFFFFF3DC),
            unselectedTextColor = Color(0xFFE8E8F0)
        )
    )
}