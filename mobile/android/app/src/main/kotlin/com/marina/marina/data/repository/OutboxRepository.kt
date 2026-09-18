package com.marina.marina.data.repository

import com.google.gson.Gson
import com.marina.marina.data.local.dao.OutboxDao
import com.marina.marina.data.local.entity.OutboxEntity
import com.marina.marina.data.remote.CloudflareSyncService
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow

/**
 * Sync-outbox queue. This is internal plumbing (not a business entity exposed
 * to the UI), so unlike the other repositories it has no domain-layer
 * interface/model — it works directly with [OutboxEntity].
 */
@Singleton
class OutboxRepository @Inject constructor(
    private val outboxDao: OutboxDao,
    private val syncService: CloudflareSyncService
) {
    private val gson = Gson()

    fun getPending(): Flow<List<OutboxEntity>> = outboxDao.getPendingPrimary()

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

    suspend fun processPending() {
        // TODO: read getPendingPrimary(), call syncService.push() per row,
        // then markDeliveredPrimary()/markFailedPrimary() based on the result.
    }

    suspend fun syncOutbox() {
        // TODO: same as processPending() but for the secondary delivery target.
    }
}
