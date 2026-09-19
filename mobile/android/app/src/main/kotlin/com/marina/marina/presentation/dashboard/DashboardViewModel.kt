package com.marina.marina.presentation.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.domain.model.SyncUiState
import com.marina.marina.domain.repository.SyncRepository
import com.marina.marina.domain.model.AuthUser
import com.marina.marina.domain.model.Booking
import com.marina.marina.domain.model.PaymentUserHotelDaySummary
import com.marina.marina.domain.model.Room
import com.marina.marina.domain.model.RoomWithPaymentStatus
import com.marina.marina.domain.repository.BookingsRepository
import com.marina.marina.domain.repository.ExpensesRepository
import com.marina.marina.domain.repository.PaymentsRepository
import com.marina.marina.domain.repository.RoomsRepository
import com.marina.marina.domain.session.UserSessionManager
import com.marina.marina.domain.util.HotelTimeEngine
import com.marina.marina.domain.util.RoomPaymentStatusCalculator
import com.marina.marina.domain.util.StatusUtils
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.Calendar
import javax.inject.Inject
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
/**
 * Reactive Dashboard engine — the Kotlin counterpart of the Flutter app's
 * dashboard providers (`core_providers`, `repository_providers`,
 * `room_payment_status_provider`):
 *
 * 1. [financialStats] — today's payments / expenses / remaining balance,
 *    scoped to the **hotel day** (14:01 boundary) and re-scoped when the
 *    hotel day rolls over (30s ticker).
 * 2. [roomsWithStatus] — rooms joined with their live booking and the
 *    22:00–23:00 (early warning) / 23:00–05:00 (overdue) payment lateness
 *    state, recomputed every minute **only inside the alert windows**
 *    (same performance contract as the Flutter provider).
 * 3. [sessionReceipts] — the current user's receipts within the login
 *    session (no hotel-day filter; a shift may cross 14:01).
 * 4. [otherUserSummaries] — other users' receipts for the current hotel
 *    day, visible to admin / manager / supervisor only.
 * 5. Auto-pull on open + hourly cloud safety net, mirroring the Flutter
 *    `_autoPullFromAppwrite` / `_dashboardCloudRefreshTimer` behavior.
 */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val roomsRepository: RoomsRepository,
    private val bookingsRepository: BookingsRepository,
    private val paymentsRepository: PaymentsRepository,
    private val expensesRepository: ExpensesRepository,
    private val syncManager: SyncRepository,
    private val sessionManager: UserSessionManager
) : ViewModel() {

    // -------------------------------------------------------------------------
    // Tickers (ports of hotelDayTickerProvider and the 1-minute room timer)
    // -------------------------------------------------------------------------

    /** Emits the hotel-day key now, then again whenever the day rolls over. */
    private val hotelDayKeyFlow = flow {
        var last = HotelTimeEngine.currentHotelDayKey()
        emit(last)
        while (true) {
            delay(HOTEL_DAY_TICK_MS)
            val current = HotelTimeEngine.currentHotelDayKey()
            if (current != last) {
                last = current
                emit(current)
            }
        }
    }

    /**
     * One-minute recompute signal for room lateness. Emits once immediately
     * (first derivation) and then only during the alert windows
     * (22:00–05:00) — outside them the lateness flags are structurally
     * false and re-derivation is skipped, exactly like the Flutter timer.
     */
    private val alertWindowTick = flow {
        emit(Unit)
        while (true) {
            val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
            if (hour >= ALERT_WINDOW_START_HOUR || hour < ALERT_WINDOW_END_HOUR) {
                emit(Unit)
            }
            delay(MINUTE_MS)
        }
    }

    // -------------------------------------------------------------------------
    // Public observable state
    // -------------------------------------------------------------------------

    val currentUser: StateFlow<AuthUser?> = sessionManager.currentUser

    /** Today's financial aggregates (hotel-day scoped). */
    val financialStats: StateFlow<FinancialStats?> = hotelDayKeyFlow
        .flatMapLatest { hotelDay ->
            combine(
                paymentsRepository.watchTotalByHotelDayKey(hotelDay),
                expensesRepository.watchTotalByHotelDayKey(hotelDay)
            ) { payments, expenses -> FinancialStats(payments, expenses) }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    /** Rooms paired with live-booking + payment-lateness state. */
    val roomsWithStatus: StateFlow<List<RoomWithPaymentStatus>> = combine(
        roomsRepository.getAll(),
        bookingsRepository.getAll(),
        alertWindowTick
    ) { rooms, bookings, _ -> deriveRoomsWithStatus(rooms, bookings) }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Whether the rooms section failed to load (parity with the Dart error UI). */
    val roomsError: StateFlow<String?> = combine(
        roomsRepository.getAll(),
        bookingsRepository.getAll()
    ) { _, _ -> null as String? }
        .catch { emit(it.message) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    /** The current user's receipts within the login session. */
    val sessionReceipts: StateFlow<Double> = sessionManager.currentUser
        .flatMapLatest { paymentsRepository.watchTotalByCurrentPaymentSession() }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0.0)

    /** Session start instant for the "النوبة بدأت HH:mm" label, or null. */
    val sessionStartedAt: Long?
        get() = sessionManager.sessionStartedAt

    /** Other users' hotel-day receipts (admin / manager / supervisor only). */
    val otherUserSummaries: StateFlow<List<PaymentUserHotelDaySummary>> =
        combine(sessionManager.currentUser, hotelDayKeyFlow) { user, hotelDay -> user to hotelDay }
            .flatMapLatest { (user, hotelDay) ->
                if (user == null) {
                    flowOf(emptyList())
                } else {
                    paymentsRepository.watchPaymentUserHotelDaySummaries(
                        hotelDayKey = hotelDay,
                        excludedUserId = user.id.toLong(),
                        excludedUserName = user.name,
                        excludedUserCloudId = user.cloudUserId
                    )
                }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Whether the current user may see other users' receipts. */
    val canViewOtherUsers: Boolean
        get() = sessionManager.currentUser.value
            ?.let { it.isAdmin || it.userType == "manager" || it.userType == "supervisor" } == true

    /** Live sync engine state + pending outbox count (header indicators). */
    val syncState: StateFlow<SyncUiState> = syncManager.syncState
    val pendingChanges: StateFlow<Int> = syncManager.pendingCount()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    /** One-shot UI events (snackbars). */
    private val _events = MutableSharedFlow<DashboardEvent>(extraBufferCapacity = 8)
    val events: SharedFlow<DashboardEvent> = _events.asSharedFlow()

    /** Booked room lookup for navigation: room number -> active booking. */
    private val _activeBookingByRoom = MutableStateFlow<Map<String, Booking>>(emptyMap())
    val activeBookingByRoom: StateFlow<Map<String, Booking>> = _activeBookingByRoom.asStateFlow()

    init {
        // Keep a room->activeBooking map for tap navigation without re-querying.
        viewModelScope.launch {
            bookingsRepository.getAll().collect { bookings ->
                _activeBookingByRoom.value = bookings
                    .filter { StatusUtils.isBookingActive(it.status) }
                    .associateBy { it.roomNumber }
            }
        }
        // Silent pull on Dashboard open (Flutter `_autoPullFromAppwrite`).
        autoPullOnOpen()
        // Hourly cloud safety net while the screen is visible — the Kotlin
        // counterpart of the Flutter `_dashboardCloudRefreshTimer`
        // (1-hour periodic silent pull; immediacy is covered by the outbox
        // watcher + this pull keeps the receipts card fresh).
        viewModelScope.launch {
            while (true) {
                delay(HOURLY_CLOUD_REFRESH_MS)
                if (syncState.value.isSyncing) continue
                syncManager.pullOnly()
            }
        }
    }

    // -------------------------------------------------------------------------
    // Actions
    // -------------------------------------------------------------------------

    /**
     * Silent pull on Dashboard open — the Kotlin counterpart of the Flutter
     * `_autoPullFromAppwrite` (robust pull, success-gated hour check). The
     * outbox watcher covers the push side, so only deltas are pulled.
     */
    fun autoPullOnOpen() {
        viewModelScope.launch {
            val pulled = syncManager.pullOnly()
            if (pulled > 0) {
                _events.emit(DashboardEvent.AutoPullSucceeded(pulled))
            }
        }
    }

    /** Manual full sync (header sync button). */
    fun triggerSync() {
        viewModelScope.launch {
            val state = syncManager.syncNow()
            _events.emit(
                if (state.isError) {
                    DashboardEvent.SyncFailed(state.lastMessage)
                } else {
                    DashboardEvent.SyncCompleted(state.pushedCount, state.pulledCount)
                }
            )
        }
    }

    /** Marks a room as under maintenance (long-press room options dialog). */
    fun setRoomUnderMaintenance(room: Room, onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            try {
                roomsRepository.updateStatus(room.id, "صيانة")
                _events.emit(DashboardEvent.RoomStatusUpdated(room.roomNumber, "صيانة"))
                onDone(true)
            } catch (e: Exception) {
                _events.emit(DashboardEvent.Error("خطأ في تحديث الحالة: ${e.message}"))
                onDone(false)
            }
        }
    }

    // -------------------------------------------------------------------------
    // Derivation
    // -------------------------------------------------------------------------

    /**
     * Delegates to [RoomPaymentStatusCalculator] (pure, unit-testable) with
     * the current wall-clock hour.
     */
    internal fun deriveRoomsWithStatus(rooms: List<Room>, bookings: List<Booking>): List<RoomWithPaymentStatus> =
        RoomPaymentStatusCalculator.calculate(
            rooms = rooms,
            bookings = bookings,
            hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        )

    companion object {
        private const val MINUTE_MS = 60_000L
        private const val HOTEL_DAY_TICK_MS = 30_000L
        private const val HOURLY_CLOUD_REFRESH_MS = 60L * 60 * 1000
        private const val ALERT_WINDOW_START_HOUR = 22
        private const val ALERT_WINDOW_END_HOUR = 5
    }
}

/** Today's hotel-day financial aggregates. */
data class FinancialStats(
    val todayPayments: Double,
    val todayExpenses: Double
) {
    /** Remaining balance = income − expenses (negative ⇒ "عجز"). */
    val balance: Double get() = todayPayments - todayExpenses
    val isDeficit: Boolean get() = balance < 0
}

/** One-shot Dashboard UI events. */
sealed interface DashboardEvent {
    /** "✅ تم سحب N سجل جديد من Cloudflare تلقائياً" — green snackbar. */
    data class AutoPullSucceeded(val pulledCount: Int) : DashboardEvent

    data class SyncCompleted(val pushedCount: Int, val pulledCount: Int) : DashboardEvent
    data class SyncFailed(val message: String) : DashboardEvent
    data class RoomStatusUpdated(val roomNumber: String, val newStatus: String) : DashboardEvent
    data class Error(val message: String) : DashboardEvent
}
