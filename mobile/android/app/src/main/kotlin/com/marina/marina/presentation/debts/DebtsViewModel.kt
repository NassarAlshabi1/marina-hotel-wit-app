package com.marina.marina.presentation.debts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.DebtsRepository
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
                    _state.value = _state.value.copy(message = "تم تسجيل الدين")
                } else {
                    debtsRepository.update(prepared)
                    _state.value = _state.value.copy(message = "تم تحديث الدين")
                }
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

    /** Records a partial payment against a debt. */
    fun addPartialPayment(debt: Debt, amount: Double) {
        viewModelScope.launch {
            try {
                if (amount <= 0) {
                    _state.value = _state.value.copy(message = "المبلغ غير صالح")
                    return@launch
                }
                val newPaid = (debt.paidAmount + amount).coerceAtMost(debt.totalAmount)
                val remaining = (debt.totalAmount - newPaid).coerceAtLeast(0.0)
                debtsRepository.update(
                    debt.copy(
                        paidAmount = newPaid,
                        remainingAmount = remaining,
                        isSettled = remaining <= 0
                    )
                )
                _state.value = _state.value.copy(
                    message = if (remaining <= 0) "تم تسديد الدين بالكامل" else "تم تسجيل الدفعة الجزئية"
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
}
