package com.marina.marina.presentation.reports

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.domain.model.SyncUiState
import com.marina.marina.domain.repository.DebtsRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Calendar
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * التقارير (hub) — port 1:1 من `reports_screen.dart` (فرع
 * feat/cloudflare-sync-execution): مؤشرات سريعة لليوم الفندقي +
 * الرسوم الثلاثة الحقيقية + اختصارات التقارير.
 *
 * ✅ (2026-09-22 في Dart — منقول هنا) إصلاح الرسوم الثلاثة الكاذبة:
 * 1) «الإشغال اليومي (آخر 7 أيام)»: احتلال فعلي لكل يوم من آخر 7 أيام
 *    فندقية من تداخل الحجوزات (دخول ≤ اليوم < خروج).
 * 2) «أعلى الغرف إشغالاً»: عدد ليالي الاحتلال لكل غرفة في آخر 30 يوم
 *    فندقي، مرتبة تنازلياً.
 * 3) «الإيرادات مقابل المصروفات (الشهر)»: نطاق الشهر الفندقي كاملاً
 *    عبر نفس DAOs التقارير (listFilteredByHotelDay).
 */
data class ReportsHubUiState(
    val isLoading: Boolean = true,
    val loadError: String? = null,
    val hotelDayKey: String = "",
    val income: Double = 0.0,
    val expenses: Double = 0.0,
    val net: Double = 0.0,
    val totalRooms: Int = 0,
    val occupiedRooms: Int = 0,
    val activeBookings: Int = 0,
    val unsettledDebts: Int = 0,
    val unsettledDebtsTotal: Double = 0.0,
    // ── الرسوم الثلاثة ──
    /** الإشغال اليومي (آخر 7 أيام) — نسبة 0..100، الأقدم إلى الأحدث. */
    val dailyOccupancy: List<Int> = emptyList(),
    /** إيرادات الشهر الفندقي الحالي (عقد التقارير نفسه). */
    val monthIncome: Double = 0.0,
    /** مصروفات الشهر الفندقي الحالي. */
    val monthExpense: Double = 0.0,
    /** أعلى الغرف إشغالاً — (رقم الغرفة، ليالي الاحتلال) بترتيب تنازلي. */
    val topRooms: List<Pair<String, Int>> = emptyList()
) {
    val occupancyPercent: Int
        get() = if (totalRooms > 0) (occupiedRooms * 100 / totalRooms) else 0
}

/** حد شاشة واحد (سناك-بار) — نظير SnackBarHelper في Dart. */
data class ReportsHubEvent(val message: String, val kind: EventKind) {
    enum class EventKind { SUCCESS, WARNING, ERROR }
}

