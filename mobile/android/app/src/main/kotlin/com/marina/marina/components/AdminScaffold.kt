package com.marina.marina.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.marina.marina.domain.model.AuthUser
import kotlinx.coroutines.launch

/**
 * How screens open the side navigation on phones. Provided by [AdminScaffold]:
 *  - on phones (< 768dp) it opens the modal drawer,
 *  - on wide screens it is `null` and [SidebarMenuButton] renders nothing
 *    (the permanent sidebar is already visible).
 */
val LocalSidebarMenuOpener = compositionLocalOf<(() -> Unit)?> { null }

/**
 * Hamburger button for a screen's top bar. Renders nothing when no drawer
 * is available (wide screens / screens outside [AdminScaffold]), so it is
 * always safe to drop into any `TopAppBar(navigationIcon = ...)`.
 */
@Composable
fun SidebarMenuButton() {
    val opener = LocalSidebarMenuOpener.current ?: return
    IconButton(onClick = opener) {
        Icon(
            imageVector = Icons.Filled.Menu,
            contentDescription = "القائمة",
            // Compact size (user request — smaller, not bigger).
            modifier = Modifier.size(22.dp)
        )
    }
}

/**
 * Responsive navigation shell — the port of the Flutter AdminLayout
 * (mobile/lib/components/admin_layout.dart):
 *
 *  - width >= 768dp: the [AdminSidebar] stays permanently beside the content
 *    (on the right in RTL), like the PHP admin panel.
 *  - width <  768dp: the same sidebar slides in as a modal drawer, opened
 *    through [SidebarMenuButton] in each screen's top bar or by swiping
 *    from the start edge.
 *
 * Selecting a destination or logging out closes the drawer first (the
 * Flutter sidebar did exactly that before navigating).
 */
@Composable
fun AdminScaffold(
    currentRoute: String?,
    currentUser: AuthUser?,
    onRouteSelected: (String) -> Unit,
    onLogout: () -> Unit,
    content: @Composable () -> Unit
) {
    BoxWithConstraints {
        if (maxWidth >= 768.dp) {
            // Tablet / landscape / desktop: permanent sidebar.
            Row(modifier = Modifier.fillMaxSize()) {
                AdminSidebar(
                    currentRoute = currentRoute,
                    onRouteSelected = onRouteSelected,
                    onLogout = onLogout,
                    currentUser = currentUser
                )
                Box(modifier = Modifier.weight(1f)) { content() }
            }
        } else {
            // Phone: modal drawer.
            val drawerState = rememberDrawerState(DrawerValue.Closed)
            val scope = rememberCoroutineScope()

            val openDrawer: () -> Unit = { scope.launch { drawerState.open() } }
            val selectAndClose: (String) -> Unit = { route ->
                scope.launch { drawerState.close() }
                onRouteSelected(route)
            }
            val logoutAndClose: () -> Unit = {
                scope.launch { drawerState.close() }
                onLogout()
            }

            CompositionLocalProvider(LocalSidebarMenuOpener provides openDrawer) {
                ModalNavigationDrawer(
                    drawerState = drawerState,
                    drawerContent = {
                        ModalDrawerSheet(
                            drawerContainerColor = Color(0xFF0F172A),
                            modifier = Modifier.width(280.dp)
                        ) {
                            AdminSidebar(
                                currentRoute = currentRoute,
                                onRouteSelected = selectAndClose,
                                onLogout = logoutAndClose,
                                currentUser = currentUser
                            )
                        }
                    }
                ) {
                    content()
                }
            }
        }
    }
}
