package com.marina.marina.data.repository

import com.google.gson.Gson
import com.marina.marina.data.local.dao.BookingsDao
import com.marina.marina.data.local.dao.DebtsDao
import com.marina.marina.data.local.dao.EmployeesDao
import com.marina.marina.data.local.dao.ExpensesDao
import com.marina.marina.data.local.dao.PaymentsDao
import com.marina.marina.data.local.dao.RoomsDao
import com.marina.marina.data.local.entity.BookingEntity
import com.marina.marina.data.local.entity.DebtEntity
import com.marina.marina.data.local.entity.EmployeeEntity
import com.marina.marina.data.local.entity.ExpenseEntity
import com.marina.marina.data.local.entity.PaymentEntity
import com.marina.marina.data.local.entity.RoomEntity
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.SyncPreferences
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Unified sync orchestrator — the Kotlin counterpart of the Flutter app's
 * `UnifiedSyncOrchestrator` (simplified single-engine version):
 *
 * 1. **Push**: drains the local outbox to the Cloudflare worker
 *    ([OutboxRepository.processPending]).
 * 2. **Pull**: fetches changed records per collection since the last pull
 *    cursor and upserts them into Room by `local_uuid` (last-write-wins by
 *    `last_modified`).
 *
 * Exposes a [SyncUiState] stream the Settings/Dashboard screens can collect.
 */
