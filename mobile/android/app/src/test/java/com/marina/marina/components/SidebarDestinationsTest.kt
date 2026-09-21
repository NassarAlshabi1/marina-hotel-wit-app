package com.marina.marina.components

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import com.marina.marina.navigation.Screen

/**
 * SidebarDestinations contract — the side navigation must keep pointing at
 * real, unique top-level routes, otherwise the drawer would navigate to a
 * dead route and the screen would go blank (a regression class we want CI
 * to catch before any device sees it).
 */
class SidebarDestinationsTest {

    @Test
    fun `every sidebar route is a real Screen route`() {
        val knownRoutes = setOf(
            Screen.Dashboard.route, Screen.Rooms.route, Screen.Bookings.route,
            Screen.Payments.route, Screen.Debts.route, Screen.Employees.route,
            Screen.Expenses.route, Screen.Inventory.route, Screen.Finance.route,
            Screen.Reports.route, Screen.Notes.route, Screen.Blacklist.route,
            Screen.Information.route, Screen.AIChat.route, Screen.Settings.route
        )
        SidebarDestinations.forEach { destination ->
            assertTrue(
                "unknown route: ${destination.route}",
                destination.route in knownRoutes
            )
        }
    }

    @Test
    fun `routes are unique — no double entries`() {
        assertEquals(
            SidebarDestinations.size,
            SidebarDestinations.map { it.route }.toSet().size
        )
    }

    @Test
    fun `labels are unique and non-blank`() {
        SidebarDestinations.forEach { destination ->
            assertTrue("blank label for ${destination.route}", destination.label.isNotBlank())
        }
        assertEquals(
            SidebarDestinations.size,
            SidebarDestinations.map { it.label }.toSet().size
        )
    }

    @Test
    fun `all fifteen top-level modules are reachable from the sidebar`() {
        assertEquals(15, SidebarDestinations.size)
        val routes = SidebarDestinations.map { it.route }.toSet()
        // The complete set of top-level modules (detail/argument routes
        // excluded — they are only reachable from within a module).
        listOf(
            Screen.Dashboard, Screen.Rooms, Screen.Bookings, Screen.Payments,
            Screen.Debts, Screen.Employees, Screen.Expenses, Screen.Inventory,
            Screen.Finance, Screen.Reports, Screen.Notes, Screen.Blacklist,
            Screen.Information, Screen.AIChat, Screen.Settings
        ).forEach { screen ->
            assertTrue("sidebar is missing ${screen.route}", screen.route in routes)
        }
    }
}
