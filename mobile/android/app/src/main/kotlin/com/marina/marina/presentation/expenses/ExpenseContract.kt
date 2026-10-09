package com.marina.marina.presentation.expenses

import com.marina.marina.domain.util.HotelTimeEngine

/**
 * Expenses screen contract — 1:1 port of the Dart pieces in
 * `screens/expenses/expenses_list.dart` (branch feat/cloudflare-sync-execution)
 * so the Kotlin screen speaks the exact same vocabulary as the Flutter one.
 */

/** Dart `kDefaultExpenseTypes` (custom_list_providers.dart l.22-31). */
val kDefaultExpenseTypes = listOf(
    "رواتب",
    "ديزل",
    "صيانة",
    "فواتير كهرباء ومياه",
    "مستلزمات",
    "مساعدة محتاج",
    "أغذية",
    "اخرى",
)

const val SALARY_TYPE = "رواتب" // Dart _salaryType
const val SALARY_WITHDRAW_ACTION = "سحب من الراتب" // Dart _salaryWithdrawAction
const val SALARY_DEDUCTION_ACTION = "خصم من الراتب" // Dart _salaryDeductionAction
const val SALARY_ADVANCE_ACTION = "سلفة" // Dart _salaryAdvanceAction

/** Dart _salaryActions (l.80-84) — the dialog transaction types, in order. */
val SALARY_ACTIONS = listOf(SALARY_ADVANCE_ACTION, SALARY_WITHDRAW_ACTION, SALARY_DEDUCTION_ACTION)

/**
 * Dart _isSalaryAction (l.1503-1518) — includes the legacy synonyms
 * (سحب راتب / خصم راتب) produced by older app versions, and سلفة which was
 * retro-added because the installment service emits it.
 */
fun isSalaryAction(type: String?): Boolean {
    if (type == null) return false
    return when (type.trim()) {
        SALARY_TYPE,
        "سحب راتب",
        SALARY_WITHDRAW_ACTION,
        SALARY_DEDUCTION_ACTION,
        SALARY_ADVANCE_ACTION,
        "خصم راتب" -> true
        else -> false
    }
}

/** Dart _mapExpenseTypeToSalaryAction (l.1520-1529). */
fun mapExpenseTypeToSalaryAction(type: String): String = when (type.trim()) {
    SALARY_DEDUCTION_ACTION, "خصم راتب" -> SALARY_DEDUCTION_ACTION
    SALARY_ADVANCE_ACTION -> SALARY_ADVANCE_ACTION
    else -> SALARY_WITHDRAW_ACTION
}

/** Dart _deriveSalaryExpenseType (l.1531-1539) — the storage expense_type. */
fun deriveSalaryExpenseType(action: String): String = when (action) {
    SALARY_DEDUCTION_ACTION -> SALARY_DEDUCTION_ACTION
    SALARY_ADVANCE_ACTION -> SALARY_ADVANCE_ACTION
    else -> "سحب راتب"
}

/**
 * Dart _hotelDayKeyFromDate (l.237-247): the picker returns a bare date, and
 * feeding midnight straight into the engine resolves to the PREVIOUS hotel
 * day. The Dart fix passes the 14:01 boundary time so picking "19 May"
 * yields hotelDayKey="2026-05-19" (14:01 May 19 → 14:00 May 20).
 */
fun hotelDayKeyFromPickedDate(dateKey: String): String {
    val millis = HotelTimeEngine.parseDate("$dateKey 14:01:00") ?: return dateKey
    return HotelTimeEngine.hotelDayKey(millis)
}
