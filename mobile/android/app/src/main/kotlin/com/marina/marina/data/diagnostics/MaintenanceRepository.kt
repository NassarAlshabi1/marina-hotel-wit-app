package com.marina.marina.data.diagnostics

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.MaintenanceCounts
import com.marina.marina.data.local.dao.MaintenanceSalaryTotals
import com.marina.marina.data.local.dao.MaintenanceQuarantineRow
import com.marina.marina.data.local.dao.MaintenanceIntegrity
import com.marina.marina.data.local.dao.QuarantineDetail
import com.marina.marina.data.local.entity.AutoFixRunEntity
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class MaintenanceReport(
    val schemaVersion: Int,
    val capturedAt: Long,
    val counts: MaintenanceCounts,
    val salary: MaintenanceSalaryTotals,
    val rows: List<MaintenanceQuarantineRow>,
    val page: Long,
    val filteredCount: Long = counts.quarantined,
    val entities: List<String> = emptyList(),
    val integrity: MaintenanceIntegrity? = null,
    val history: List<AutoFixRunEntity> = emptyList(),
    val historyPage: Long = 0, val historyCount: Long = 0
) {
    val hasNext: Boolean get() = (page + 1) * MaintenanceRepository.PAGE_SIZE < filteredCount
}

/** Local SELECTs only; no network, repair, outbox changes, deletion or payload loading. */
@Singleton
class MaintenanceRepository @Inject constructor(private val db: AppDatabase) {
    suspend fun read(requestedPage: Long = 0, search: String = "", entity: String? = null, requestedHistoryPage: Long = 0): MaintenanceReport = withContext(Dispatchers.IO) {
        db.withTransaction {
            val dao = db.maintenanceDao()
            val counts = dao.counts()
            val filtered = dao.filteredCount(search.take(120), entity)
            val lastPage = ((filtered - 1).coerceAtLeast(0)) / PAGE_SIZE
            val page = requestedPage.coerceIn(0, lastPage)
            val historyCount = dao.repairHistoryCount()
            val historyPage = requestedHistoryPage.coerceIn(0, (historyCount - 1).coerceAtLeast(0) / 20)
            MaintenanceReport(
                schemaVersion = db.openHelper.readableDatabase.version,
                capturedAt = System.currentTimeMillis(),
                counts = counts,
                salary = dao.salaryTotals(),
                rows = dao.filteredPage(search.take(120), entity, PAGE_SIZE, page * PAGE_SIZE),
                page = page, filteredCount = filtered, entities = dao.quarantineEntities(),
                integrity = dao.integrity(), history = dao.repairHistory(20, historyPage * 20),
                historyPage = historyPage, historyCount = historyCount
            )
        }
    }

    suspend fun detail(entity: String, key: String): QuarantineDetail? =
        withContext(Dispatchers.IO) { db.maintenanceDao().quarantineDetail(entity, key) }

    suspend fun quickCheck(): Boolean = withContext(Dispatchers.IO) {
        db.openHelper.readableDatabase.query("PRAGMA quick_check(1)").use { cursor ->
            cursor.moveToFirst() && cursor.getString(0) == "ok" && !cursor.moveToNext()
        }
    }

    companion object { const val PAGE_SIZE = 50 }
}
