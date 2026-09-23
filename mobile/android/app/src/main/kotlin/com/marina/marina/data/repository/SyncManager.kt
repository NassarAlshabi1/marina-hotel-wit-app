package com.marina.marina.data.repository

import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.domain.model.SyncUiState
import com.marina.marina.domain.repository.SyncRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Unified sync orchestrator — the Kotlin counterpart of the Flutter app's
 * `CloudflareSyncManager` (simplified single-engine version).
 *
 * ✅ (2026-09-24) أُعيدت كتابة دورة السحب على عقد الـ worker الحقيقي:
 *
 * 1. **Login (lazy)**: [CloudflareSyncService.ensureLoggedIn] يضمن JWT
 *    خادمياً قبل أي شيء (admin/admin افتراضياً — دخول تلقائي).
 * 2. **Push**: drains the local outbox in native worker batches
 *    ([OutboxRepository.processPending] — ≤100 عملية/نداء).
 * 3. **Pull**: `GET /api/sync/pull?cursor&limit&exclude_device` — دلتا
 *    عبر كل الجداول دفعة واحدة؛ كل سجل يُوجَّه عبر `_entity` إلى جدوله
 *    المحلي ([SyncIngestorRegistry]). المؤشر المرجع هو مؤشر الخادم
 *    (updated_at) ويُحفظ عبر الجلسات — **لا يتقدم إلا عند دورة نظيفة**
 *    (errors فارغة — عقد PullResult في worker/src/database.ts).
 * 4. **Echo filter**: exclude_device يستثني سجلات هذا الجهاز (خطة 2.5).
 *
 * Exposes a [SyncUiState] stream the Settings/Dashboard screens can collect.
 */
@Singleton
class SyncManager @Inject constructor(
    private val outboxRepository: OutboxRepository,
    private val syncService: CloudflareSyncService,
    private val preferences: SyncPreferences,
    private val ingestorRegistry: SyncIngestorRegistry
) : SyncRepository {

    private val _syncState = MutableStateFlow(SyncUiState())
    override val syncState: StateFlow<SyncUiState> = _syncState.asStateFlow()

    override fun pendingCount(): Flow<Int> = outboxRepository.pendingCount()

    /**
     * Runs a full sync cycle: ensure login, push local changes, then pull
     * remote deltas. Safe to call repeatedly; concurrent calls are serialized
     * by the isSyncing flag (callers should check it, best-effort).
     */
    override suspend fun syncNow(): SyncUiState {
        if (_syncState.value.isSyncing) return _syncState.value
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ الدخول...")

        // ---- Phase 0: lazy login (admin/admin default — auto-login) ----
        if (!syncService.ensureLoggedIn()) {
            finishWithError("فشل تسجيل الدخول إلى الخادم — تحقق من الشبكة")
            return _syncState.value
        }

        // ---- Phase 1: push -------------------------------------------------
        _syncState.value = _syncState.value.copy(lastMessage = "جارٍ الدفع...")
        val pushed = try {
            outboxRepository.processPending() + outboxRepository.syncOutbox()
        } catch (e: Exception) {
            finishWithError("فشل الدفع: ${e.message}")
            return _syncState.value
        }
        preferences.saveLastPushTs(System.currentTimeMillis())

        // ---- Phase 2: pull -------------------------------------------------
        _syncState.value = _syncState.value.copy(lastMessage = "جارٍ السحب...", pushedCount = pushed)
        val pulled = try {
            pullDelta()
        } catch (e: Exception) {
            finishWithError("فشل السحب: ${e.message}")
            return _syncState.value
        }
        if (pulled < 0) {
            finishWithError("فشل السحب: جداول فاشلة على الخادم — لم يتقدم المؤشر")
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
    override suspend fun pullOnly(): Int {
        if (_syncState.value.isSyncing) return -1
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ السحب...")
        if (!syncService.ensureLoggedIn()) {
            finishWithError("فشل تسجيل الدخول إلى الخادم")
            return -1
        }
        val pulled = try {
            pullDelta()
        } catch (e: Exception) {
            finishWithError("فشل السحب: ${e.message}")
            return -1
        }
        if (pulled < 0) {
            finishWithError("فشل السحب: جداول فاشلة على الخادم")
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

    /**
     * دلتا واحدة بمؤشر الخادم المحفوظ: صفحات [CloudflareConfig.DELTA_PULL_BATCH_SIZE]
     * حتى has_more=false. المؤشر لا يتقدم إلا بعد استيعاب كل الصفحات بنجاح
     * ودون errors خادمية (عقد PullResult: جداول فاشلة = دورة فاشلة).
     *
     * @return عدد السجلات المستوعبة، أو -1 عند الفشل.
     */
    private suspend fun pullDelta(): Int {
        val deviceId = preferences.getDeviceId()
        var cursor = preferences.getLastPullCursor()
        var ingested = 0

        while (true) {
            val result = syncService.pull(
                cursor = cursor,
                limit = CloudflareConfig.DELTA_PULL_BATCH_SIZE,
                excludeDevice = deviceId?.takeIf { it.isNotBlank() }
            )
            val response = result.getOrNull() ?: run {
                throw result.exceptionOrNull() ?: Exception("empty pull response")
            }

            // جداول فاشلة على الخادم (schema drift عادةً) — لا نقدّم المؤشر؛
            // إصلاح D1 وإعادة المحاولة تُكمّل الصفوف (عقد worker).
            if (!response.errors.isNullOrEmpty()) {
                return -1
            }

            val changes = response.changes.orEmpty()
            changes.forEach { record ->
                ingestorRegistry.ingest(record)
                ingested++
            }

            val nextCursor = response.cursor?.toLongOrNull()
            val hasMore = response.hasMore == true && nextCursor != null && nextCursor > cursor
            if (!hasMore) break
            cursor = nextCursor!!
        }

        // دورة نظيفة كاملة — الآن فقط نقدّم نقطة التفتيش المحفوظة.
        preferences.saveLastPullCursor(cursor)
        return ingested
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
