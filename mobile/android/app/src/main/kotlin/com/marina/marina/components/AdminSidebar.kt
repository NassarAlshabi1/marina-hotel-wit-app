package com.marina.marina.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AccountBalanceWallet
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.AttachMoney
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bed
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Gavel
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Hotel
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Note
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ReceiptLong
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SmartToy
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.navigation.Screen
import com.marina.marina.ui.theme.AppTypography

/** One navigation entry in the side navigation. */
data class SidebarDestination(
    val label: String,
    val route: String,
    val icon: ImageVector
)

/**
 * The sidebar's navigation entries — one per top-level screen, in the
 * Flutter/PHP order. Exposed for unit tests (uniqueness/completeness).
 */
val SidebarDestinations = listOf(
    SidebarDestination("لوحة التحكم", Screen.Dashboard.route, Icons.Filled.Dashboard),
    SidebarDestination("إدارة الغرف", Screen.Rooms.route, Icons.Filled.Bed),
    SidebarDestination("إدارة الحجوزات", Screen.Bookings.route, Icons.Filled.Assignment),
    SidebarDestination("إدارة المدفوعات", Screen.Payments.route, Icons.Filled.AttachMoney),
    SidebarDestination("الديون", Screen.Debts.route, Icons.Filled.AccountBalance),
    SidebarDestination("الموظفون", Screen.Employees.route, Icons.Filled.Groups),
    SidebarDestination("إدارة المصروفات", Screen.Expenses.route, Icons.Filled.ReceiptLong),
    SidebarDestination("المخزون", Screen.Inventory.route, Icons.Filled.Inventory2),
    SidebarDestination("الصندوق والمالية", Screen.Finance.route, Icons.Filled.AccountBalanceWallet),
    SidebarDestination("التقارير", Screen.Reports.route, Icons.Filled.BarChart),
    SidebarDestination("الملاحظات والتنبيهات", Screen.Notes.route, Icons.Filled.Note),
    SidebarDestination("القائمة السوداء", Screen.Blacklist.route, Icons.Filled.Gavel),
    SidebarDestination("سجل المعلومية", Screen.Information.route, Icons.Filled.Badge),
    SidebarDestination("المساعد الذكي", Screen.AIChat.route, Icons.Filled.SmartToy),
    SidebarDestination("الإعدادات", Screen.Settings.route, Icons.Filled.Settings)
)

/**
 * The app's side navigation — a 1:1 port of the Flutter AdminSidebar
 * (mobile/lib/components/admin_sidebar.dart, itself mirroring the PHP admin):
 *
 *  - dark navy rail (0xFF0F172A) with a branded header (0xFF16213C),
 *  - a logged-in user card (name + role),
 *  - one entry per top-level screen,
 *  - logout pinned at the bottom.
 *
 * It is rendered permanently beside the content on wide screens (>= 768dp)
 * and inside a modal drawer on phones — see [AdminScaffold].
 */
@Composable
fun AdminSidebar(
    currentRoute: String?,
    onRouteSelected: (String) -> Unit,
    onLogout: () -> Unit,
    currentUser: AuthUser?,
    modifier: Modifier = Modifier
) {
    Surface(color = SidebarColors.Background, modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxHeight()
                .width(280.dp)
                .statusBarsPadding()
        ) {
            SidebarHeader(currentUser)

            Column(
                modifier = Modifier
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                SidebarDestinations.forEach { destination ->
                    SidebarEntry(
                        label = destination.label,
                        route = destination.route,
                        icon = destination.icon,
                        currentRoute = currentRoute,
                        onRouteSelected = onRouteSelected
                    )
                }
            }

            // Logout pinned at the bottom (Flutter: Padding + logout item).
            HorizontalDivider(color = SidebarColors.Divider, modifier = Modifier.padding(horizontal = 16.dp))
            SidebarEntry(
                label = "تسجيل الخروج",
                route = "",
                icon = Icons.Filled.Logout,
                currentRoute = currentRoute,
                onRouteSelected = { onLogout() },
                isLogout = true
            )
        }
    }
}

/** Branded header + logged-in user card, identical layout to the Flutter sidebar. */
@Composable
private fun SidebarHeader(currentUser: AuthUser?) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(SidebarColors.HeaderBackground)
            .padding(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Surface(
                color = SidebarColors.CardOverlay,
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.size(48.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Hotel,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.padding(10.dp)
                )
            }
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = "فندق مارينا",
                style = AppTypography.titleLarge,
                color = Color.White,
                fontWeight = FontWeight.Bold
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .background(SidebarColors.CardOverlay, RoundedCornerShape(12.dp))
                .padding(12.dp)
        ) {
            Surface(
                color = Color(0x33FFFFFF),
                shape = RoundedCornerShape(50),
                modifier = Modifier.size(36.dp)
            ) {
                Icon(
                    imageVector = Icons.Filled.Person,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.padding(7.dp)
                )
            }
            Spacer(modifier = Modifier.width(10.dp))
            Column {
                Text(
                    text = currentUser?.name?.ifEmpty { "مستخدم" } ?: "مستخدم",
                    style = AppTypography.titleSmall,
                    color = Color.White,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Text(
                    text = if (currentUser?.isAdmin == true) "مدير النظام" else "موظف",
                    fontSize = 12.sp,
                    color = SidebarColors.Inactive
                )
            }
        }
    }
    HorizontalDivider(color = SidebarColors.Divider)
}

@Composable
private fun SidebarEntry(
    label: String,
    route: String,
    icon: ImageVector,
    currentRoute: String?,
    onRouteSelected: (String) -> Unit,
    isLogout: Boolean = false
) {
    val selected = !isLogout && currentRoute == route
    NavigationDrawerItem(
        label = {
            Text(
                text = label,
                style = AppTypography.titleSmall,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        },
        icon = { Icon(icon, contentDescription = null) },
        selected = selected,
        onClick = { onRouteSelected(route) },
        modifier = Modifier.padding(horizontal = 8.dp),
        colors = NavigationDrawerItemDefaults.colors(
            selectedContainerColor = SidebarColors.SelectedBackground,
            unselectedContainerColor = Color.Transparent,
            selectedIconColor = Color.White,
            unselectedIconColor = SidebarColors.Inactive,
            selectedTextColor = Color.White,
            unselectedTextColor = SidebarColors.Inactive
        )
    )
}

/** Sidebar palette ported from the Flutter AdminSidebar constants. */
private object SidebarColors {
    val Background = Color(0xFF0F172A)
    val HeaderBackground = Color(0xFF16213C)
    val CardOverlay = Color(0x14FFFFFF)   // white 8%
    val Divider = Color(0x1FFFFFFF)       // white 12%
    val Inactive = Color(0xB8FFFFFF)      // white 72%
    val SelectedBackground = Color(0x1FFFFFFF) // white 12%
}
