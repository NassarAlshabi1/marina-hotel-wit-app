package com.marina.marina.navigation

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
    object Maintenance : Screen("maintenance")
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
    object SyncHealth : Screen("sync_health")
    object SyncDiagnostics : Screen("sync_diagnostics")
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

    /** البحث الشامل — نظير GlobalSearchScreen (فرع feat/cloudflare-sync-execution). */
    object GlobalSearch : Screen("global_search")

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
