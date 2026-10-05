package com.marina.marina.domain.model

/** Stable wire values. Legacy inference is only for migration/old payloads,
 * never for reclassifying an already typed expense after a description edit. */
object ExpenseKind {
    const val NORMAL = "normal"
    const val ADVANCE = "salary_advance"
    const val INSTALLMENT = "salary_installment"
    const val WITHDRAWAL = "salary_withdrawal"
    const val DEDUCTION = "salary_deduction"
    const val UNCLASSIFIED = "unclassified"
    val values = setOf(NORMAL, ADVANCE, INSTALLMENT, WITHDRAWAL, DEDUCTION, UNCLASSIFIED)
    fun requireValid(value: String): String {
        require(value in values) { "Invalid expense_kind: $value" }
        return value
    }
    fun fromLegacy(type: String, auto: Boolean, description: String): String = when (type.trim()) {
        "رواتب", "سحب راتب", "سحب من الراتب" -> WITHDRAWAL
        "سلفة" -> ADVANCE
        "خصم من الراتب" -> when {
            !auto -> DEDUCTION
            description.contains("قسط سلفة") -> INSTALLMENT
            else -> UNCLASSIFIED // An edited old description cannot prove installment vs deduction.
        }
        "خصم راتب", "خصم", "غياب" -> DEDUCTION
        else -> NORMAL
    }
}
