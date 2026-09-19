package com.marina.marina.data.repository

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.marina.marina.data.local.dao.OutboxDao
import com.marina.marina.data.local.entity.OutboxEntity
import com.marina.marina.data.remote.CloudflareSyncService
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

/**
 * Sync-outbox queue. This is internal plumbing (not a business entity exposed
 * to the UI), so unlike the other repositories it has no domain-layer
 * interface/model — it works directly with [OutboxEntity].
 *
 * Every local write enqueues a row here; [processPending] drains the queue to
 * the Cloudflare worker (primary target) and [syncOutbox] handles the
 * secondary target. Rows are only cleaned up once delivered to BOTH targets.
 */
@Singleton
class OutboxRepository @Inject constructor(
    private val outboxDao: OutboxDao,
    private val syncService: CloudflareSyncService
) {
    companion object {
        private const val WORKER_NAME = "outbox-processor"
        private const val MAX_ATTEMPTS_BEFORE_BACKOFF = 5
    }

    private val gson = Gson()

    fun getPending(): Flow<List<OutboxEntity>> = outboxDao.getPendingPrimary()

    fun pendingCount(): Flow<Int> = outboxDao.pendingCount()

    suspend fun enqueue(entity: String, op: String, localUuid: String, payload: Map<String, Any>): Long {
        val outbox = OutboxEntity(
            entity = entity,
            op = op,
            localUuid = localUuid,
            payload = gson.toJson(payload),
            clientTs = System.currentTimeMillis(),
            idempotencyKey = "${entity}_${op}_${localUuid}"
        )
        return outboxDao.insert(outbox)
    }

    /** Generic helper: serializes any entity/model into an outbox payload. */
    suspend fun enqueueObject(entity: String, op: String, localUuid: String, payloadObject: Any): Long {
        val mapType = object : TypeToken<Map<String, Any>>() {}.type
        @Suppress("UNCHECKED_CAST")
        val payload = gson.fromJson<Map<String, Any>>(gson.toJson(payloadObject), mapType) ?: emptyMap()
        return enqueue(entity, op, localUuid, payload)
    }

    /**
     * Drains the pending-primary queue: pushes each row to the Cloudflare
     * worker and marks it delivered or failed. Failed rows stay queued for the
     * next pass (with attempt bookkeeping so callers can apply backoff).
     *
     * @return the number of rows successfully delivered in this pass.
     */
    suspend fun processPending(): Int {
        val pending = outboxDao.getPendingPrimary().first()
        var delivered = 0

        for (row in pending) {
            // Skip rows that already exhausted too many attempts this session
            // (they will be retried on a later explicit sync).
            if (row.attempts >= MAX_ATTEMPTS_BEFORE_BACKOFF) continue

            outboxDao.markProcessing(row.id, "processing", System.currentTimeMillis(), WORKER_NAME)

            val payload = decodePayload(row.payload)
            val result = syncService.push(
                entity = row.entity,
                op = row.op,
                localUuid = row.localUuid,
                payload = payload,
                clientTs = row.clientTs,
                idempotencyKey = row.idempotencyKey
            )

            result.fold(
                onSuccess = {
                    outboxDao.markDeliveredPrimary(row.id)
                    outboxDao.markProcessing(row.id, "completed", System.currentTimeMillis(), WORKER_NAME)
                    delivered++
                },
                onFailure = { error ->
                    outboxDao.markFailedPrimary(row.id, error.message ?: "unknown error")
                    outboxDao.markProcessing(row.id, "pending", System.currentTimeMillis(), WORKER_NAME)
                }
            )
        }

        // Fully delivered rows can finally leave the queue.
        outboxDao.cleanupDelivered()
        return delivered
    }

    /**
     * Same drain loop for the secondary delivery target. The scaffold marks
     * rows `delivered_to_secondary = 1` by default, so this is a no-op unless
     * a second backend is configured — kept for parity with the Flutter app's
     * dual-engine outbox.
     */
    suspend fun syncOutbox(): Int {
        val pending = outboxDao.getPendingSecondary().first()
        // No secondary backend is wired yet: acknowledge everything pending so
        // rows become cleanup-eligible instead of blocking forever.
        for (row in pending) {
            outboxDao.markDeliveredSecondary(row.id)
        }
        outboxDao.cleanupDelivered()
        return 0
    }

    private fun decodePayload(json: String): Map<String, Any> {
        if (json.isBlank()) return emptyMap()
        return try {
            val mapType = object : TypeToken<Map<String, Any>>() {}.type
            gson.fromJson(json, mapType) ?: emptyMap()
        } catch (_: Exception) {
            emptyMap()
        }
    }
}
