package com.marinahotel.kotlin.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marinahotel.kotlin.data.repository.HotelRepository
import com.marinahotel.kotlin.domain.model.BookingStatus
import com.marinahotel.kotlin.domain.model.BookingSummary
import com.marinahotel.kotlin.domain.model.Expense
import com.marinahotel.kotlin.domain.model.Payment
import com.marinahotel.kotlin.domain.model.Room
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class ReportsViewModel(
    private val repository: HotelRepository
) : ViewModel() {

    private val zoneId = ZoneId.systemDefault()
    private val dateFormatter = DateTimeFormatter.ofPattern("dd MMM yyyy", Locale.getDefault())
    private val dayLabelFormatter = DateTimeFormatter.ofPattern("dd MMM", Locale.getDefault())

    private val defaultRange = DateRange(
        from = startOfDay(System.currentTimeMillis() - (DEFAULT_DAYS - 1) * DAY_MILLIS),
        to = startOfDay(System.currentTimeMillis())
    )

    private val dateRange = MutableStateFlow(defaultRange)

    private val _uiState = MutableStateFlow(
        ReportsUiState(
            fromDate = defaultRange.from,
            toDate = defaultRange.to,
            totalRevenue = 0,
            totalExpenses = 0,
            netIncome = 0,
            summaries = emptyList(),
            isLoading = true
        )
    )
    val uiState: StateFlow<ReportsUiState> = _uiState.asStateFlow()

    init {
        observeReports()
    }

    private fun observeReports() {
        viewModelScope.launch {
            dateRange
                .flatMapLatest { range ->
                    combine(
                        repository.observeRooms(),
                        repository.observeBookings(),
                        repository.observePaymentsBetween(range.from, range.to + DAY_MILLIS - 1),
                        repository.observeExpensesBetween(range.from, range.to + DAY_MILLIS - 1)
                    ) { rooms, bookings, payments, expenses ->
                        computeState(range, rooms, bookings, payments, expenses)
                    }
                }
                .collect { state ->
                    _uiState.value = state
                }
        }
    }

    fun onSelectFromDate(timestamp: Long) {
        val normalized = startOfDay(timestamp)
        val current = dateRange.value
        val adjustedRange = if (normalized <= current.to) {
            current.copy(from = normalized)
        } else {
            DateRange(from = normalized, to = normalized)
        }
        _uiState.update { it.copy(fromDate = adjustedRange.from, toDate = adjustedRange.to, isLoading = true) }
        dateRange.value = adjustedRange
    }

    fun onSelectToDate(timestamp: Long) {
        val normalized = startOfDay(timestamp)
        val current = dateRange.value
        val adjustedRange = if (normalized >= current.from) {
            current.copy(to = normalized)
        } else {
            DateRange(from = normalized, to = normalized)
        }
        _uiState.update { it.copy(fromDate = adjustedRange.from, toDate = adjustedRange.to, isLoading = true) }
        dateRange.value = adjustedRange
    }

    fun formatDate(timestamp: Long): String {
        val instant = Instant.ofEpochMilli(timestamp)
        return dateFormatter.format(instant.atZone(zoneId).toLocalDate())
    }

    private fun computeState(
        range: DateRange,
        rooms: List<Room>,
        bookings: List<BookingSummary>,
        payments: List<Payment>,
        expenses: List<Expense>
    ): ReportsUiState {
        val dayStarts = generateDayList(range.from, range.to)
        val totalRooms = rooms.size.coerceAtLeast(1)
        val paymentsByDay = payments.groupBy { startOfDay(it.paymentDate) }.mapValues { entry -> entry.value.sumOf { it.amount } }
        val expensesByDay = expenses.groupBy { startOfDay(it.date) }.mapValues { entry -> entry.value.sumOf { it.amount } }
        val relevantBookings = bookings.filter { it.booking.status != BookingStatus.CANCELLED }

        val summaries = dayStarts.map { dayStart ->
            val dayEnd = dayStart + DAY_MILLIS
            val occupiedRooms = relevantBookings.count { summary ->
                val booking = summary.booking
                val checkout = booking.checkoutDate ?: (range.to + DAY_MILLIS)
                booking.checkinDate < dayEnd && checkout > dayStart
            }
            val occupancyPercent = if (rooms.isEmpty()) 0f else (occupiedRooms.toFloat() / totalRooms.toFloat()) * 100f
            val revenue = paymentsByDay[dayStart] ?: 0
            val dailyExpenses = expensesByDay[dayStart] ?: 0
            DailySummary(
                date = dayStart,
                label = formatDayLabel(dayStart),
                occupancyPercent = occupancyPercent,
                revenue = revenue,
                expenses = dailyExpenses
            )
        }

        val totalRevenue = payments.sumOf { it.amount }
        val totalExpenses = expenses.sumOf { it.amount }
        val netIncome = totalRevenue - totalExpenses

        return ReportsUiState(
            fromDate = range.from,
            toDate = range.to,
            totalRevenue = totalRevenue,
            totalExpenses = totalExpenses,
            netIncome = netIncome,
            summaries = summaries,
            isLoading = false
        )
    }

    private fun generateDayList(from: Long, to: Long): List<Long> {
        val days = mutableListOf<Long>()
        var current = from
        while (current <= to) {
            days.add(current)
            current += DAY_MILLIS
        }
        return days
    }

    private fun formatDayLabel(dayStart: Long): String {
        val instant = Instant.ofEpochMilli(dayStart)
        return dayLabelFormatter.format(instant.atZone(zoneId).toLocalDate())
    }

    private fun startOfDay(timestamp: Long): Long {
        val instant = Instant.ofEpochMilli(timestamp)
        return instant.atZone(zoneId).toLocalDate().atStartOfDay(zoneId).toInstant().toEpochMilli()
    }

    private data class DateRange(val from: Long, val to: Long)

    data class ReportsUiState(
        val fromDate: Long,
        val toDate: Long,
        val totalRevenue: Int,
        val totalExpenses: Int,
        val netIncome: Int,
        val summaries: List<DailySummary>,
        val isLoading: Boolean
    )

    data class DailySummary(
        val date: Long,
        val label: String,
        val occupancyPercent: Float,
        val revenue: Int,
        val expenses: Int
    )

    companion object {
        private const val DAY_MILLIS = 86_400_000L
        private const val DEFAULT_DAYS = 7L
    }
}