@HiltViewModel
class ReportsHubViewModel @Inject constructor(
    private val expensesRepository: ExpensesRepository,
    private val debtsRepository: DebtsRepository,
    private val roomsRepository: RoomsRepository,
    private val paymentsDao: PaymentsDao,
    private val expensesDao: ExpensesDao,
    private val bookingsDao: BookingsDao,
    private val syncRepository: SyncRepository
) : ViewModel() {

    private val _state = MutableStateFlow(ReportsHubUiState())
    val state: StateFlow<ReportsHubUiState> = _state.asStateFlow()

    private val _events = MutableSharedFlow<ReportsHubEvent>(extraBufferCapacity = 8)
    val events: SharedFlow<ReportsHubEvent> = _events.asSharedFlow()

    init {
        // المؤشرات السريعة — تيارات حية (نظير _loadData المالي + الغرف).
        combine(
            paymentsDao.getAll(),
            expensesRepository.getAll(),
            debtsRepository.getAll(),
            roomsRepository.getAll()
        ) { payments, expenses, debts, rooms ->
            val hotelDay = HotelTimeEngine.currentHotelDayKey()
            // Dart l.87-116: hotel-day key equality + legacy date LIKE fallback,
            // voided excluded.
            val dayIncome = payments.filter {
                !it.isVoided && (it.hotelDayKey == hotelDay ||
                    (it.hotelDayKey == null && it.paymentDate.startsWith(hotelDay)))
            }.sumOf { it.amount }
            val dayExpenses = expenses.filter {
                it.hotelDayKey == hotelDay ||
                    (it.hotelDayKey == null && it.date.startsWith(hotelDay))
            }.sumOf { it.amount }
            val unsettled = debts.filter { !it.isSettled }
            // Dart l.127-136: occupancy = busy rooms / total rooms.
            val busy = rooms.count { StatusUtils.isRoomOccupied(it.status) }
            val totalRooms = if (rooms.isNotEmpty()) rooms.size else 1
            _state.value.copy(
                isLoading = false,
                hotelDayKey = hotelDay,
                income = dayIncome,
                expenses = dayExpenses,
                net = dayIncome - dayExpenses,
                totalRooms = totalRooms,
                occupiedRooms = busy,
                activeBookings = _state.value.activeBookings,
                unsettledDebts = unsettled.size,
                unsettledDebtsTotal = unsettled.sumOf { it.remainingAmount }
            )
        }.onEach { _state.value = it }.launchIn(viewModelScope)

        loadCharts()
    }

    /** زر «مزامنة» — نظير triggerManualCloudflareSync: دورة سحابية حقيقية
     *  (دفع + سحب) بنتيجة ظاهرة بدل الوهم الصامت السابق. */
    fun runManualSync() {
        viewModelScope.launch {
            try {
                val result = syncRepository.syncNow()
                if (result.isError) {
                    _events.emit(ReportsHubEvent("⚠️ فشلت المزامنة: ${result.lastMessage}", ReportsHubEvent.EventKind.ERROR))
                } else {
                    _events.emit(ReportsHubEvent("✅ تمت المزامنة بنجاح", ReportsHubEvent.EventKind.SUCCESS))
                    loadCharts()
                }
            } catch (e: Exception) {
                _events.emit(ReportsHubEvent("❌ خطأ أثناء المزامنة: ${e.message}", ReportsHubEvent.EventKind.ERROR))
            }
        }
    }

    /** الرسوم الثلاثة — نظير `_loadData` الحسابي في Dart. */
    fun loadCharts() {
        viewModelScope.launch {
            try {
                val rooms = roomsRepository.getAllOnce()
                val total = if (rooms.isEmpty()) 1 else rooms.size

                // الحجوزات غير الملغاة (المغادِرة تُحتسب تاريخياً) — Dart l.140-147
                val occupancyBookings = bookingsDao.listAllIncludingDeleted()
                    .filter { it.deletedAt == null && it.status !in listOf("ملغي", "cancelled") }

                // 1) الإشغال اليومي — آخر 7 أيام فندقية (الأقدم إلى الأحدث)
                val daily = mutableListOf<Int>()
                for (i in 6 downTo 0) {
                    val dayKey = hotelDayKeyDaysAgo(i)
                    val occupied = occupancyBookings.count { occupiedOnHotelDay(it.checkinDate, it.actualCheckout, it.checkoutDate, dayKey) }
                    daily.add((occupied * 100 / total))
                }

                // 3) إيرادات ومصروفات الشهر الفندقي الحالي (عقد التقارير نفسه)
                val monthStartHotelDay = firstOfMonthHotelDay()
                val todayHotelDay = HotelTimeEngine.currentHotelDayKey()
                val monthPayments = paymentsDao.listFilteredByHotelDay(
                    fromHotelDay = monthStartHotelDay,
                    toHotelDay = todayHotelDay,
                    toHotelDayExclusive = null,
                    roomNumber = null,
                    excludeVoided = true,
                    excludePendingBalance = true
                )
                val monthExpenses = expensesDao.listFilteredByHotelDay(
                    fromHotelDay = monthStartHotelDay,
                    toHotelDay = todayHotelDay,
                    toHotelDayExclusive = null,
                    expenseType = null,
                    isSalaryType = false,
                    excludeAdvance = false,
                    search = null
                )
                val monthIncome = monthPayments.sumOf { it.amount }
                val monthExpense = monthExpenses.sumOf { it.amount }

                // 2) أعلى الغرف إشغالاً — ليالي الاحتلال في آخر 30 يوم فندقي
                val nightsByRoom = LinkedHashMap<String, Int>()
                val last30 = (29 downTo 0).map { hotelDayKeyDaysAgo(it) }
                for (b in occupancyBookings) {
                    for (dayKey in last30) {
                        if (occupiedOnHotelDay(b.checkinDate, b.actualCheckout, b.checkoutDate, dayKey)) {
                            nightsByRoom[b.roomNumber] = (nightsByRoom[b.roomNumber] ?: 0) + 1
                        }
                    }
                }
                val topEntries = nightsByRoom.entries.sortedByDescending { it.value }.map { it.key to it.value }

                _state.value = _state.value.copy(
                    loadError = null,
                    dailyOccupancy = daily,
                    monthIncome = monthIncome,
                    monthExpense = monthExpense,
                    topRooms = topEntries
                )
            } catch (_: Exception) {
                _state.value = _state.value.copy(
                    loadError = "تعذر تحميل مؤشرات التقارير. حاول التحديث مرة أخرى."
                )
            }
        }
    }

    /** هل احتل هذا الحجز اليوم الفندقي المعطى؟ (دخول ≤ اليوم < خروج فعلي/مخطط)
     *  المقارنة على مفاتيح 'yyyy-MM-dd' النصية — نظير `_occupiedOnHotelDay`. */
    private fun occupiedOnHotelDay(checkinDate: String, actualCheckout: String?, checkoutDate: String?, dayKey: String): Boolean {
        val checkin = if (checkinDate.length >= 10) checkinDate.substring(0, 10) else checkinDate
        if (checkin > dayKey) return false
        val end = actualCheckout ?: checkoutDate ?: ""
        if (end.length >= 10 && end.substring(0, 10) <= dayKey) return false
        return true
    }

    /** مفتاح اليوم الفندقي قبل [days] يوم — نفس عقد Dart getHotelDayKey(dateTime:). */
    private fun hotelDayKeyDaysAgo(days: Int): String {
        val cal = Calendar.getInstance()
        cal.add(Calendar.DAY_OF_YEAR, -days)
        return HotelTimeEngine.hotelDayKey(cal.timeInMillis)
    }

    /** مفتاح اليوم الفندقي لأول الشهر الحالي (اليوم 1 عند 14:01 → بعد القطع). */
    private fun firstOfMonthHotelDay(): String {
        val cal = Calendar.getInstance()
        cal.set(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 14)
        cal.set(Calendar.MINUTE, 1)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return HotelTimeEngine.hotelDayKey(cal.timeInMillis)
    }
}
