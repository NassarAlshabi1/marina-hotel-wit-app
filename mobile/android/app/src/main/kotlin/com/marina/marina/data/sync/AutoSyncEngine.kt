package com.marina.marina.data.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.data.repository.SyncManager
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * ✅ (2026-09-25) محرك المزامنة التلقائية — الجسر التنفيذي للآليات الثلاث
 * التي كان تطبيق Kotlin ينقصها ويملكها مرجع Flutter (فرع
 * feat/cloudflare-sync-execution) مما جعل المستخدم يرى «المزامنة لا تعمل»:
 *
 * 1. **مراقب الـ outbox** — نظير AutoOutboxSyncWatcher (auto_outbox_sync_watcher.dart):
 *    أي كتابة محلية تُدخل صفاً في outbox → هذا المراقب يستيقظ (Room Flow على
 *    pendingCount) → دفعة مؤجلة 3 ثوانٍ (SyncConstants.outboxDebounceWindow)
 *    → رفع تلقائي. بلا هذا المراقب كانت الشاشات التي لا تستدعي push يدوياً
 *    (المصروفات/الرواتب/المخزون/الغرف/القائمة السوداء/الملاحظات) تبقى بياناتها
 *    محلية فقط حتى يفتح المستخدم شاشة تدفع يدوياً.
 *
 * 2. **بوابة سحب فتح التطبيق** — نظير AppOpenPullGate (sync/app_open_pull_gate.dart):
 *    عند إقلاع التطبيق يُسحب دلتا مرة واحدة إن مضى على آخر سحب ≥ ساعة
 *    (appOpenSyncInterval) — بنفس مفتاح prefs الدارتي
 *    last_app_open_pull_epoch_ms، ويُختم فقط بعد نجاح فعلي (عقد الدارت).
 *    محكوم بإعداد sync_on_startup (appwrite_sync_on_startup).
 *
 * 3. **الدورة الدورية** — نظير UnifiedSyncScheduler/autoSyncIntervalPrefKey:
 *    كل [SyncPreferences.getSyncIntervalMinutes] دقيقة (افتراضي 15، مدى
 *    1..120 مثل autoSyncIntervalMin/MaxMinutes) دورة كاملة push+pull
 *    (syncNow) محكومة بـ appwrite_auto_sync_enabled + appwrite_sync_enabled.
 *    ابدأها من [startPeriodicLoop] بعد [start].
 *
 * 4. **وعي الشبكة**: الدفع مؤجل بلا إنترنت، وعند عودة الاتصال (NetworkCallback
 *    — نظير onConnectivityChanged في الدارت) يُفلش الـ outbox فوراً.
 *    wifi_only_sync محترم: على بيانات الجوال لا مزامنة إن كان الإعداد فعالاً.
 *
 * 5. **استرداد الانهيار** — نظير عقد P0-H في الدارت: عند الإقلاع تُعاد صفوف
 *    outbox المحجوزة processing (عملية دفع انقطعت بانهيار) إلى pending.
 *
 * كل الدورات تمر عبر [SyncManager] فتتسلسل تلقائياً عبر isSyncing ولا
 * يتصادم أي مسار مع زر يدوي أو دورة أخرى.
 */
