package com.marina.marina.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import com.marina.marina.presentation.login.LoginScreen
import com.marina.marina.presentation.auth.AuthViewModel
import com.marina.marina.presentation.dashboard.DashboardScreen
import com.marina.marina.presentation.rooms.RoomsListScreen
import com.marina.marina.presentation.bookings.BookingsListScreen
import com.marina.marina.presentation.payments.PaymentsMainScreen
import com.marina.marina.presentation.debts.DebtsListScreen
import com.marina.marina.presentation.employees.EmployeesListScreen
import com.marina.marina.presentation.expenses.ExpensesListScreen
import com.marina.marina.presentation.notes.NotesScreen
import com.marina.marina.presentation.settings.SettingsScreen

sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Dashboard : Screen("dashboard")
    object Rooms : Screen("rooms")
    object Bookings : Screen("bookings")
    object Payments : Screen("payments")
    object Debts : Screen("debts")
    object Employees : Screen("employees")
    object Expenses : Screen("expenses")
    object Notes : Screen("notes")
    object Settings : Screen("settings")
    object Reports : Screen("reports")
    object Finance : Screen("finance")
    object Information : Screen("information")
    object Inventory : Screen("inventory")
    object AIChat : Screen("ai_chat")
}

@Composable
fun MarinaNavGraph(
    navController: NavHostController,
    authViewModel: AuthViewModel,
    startDestination: String = Screen.Login.route
) {
    NavHost(
        navController = navController,
        startDestination = startDestination
    ) {
            composable(Screen.Login.route) {
                LoginScreen(
                    viewModel = authViewModel,
                    onLoginSuccess = {
                        navController.navigate(Screen.Dashboard.route) {
                            popUpTo(Screen.Login.route) { inclusive = true }
                        }
                    }
                )
            }
            composable(Screen.Dashboard.route) {
                DashboardScreen(
                    onNavigate = { route -> navController.navigate(route) }
                )
            }
            composable(Screen.Rooms.route) {
                RoomsListScreen()
            }
            composable(Screen.Bookings.route) {
                BookingsListScreen()
            }
            composable(Screen.Payments.route) {
                PaymentsMainScreen()
            }
            composable(Screen.Debts.route) {
                DebtsListScreen()
            }
            composable(Screen.Employees.route) {
                EmployeesListScreen()
            }
            composable(Screen.Expenses.route) {
                ExpensesListScreen()
            }
            composable(Screen.Notes.route) {
                NotesScreen()
            }
            composable(Screen.Settings.route) {
                SettingsScreen()
            }
            composable(Screen.Reports.route) {
                // ReportsScreen()
            }
            composable(Screen.Finance.route) {
                // FinanceScreen()
            }
            composable(Screen.Information.route) {
                // InformationScreen()
            }
            composable(Screen.Inventory.route) {
                // InventoryScreen()
            }
            composable(Screen.AIChat.route) {
                // AIChatScreen()
            }
    }
}