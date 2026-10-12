package com.marina.marina.presentation.blacklist

import android.util.Log
import com.marina.marina.data.blacklist.BlacklistAlertStore
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.domain.model.BlacklistEntry
import com.marina.marina.domain.repository.BlacklistRepository
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Blacklist Alert Service — parity with Flutter `BlacklistAlertService`.
 * Scans active bookings on startup, checks new bookings against blacklist,
 * and exposes a stream of active alerts for UI display.
 * Persists alerts via DataStore.
 */
@Singleton
class BlacklistAlertService @Inject constructor(
    private val db: AppDatabase,
    private val blacklistRepository: BlacklistRepository,
    private val alertStore: BlacklistAlertStore
) {
    private val scope = kotlinx.coroutines.CoroutineScope(
        kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO
    )

    private val _alerts = ConcurrentHashMap<Long, BlacklistAlert>()
    private val _alertsFlow = kotlinx.coroutines.flow.MutableStateFlow<List<BlacklistAlert>>(emptyList())

    val alertsFlow: kotlinx.coroutines.flow.StateFlow<List<BlacklistAlert>> = _alertsFlow

    data class BlacklistAlert(
        val guestName: String,
        val roomNumber: String,
        val bookingId: Long,
        val blacklistEntry: BlacklistEntry,
        val detectedAt: Long = System.currentTimeMillis()
    ) {
        val displayName: String = "${blacklistEntry.name} (غرفة $roomNumber)"
        val reasonText: String = blacklistEntry.reason ?: "سبب غير محدد"

        // Gson — نفس حزمة التسلسل المعتمدة في بقية المشروع (لا حاجة لإضافة
        // kotlinx-serialization إلى إعدادات البناء من أجل ميزة واحدة).
        fun toJson(): String = gson.toJson(this)
        companion object {
            private val gson = Gson()
            fun fromJson(json: String): BlacklistAlert = gson.fromJson(json, BlacklistAlert::class.java)
        }
    }

    init {
        loadPersistedAlerts()
    }

    /**
     * Initialize: load persisted alerts + scan current checked-in guests
     */
    fun initialize() {
        scope.launch(Dispatchers.IO) {
            scanCurrentGuests()
        }
    }

    /**
     * Check a new guest at check-in time.
     * Returns alert if matched, null otherwise.
     */
    suspend fun checkGuest(
        guestName: String,
        roomNumber: String,
        bookingId: Long
    ): BlacklistAlert? {
        if (guestName.isBlank()) return null

        val match = blacklistRepository.findBlacklistMatch(guestName)
        if (match == null || !match.active) return null

        // Prevent duplicate for same booking
        if (_alerts.containsKey(bookingId)) return _alerts[bookingId]

        val alert = BlacklistAlert(
            guestName = guestName,
            roomNumber = roomNumber,
            bookingId = bookingId,
            blacklistEntry = match
        )

        _alerts[bookingId] = alert
        _alertsFlow.value = _alerts.values.toList()
        persistAlerts()

        Log.w("BlacklistAlert", "🚨 BLACKLIST ALERT: ${match.name} matched guest \"$guestName\" in room $roomNumber (booking #$bookingId)")
        return alert
    }

    /**
     * Scan all currently checked-in guests (on app start)
     */
    private suspend fun scanCurrentGuests() {
        try {
            val activeBookings = db.bookingsDao().getCheckedInGuests()
            val repo = blacklistRepository
            var newAlerts = 0

            for (booking in activeBookings) {
                if (_alerts.containsKey(booking.id)) continue

                val match = repo.findBlacklistMatch(booking.guest_name)
                if (match != null && match.active) {
                    val alert = BlacklistAlert(
                        guestName = booking.guest_name,
                        roomNumber = booking.room_number,
                        bookingId = booking.id,
                        blacklistEntry = match
                    )
                    _alerts[booking.id] = alert
                    newAlerts++
                }
            }

            if (newAlerts > 0) {
                _alertsFlow.value = _alerts.values.toList()
                persistAlerts()
                Log.w("BlacklistAlert", "🚨 Blacklist scan: $newAlerts new alert(s) found")
            }
        } catch (e: Exception) {
            Log.e("BlacklistAlert", "⚠️ Blacklist scan failed: ${e.message}")
        }
    }

    /**
     * Dismiss alert when guest checks out
     */
    fun dismissAlert(bookingId: Long) {
        _alerts.remove(bookingId)
        _alertsFlow.value = _alerts.values.toList()
        persistAlerts()
    }

    /**
     * Clear all alerts
     */
    fun clearAll() {
        _alerts.clear()
        _alertsFlow.value = emptyList()
        persistAlerts()
    }

    /**
     * Load persisted alerts from DataStore
     */
    private fun loadPersistedAlerts() {
        scope.launch(Dispatchers.IO) {
            try {
                val savedAlerts = alertStore.loadAlerts()
                if (savedAlerts.isEmpty()) return@launch

                val allEntries = blacklistRepository.getActive().firstOrNull() ?: emptyList()
                val activeEntries = allEntries.filter { it.active }.associateBy { it.name }

                _alerts.clear()
                for (alert in savedAlerts) {
                    // Verify booking still checked-in
                    val booking = db.bookingsDao().getById(alert.bookingId)
                        ?: continue
                    if (booking.status != "checked_in") continue

                    // Verify blacklist entry still exists and active
                    val entry = activeEntries[alert.blacklistEntry.name]
                        ?: continue

                    _alerts[alert.bookingId] = alert.copy(blacklistEntry = entry)
                }
                _alertsFlow.value = _alerts.values.toList()
            } catch (e: Exception) {
                Log.e("BlacklistAlert", "⚠️ Failed to load blacklist alerts: ${e.message}")
            }
        }
    }

    /**
     * Persist alerts to DataStore
     */
    private fun persistAlerts() {
        scope.launch(Dispatchers.IO) {
            try {
                alertStore.saveAlerts(_alerts.values.toList())
            } catch (e: Exception) {
                Log.e("BlacklistAlert", "⚠️ Failed to persist blacklist alerts: ${e.message}")
            }
        }
    }
}