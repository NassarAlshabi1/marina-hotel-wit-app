package com.marina.marina.data.diagnostics

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import com.marina.marina.data.local.dao.MaintenanceCounts
import com.marina.marina.data.local.dao.MaintenanceSalaryTotals
import com.marina.marina.data.local.dao.MaintenanceQuarantineRow
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
    val page: Long
) {
    val hasNext: Boolean get() = (page + 1) * MaintenanceRepository.PAGE_SIZE < counts.quarantined
}

/** Local SELECTs only; no network, repair, outbox changes, deletion or payload loading. */
@Singleton
class MaintenanceRepository @Inject constructor(private val db: AppDatabase) {
    suspend fun read(requestedPage: Long = 0): MaintenanceReport = withContext(Dispatchers.IO) {
        db.withTransaction {
            val dao = db.maintenanceDao()
            val counts = dao.counts()
            val lastPage = ((counts.quarantined - 1).coerceAtLeast(0)) / PAGE_SIZE
            val page = requestedPage.coerceIn(0, lastPage)
            MaintenanceReport(
                schemaVersion = db.openHelper.readableDatabase.version,
                capturedAt = System.currentTimeMillis(),
                counts = counts,
                salary = dao.salaryTotals(),
                rows = dao.quarantinePage(PAGE_SIZE, page * PAGE_SIZE),
                page = page
            )
        }
    }

    companion object { const val PAGE_SIZE = 50 }
}
