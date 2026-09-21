package com.marina.marina.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.navArgument
import com.marina.marina.components.AdminScaffold
import com.marina.marina.presentation.aichat.AIChatScreen
import com.marina.marina.presentation.blacklist.BlacklistScreen
import com.marina.marina.presentation.debts.CreateDebtFromBookingScreen
import com.marina.marina.presentation.employees.SalaryEntitlementsScreen
import com.marina.marina.presentation.auth.CloudflareLoginScreen
import com.marina.marina.presentation.payments.BookingCheckoutScreen
import com.marina.marina.presentation.payments.PaymentHistoryScreen
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
    object Blacklist : Screen("blacklist")
    object PaymentHistory : Screen("payment_history")
    object SalaryEntitlements : Screen("salary_entitlements")
    object CloudflareLogin : Screen("cloudflare_login")
    object BookingCheckout : Screen("booking_checkout/{bookingId}") {
        const val ARG_BOOKING_ID = "bookingId"
        fun createRoute(bookingId: Long) = "booking_checkout/$bookingId"
    }
    object CreateDebt : Screen("create_debt/{bookingId}") {
        const val ARG_BOOKING_ID = "bookingId"
        fun createRoute(bookingId: Long) = "create_debt/$bookingId"
    }
    object Inventory : Screen("inventory")
    object AIChat : Screen("ai_chat")
}

/**
 * Registers a top-level destination wrapped in [AdminScaffold] so it gets
 * the side navigation (permanent on wide screens, drawer on phones).
 * Selecting another module switches it without piling up the back stack.
 */
private fun NavGraphBuilder.adminScreen(
    navController: NavHostController,
    authViewModel: AuthViewModel,
    route: String,
    content: @Composable () -> Unit
) {
    composable(route) { entry ->
        val authState by authViewModel.authState.collectAsState()
        AdminScaffold(
            currentRoute = entry.destination.route,
            currentUser = authState.currentUser,
            onRouteSelected = { target ->
                navController.navigate(target) {
                    popUpTo(Screen.Dashboard.route) { saveState = true }
                    launchSingleTop = true
                    restoreState = true
                }
            },
            onLogout = {
                authViewModel.logout()
                navController.navigate(Screen.Login.route) {
                    popUpTo(0) { inclusive = true }
                }
            }
        ) {
            content()
        }
    }
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

        adminScreen(navController, authViewModel, Screen.Dashboard.route) {
            DashboardScreen(
                onNavigate = { route -> navController.navigate(route) }
            )
        }

        adminScreen(navController, authViewModel, Screen.Rooms.route) {
            RoomsListScreen()
        }

        adminScreen(navController, authViewModel, Screen.Bookings.route) {
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

        adminScreen(navController, authViewModel, Screen.Payments.route) {
            PaymentsMainScreen()
        }

        adminScreen(navController, authViewModel, Screen.Debts.route) {
            DebtsListScreen()
        }

        adminScreen(navController, authViewModel, Screen.Employees.route) {
            EmployeesListScreen()
        }

        adminScreen(navController, authViewModel, Screen.Expenses.route) {
            ExpensesListScreen()
        }

        adminScreen(navController, authViewModel, Screen.Notes.route) {
            NotesScreen()
        }

        adminScreen(navController, authViewModel, Screen.Settings.route) {
            SettingsScreen(
                onLogout = {
                    authViewModel.logout()
                    navController.navigate(Screen.Login.route) {
                        popUpTo(Screen.Dashboard.route) { inclusive = true }
                    }
                }
            )
        }

        adminScreen(navController, authViewModel, Screen.Reports.route) {
            ReportsScreen()
        }

        adminScreen(navController, authViewModel, Screen.Finance.route) {
            FinanceScreen(
                onBookingClick = { bookingId ->
                    navController.navigate(Screen.BookingPayment.createRoute(bookingId))
                }
            )
        }

        adminScreen(navController, authViewModel, Screen.Information.route) {
            InformationScreen()
        }

        adminScreen(navController, authViewModel, Screen.Inventory.route) {
            InventoryScreen()
        }

        adminScreen(navController, authViewModel, Screen.AIChat.route) {
            AIChatScreen()
        }

        adminScreen(navController, authViewModel, Screen.Blacklist.route) {
            BlacklistScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.PaymentHistory.route) {
            PaymentHistoryScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.SalaryEntitlements.route) {
            SalaryEntitlementsScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.CloudflareLogin.route) {
            CloudflareLoginScreen(
                viewModel = authViewModel,
                onLoginSuccess = {
                    navController.navigate(Screen.Dashboard.route) {
                        popUpTo(Screen.Login.route) { inclusive = true }
                    }
                },
                onBack = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.BookingCheckout.route,
            arguments = listOf(navArgument(Screen.BookingCheckout.ARG_BOOKING_ID) {
                type = NavType.LongType
                defaultValue = 0L
            })
        ) { backStackEntry ->
            BookingCheckoutScreen(
                bookingId = backStackEntry.arguments?.getLong(Screen.BookingCheckout.ARG_BOOKING_ID) ?: 0L,
                onBack = { navController.popBackStack() },
                onCheckedOut = { navController.popBackStack() }
            )
        }

        composable(
            route = Screen.CreateDebt.route,
            arguments = listOf(navArgument(Screen.CreateDebt.ARG_BOOKING_ID) {
                type = NavType.LongType
                defaultValue = 0L
            })
        ) { backStackEntry ->
            CreateDebtFromBookingScreen(
                bookingId = backStackEntry.arguments?.getLong(Screen.CreateDebt.ARG_BOOKING_ID) ?: 0L,
                onBack = { navController.popBackStack() },
                onSaved = { navController.popBackStack() }
            )
        }
    }
}
