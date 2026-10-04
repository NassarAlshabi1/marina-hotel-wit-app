package com.marina.marina.data.repository

import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.sync.SyncEpochPolicy
import com.marina.marina.data.sync.SyncOperationRunner
import com.marina.marina.domain.model.SyncUiState
import com.marina.marina.domain.repository.SyncRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

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
 *    (updated_at)، ويُتحقق من رتابته ولا يُحفظ إلا بعد دورة نظيفة.
 * 4. **Epoch**: جيل D1 يكتشف الاستعادة/إعادة الاستيراد؛ الصفحة القديمة
 *    تُهمَل ويُعاد السحب من الصفر مرة واحدة، مع دعم Worker أقدم بلا epoch.
 * 5. **Echo filter**: exclude_device يستثني سجلات هذا الجهاز (خطة 2.5).
 *
 * Exposes a [SyncUiState] stream the Settings/Dashboard screens can collect.
 */
@Singleton
class SyncManager @Inject constructor(
    private val outboxRepository: OutboxRepository,
    private val syncService: CloudflareSyncService,
    private val preferences: SyncPreferences,
    private val ingestorRegistry: SyncIngestorRegistry,
    private val operationRunner: SyncOperationRunner
) : SyncRepository {

    private val _syncState = MutableStateFlow(SyncUiState())
    override val syncState: StateFlow<SyncUiState> = _syncState.asStateFlow()

    override suspend fun syncNow(): SyncUiState = runOwned(
        onBusy = {
            _syncState.value.copy(isSyncing = true, isError = true, lastMessage = "توجد مزامنة جارية حالياً")
        }
    ) { performSyncNow() }

    override suspend fun pullOnly(): Int = runOwned(onBusy = { -1 }) { performPullOnly() }

    override suspend fun pushOnly(): Int = runOwned(onBusy = { -1 }) { performPushOnly() }

    override suspend fun fullPull(): Int = runOwned(onBusy = { -1 }) { performFullPull() }

    private suspend fun <T> runOwned(onBusy: () -> T, operation: suspend () -> T): T =
        operationRunner.runIfIdle(
            onBusy = onBusy,
            onAccepted = {
                _syncState.update {
                    it.copy(isSyncing = true, isError = false, lastMessage = "جارٍ بدء المزامنة...",
                        pushedCount = 0, pulledCount = 0)
                }
            },
            onFinished = { cause ->
                _syncState.update {
                    if (cause != null && !it.isError) {
                        it.copy(isSyncing = false, isError = true, lastMessage = "توقفت المزامنة قبل اكتمالها")
                    } else {
                        it.copy(isSyncing = false)
                    }
                }
            },
            operation = operation
        )

    override fun pendingCount(): Flow<Int> = outboxRepository.pendingCount()
    override fun undeliveredCount(): Flow<Int> = outboxRepository.undeliveredCount()

    /**
     * Runs a full sync cycle: ensure login, push local changes, then pull
     * remote deltas. Safe to call repeatedly; overlapping requests are rejected
     * atomically by SyncOperationRunner, independent of the caller lifecycle.
     */
    private suspend fun performSyncNow(): SyncUiState {
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ الدخول...")

        // ---- Phase 0: lazy login (admin/admin default — auto-login) ----
        if (!syncService.ensureLoggedIn()) {
            finishWithError("فشل تسجيل الدخول إلى الخادم — تحقق من الشبكة", operation = "login")
            return _syncState.value
        }

        // ---- Phase 1: push -------------------------------------------------
        _syncState.value = _syncState.value.copy(lastMessage = "جارٍ الدفع...")
        val pushed = try {
            outboxRepository.processPending() + outboxRepository.syncOutbox()
        } catch (e: Exception) {
            finishWithError("فشل الدفع: ${e.message}", operation = "push")
            return _syncState.value
        }
        preferences.saveLastPushTs(System.currentTimeMillis())

        // ---- Phase 2: pull -------------------------------------------------
        _syncState.value = _syncState.value.copy(lastMessage = "جارٍ السحب...", pushedCount = pushed)
        val pulled = try {
            pullDelta()
        } catch (e: Exception) {
            finishWithError("فشل السحب: ${e.message}", operation = "pull_delta")
            return _syncState.value
        }
        if (pulled < 0) {
            finishWithError("فشل السحب: جداول فاشلة على الخادم — لم يتقدم المؤشر", operation = "pull_delta")
            return _syncState.value
        }
        preferences.saveLastPullTs(System.currentTimeMillis())

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
    private suspend fun performPullOnly(): Int {
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ السحب...")
        if (!syncService.ensureLoggedIn()) {
            finishWithError("فشل تسجيل الدخول إلى الخادم", operation = "login")
            return -1
        }
        val pulled = try {
            pullDelta()
        } catch (e: Exception) {
            finishWithError("فشل السحب: ${e.message}", operation = "pull_delta")
            return -1
        }
        if (pulled < 0) {
            finishWithError("فشل السحب: جداول فاشلة على الخادم", operation = "pull_delta")
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
     * ✅ (2026-09-24) «رفع التغييرات المحلية» — نقل _runPushNow من
     * unified_sync_settings_screen.dart: رفع فقط بدون سحب — يفرّغ outbox
     * إلى السيرفر بلا أي سحب (فصل الرفع عن السحب الكامل — طلب المستخدم).
     *
     * @return عدد الصفوف المرفوعة بنجاح، أو -1 عند الفشل.
     */
    private suspend fun performPushOnly(): Int {
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ الرفع...")
        if (!syncService.ensureLoggedIn()) {
            finishWithError("فشل تسجيل الدخول إلى الخادم", operation = "login")
            return -1
        }
        val pushed = try {
            outboxRepository.processPending() + outboxRepository.syncOutbox()
        } catch (e: Exception) {
            finishWithError("فشل الرفع: ${e.message}", operation = "push")
            return -1
        }
        preferences.saveLastPushTs(System.currentTimeMillis())
        _syncState.value = _syncState.value.copy(
            isSyncing = false,
            lastSyncAt = System.currentTimeMillis(),
            lastMessage = "تم رفع $pushed سجل",
            pushedCount = pushed
        )
        return pushed
    }

    /**
     * ✅ (2026-09-25) «السحب الكامل من السيرفر» — نقل _runFullSync من
     * unified_sync_settings_screen.dart: fullSync(push: false) — تصفير
     * مؤشر السحب + سحب كل البيانات من الصفر بصفحات أكبر وأسرع
     * ([CloudflareConfig.FULL_PULL_BATCH_SIZE]) — **سحب فقط بدون أي رفع**
     * (فصل صريح عن زر الرفع بناء على طلب المستخدم 2026-09-09).
     *
     * ✅ (2026-09-25) العقد الدارتي الحاسم: السحب الكامل **لا يمرر
     * exclude_device إطلاقاً** (excludeOwnDevice: !wasFullSync) — يجب أن
     * يشمل صفوف الجهاز نفسه كي يتعلم ظلّ server_id لصفوفه هو (إصلاح
     * «107 سجلاً بعلاقات أب غير محلولة»). بدون هذا، جهاز دفع بياناته
     * إلى D1 يسحبها **صفراً** — العلة الجذرية لـ«السحب الكامل لا يعمل».
     *
     * @return عدد السجلات المسحوبة، أو -1 عند الفشل.
     */
    private suspend fun performFullPull(): Int {
        _syncState.value = _syncState.value.copy(isSyncing = true, isError = false, lastMessage = "جارٍ السحب الكامل...")
        if (!syncService.ensureLoggedIn()) {
            finishWithError("فشل تسجيل الدخول إلى الخادم", operation = "login")
            return -1
        }
        // 1) إعادة ضبط مؤشر السحب — الجلب يبدأ من الصفر.
        preferences.setFullReplayPending(true)
        preferences.saveLastPullCursor(0L)
        val pulled = try {
            pullDelta(batchSize = CloudflareConfig.FULL_PULL_BATCH_SIZE, isFullPull = true)
        } catch (e: Exception) {
            finishWithError("فشل السحب الكامل: ${e.message}", operation = "pull_full")
            return -1
        }
        if (pulled < 0) {
            finishWithError("فشل السحب الكامل: جداول فاشلة على الخادم", operation = "pull_full")
            return -1
        }
        preferences.saveLastPullTs(System.currentTimeMillis())
        _syncState.value = _syncState.value.copy(
            isSyncing = false,
            lastSyncAt = System.currentTimeMillis(),
            lastMessage = if (preferences.isFullReplayPending()) "سُحب $pulled سجل؛ ستُستكمل بقية الصفحات في الدورة القادمة"
                else "اكتمل السحب الكامل: $pulled سجل (بدون رفع)",
            pulledCount = pulled
        )
        return pulled
    }

    companion object {
        /**
         * ✅ (2026-09-25) سقف الصفحات في الدورة الواحدة (H2 في Dart = 100):
         * كاتب ساخن بلا توقف يجب ألا يحبس الدورة — خروج نظيف جزئي
         * والمؤشر تقدم عبر ما طُبّق بسلامة، والبقية تُستأنف تلقائياً.
         */
        private const val MAX_PULL_PAGES_PER_CYCLE = 100

        /** ✅ معاينة remaining الخادمية كل 5 صفحات (Dart 2026-09-22 — تخفيف الحمل ~80%). */
        private const val REMAINING_SAMPLE_EVERY_PAGES = 5
    }

    /**
     * ✅ (2026-09-25) أُعيدت كتابتها على العقد الدارتي الكامل:
     *
     *  • **السحب الكامل بلا فلتر صدى** ([isFullPull] → بلا exclude_device):
     *    الجهاز يتعلم ظلّ server_id لصفوفه هو — الدلتا تستمر باستبعاده.
     *  • **تطبيق الصفحة داخل معاملة** عبر [SyncIngestorRegistry.ingestPage]
     *    مع ترجمة FK وتعلّم الظل والدمج الطبيعي (تفاصيل السجل هناك).
     *  • **فشل تطبيق حقيقي (SQL) = دورة فاشلة** — المؤشر لا يتقدم إطلاقاً
     *    (عقد «لا نجاح مع جداول ناقصة» 2026-09-08).
     *  • **المؤجلون علاقياً** (أب لم يصل بعد) يُعادون بعد اكتمال الصفحات؛
     *    ما بقي غير محلول لا يفشل الدورة — المؤشر يتقدم (عقد 2026-09-15
     *    ضد تجميد المؤشر) ويُستكمل في السحب الكامل القادم.
     *  • **سقف صفحات** [MAX_PULL_PAGES_PER_CYCLE] — خروج نظيف جزئي.
     *  • **تقدم حي** لكل صفحة في lastMessage (+ المتبقي الخادمي للسحب
     *    الكامل كل 5 صفحات) — لا مزيد «يبدو معلقاً».
     *  • **تطبيع الطوابع** normalize_timestamps في أول صفحة سحب كامل
     *    مرة واحدة (شفاء خادمي لطوابع المللي القديمة).
     *
     * @param batchSize حجم الصفحة — دلتا [CloudflareConfig.DELTA_PULL_BATCH_SIZE]
     *   أو سحب كامل [CloudflareConfig.FULL_PULL_BATCH_SIZE].
     * @param isFullPull true للسحب الكامل: بلا فلتر صدى + remaining + تطبيع.
     * @return عدد السجلات المستوعبة، أو -1 عند الفشل الخادمي.
     * @throws Exception فشل شبكة أو فشل تطبيق — المؤشر لا يتقدم (المستدعي
     *   يلتقط ويعرض الخطأ؛ نقطة التفتيش المحفوظة تبقى كما هي).
     */
    private suspend fun pullDelta(
        batchSize: Int = CloudflareConfig.DELTA_PULL_BATCH_SIZE,
        isFullPull: Boolean = false,
        allowEpochRestart: Boolean = true
    ): Int {
        val deviceId = preferences.getDeviceId()
        var cursor = preferences.getLastPullCursor()
        val fullReplay = isFullPull || cursor == 0L || preferences.isFullReplayPending()
        if (fullReplay) preferences.setFullReplayPending(true)
        var reachedEnd = false
        var ingested = 0
        var pagesDone = 0
        var epochReset = false

        while (true) {
            // سقف الصفحات (H2) — خروج نظيف والبقية دورة قادمة.
            if (pagesDone >= MAX_PULL_PAGES_PER_CYCLE) break

            val includeRemaining = fullReplay &&
                pagesDone % REMAINING_SAMPLE_EVERY_PAGES == 0
            val normalizeTimestamps = pagesDone == 0 && fullReplay &&
                !preferences.isTimestampNormalizationDone()
            // ⚠️ العقد الدارتي: السحب الكامل وحده يستثني فلتر الصدى —
            // excludeOwnDevice: !wasFullSync (Dart l.2063).
            val excludeDevice = deviceId
                ?.takeIf { it.isNotBlank() && !fullReplay }

            val result = syncService.pull(
                cursor = cursor,
                limit = batchSize,
                excludeDevice = excludeDevice,
                includeRemaining = includeRemaining,
                normalizeTimestamps = normalizeTimestamps
            )
            val response = result.getOrNull() ?: run {
                throw result.exceptionOrNull() ?: Exception("empty pull response")
            }

            // A page from a previous server generation is not safe to apply.
            // Adopt first observations silently; a changed epoch on a
            // non-zero checkpoint resets and replays the pull from zero.
            val epochDecision = SyncEpochPolicy.evaluate(
                storedEpoch = preferences.getSyncEpoch(),
                responseEpoch = response.epoch,
                pageBuiltFromZero = cursor == 0L && pagesDone == 0
            )
            if (epochDecision.restartFromZero) {
                preferences.setFullReplayPending(true)
                preferences.saveLastPullCursor(0L)
                preferences.setFullSyncComplete(false)
                ingestorRegistry.clearPendingLinksForEpochReset()
                epochReset = true
                _syncState.value = _syncState.value.copy(
                    lastMessage = "تغير جيل بيانات الخادم — إعادة السحب من البداية..."
                )
                break
            }

            epochDecision.epochToPersist?.let { epoch ->
                if (preferences.getSyncEpoch() != null) ingestorRegistry.clearPendingLinksForEpochReset()
                preferences.saveSyncEpoch(epoch)
            }

            // جداول فاشلة على الخادم (schema drift عادةً) — لا نقدّم المؤشر؛
            // إصلاح D1 وإعادة المحاولة تُكمّل الصفوف (عقد worker).
            if (!response.errors.isNullOrEmpty()) {
                val errorDetails = response.errors.orEmpty()
                    .take(10)
                    .joinToString("; ") { error ->
                        listOfNotNull(
                            error.entity?.takeIf { it.isNotBlank() }?.take(80),
                            error.error?.takeIf { it.isNotBlank() }?.take(300)
                        ).joinToString(": ")
                    }
                    .take(1_500)
                throw IllegalStateException(
                    if (errorDetails.isBlank()) "جداول فشلت على الخادم — لم يتقدم المؤشر"
                    else "جداول فشلت على الخادم — لم يتقدم المؤشر: $errorDetails"
                )
            }

            val nextCursor = response.cursor?.toLongOrNull()
                ?: throw Exception("Pull response is missing a valid cursor")
            val hasMore = response.hasMore
                ?: throw Exception("Pull response is missing has_more")
            if (nextCursor < cursor) {
                throw Exception("Pull cursor regressed from $cursor to $nextCursor")
            }
            val changes = response.changes.orEmpty()
            if (changes.isNotEmpty() && nextCursor <= cursor) {
                throw Exception("Pull returned records without advancing the cursor")
            }
            if (hasMore && nextCursor <= cursor) {
                throw Exception("Pull pagination stalled at cursor $cursor")
            }
            if (changes.isNotEmpty()) {
                val report = ingestorRegistry.ingestPage(changes)
                ingested += report.applied
                if (report.hasFailures) {
                    // فشل تطبيق فعلي — دورة فاشلة: المؤشر لا يتقدم
                    // (التراجع الكامل يضمن إعادة سحب ما بين الحدين).
                    throw Exception(
                        "فشل تطبيق ${report.failed} سجلاً: ${report.firstError ?: "غير معروف"}"
                    )
                }
            }
            if (normalizeTimestamps) preferences.setTimestampNormalizationDone(true)
            pagesDone++

            // تقدم حي — pulled تراكمي + remaining خادمي عند توفره.
            val remainingText = response.remaining?.let { " • المتبقي ${it.toLong()}" } ?: ""
            _syncState.value = _syncState.value.copy(
                lastMessage = "جارٍ السحب... $ingested$remainingText (صفحة $pagesDone)"
            )

            if (!hasMore) {
                reachedEnd = true
                cursor = nextCursor
                break
            }
            cursor = nextCursor
        }

        if (epochReset) {
            if (!allowEpochRestart) {
                // Keep the checkpoint at zero and report the repeated change;
                // the next scheduled cycle will retry without an unbounded loop.
                throw Exception("Sync epoch changed repeatedly during one pull cycle")
            }
            return ingested + pullDelta(
                batchSize = batchSize,
                isFullPull = true,
                allowEpochRestart = false
            )
        }

        // Every unresolved payload is already durable before advancing the checkpoint.
        // Retry on every cycle, including an empty delta after the parent arrived earlier.
        val retry = ingestorRegistry.retryPendingLinks()
        ingested += retry.applied
        if (retry.hasFailures) {
            throw Exception("فشل تطبيق سجل مؤجل: ${retry.firstError ?: "غير معروف"}")
        }

        // دورة نظيفة كاملة — الآن فقط نقدّم نقطة التفتيش المحفوظة.
        preferences.saveLastPullCursor(cursor)
        if (fullReplay && reachedEnd) {
            preferences.setFullReplayPending(false)
            preferences.setFullSyncComplete(true)
        }
        return ingested
    }

    private fun finishWithError(message: String, operation: String) {
        // Diagnostics must never mask the original sync failure if local storage fails.
        runCatching {
            preferences.recordSyncError(
                operation = operation,
                message = message,
                pullCursor = preferences.getLastPullCursor(),
                deviceId = preferences.getDeviceId()
            )
        }
        _syncState.value = _syncState.value.copy(
            isSyncing = false,
            isError = true,
            lastMessage = message,
            lastSyncAt = System.currentTimeMillis()
        )
    }
}
