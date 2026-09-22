package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.Debt
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.util.HotelTimeEngine
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

/**
 * تقرير الديون — 1:1 port of `debts_report_screen.dart`:
 * all debts loaded then filtered **in-memory on paymentDate** against the
 * 14:01/14:00:59 range (bug-compatible with Dart — NOT hotelDayKey based),
 * guest summaries sorted by remaining desc, totals chips.
 */
data class DebtsReportUiState(
    val isLoading: Boolean = false,
    val range: ReportDateRange = ReportDateRange.defaultHotelDay(),
    val rows: List<Debt> = emptyList(),
    val guestSummaries: List<DebtGuestSummary> = emptyList(),
    val totalDebt: Double = 0.0,
    val totalPaid: Double = 0.0,
    val totalRemaining: Double = 0.0
) {
    val settledCount: Int get() = rows.count { it.isSettled }
    val unsettledCount: Int get() = rows.count { !it.isSettled }
}

data class DebtGuestSummary(
    val guestName: String,
    val totalDebt: Double,
    val paid: Double,
    val remaining: Double,
    val count: Int
)

@HiltViewModel
class DebtsReportViewModel @Inject constructor(
    private val debtsRepository: DebtsRepository,
    private val bookingsRepository: BookingsRepository
) : ViewModel() {

    private val _state = MutableStateFlow(DebtsReportUiState())
    val state: StateFlow<DebtsReportUiState> = _state.asStateFlow()

    init { fetch() }

    fun setRange(range: ReportDateRange) {
        _state.value = _state.value.copy(range = range)
        fetch()
    }

    fun fetch() {
        viewModelScope.launch {
            try {
                _state.value = _state.value.copy(isLoading = true)
                val range = _state.value.range
                val all = debtsRepository.getAll().firstOrNull() ?: emptyList()

                // Dart l.98-97: in-memory filter on parsed paymentDate (raw
                // DateTime comparison against the 14:01 / 14:00:59 bounds).
                val rows = all.mapNotNull { debt ->
                    val date = HotelTimeEngine.parseDate(debt.paymentDate) ?: return@mapNotNull null
                    debt to date
                }.filter { (_, date) ->
                    date >= range.from && date <= range.to
                }.map { it.first }
                    .sortedByDescending { HotelTimeEngine.parseDate(it.paymentDate) ?: 0L }

                val guests = rows.groupBy { it.guestName }.map { (name, list) ->
                    DebtGuestSummary(
                        guestName = name,
                        totalDebt = list.sumOf { it.totalAmount },
                        paid = list.sumOf { it.paidAmount },
                        remaining = list.sumOf { it.remainingAmount },
                        count = list.size
                    )
                }.sortedByDescending { it.remaining }

                _state.value = _state.value.copy(
                    isLoading = false,
                    rows = rows,
                    guestSummaries = guests,
                    totalDebt = rows.sumOf { it.totalAmount },
                    totalPaid = rows.sumOf { it.paidAmount },
                    totalRemaining = rows.sumOf { it.remainingAmount }
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(isLoading = false)
            }
        }
    }
}