@Singleton
class AutoSyncEngine @Inject constructor(
    @ApplicationContext private val context: Context,
    private val syncManager: SyncManager,
    private val outboxRepository: OutboxRepository,
    private val preferences: SyncPreferences
) {
    companion object {
        /** نافذة تجميع الكتابات قبل الدفع — 3 ثوانٍ (outboxDebounceWindow). */
        private const val OUTBOX_DEBOUNCE_MS = 3_000L

        /** إعادة محاولة الدفع طالما بقيت معلّقات بعد فشل مؤقت — 30 ثانية (guardianOutboxDebounce). */
        private const val PENDING_RETRY_MS = 30_000L

        /** تأخير الفلش بعد عودة الاتصال — 500ms (appForegroundDelay). */
        private const val BACK_ONLINE_FLUSH_DELAY_MS = 500L

        /** مفتاح آخر سحب عند فتح التطبيق — نفس سلسلة Dart حرفياً. */
        private const val APP_OPEN_PULL_KEY = "last_app_open_pull_epoch_ms"

        /** فاصل سحب فتح التطبيق — ساعة (appOpenSyncInterval). */
        private const val APP_OPEN_PULL_INTERVAL_MS = 60L * 60 * 1000

        /** مدى فترة المزامنة الدورية بالدقائق (autoSyncIntervalMin/MaxMinutes). */
        private const val INTERVAL_MIN_MINUTES = 1
        private const val INTERVAL_MAX_MINUTES = 120
    }

    private val prefs by lazy {
        context.getSharedPreferences("marina_cloudflare_prefs", Context.MODE_PRIVATE)
    }

    private val connectivityManager by lazy {
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    }

    private var scope: CoroutineScope? = null
    private var pushJob: Job? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Volatile private var started = false

    /** يبدأ المحرك (idempotent — الاستدعاء المتكرر لا يعيد التهيئة). */
    @Synchronized
    fun start() {
        if (started) return
        started = true
        val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope = appScope

        // 5) استرداد صفوف الـ processing المعلّقة من انهيار سابق (P0-H).
        appScope.launch {
            val recovered = runCatching { outboxRepository.recoverStaleProcessing() }.getOrDefault(0)
            if (recovered > 0) schedulePush(OUTBOX_DEBOUNCE_MS)
        }

        // 2) بوابة سحب فتح التطبيق (باردة) — سحب فقط.
        appScope.launch { runStartupPullGate() }

        // 1) مراقب الـ outbox — أي صف pending جديد يفجّر دفعة مؤجلة.
        appScope.launch {
            outboxRepository.pendingCount().collect { count ->
                if (count > 0) schedulePush(OUTBOX_DEBOUNCE_MS)
            }
        }

        // 3) الدورة الدورية — فترتها من الإعدادات وتُقرأ من جديد كل دورة.
        appScope.launch { periodicLoop(appScope) }

        // 4) عودة الاتصال → فلش فوري للـ outbox (نظير onConnectivityChanged).
        registerNetworkCallback(appScope)
    }

    /** يوقف المحرك ويحرر الموارد (للاختبارات). */
    @Synchronized
    fun stop() {
        pushJob?.cancel()
        pushJob = null
        networkCallback?.let { cb ->
            runCatching { connectivityManager?.unregisterNetworkCallback(cb) }
        }
        networkCallback = null
        scope?.cancel()
        scope = null
        started = false
    }

    // ─── 1) مجدول الدفع ──────────────────────────────────────────

    /**
     * يجدول دفعة دفع بعد [delayMs]: الاستدعاءات المتلاحقة (كتابات متتالية)
     * تُلغي الجدولة السابقة — سلوك debounce مطابق للدارت.
     */
    private fun schedulePush(delayMs: Long) {
        val appScope = scope ?: return
        pushJob?.cancel()
        pushJob = appScope.launch {
            delay(delayMs)
            drainOutbox()
        }
    }

    /**
     * محاولة دفع واحدة: بوابات الماستر والشبكة ثم pushOnly. بعد المحاولة،
     * إن بقيت معلّقات (فشل شبكة مؤقت أو دورة أخرى كانت تعمل) يُعاد الجدولة
     * بعد 30 ثانية كي لا يتوقف الرفع حتى تُفرغ الطابور — نظير حلقة الـ
     * guardian في الدارت (guardianOutboxDebounce).
     */
    private suspend fun drainOutbox() {
        if (!masterSyncEnabled()) return
        if (!networkAllowed()) return // سيتفلش عند عودة الاتصال عبر NetworkCallback
        runCatching { syncManager.pushOnly() }
        val stillPending = runCatching { outboxRepository.pendingCount().first() }.getOrDefault(0)
        if (stillPending > 0) schedulePush(PENDING_RETRY_MS)
    }

    // ─── 2) بوابة سحب فتح التطبيق ────────────────────────────────

    /**
     * سحب عند الإطلاق وفق بوابة الدارت: فقط إن مضى على آخر سحب ناجح ≥ ساعة
     * (أو لم يسبق سحب)، ومحكوم بـ sync_on_startup. الختم بعد نجاح فعلي فقط.
     */
    private suspend fun runStartupPullGate() {
        if (!preferences.getCloudflareSyncEnabled()) return
        if (!preferences.getSyncOnStartup()) return
        val lastPull = prefs.getLong(APP_OPEN_PULL_KEY, 0L)
        val elapsed = System.currentTimeMillis() - lastPull
        if (lastPull != 0L && elapsed < APP_OPEN_PULL_INTERVAL_MS) return
        if (!networkAllowed()) return
        val pulled = runCatching { syncManager.pullOnly() }.getOrDefault(-1)
        if (pulled >= 0) {
            prefs.edit().putLong(APP_OPEN_PULL_KEY, System.currentTimeMillis()).apply()
        }
    }

    // ─── 3) الدورة الدورية ───────────────────────────────────────

    /** حلقة دورية push+pull — تُقرأ فترتها من الإعدادات في كل تكرار. */
    private suspend fun periodicLoop(appScope: CoroutineScope) {
        while (appScope.isActive) {
            val minutes = preferences.getSyncIntervalMinutes()
                .coerceIn(INTERVAL_MIN_MINUTES, INTERVAL_MAX_MINUTES)
            delay(minutes * 60_000L)
            if (!masterSyncEnabled()) continue
            if (!networkAllowed()) continue
            runCatching { syncManager.syncNow() }
        }
    }

    // ─── 4) وعي الشبكة ───────────────────────────────────────────

    /** الماستر: مزامنة Cloudflare مفعلة + مزامنة تلقائية مفعلة. */
    private fun masterSyncEnabled(): Boolean =
        preferences.getCloudflareSyncEnabled() && preferences.getAutoSyncEnabled()

    /**
     * هل الشبكة الحالية تسمح بالمزامنة؟ مراعاة wifi_only_sync:
     * على بيانات الجوال لا مزامنة إن كان الإعداد فعالاً (نفس سلوك الدارت).
     */
    private fun networkAllowed(): Boolean {
        val cm = connectivityManager ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        val hasInternet = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        if (!hasInternet) return false
        if (!preferences.getWifiOnly()) return true
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    /** عودة الاتصال → فلش الـ outbox بعد مهلة قصيرة (نظير الدارت). */
    private fun registerNetworkCallback(appScope: CoroutineScope) {
        val cm = connectivityManager ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                appScope.launch {
                    delay(BACK_ONLINE_FLUSH_DELAY_MS)
                    if (masterSyncEnabled()) schedulePush(0L)
                }
            }
        }
        runCatching {
            cm.registerNetworkCallback(
                NetworkRequest.Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build(),
                callback
            )
            networkCallback = callback
        }
    }
}
