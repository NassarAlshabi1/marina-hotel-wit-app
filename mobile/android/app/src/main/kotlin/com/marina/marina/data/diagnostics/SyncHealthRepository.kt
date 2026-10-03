package com.marina.marina.data.diagnostics

import androidx.room.withTransaction
import com.marina.marina.data.local.AppDatabase
import javax.inject.Inject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class SyncHealthLevel(val label: String) {
    HEALTHY("سليم محلياً"), OK("تغييرات بانتظار المزامنة"), WARNING("تحذير"), ERROR("خطأ"), CRITICAL("حرج")
}

data class SyncHealthReport(
    val pending: Long, val processing: Long, val failed: Long, val completed: Long,
    val stuck: Long, val oldestAgeMs: Long?, val entities: Map<String, Long>,
    val tables: Map<String, Long>, val fkViolations: Long, val timestamp: Long
) {
    val level: SyncHealthLevel get() = when {
        fkViolations > 0 || stuck > 10 -> SyncHealthLevel.CRITICAL
        failed > 20 || (oldestAgeMs ?: 0) > 600_000L -> SyncHealthLevel.ERROR
        failed > 5 || pending > 100 || stuck > 0 -> SyncHealthLevel.WARNING
        pending == 0L && failed == 0L && processing == 0L -> SyncHealthLevel.HEALTHY
        else -> SyncHealthLevel.OK
    }
}

/** Read-only aggregate snapshot. No payloads, credentials, network requests or repairs. */
class SyncHealthRepository @Inject constructor(private val db: AppDatabase) {
    suspend fun read(now: Long = System.currentTimeMillis()): SyncHealthReport = withContext(Dispatchers.IO) {
        db.withTransaction {
            val sql = db.openHelper.readableDatabase
            // Delivery acknowledgement takes priority over legacy status fields.
            val status = """CASE WHEN delivered_to_primary = 1 THEN 'completed'
                WHEN processing_status = 'failed' OR primary_processing_status = 'failed' THEN 'failed'
                WHEN processing_status = 'processing' OR primary_processing_status = 'processing' THEN 'processing'
                ELSE 'pending' END"""
            val counts = mutableMapOf<String, Long>()
            sql.query("SELECT $status AS phase, COUNT(*) FROM outbox WHERE source = 'local' GROUP BY phase").use {
                while (it.moveToNext()) counts[it.getString(0)] = it.getLong(1)
            }
            fun epoch(column: String) = "CASE WHEN $column < 100000000000 THEN $column * 1000 ELSE $column END"
            val oldest = sql.query("SELECT MIN(${epoch("client_ts")}) FROM outbox WHERE source='local' AND delivered_to_primary=0 AND client_ts>0").use {
                it.moveToFirst(); if (it.isNull(0)) null else it.getLong(0)
            }
            val stuck = sql.query("""SELECT COUNT(*) FROM outbox WHERE source='local' AND delivered_to_primary=0
                AND (processing_status='processing' OR primary_processing_status='processing')
                AND processing_started_at>0 AND ${epoch("processing_started_at")} < ?""", arrayOf<Any>(now - 300_000L)).use {
                it.moveToFirst(); it.getLong(0)
            }
            val entities = linkedMapOf<String, Long>()
            sql.query("SELECT entity, COUNT(*) FROM outbox WHERE source='local' AND delivered_to_primary=0 GROUP BY entity ORDER BY COUNT(*) DESC").use {
                while (it.moveToNext()) entities[it.getString(0)] = it.getLong(1)
            }
            val tables = listOf("rooms", "bookings", "payments", "expenses", "debts", "employees", "salary_withdrawals", "inventory_items").associateWith { table ->
                // Identifiers are from this fixed whitelist, never user input.
                sql.query("SELECT COUNT(*) FROM `$table`").use { it.moveToFirst(); it.getLong(0) }
            }
            val fkCount = sql.query("PRAGMA foreign_key_check").use { cursor ->
                var count = 0L
                while (cursor.moveToNext()) count++
                count
            }
            SyncHealthReport(counts["pending"] ?: 0, counts["processing"] ?: 0,
                counts["failed"] ?: 0, counts["completed"] ?: 0, stuck,
                oldest?.let { (now - it).coerceAtLeast(0) }, entities, tables, fkCount, now)
        }
    }
}
