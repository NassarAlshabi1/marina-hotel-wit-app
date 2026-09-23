package com.marina.marina.presentation.debts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

data class DebtsUiState(
    val isLoading: Boolean = false,
    val debts: List<Debt> = emptyList(),
    val searchQuery: String = "",
    val statusFilter: String = "all", // all | pending | settled | overdue
    val error: String? = null,
    val message: String? = null
) {
    private fun overdueDays(debt: Debt): Long {
        val recorded = debt.dateRecorded.toLongOrNull() ?: return 0
        // dateRecorded is stored as millis-string in the cached fields; fall
        // back to createdAt when unparseable.
        val base = if (recorded > 0) recorded else debt.createdAt
        return TimeUnit.MILLISECONDS.toDays(System.currentTimeMillis() - base)
    }

    val filtered: List<Debt>
        get() {
            var list = debts
            when (statusFilter) {
                "pending" -> list = list.filter { !it.isSettled }
                "settled" -> list = list.filter { it.isSettled }
                "overdue" -> list = list.filter { !it.isSettled && overdueDays(it) > 30 }
            }
            val q = searchQuery.trim()
            if (q.isNotBlank()) {
                list = list.filter { it.guestName.contains(q, ignoreCase = true) }
            }
            return list
        }

    val totalCount: Int get() = debts.size
    val pendingCount: Int get() = debts.count { !it.isSettled }
    val totalRemaining: Double get() = debts.filter { !it.isSettled }.sumOf { it.remainingAmount }
}

@HiltViewModel
class DebtsViewModel @Inject constructor(
    private val debtsRepository: DebtsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(DebtsUiState(isLoading = true))
    val state: StateFlow<DebtsUiState> = _state.asStateFlow()

    init {
        debtsRepository.getAll().onEach { debts ->
            _state.value = _state.value.copy(isLoading = false, debts = debts, error = null)
        }.launchIn(viewModelScope)
    }

    fun setSearchQuery(query: String) {
        _state.value = _state.value.copy(searchQuery = query)
    }

    fun setStatusFilter(filter: String) {
        _state.value = _state.value.copy(statusFilter = filter)
    }

    fun consumeMessage() {
        _state.value = _state.value.copy(message = null)
    }

    fun saveDebt(debt: Debt) {
        viewModelScope.launch {
            try {
                val prepared = debt.copy(remainingAmount = (debt.totalAmount - debt.paidAmount).coerceAtLeast(0.0))
                if (prepared.id == 0L) {
                    debtsRepository.insert(prepared)
                    _state.value = _state.value.copy(message = "تم إضافة الدين بنجاح")
                } else {
                    debtsRepository.update(prepared)
                    _state.value = _state.value.copy(message = "تم تحديث الدين بنجاح")
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    /** Dart edit flow (l.1206-1586) — full-field update of an existing debt. */
    fun updateDebt(debt: Debt) {
        viewModelScope.launch {
            try {
                debtsRepository.update(
                    debt.copy(remainingAmount = (debt.totalAmount - debt.paidAmount).coerceAtLeast(0.0))
                )
                _state.value = _state.value.copy(message = "تم تحديث الدين بنجاح")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    /** Settles a debt in full. */
    fun settleDebt(debt: Debt) {
        viewModelScope.launch {
            try {
                debtsRepository.markSettled(debt.id, debt.totalAmount)
                _state.value = _state.value.copy(message = "تم تسديد الدين بالكامل")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    /**
     * Dart partial-payment flow (debts_list l.983-1194): amount validation
     * (>0 and <= remaining), a chosen payment date + optional note, the
     * paymentDate field updated, and every instalment appended to the JSON
     * payment log stored inside the debt's note
     * (`{"payments":[{amount,date,note}],"original_note":...}`).
     */
    fun addPartialPayment(debt: Debt, amount: Double, paymentDate: String = "", note: String = "") {
        viewModelScope.launch {
            try {
                if (amount <= 0) {
                    _state.value = _state.value.copy(message = "يرجى إدخال مبلغ صحيح")
                    return@launch
                }
                if (amount > debt.remainingAmount) {
                    _state.value = _state.value.copy(
                        message = "المبلغ يتجاوز المتبقي (${debt.remainingAmount.toInt()})"
                    )
                    return@launch
                }
                val newPaid = (debt.paidAmount + amount).coerceAtMost(debt.totalAmount)
                val remaining = (debt.totalAmount - newPaid).coerceAtLeast(0.0)
                val chosenDate = paymentDate.trim()
                    .ifBlank { HotelTimeEngine.formatIso(System.currentTimeMillis()).take(10) }
                debtsRepository.update(
                    debt.copy(
                        paidAmount = newPaid,
                        remainingAmount = remaining,
                        isSettled = remaining <= 0,
                        paymentDate = chosenDate,
                        note = appendPaymentLog(debt.note, amount, chosenDate, note)
                    )
                )
                _state.value = _state.value.copy(
                    message = if (remaining <= 0) {
                        "تم تسجيل الدفعة الجزئية بمبلغ ${amount.toInt()} بتاريخ $chosenDate — تمت تسوية الدين بالكامل"
                    } else {
                        "تم تسجيل الدفعة الجزئية بمبلغ ${amount.toInt()} بتاريخ $chosenDate"
                    }
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    fun deleteDebt(debt: Debt) {
        viewModelScope.launch {
            try {
                debtsRepository.softDelete(debt.id)
                _state.value = _state.value.copy(message = "تم حذف الدين")
            } catch (e: Exception) {
                _state.value = _state.value.copy(error = e.message)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Dart JSON payment-log helpers (debts_list l.848-976)
    // -------------------------------------------------------------------------

    private val gson = Gson()

    /** Appends `{amount,date,note}` to the note's `{"payments":[...]}` log. */
    private fun appendPaymentLog(rawNote: String?, amount: Double, date: String, note: String): String {
        return try {
            val root = if (!rawNote.isNullOrBlank()) {
                try { JsonParser.parseString(rawNote).asJsonObject } catch (_: Exception) { null }
            } else null
            if (root != null && root.has("payments")) {
                val payments = root.getAsJsonArray("payments")
                val entry = JsonObject().apply {
                    addProperty("amount", amount)
                    addProperty("date", date)
                    addProperty("note", note)
                }
                payments.add(entry)
                root.toString()
            } else {
                val newRoot = JsonObject().apply {
                    addProperty("original_note", rawNote ?: "")
                    val payments = com.google.gson.JsonArray()
                    val entry = JsonObject().apply {
                        addProperty("amount", amount)
                        addProperty("date", date)
                        addProperty("note", note)
                    }
                    payments.add(entry)
                    add("payments", payments)
                }
                newRoot.toString()
            }
        } catch (_: Exception) {
            rawNote ?: ""
        }
    }

    /** Parses the instalment log for rendering (سجل الدفعات). */
    fun parsePaymentLog(rawNote: String?): Pair<String, List<Triple<Double, String, String>>> {
        if (rawNote.isNullOrBlank()) return "" to emptyList()
        return try {
            val root = JsonParser.parseString(rawNote).asJsonObject
            val original = root.get("original_note")?.asString ?: ""
            val payments = root.getAsJsonArray("payments").mapNotNull { el ->
                val obj = el.asJsonObject
                Triple(
                    obj.get("amount")?.asDouble ?: 0.0,
                    obj.get("date")?.asString ?: "",
                    obj.get("note")?.asString ?: ""
                )
            }
            original to payments
        } catch (_: Exception) {
            rawNote to emptyList()
        }
    }
}
