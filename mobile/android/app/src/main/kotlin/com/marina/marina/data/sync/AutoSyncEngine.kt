package com.marina.marina.data.sync

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.SystemClock
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.realtime.CloudflareRealtimeClient
import com.marina.marina.data.repository.OutboxRepository
import com.marina.marina.data.repository.SyncManager
import dagger.Lazy
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Offline-first process engine. Upload watching is independent from hourly delta pulling.
 * App entry never awaits network. All automatic pulls share one health/hour gate;
 * SyncManager retains cursor, epoch, foreground lifetime and atomic operation admission.
 */
@Singleton
class AutoSyncEngine @Inject constructor(
    @ApplicationContext private val context: Context,
    private val syncManagerProvider: Lazy<SyncManager>,
    private val outboxRepositoryProvider: Lazy<OutboxRepository>,
    private val preferences: SyncPreferences,
    private val serviceProvider: Lazy<CloudflareSyncService>,
    private val realtimeProvider: Lazy<CloudflareRealtimeClient>
) {
    private val syncManager: SyncManager get() = syncManagerProvider.get()
    /**
     * عميل Realtime يُحلّ عند الحاجة فقط — لا يفتح مقبساً ولا يكلّف شبكة
     * أثناء الإقلاع (نمط `Lazy` المستخدم لباقي التبعات الثقيلة هنا).
     */
    private val realtime: CloudflareRealtimeClient get() = realtimeProvider.get()
    private val outboxRepository: OutboxRepository get() = outboxRepositoryProvider.get()
    private val connectivityManager by lazy {
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
    }
    private val pullGate by lazy {
        AutomaticDeltaGate(
            enabled = ::masterSyncEnabled, networkAllowed = ::networkAllowed,
            lastSuccess = preferences::getLastPullTs, now = System::currentTimeMillis,
            monotonicNow = SystemClock::elapsedRealtime,
            probe = { serviceProvider.get().checkD1Connection() },
            pullIfDue = { syncManager.pullAutomaticallyIfDue() },
            canStart = { foreground }
        )
    }
    val automaticStatus get() = pullGate.status
    private var scope: CoroutineScope? = null
    private var pushJob: Job? = null
    private var pullCheckJob: Job? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var started = false
    @Volatile private var foreground = false

    /** إشارة تغيير بعيد وصلت والتطبيق في الخلفية — تُستهلك عند العودة. */
    @Volatile private var remoteSignalWhileBackgrounded = false

    @Synchronized
    fun start() {
        if (started) return
        started = true
        val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        scope = appScope
        // المزامنة الفورية: مسار سحب الحدث = دلتا فقط عبر المحرك (نفس
        // realtimeTriggeredPull في Dart) — لا رفع ولا full sync من حدث.
        realtime.setPullTrigger { syncManager.pullOnRealtimeEvent() }
        appScope.launch {
            // حارس الإقلاع ضد المؤشر المسموم (Dart l.553) — قبل أي دورة.
            recover { syncManager.sanitizeStoredCursorIfNeeded() }
            val recovered = recover { outboxRepository.recoverStaleProcessing() } ?: 0
            if (recovered > 0) schedulePush(3_000L)
        }
        appScope.launch {
            outboxRepository.pendingCount().collect { count ->
                if (count > 0) schedulePush(3_000L)
            }
        }
        appScope.launch { periodicLoop(appScope) }
        registerNetworkCallback(appScope)
    }

    /** Called at real Activity entry/resume, not each Dashboard recomposition. */
    fun onForeground() {
        if (foreground) return
        foreground = true
        // Realtime في الواجهة فقط (نفس مرحلة Flutter 3.3): استئناف المقبس
        // عند العودة، ثم إن كان قد وصل حدث أثناء الغياب نسحبه فوراً.
        if (masterSyncEnabled()) realtime.ensureStarted()
        if (remoteSignalWhileBackgrounded &&
            RemoteSignalPolicy.shouldConsumeDeferred(masterSyncEnabled(), networkAllowed())
        ) {
            remoteSignalWhileBackgrounded = false
            realtime.noteRemoteChange("foreground")
        }
        if (preferences.getSyncOnStartup()) requestPullCheck(probeWhenFresh = true)
    }

    fun onBackground() {
        foreground = false
        realtime.stop()
    }

    /**
     * إشارة تغيير بعيد من FCM (رسالة بيانات) — نظير `_triggerPull` في
     * Flutter `fcm_service.dart`:
     *
     *  • المفتاح معطّل → لا شيء.
     *  • التطبيق في الواجهة → شارة UI + سحب دلتا مُدمج مباشرة.
     *  • التطبيق في الخلفية → تُحفظ الإشارة وتُستهلك عند العودة للواجهة
     *    بدل بدء شبكة من عملية غير ظاهرة (قيد Android على حدود الخلفية؛
     *    بديل صريح لا ادعاء مطابقة).
     */
    fun onRemoteSignal(source: String) {
        when (RemoteSignalPolicy.decide(masterSyncEnabled(), foreground)) {
            RemoteSignalPolicy.Decision.IGNORE -> Unit
            RemoteSignalPolicy.Decision.DELIVER -> realtime.noteRemoteChange(source)
            RemoteSignalPolicy.Decision.DEFER -> remoteSignalWhileBackgrounded = true
        }
    }

    @Synchronized
    fun stop() {
        foreground = false
        realtime.stop()
        remoteSignalWhileBackgrounded = false
        pushJob?.cancel()
        pushJob = null
        pullCheckJob?.cancel()
        pullCheckJob = null
        networkCallback?.let { runCatching { connectivityManager?.unregisterNetworkCallback(it) } }
        networkCallback = null
        scope?.cancel()
        scope = null
        started = false
    }

    @Synchronized
    private fun requestPullCheck(probeWhenFresh: Boolean) {
        val appScope = scope ?: return
        if (!foreground || pullCheckJob?.isActive == true) return
        pullCheckJob = appScope.launch {
            do {
                if (!foreground) break
                pullGate.check(probeWhenFresh)
                if (!pullGate.status.value.needsRetry || !masterSyncEnabled()) break
                delay(30_000L)
            } while (foreground)
        }
    }

    @Synchronized
    private fun schedulePush(delayMs: Long) {
        val appScope = scope ?: return
        pushJob?.cancel()
        pushJob = appScope.launch {
            delay(delayMs)
            drainOutbox()
        }
    }

    private suspend fun drainOutbox() {
        if (!masterSyncEnabled() || !networkAllowed()) return
        recover { syncManager.pushOnly() }
        val stillPending = recover { outboxRepository.pendingCount().first() } ?: 0
        if (stillPending > 0) schedulePush(30_000L)
    }

    /** The preference controls check cadence, never bypasses the one-hour pull floor. */
    private suspend fun periodicLoop(appScope: CoroutineScope) {
        while (appScope.isActive) {
            val now = System.currentTimeMillis()
            val last = preferences.getLastPullTs()
            val untilDue = if (automaticPullDue(now, last)) 30_000L
                else (AUTOMATIC_PULL_INTERVAL_MS - (now - last)).coerceAtLeast(30_000L)
            val configured = preferences.getSyncIntervalMinutes().coerceIn(1, 120) * 60_000L
            delay(minOf(configured, untilDue))
            // Do not initiate an Android foreground service from an invisible app.
            // An already accepted operation still survives Home through SyncOperationRunner.
            if (foreground) requestPullCheck(probeWhenFresh = false)
        }
    }

    private fun masterSyncEnabled(): Boolean =
        preferences.getCloudflareSyncEnabled() && preferences.getAutoSyncEnabled()

    private fun networkAllowed(): Boolean {
        val cm = connectivityManager ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ||
            !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) return false
        return !preferences.getWifiOnly() || caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    private fun registerNetworkCallback(appScope: CoroutineScope) {
        val cm = connectivityManager ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = changed()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = changed()
            override fun onLost(network: Network) = changed()
            private fun changed() {
                appScope.launch {
                    delay(500L)
                    // Validation may arrive after onAvailable (including captive portal login).
                    requestPullCheck(probeWhenFresh = true)
                    if (masterSyncEnabled() && networkAllowed()) schedulePush(0L)
                }
            }
        }
        runCatching { cm.registerDefaultNetworkCallback(callback) }.onSuccess { networkCallback = callback }
    }

    private suspend fun <T> recover(block: suspend () -> T): T? = try {
        block()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        null
    }
}
