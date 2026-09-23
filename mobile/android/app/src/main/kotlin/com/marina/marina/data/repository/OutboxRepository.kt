package com.marina.marina.data.repository

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.marina.marina.data.local.dao.OutboxDao
import com.marina.marina.data.local.entity.OutboxEntity
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.PushWireContract
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerPushResult
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first

/**
 * Sync-outbox queue. This is internal plumbing (not a business entity exposed
 * to the UI), so unlike the other repositories it has no domain-layer
 * interface/model — it works directly with [OutboxEntity].
 *
 * ✅ (2026-09-24) أُعيدت كتابة الدفع على عقد الـ worker الحقيقي:
 *  • دفعة واحدة POST /api/sync/push {operations:[…]} بحد 100 عملية.
 *  • بناء العملية عبر [PushWireContract] (تكافؤ buildPushOperation في
 *    Flutter sync/payload_normalizer.dart — snake_case + bool→int +
 *    حقن local_uuid + vectorClock من الحمولة + insert→create).
 *  • تصنيف الرفض (fix M4): validation_error/conflict = فشل دائم →
 *    dead-letter (markFailedPrimary) بلا إعادة دفع أبدية؛ فشل الشبكة
 *    (P0-G) يعيد الصف pending للمحاولة القادمة.
 */
@Singleton
class OutboxRepository @Inject constructor(
    private val outboxDao: OutboxDao,
    private val syncService: CloudflareSyncService,
    private val preferences: SyncPreferences
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
     * Drains the pending-primary queue in worker-native batches: pushes up
     * to [CloudflareConfig.PUSH_BATCH_SIZE] operations per request and
     * reconciles every per-operation result. Network failures requeue the
     * rows as pending; permanent rejections (validation_error / conflict)
     * are dead-lettered so they never retry forever.
     *
     * @return the number of rows successfully delivered in this pass.
     */
    suspend fun processPending(): Int {
        val pending = outboxDao.getPendingPrimary().first()
            .filter { it.attempts < MAX_ATTEMPTS_BEFORE_BACKOFF }
        if (pending.isEmpty()) return 0

        // الدخول الكسول: أول دفعة تضمن توكن JWT خادمياً (admin/admin
        // افتراضياً من CloudflareConfig) — تكافؤ lazy init في Flutter.
        if (!syncService.ensureLoggedIn()) {
            // لا شبكة الآن — كل الصفوف تبقى pending للدورة القادمة.
            pending.forEach { row ->
                outboxDao.markProcessing(row.id, "pending", System.currentTimeMillis(), WORKER_NAME)
            }
            return 0
        }

        val deviceId = preferences.getDeviceId().orEmpty().ifEmpty { "unknown-origin" }
        var delivered = 0

        pending.chunked(CloudflareConfig.PUSH_BATCH_SIZE).forEach { batch ->
            // 1) حجز الصفوف (processing) قبل الإرسال — استرداد الانهيار
            //    يعيدها pending عند الإقلاع القادم (عقد P0-H في Flutter).
            batch.forEach { row ->
                outboxDao.markProcessing(row.id, "processing", System.currentTimeMillis(), WORKER_NAME)
            }

            val operations = batch.map { row -> PushWireContract.buildOperation(row, deviceId) }
            val response = syncService.push(operations)

            response.fold(
                onSuccess = { body ->
                    val byKey = body.results.orEmpty().associateBy { it.idempotencyKey.orEmpty() }
                    batch.forEachIndexed { index, row ->
                        val opResult = byKey[operations[index].idempotencyKey]
                            ?: body.results.orEmpty().getOrNull(index)
                        when {
                            opResult == null -> {
                                // الخادم لم يُرجع نتيجة للعملية — عوّدها pending.
                                outboxDao.markProcessing(row.id, "pending", System.currentTimeMillis(), WORKER_NAME)
                            }
                            opResult.success == true -> {
                                outboxDao.markDeliveredPrimary(row.id)
                                outboxDao.markProcessing(row.id, "completed", System.currentTimeMillis(), WORKER_NAME)
                                delivered++
                            }
                            isPermanentRejection(opResult) -> {
                                // fix M4: validation_error/conflict = رفض دائم
                                // (dead-letter) — إعادة الدفع بلا فائدة.
                                outboxDao.markFailedPrimary(
                                    row.id,
                                    "${opResult.status}: ${opResult.error ?: "rejected"}"
                                )
                                outboxDao.markProcessing(row.id, "completed", System.currentTimeMillis(), WORKER_NAME)
                            }
                            else -> {
                                // خطأ مؤقت (internal_error) — عوّدها pending.
                                outboxDao.markFailedPrimary(
                                    row.id,
                                    opResult.error ?: "temporary failure"
                                )
                                outboxDao.markProcessing(row.id, "pending", System.currentTimeMillis(), WORKER_NAME)
                            }
                        }
                    }
                },
                onFailure = { error ->
                    // ✅ P0-G: خطأ شبكة (DNS/timeout/socket) — ليس رفضاً.
                    // نُعيد الصفوف لحالة pending لإعادة المحاولة لاحقاً.
                    batch.forEach { row ->
                        outboxDao.markFailedPrimary(row.id, error.message ?: "network error")
                        outboxDao.markProcessing(row.id, "pending", System.currentTimeMillis(), WORKER_NAME)
                    }
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

    /** الرفض الدائم (dead-letter) — fix M4: يُعاد للمحاولة بلا فائدة. */
    private fun isPermanentRejection(result: WorkerPushResult): Boolean {
        return result.success != true &&
            (result.status == "validation_error" || result.status == "conflict")
    }
}
