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
import com.marina.marina.presentation.search.GlobalSearchScreen
import com.marina.marina.presentation.rooms.RoomsListScreen
import com.marina.marina.presentation.settings.BookingsReminderScreen
import com.marina.marina.presentation.settings.CloudflareSyncSettingsScreen
import com.marina.marina.presentation.settings.SettingsScreen
import com.marina.marina.presentation.settings.SyncHealthScreen
import com.marina.marina.presentation.settings.SyncDiagnosticsScreen
import com.marina.marina.presentation.settings.backup.ComprehensiveBackupScreen

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
                onOpenReport = { route -> navController.navigate(route) },
                // ✅ زر البحث في ترويسة التقارير — نقطة الدخول الطبيعية للبحث الشامل.
                onOpenSearch = { navController.navigate(Screen.GlobalSearch.route) }
            )
        }

        adminScreen(navController, authViewModel, Screen.GlobalSearch.route) {
            GlobalSearchScreen(onBack = { navController.popBackStack() })
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
                },
                onOpenDiagnostics = {
                    navController.navigate(Screen.SyncDiagnostics.route)
                }
            )
        }

        composable(Screen.SyncHealth.route) {
            SyncHealthScreen(
                onBack = { navController.popBackStack() },
                onOpenDiagnostics = { navController.navigate(Screen.SyncDiagnostics.route) },
                onOpenSettings = { navController.navigate(Screen.CloudflareSyncSettings.route) }
            )
        }

        composable(Screen.SyncDiagnostics.route) {
            SyncDiagnosticsScreen(onBack = { navController.popBackStack() })
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