@Singleton
class SyncManager @Inject constructor(
    private val outboxRepository: OutboxRepository,
    private val syncService: CloudflareSyncService,
    private val preferences: SyncPreferences,
    private val roomsDao: RoomsDao,
    private val bookingsDao: BookingsDao,
    private val paymentsDao: PaymentsDao,
    private val expensesDao: ExpensesDao,
    private val employeesDao: EmployeesDao,
    private val debtsDao: DebtsDao
) {
    companion object {
        private const val PULL_BATCH_SIZE = 200
        private val PULL_COLLECTIONS = listOf(
            "rooms", "bookings", "payments", "expenses", "employees", "debts"
        )
    }

    data class SyncUiState(
        val isSyncing: Boolean = false,
        val lastSyncAt: Long = 0,
        val lastMessage: String = "",
        val isError: Boolean = false,
        val pushedCount: Int = 0,
        val pulledCount: Int = 0
    )

    private val gson = Gson()

    private val _syncState = MutableStateFlow(SyncUiState())
    val syncState: StateFlow<SyncUiState> = _syncState.asStateFlow()

    fun pendingCount(): Flow<Int> = outboxRepository.pendingCount()

    /**
     * Runs a full sync cycle: push local changes, then pull remote deltas.
     * Safe to call repeatedly; concurrent calls are serialized by the
     * isSyncing flag (callers should check it, best-effort).
     */
    suspend fun syncNow(): SyncUiState {
        if (_syncState.value.isSyncing) return _syncState.value
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ الدفع...")

        // ---- Phase 1: push -------------------------------------------------
        val pushed = try {
            outboxRepository.processPending() + outboxRepository.syncOutbox()
        } catch (e: Exception) {
            finishWithError("فشل الدفع: ${e.message}")
            return _syncState.value
        }
        preferences.saveLastPushTs(System.currentTimeMillis())

        // ---- Phase 2: pull -------------------------------------------------
        _syncState.value = _syncState.value.copy(lastMessage = "جارٍ السحب...", pushedCount = pushed)
        var pulled = 0
        try {
            for (collection in PULL_COLLECTIONS) {
                pulled += pullCollection(collection)
            }
        } catch (e: Exception) {
            finishWithError("فشل السحب: ${e.message}")
            return _syncState.value
        }
        preferences.saveLastPullTs(System.currentTimeMillis())
        preferences.setFullSyncComplete(true)

        _syncState.value = _syncState.value.copy(
            isSyncing = false,
            lastSyncAt = System.currentTimeMillis(),
            lastMessage = "تمت المزامنة: دُفع $pushed، سُحب $pulled",
            pulledCount = pulled
        )
        return _syncState.value
    }

    /**
     * Silent pull-only cycle — the Kotlin counterpart of the Flutter
     * dashboard's `_runRobustSilentPull` (`sync(push: false, deltaOnly: true,
     * forcePull: true)`): the push side is covered by the outbox watcher, so
     * opening the Dashboard only pulls remote deltas.
     *
     * @return the number of records pulled, or -1 when the cycle failed.
     */
    suspend fun pullOnly(): Int {
        if (_syncState.value.isSyncing) return -1
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ السحب...")
        var pulled = 0
        try {
            for (collection in PULL_COLLECTIONS) {
                pulled += pullCollection(collection)
            }
        } catch (e: Exception) {
            finishWithError("فشل السحب: ${e.message}")
            return -1
        }
        preferences.saveLastPullTs(System.currentTimeMillis())
        _syncState.value = _syncState.value.copy(
            isSyncing = false,
            lastSyncAt = System.currentTimeMillis(),
            lastMessage = "تم سحب $pulled سجل",
            pulledCount = pulled
        )
        return pulled
    }

    private suspend fun pullCollection(collection: String): Int {
        var ingested = 0
        var cursor: Long = 0 // full delta pull each cycle; cursors tracked globally by timestamps
        var hasMore = true

        while (hasMore) {
            val result = syncService.pull(collection, cursor, PULL_BATCH_SIZE)
            val response = result.getOrNull() ?: run {
                result.exceptionOrNull()?.let { throw it }
                return ingested
            }
            val records = response.records.orEmpty()
            for (record in records) {
                ingestRecord(collection, record)
                ingested++
            }
            val next = response.nextCursor
            hasMore = records.size >= PULL_BATCH_SIZE && next != null && next > cursor
            if (next != null) cursor = next
        }
        return ingested
    }

    /** Upserts one remote record by local_uuid (last-write-wins). */
    private suspend fun ingestRecord(collection: String, record: Map<String, Any>) {
        val json = gson.toJson(record)
        val remoteLastModified = (record["last_modified"] as? Number)?.toLong() ?: 0L

        when (collection) {
            "rooms" -> {
                val remote = gson.fromJson(json, RoomEntity::class.java)
                val existing = roomsDao.getByLocalUuid(remote.localUuid)
                if (existing == null) roomsDao.insert(remote)
                else if (remoteLastModified >= existing.lastModified) roomsDao.insert(remote.copy(id = existing.id))
            }
            "bookings" -> {
                val remote = gson.fromJson(json, BookingEntity::class.java)
                val existing = bookingsDao.getByLocalUuid(remote.localUuid)
                if (existing == null) bookingsDao.insert(remote)
                else if (remoteLastModified >= existing.lastModified) bookingsDao.insert(remote.copy(id = existing.id))
            }
            "payments" -> {
                val remote = gson.fromJson(json, PaymentEntity::class.java)
                val existing = paymentsDao.getByLocalUuid(remote.localUuid)
                if (existing == null) paymentsDao.insert(remote)
                else if (remoteLastModified >= existing.lastModified) paymentsDao.insert(remote.copy(id = existing.id))
            }
            "expenses" -> {
                val remote = gson.fromJson(json, ExpenseEntity::class.java)
                val existing = expensesDao.getByLocalUuid(remote.localUuid)
                if (existing == null) expensesDao.insert(remote)
                else if (remoteLastModified >= existing.lastModified) expensesDao.insert(remote.copy(id = existing.id))
            }
            "employees" -> {
                val remote = gson.fromJson(json, EmployeeEntity::class.java)
                val existing = employeesDao.getByLocalUuid(remote.localUuid)
                if (existing == null) employeesDao.insert(remote)
                else if (remoteLastModified >= existing.lastModified) employeesDao.insert(remote.copy(id = existing.id))
            }
            "debts" -> {
                val remote = gson.fromJson(json, DebtEntity::class.java)
                val existing = debtsDao.getByLocalUuid(remote.localUuid)
                if (existing == null) debtsDao.insert(remote)
                else if (remoteLastModified >= existing.lastModified) debtsDao.insert(remote.copy(id = existing.id))
            }
        }
    }

    private fun finishWithError(message: String) {
        _syncState.value = _syncState.value.copy(
            isSyncing = false,
            isError = true,
            lastMessage = message,
            lastSyncAt = System.currentTimeMillis()
        )
    }
}
