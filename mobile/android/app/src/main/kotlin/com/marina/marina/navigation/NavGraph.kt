package com.marina.marina.navigation

import androidx.compose.runtime.Composable
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.marina.marina.presentation.aichat.AIChatScreen
import com.marina.marina.presentation.auth.AuthViewModel
import com.marina.marina.presentation.bookings.BookingEditScreen
import com.marina.marina.presentation.bookings.BookingsListScreen
import com.marina.marina.presentation.dashboard.DashboardScreen
import com.marina.marina.presentation.debts.DebtsListScreen
import com.marina.marina.presentation.employees.EmployeesListScreen
import com.marina.marina.presentation.expenses.ExpensesListScreen
import com.marina.marina.presentation.finance.FinanceScreen
import com.marina.marina.presentation.information.InformationScreen
import com.marina.marina.presentation.inventory.InventoryScreen
import com.marina.marina.presentation.login.LoginScreen
import com.marina.marina.presentation.notes.NotesScreen
import com.marina.marina.presentation.payments.BookingPaymentScreen
import com.marina.marina.presentation.payments.PaymentsMainScreen
import com.marina.marina.presentation.reports.ReportsScreen
import com.marina.marina.presentation.rooms.RoomsListScreen
import com.marina.marina.presentation.settings.SettingsScreen

sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Dashboard : Screen("dashboard")
    object Rooms : Screen("rooms")
    object Bookings : Screen("bookings")
    object BookingEdit : Screen("booking_edit?bookingId={bookingId}&roomNumber={roomNumber}") {
        const val ARG_BOOKING_ID = "bookingId"
        const val ARG_ROOM_NUMBER = "roomNumber"
        fun createRoute(bookingId: Long = 0L, roomNumber: String = "") =
            "booking_edit?bookingId=$bookingId&roomNumber=$roomNumber"
    }
    object BookingPayment : Screen("booking_payment/{bookingId}") {
        const val ARG_BOOKING_ID = "bookingId"
        fun createRoute(bookingId: Long) = "booking_payment/$bookingId"
    }
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
            BookingsListScreen(
                onBookingClick = { bookingId ->
                    navController.navigate(Screen.BookingPayment.createRoute(bookingId))
                },
                onAddBooking = {
                    navController.navigate(Screen.BookingEdit.createRoute(0L))
                }
            )
        }

        composable(
            route = Screen.BookingEdit.route,
            arguments = listOf(
                navArgument(Screen.BookingEdit.ARG_BOOKING_ID) {
                    type = NavType.LongType
                    defaultValue = 0L
                },
                navArgument(Screen.BookingEdit.ARG_ROOM_NUMBER) {
                    type = NavType.StringType
                    defaultValue = ""
                }
            )
        ) {
            BookingEditScreen(
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.BookingPayment.route,
            arguments = listOf(navArgument(Screen.BookingPayment.ARG_BOOKING_ID) {
                type = NavType.LongType
            })
        ) {
            BookingPaymentScreen(
                onBack = { navController.popBackStack() }
            )
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
            SettingsScreen(
                onLogout = {
                    authViewModel.logout()
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Dashboard.route) { inclusive = true }
                    }
                }
            )
        }

        composable(Screen.Reports.route) {
            ReportsScreen()
        }

        composable(Screen.Finance.route) {
            FinanceScreen(
                onBookingClick = { bookingId ->
                    navController.navigate(Screen.BookingPayment.createRoute(bookingId))
                }
            )
        }

        composable(Screen.Information.route) {
            InformationScreen()
        }

        composable(Screen.Inventory.route) {
            InventoryScreen()
        }

        composable(Screen.AIChat.route) {
            AIChatScreen()
        }
    }
}
