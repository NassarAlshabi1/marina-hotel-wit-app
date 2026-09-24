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
import com.marina.marina.presentation.reports.DebtsReportScreen
import com.marina.marina.presentation.reports.ExpensesReportScreen
import com.marina.marina.presentation.reports.GuestDetailReportScreen
import com.marina.marina.presentation.reports.IncomeExpenseReportScreen
import com.marina.marina.presentation.reports.InventoryReportScreen
import com.marina.marina.presentation.reports.PaymentsReportScreen
import com.marina.marina.presentation.reports.ReportsScreen
import com.marina.marina.presentation.reports.SalaryWithdrawalsReportScreen
import com.marina.marina.presentation.rooms.RoomsListScreen
import com.marina.marina.presentation.settings.BookingsReminderScreen
import com.marina.marina.presentation.settings.CloudflareSyncSettingsScreen
import com.marina.marina.presentation.settings.SettingsScreen
import com.marina.marina.presentation.settings.backup.ComprehensiveBackupScreen

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
    object PaymentHistory : Screen("payment_history?bookingId={bookingId}") {
        const val ARG_BOOKING_ID = "bookingId"
        fun createRoute(bookingId: Long? = null) =
            if (bookingId != null && bookingId > 0) "payment_history?bookingId=$bookingId" else "payment_history"
    }
    object SalaryEntitlements : Screen("salary_entitlements")

    /**
     * شاشة الاتصال بـ Cloudflare — نظير cloudflare_login_screen.dart:
     * تُفتح من إعدادات المزامنة (أو مؤشر المزامنة) ولا تنتقل بعيداً
     * بعد الدخول — الحالة تتحدث حياً على الشاشة نفسها.
     */
    object CloudflareLogin : Screen("cloudflare_login")

    /** ✅ (2026-09-24) إعدادات المزامنة الموحدة — نظير UnifiedSyncSettingsScreen. */
    object CloudflareSyncSettings : Screen("cloudflare_sync_settings")
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

    /** النسخ الاحتياطي والاستعادة — نظير ComprehensiveBackupScreen. */
    object Backup : Screen("backup")

    // Report sub-screens (Dart reports module).
    object PaymentsReport : Screen("payments_report")
    object ExpensesReport : Screen("expenses_report")
    object IncomeExpenseReport : Screen("income_expense_report")
    object DebtsReport : Screen("debts_report")
    object InventoryReport : Screen("inventory_report")
    object SalaryReport : Screen("salary_report")
    object GuestDetailReport : Screen("guest_detail_report")
    object BookingsReminder : Screen("bookings_reminder")
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
            RoomsListScreen(
                onNewBooking = { roomNumber ->
                    // Dart rooms_dashboard l.159-202 — an available room opens
                    // the booking editor with the room pre-selected.
                    navController.navigate(Screen.BookingEdit.createRoute(0L, roomNumber))
                },
                onOpenBookingPayment = { bookingId ->
                    navController.navigate(Screen.BookingPayment.createRoute(bookingId))
                }
            )
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
        ) { entry ->
            // Dart actions_tab.dart l.179-239 — the admin-discount tool is
            // gated by the REAL logged-in role (never hardcoded).
            val authState by authViewModel.authState.collectAsState()
            BookingPaymentScreen(
                onBack = { navController.popBackStack() },
                onOpenPaymentHistory = {
                    val bookingId = entry.arguments?.getLong(Screen.BookingPayment.ARG_BOOKING_ID) ?: 0L
                    navController.navigate(Screen.PaymentHistory.createRoute(bookingId))
                },
                onOpenDebts = { navController.navigate(Screen.Debts.route) },
                isAdmin = authState.currentUser?.isAdmin ?: true
            )
        }

        adminScreen(navController, authViewModel, Screen.Payments.route) {
            PaymentsMainScreen(
                onOpenBookingCheckout = { bookingId ->
                    navController.navigate(Screen.BookingCheckout.createRoute(bookingId))
                }
            )
        }

        adminScreen(navController, authViewModel, Screen.Debts.route) {
            DebtsListScreen(
                // Dart debts_list l.750-791 — the quick-add "from booking" entry.
                onCreateFromBooking = {
                    navController.navigate(Screen.CreateDebt.createRoute(0L))
                }
            )
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
                onNavigate = { route -> navController.navigate(route) }
            )
        }

        adminScreen(navController, authViewModel, Screen.Reports.route) {
            ReportsScreen(
                onOpenReport = { route -> navController.navigate(route) }
            )
        }

        adminScreen(navController, authViewModel, Screen.Finance.route) {
            FinanceScreen(
                // Dart finance_screen l.824-845 — the booking "دفع" button opens
                // the CHECKOUT screen (not the payment screen).
                onBookingClick = { bookingId ->
                    navController.navigate(Screen.BookingCheckout.createRoute(bookingId))
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

        composable(
            route = Screen.PaymentHistory.route,
            arguments = listOf(navArgument(Screen.PaymentHistory.ARG_BOOKING_ID) {
                type = NavType.LongType
                defaultValue = 0L
            })
        ) { entry ->
            val bookingId = entry.arguments?.getLong(Screen.PaymentHistory.ARG_BOOKING_ID) ?: 0L
            PaymentHistoryScreen(
                bookingId = if (bookingId > 0) bookingId else null,
                onBack = { navController.popBackStack() }
            )
        }

        composable(Screen.SalaryEntitlements.route) {
            SalaryEntitlementsScreen(onBack = { navController.popBackStack() })
        }

        composable(Screen.CloudflareLogin.route) {
            CloudflareLoginScreen(
                onBack = { navController.popBackStack() }
            )
        }

        // ✅ (2026-09-24) إعدادات المزامنة الموحدة — نظير UnifiedSyncSettingsScreen.
        composable(Screen.CloudflareSyncSettings.route) {
            CloudflareSyncSettingsScreen(
                onBack = { navController.popBackStack() },
                onOpenCloudflareLogin = {
                    navController.navigate(Screen.CloudflareLogin.route)
                }
            )
        }

        composable(
            route = Screen.BookingCheckout.route,
            arguments = listOf(navArgument(Screen.BookingCheckout.ARG_BOOKING_ID) {
                type = NavType.LongType
                defaultValue = 0L
            })
        ) {
            BookingCheckoutScreen(
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

        // -------------------------------------------------------------------
        // Report sub-screens (Dart reports module — plain depth pages).
        // -------------------------------------------------------------------
        composable(Screen.PaymentsReport.route) {
            PaymentsReportScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.ExpensesReport.route) {
            ExpensesReportScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.IncomeExpenseReport.route) {
            IncomeExpenseReportScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.DebtsReport.route) {
            DebtsReportScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.InventoryReport.route) {
            InventoryReportScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.SalaryReport.route) {
            SalaryWithdrawalsReportScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.GuestDetailReport.route) {
            GuestDetailReportScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.BookingsReminder.route) {
            BookingsReminderScreen(onBack = { navController.popBackStack() })
        }
        composable(Screen.Backup.route) {
            ComprehensiveBackupScreen(onBack = { navController.popBackStack() })
        }
    }
}
