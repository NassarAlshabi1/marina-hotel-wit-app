package com.marina.marina.data.repository

import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.sync.MAX_SANE_PULL_CURSOR_FUTURE
import com.marina.marina.data.sync.SyncEpochPolicy
import com.marina.marina.data.sync.SyncOperationRunner
import com.marina.marina.data.sync.evaluateStoredCursor
import com.marina.marina.data.sync.isPendingCursorSafeToInstall
import com.marina.marina.data.sync.isServerCursorRejected
import com.marina.marina.data.sync.tombstoneSweepDue
import com.marina.marina.domain.model.SyncUiState
import com.marina.marina.domain.repository.SyncRepository
import kotlinx.coroutines.CancellationException
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
    private val operationRunner: SyncOperationRunner,
    private val derivedRefresh: BookingDerivedRefreshService
) : SyncRepository {

    private val _syncState = MutableStateFlow(SyncUiState())
    override val syncState: StateFlow<SyncUiState> = _syncState.asStateFlow()

    override suspend fun syncNow(): SyncUiState = runOwned(
        onBusy = {
            _syncState.value.copy(isSyncing = true, isError = true, lastMessage = "توجد مزامنة جارية حالياً")
        },
        onFailure = { _syncState.value }
    ) { performSyncNow() }

    override suspend fun pullOnly(): Int = runOwned(onBusy = { -1 }) { performPullOnly() }

    /** Recheck under the shared operation lock, including after a concurrent manual pull. */
    suspend fun pullAutomaticallyIfDue(): Int = runOwned(onBusy = { -1 }) {
        if (!preferences.getCloudflareSyncEnabled() || !preferences.getAutoSyncEnabled() ||
            !com.marina.marina.data.sync.automaticPullDue(System.currentTimeMillis(), preferences.getLastPullTs())) {
            _syncState.update { it.copy(lastMessage = "لا حاجة إلى سحب تلقائي الآن") }
            0
        } else performPullOnly()
    }

    override suspend fun pushOnly(): Int = runOwned(onBusy = { -1 }) { performPushOnly() }

    override suspend fun fullPull(): Int = runOwned(onBusy = { -1 }) { performFullPull() }

    /**
     * سحب مُشغَّل بحدث Realtime/FCM — نظير `realtimeTriggeredPull` في
     * Flutter (cloudflare_sync_manager.dart l.4303):
     *
     *  • **دلتا فقط**: `push:false, deltaOnly:true` — الرفع الفوري مسؤولية
     *    مراقب outbox، ومسار الحدث لا يبدأ full sync ولا يرفع بيانات.
     *  • **يتخطى بصمت عند الانشغال**: مزامنة جارية = `false` بلا انتظار
     *    (المستدعي يجدول متابعة بعد التهدئة بدل تكديس دورات).
     *  • **يتجاوز بوابة الساعة عمداً**: الحدث دليل تغيير فعلي — نفس
     *    `forcePull:true` في Dart — فلا معنى لتأجيله ساعة كاملة.
     *
     * @return true إذا اكتملت دورة السحب فعلاً (>= 0 سجل)، وfalse عند
     *   الانشغال أو الفشل — عقد `RemoteChangePull` نفسه في Dart.
     */
    suspend fun pullOnRealtimeEvent(): Boolean {
        if (_syncState.value.isSyncing) return false
        val pulled = runCatching { pullOnly() }.getOrNull() ?: -1
        return pulled >= 0
    }

    /**
     * حارس الإقلاع ضد المؤشر المسموم (Dart l.553): مؤشر محفوظ فوق الحد
     * الثابت (ميلي ثانية/ sentinel) يُصفَّر مع علامة full sync ليعيد
     * الجهاز سحباً كاملاً نظيفاً. يعيد true عند حدوث إعادة تعيين.
     */
    suspend fun sanitizeStoredCursorIfNeeded(): Boolean {
        val stored = preferences.getLastPullCursor()
        if (!evaluateStoredCursor(stored).mustReset) return false
        preferences.resetPullCursorForFreshReplay()
        runCatching {
            preferences.recordSyncError(
                operation = "pull_cursor_poisoned",
                message = "مؤشر سحب مسموم ($stored) تجاوز الحد الآمن " +
                    "$MAX_SANE_PULL_CURSOR_FUTURE — صُفّر المؤشر وعلامة full sync لسحب كامل نظيف",
                pullCursor = 0L,
                deviceId = preferences.getDeviceId()
            )
        }
        _syncState.update {
            it.copy(lastMessage = "مؤشر السحب المحفوظ كان مسمّماً — أُعيد الضبط لسحب كامل نظيف")
        }
        return true
    }

    private suspend fun <T> runOwned(
        onBusy: () -> T,
        onFailure: () -> T = onBusy,
        operation: suspend () -> T
    ): T = try {
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
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        // In particular, an Android foreground-start restriction must not crash
        // screens that rely on the repository's error-state / -1 contract.
        onFailure()
    }

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
            // deltaOnly: زر اللوحة والسحب التلقائي وRealtime دلتا دائماً —
            // لا bootstrap صامت على مؤشر صفر (نظير Dart l.1850-1851:
            // «Full Sync عملية صريحة»).
            pullDelta(deltaOnly = true)
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

        /**
         * سقف صفحات مسح الحذفيات في الدورة الواحدة (فلسفة H2 نفسها):
         * مسح ضخم لا يجوز أن يحبس دورة السحب — البقية تُستأنف من مؤشر
         * المسح المحفوظ في الدورة القادمة (العلم لا يُضبط قبل الاكتمال).
         */
        private const val MAX_TOMBSTONE_SWEEP_PAGES_PER_CYCLE = 20
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
     * @param deltaOnly يمنع بدء bootstrap صامت على مؤشر صفر (نظير
     *   `deltaOnly` في Dart): سحب تفاضلي بفلتر الصدى دائماً، ولا يمس علم
     *   الـ bootstrap — إكماله من الإجراء الصريح [fullPull].
     * @return عدد السجلات المستوعبة، أو -1 عند الفشل الخادمي.
     * @throws Exception فشل شبكة، أو خطأ في عقد الصفحة (JSON/جداول خادمية)،
     *   أو تدوير epoch متكرر — المؤشر لا يتقدم (المستدعي يلتقط ويعرض الخطأ؛
     *   نقطة التفتيش المحفوظة تبقى كما هي). أما **فشل تطبيق صفٍّ بعينه**
     *   فلا يرمي: الصف يُعزل بحمولته والمؤشر يتقدم (نظير Dart).
     */
    private suspend fun pullDelta(
        batchSize: Int = CloudflareConfig.DELTA_PULL_BATCH_SIZE,
        isFullPull: Boolean = false,
        allowEpochRestart: Boolean = true,
        deltaOnly: Boolean = false
    ): Int {
        // حارس الإقلاع (Dart l.553) ثم مسح التقارب لمرة واحدة (Dart l.1794)
        // قبل أي صفحة — كلاهما لا يمسّ تدفق المؤشر الرئيسي عند الفشل.
        sanitizeStoredCursorIfNeeded()
        performTombstoneSweepIfDue()

        val deviceId = preferences.getDeviceId()
        var cursor = preferences.getLastPullCursor()
        // ✅ نظير Dart (cloudflare_sync_manager.dart l.1850-1851):
        // «Full Sync عملية صريحة» — سحب الدلتا لا يبدأ bootstrap صامتاً حتى
        // لو كان مؤشر هذا الجهاز صفراً؛ يبقى سحباً تفاضلياً بفلتر الصدى
        // (البيانات كلها تُسحب لأن المؤشر 0)، وإكمال الـ bootstrap مسؤولية
        // الإجراء الصريح fullPull(). الاستئناف المُعلَّم (تدوير epoch/
        // استعادة نسخة) لا يُلغى — العلم يعني «بدأناه ويجب إنهاؤه».
        val pendingReplay = preferences.isFullReplayPending()
        val fullReplay = isFullPull || pendingReplay || (!deltaOnly && cursor == 0L)
        if (fullReplay) preferences.setFullReplayPending(true)
        var reachedEnd = false
        var ingested = 0
        var pagesDone = 0
        var epochReset = false
        var repairRetries = 0
        // كيانات الصفوف المطبَّقة في هذه الدورة — تُقرأ منها الحقول المشتقة
        // للحجوزات بعد اكتمال الدورة (نظير pulledDerivedEntities في Dart).
        val pulledEntities = mutableSetOf<String>()
        // صفوف فشل التطبيق في هذه الدورة (تُحاسب مرة واحدة بعد الصفحات).
        val pageFailures = mutableListOf<com.marina.marina.data.repository.DeferredRecord>()

        // ✅ (2026-10-06) شفاء دوري من الحمولة المحفوظة — نظير
        // `collectHealCandidates()` في Dart (`pull_quarantine.dart`): كل دورة
        // تُعيد تطبيق ما عُزل سابقاً من حمولته الكاملة بلا إعادة سحب أي صفحة.
        // سبب العزل قد يزول: وصول الأب، أو إصلاح قيمة على الخادم، أو ترقية
        // التطبيق نفسها (أعمدة/تحويلات كانت ناقصة) — فينجو الصف بلا انتظار
        // إعادة بثّه من الخادم.
        val healed = runCatching { ingestorRegistry.healQuarantinedBatch() }.getOrNull()
        pulledEntities += healed?.touched.orEmpty()
        // المُشفى يدخل عدّاد الاستيعاب (نظير Dart: onApplied يُحسب تطبيقاً فعلياً).
        ingested += healed?.applied ?: 0

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
            // حارس التسمم أثناء التشغيل (Dart l.2081) — قبل تطبيق الصفحة:
            // مؤشر خادم يتقدم فوق server_time المُعلن في الرد نفسه بأكثر من
            // هامش سنة = صفوف بطوابع sentinel/ميلي ما زالت تُقدَّم (worker
            // غير مُصلح). لا تُطبَّق الصفحة (طوابعها المسمومة كانت ستكسب كل
            // قرارات LWW) ولا يتقدم المؤشر.
            if (nextCursor > cursor && isServerCursorRejected(nextCursor, response.serverTime?.toLong())) {
                throw IllegalStateException(
                    "مؤشر خادم مسموم رُفض ($nextCursor مقابل server_time=${response.serverTime}) — " +
                        "لم يتقدم المؤشر ولم تُطبَّق الصفحة"
                )
            }
            val changes = response.changes.orEmpty()
            if (changes.isNotEmpty() && nextCursor <= cursor) {
                throw Exception("Pull returned records without advancing the cursor")
            }
            if (hasMore && nextCursor == cursor) {
                // Acknowledged server repair may need another read of this cursor.
                // Never accept arbitrary stalls or let repair consume the cycle
                // budget and be reported as successful without any progress.
                if (changes.isEmpty() && response.repairPending == true && repairRetries < 3 &&
                    pagesDone + 1 < MAX_PULL_PAGES_PER_CYCLE) {
                    repairRetries++
                    pagesDone++
                    continue
                }
                throw Exception("Pull pagination stalled at cursor $cursor")
            }
            repairRetries = 0
            if (changes.isNotEmpty()) {
                val report = ingestorRegistry.ingestPage(changes)
                ingested += report.applied
                pulledEntities += report.touched
                if (report.hasFailures) {
                    // ✅ (2026-10-06) **لا تجميد للمؤشر** — مطابقة `pull_quarantine.dart`:
                    //  • الصفحة نفسها سليمة (شبكة/HTTP/JSON/جداول خادمية)، وقد
                    //    طُبّق منها ما طُبّق.
                    //  • الصفوف الفاشلة تُحاسب (عدّاد + أول عزل) وتُعاد محاولتها
                    //    من حمولتها في كل دورة ([healQuarantinedBatch]).
                    //  • تجميد المؤشر لصف واحد كان يعني «جهاز متوقف نهائياً»
                    //    (عطل مُبلَّغ: الدلتا لا تسحب جدولاً ولا حقلاً) لأن
                    //    إعادة التطبيق تعطي النتيجة نفسها دائماً — إعادة السحب
                    //    لا تُشفي ما لا يُشفيه غيره.
                    // تبقى «جداول فاشلة على الخادم» (`response.errors`) دورة
                    // فاشلة كما هي: تلك تُشفى بإصلاح D1 وإعادة المحاولة.
                    pageFailures += report.failedRecords
                }
            }
            if (normalizeTimestamps && response.normalization?.complete == true &&
                response.normalization.remaining == 0.0) {
                preferences.setTimestampNormalizationDone(true)
            }
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
            if (pageFailures.isNotEmpty()) ingestorRegistry.enforceQuarantineCap()
            // isFullPull=true هنا إعادة لعب كاملة *بعد* تدوير epoch (حماية
            // سلامة بيانات، وليس bootstrap اختياري) — تُنفَّذ بنفس
            // deltaOnly للاستدعاء الأصلي (نظير Dart l.2520:
            // `_pullChanges(deltaOnly: deltaOnly)`)، وعلم الاستئناف
            // full_replay_pending مضبوط قبلها فيبقى fullReplay=true.
            return ingested + pullDelta(
                batchSize = batchSize,
                isFullPull = true,
                allowEpochRestart = false,
                deltaOnly = deltaOnly
            )
        }

        // Every unresolved payload is already durable before advancing the checkpoint.
        // Retry on every cycle, including an empty delta after the parent arrived earlier.
        val retry = ingestorRegistry.retryPendingLinks()
        ingested += retry.applied
        pulledEntities += retry.touched
        // المؤجَّل الفاشل محفوظ بحمولته في pending_sync_links ويُعاد كل دورة
        // (نظير سجل الانتظار الدارتي) — يُحاسب ولا يجمّد المؤشر.
        pageFailures += retry.failedRecords
        if (pageFailures.isNotEmpty()) {
            // المحاسبة تُبقي الحجر داخل السقف؛ العائد = عدد المُخلَّى بالسقف
            // ولا يدخل في عدّاد المُطبَّق (لا صلة له بعدد الصفوف المطبَّقة).
            ingestorRegistry.enforceQuarantineCap()
            // العدّ للرسالة مُوحَّد بالهوية (كيان + local_uuid): الصف نفسه قد
            // يفشل أكثر من مرة في الدورة (شفاء ثم صفحة، أو صفحة ثم مؤجَّل)
            // — فلا يُعرض رقم مُنفَّخ.
            val quarantinedNow = pageFailures
                .distinctBy { it.entity to (it.record["local_uuid"] as? String ?: "") }
                .size
            _syncState.update {
                it.copy(
                    lastMessage = it.lastMessage +
                        " • عُزل $quarantinedNow سجلاً غير قابل للتطبيق ويُعاد حلّها من حمولتها"
                )
            }
        }

        // دورة نظيفة كاملة — الآن فقط نقدّم نقطة التفتيش المحفوظة.
        // حارس التثبيت النهائي (Dart l.2534 — طبقة الدفاع الثالثة): الحارس
        // الديناميكي أعلاه يحتاج server_time، وworker قديم بلا الحقل كان
        // سيمرر السم؛ هنا حد ثابت صرف (مرآة عتبة الخادم 2e9).
        if (!isPendingCursorSafeToInstall(cursor)) {
            preferences.resetPullCursorForFreshReplay()
            runCatching {
                preferences.recordSyncError(
                    operation = "pull_cursor_install_blocked",
                    message = "منع تثبيت مؤشر مسموم ($cursor) فوق الحد الثابت " +
                        "$MAX_SANE_PULL_CURSOR_FUTURE — صُفّر المؤشر وعلامة full sync",
                    pullCursor = 0L,
                    deviceId = preferences.getDeviceId()
                )
            }
            _syncState.update {
                it.copy(lastMessage = "رُفض تثبيت مؤشر مسموم — ستُعاد المزامنة الكاملة نظيفة")
            }
            refreshDerivedAfterCycle(pulledEntities, ingested)
            return ingested
        }
        preferences.saveLastPullCursor(cursor)
        if (fullReplay && reachedEnd) {
            preferences.setFullReplayPending(false)
            preferences.setFullSyncComplete(true)
        }
        refreshDerivedAfterCycle(pulledEntities, ingested)
        return ingested
    }

    /**
     * إعادة بناء الحقول المشتقة للحجوزات بعد دورة سحب ناجحة — نظير
     * `_refreshDerivedAfterPull` في Dart (cloudflare_sync_manager.dart l.3780)
     * يُستدعى من `_pullChanges` l.2591.
     *
     * الشرط حرفي كالدارتي: `pulledDerivedEntities.isNotEmpty && totalPulled > 0`
     * — دورة طبّقت صفاً من `bookings`/`booking_nights`/`payments`/
     * `price_adjustments`/`booking_price_adjustments`/`payment_voids` فقط.
     * (في Dart أيضاً لا تُنفَّذ في الدورة الفاشلة: مسار الخطأ يرمي قبل هذا
     * السطر — وأندرويد كذلك لأن الفشل الواقعي يرمي في تقرير التطبيق.)
     *
     * بلا رفع وبلا رسالة إضافية: Dart يطبع سطر تشخيص فقط، والقيم تُحدَّث
     * عبر `BookingsDao.updateFinancialCache` التي لا تمس بيانات المزامنة.
     *
     * فشل إعادة البناء لا يُفشل دورة السحب (نظير `try/catch` الدارتي في
     * `_refreshDerivedAfterPull`) — لكنه لا يبتلع الإلغاء: كوريوتين الدورة
     * الملغاة تتوقف هنا كما في أي نقطة أخرى.
     */
    private suspend fun refreshDerivedAfterCycle(pulledEntities: Set<String>, ingested: Int) {
        if (ingested <= 0 || !BookingDerivedRefreshService.affectsDerived(pulledEntities)) return
        try {
            derivedRefresh.refreshAllActiveBookings()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            android.util.Log.w("SyncManager", "تعذّر إعادة بناء الحقول المشتقة بعد السحب", error)
        }
    }

    // ─── مسح تقارب الحذفيات التاريخي (نظير _sweepHistoricalTombstones) ───

    /**
     * بوابة المسح: علم غير مضبوط + جهاز قائم فعلاً — تُنفَّذ قبل أي دورة
     * سحب في [pullDelta]. أفضل جهد: أي فشل يؤجل المسح للدورة القادمة بلا
     * أي تأثير على المؤشر الرئيسي أو على نتيجة دورة السحب نفسها.
     */
    private suspend fun performTombstoneSweepIfDue() {
        if (!tombstoneSweepDue(
                preferences.isTombstoneSweepDone(),
                preferences.getLastPullCursor(),
                preferences.isFullSyncComplete()
            )
        ) {
            return
        }
        val outcome = runCatching { sweepHistoricalTombstones() }.getOrNull() ?: return
        // بلوغ سقف الدورة ليس اكتمالاً: المؤشر المحفوظ يستأنف البقية،
        // والعلم يبقى مفتوحاً (لا يجوز إسقاط صفحات حذفيات لم تُطبَّق).
        if (!outcome.completed) return
        preferences.setTombstoneSweepDone(true)
        preferences.clearTombstoneSweepCursor()
        if (outcome.handled > 0) {
            _syncState.update {
                it.copy(lastMessage = "اكتمل مسح الحذفيات التاريخية: ${outcome.handled} سجلاً")
            }
        }
    }

    /** نتيجة صفحة/دورة مسح: ما طُبّق فعلاً + هل نفدت الصفحات. */
    private data class SweepOutcome(val handled: Int, val completed: Boolean)

    /**
     * مسح تقارب لمرة واحدة للحذفيات التاريخية — نظير
     * `_sweepHistoricalTombstones` في Dart (l.3661):
     *
     *  • `tombstones_only=1` + استبعاد جهازنا: الحذفيات التي لم تُبَث لهذا
     *    الجهاز أثناء نافذة العقد القديم تُطبَّق الآن كحذف محلي.
     *  • مؤشر **مستقل** محفوظ بعد كل صفحة مطبَّقة: فشل شبكي/HTTP يستأنف من
     *    حيث توقف بدل إعادة المسح من الصفر.
     *  • حارس تقدم: مؤشر ثابت مع صفوف = حلقة محتملة → إجهاض بلا ضبط العلم.
     *  • سقف صفحات لكل دورة (فلسفة H2 في هذا الملف): لا نحبس دورة السحب
     *    خلف مسح ضخم — البقية تُستأنف من المؤشر المحفوظ.
     *
     * @return نتيجة الدورة ([SweepOutcome.completed] = نفدت الصفحات فعلاً)،
     *   أو null عند فشل يستوجب إعادة المحاولة لاحقاً (الشبكة/HTTP/رد ناقص
     *   أو مؤشر متوقف) — العلم لا يُضبط في هاتين الحالتين.
     */
    private suspend fun sweepHistoricalTombstones(): SweepOutcome? {
        if (!syncService.hasWorkerToken()) return null
        val excludeDevice = preferences.getDeviceId()?.takeIf { it.isNotBlank() }
        var cursor = preferences.getTombstoneSweepCursor()
        var handled = 0
        var pages = 0
        while (pages < MAX_TOMBSTONE_SWEEP_PAGES_PER_CYCLE) {
            val result = syncService.pull(
                cursor = cursor,
                limit = CloudflareConfig.DELTA_PULL_BATCH_SIZE,
                excludeDevice = excludeDevice,
                tombstonesOnly = true
            )
            val response = result.getOrNull() ?: return null
            val changes = response.changes.orEmpty()
            if (changes.isNotEmpty()) {
                // أفضل جهد: فشل تطبيق صف فردي لا يوقف المسح ولا يُفشل الدورة
                // (Dart: report.errors → متابعة) — المؤشر الرئيسي غير معني.
                val report = runCatching { ingestorRegistry.ingestPage(changes) }.getOrNull()
                if (report != null) handled += report.applied
            }
            val serverCursor = response.cursor?.toLongOrNull() ?: return null
            val hasMore = response.hasMore ?: return null
            if (serverCursor > cursor) {
                cursor = serverCursor
                preferences.saveTombstoneSweepCursor(cursor)
            } else if (hasMore && changes.isNotEmpty()) {
                // مؤشر متوقف مع صفوف = حلقة لا نهائية محتملة.
                return null
            }
            pages++
            if (!hasMore || changes.isEmpty()) return SweepOutcome(handled, completed = true)
        }
        // سقف الدورة: تقدم محفوظ للاستئناف، والعلم يبقى مفتوحاً.
        return SweepOutcome(handled, completed = false)
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
