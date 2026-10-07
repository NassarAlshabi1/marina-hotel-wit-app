package com.marina.marina.data.remote.realtime

import com.marina.marina.data.auth.LocalAdminAuth
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerEndpoints
import com.marina.marina.domain.model.RealtimeSyncState
import com.marina.marina.domain.repository.RealtimeSyncRepository
import java.net.URI
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/**
 * عميل المزامنة الفورية — نظير `CloudflareRealtimeSync` في Flutter
 * (mobile/lib/services/cloudflare_realtime_sync.dart، فرع
 * feat/cloudflare-sync-execution) على `/api/realtime` (RealtimeHubDO):
 *
 *  • **المسار الوحيد المقبول للبيانات الواردة**: حدث `change` إشارة فقط
 *    → سحب Delta عبر المحرك الموثوق → دمج محلي. لا تطبيق مباشر من حمولة
 *    الحدث إطلاقاً (نفس عقد Flutter/P0-C).
 *  • **echo filter**: الخادم يبث لكل الجلسات شاملاً جهاز الدفع نفسه —
 *    حدثنا الذاتي لا يُطلق سحباً.
 *  • **تدوير نقاط النهاية**: يُقرأ المرشّح الفعّال عند كل اتصال (نطاق
 *    مخصّص ↔ workers.dev، حجب SNI اليمني)، والنجاح يُثبَّت والفشل يُنزّل.
 *  • **إعادة الاتصال**: backoff أُسّي 1s→60s بحد 6 محاولات، ثم إعادة
 *    تسليح دورية كل دقيقتين (مراجعة #17) — لا ميت أبداً.
 *  • **استرداد بعد الانقطاع**: أول اتصال ناجح بعد انقطاع غير مقصود يطلق
 *    سحباً واحداً يستدرك ما فات (delta من المؤشر المحفوظ).
 *  • **دورة الحياة**: يعمل في الواجهة فقط (offline-first وبطارية)؛
 *    يوقفه المحرك عند الخلفية ويستأنفه عند العودة.
 *
 * التشخيصات والشارة تُعرض للواجهة عبر [RealtimeSyncRepository] — بلا
 * اعتماد على أي شاشة أو ViewModel.
 */
@Singleton
class CloudflareRealtimeClient @Inject constructor(
    client: OkHttpClient,
    private val endpoints: WorkerEndpoints,
    private val preferences: SyncPreferences
) : RealtimeSyncRepository {

    /** عميل WebSocket مشتق: ping بروتوكولي 30s + بلا مهلة قراءة + مهلة اتصال 15s. */
    private val socketClient: OkHttpClient = client.newBuilder()
        .pingInterval(REALTIME_HEARTBEAT_MS, TimeUnit.MILLISECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .connectTimeout(REALTIME_CONNECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .build()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _realtimeState = MutableStateFlow(RealtimeSyncState())
    override val realtimeState: StateFlow<RealtimeSyncState> = _realtimeState.asStateFlow()

    private val scheduler = RealtimePullScheduler(
        scope = scope,
        now = System::currentTimeMillis,
        execute = { executeTriggeredPull() }
    )

    private var pullTrigger: (suspend () -> Boolean)? = null
    private var webSocket: WebSocket? = null
    private var currentBase: URI? = null
    private var candidateQueue: List<URI> = emptyList()
    private var pendingToken: String? = null
    private var reconnectJob: Job? = null
    private var rearmJob: Job? = null
    private var watchdogJob: Job? = null

    @Volatile private var listening = false
    @Volatile private var intentionallyStopped = false
    @Volatile private var connectInFlight = false
    private var reconnectAttempt = 0
    private var recoveryPullPending = false
    private var lastConnectedAt: Long? = null
    private var lastEventAt: Long? = null
    private var lastError: String? = null
    private var lastErrorAt: Long? = null
    private var connectAttempts = 0

    // ─── عقد الواجهة/المحرك ──────────────────────────────────────

    /** هل المزامنة الفورية مفعّلة محلياً؟ (المفتاح + تفعيل Cloudflare). */
    fun isEnabled(): Boolean =
        preferences.getRealtimeSyncEnabled() && preferences.getCloudflareSyncEnabled()

    /**
     * حقن مسار السحب الفعلي (يُضبط من المحرك): دلتا فقط، ويعيد true عند
     * اكتمال دورة فعلية — عقد `RemoteChangePull` نفسه في Dart.
     */
    fun setPullTrigger(trigger: suspend () -> Boolean) {
        pullTrigger = trigger
    }

    /** بدء الاستماع (idempotent) — لا يفعل شيئاً إذا كان المفتاح معطّلاً. */
    fun start() {
        if (!isEnabled()) {
            publishState()
            return
        }
        if (listening && !intentionallyStopped) return
        listening = true
        intentionallyStopped = false
        publishState()
        connect()
    }

    /**
     * استئناف بعد stop()/استسلام إعادة الاتصال (عودة التطبيق للواجهة):
     * يصفّر عدّاد المحاولات ويجرّب فوراً (Dart `ensureStarted`).
     */
    fun ensureStarted() {
        // المفتاح يُحترم في كل مسار استئناف — لا مقبس حين يكون Realtime معطّلاً.
        if (!isEnabled()) {
            if (listening) stop()
            return
        }
        reconnectAttempt = 0
        reconnectJob?.cancel()
        reconnectJob = null
        if (!listening || intentionallyStopped) {
            intentionallyStopped = false
            listening = true
        }
        publishState()
        if (webSocket != null || connectInFlight) return
        connect()
    }

    /** إيقاف مقصود (خلفية التطبيق): لا إعادة اتصال بعده. */
    fun stop() {
        intentionallyStopped = true
        listening = false
        reconnectJob?.cancel()
        reconnectJob = null
        rearmJob?.cancel()
        rearmJob = null
        watchdogJob?.cancel()
        watchdogJob = null
        scheduler.cancelPending()
        runCatching { webSocket?.close(1000, "background") }
        webSocket = null
        currentBase = null
        candidateQueue = emptyList()
        connectInFlight = false
        clearRemoteChanges()
        pushState { it.copy(connected = false, reconnecting = false) }
    }

    /** تصفير شارة الواجهة بعد نجاح السحب (نفس عقد Flutter). */
    fun clearRemoteChanges() {
        _realtimeState.update { it.copy(pendingRemoteChanges = 0) }
    }

    /**
     * إشارة تغيير بعيد (WS change أو FCM) — تزيد الشارة وتجدول سحباً
     * مُدمجاً. تُستخدم من خدمة FCM أيضاً حين لا يكون المقبس مفتوحاً.
     */
    fun noteRemoteChange(source: String) {
        if (!isEnabled()) return
        _realtimeState.update { it.copy(pendingRemoteChanges = it.pendingRemoteChanges + 1) }
        publishState()
        scheduler.onRemoteChange()
    }

    // ─── استقبال الرسائل ────────────────────────────────────────

    /** نواة القرار (قابلة للاختبار بلا شبكة) — echo filter ثم إشارة السحب. */
    internal fun handleIncomingMessage(message: RealtimeMessage) {
        val ownDeviceId = preferences.getDeviceId()
        if (!message.deviceId.isNullOrEmpty() && message.deviceId == ownDeviceId) return
        when (message.type) {
            "change" -> noteRemoteChange("ws")
            // presence/lock/unlock: لا سحب — الأقفال تُدار خادمياً،
            // والانضمام/المغادرة ليست تغيّر بيانات (عقد Dart).
            else -> Unit
        }
    }

    internal fun handleMessageText(raw: String?) {
        lastEventAt = System.currentTimeMillis()
        publishState()
        val message = RealtimeMessage.tryParse(raw) ?: return
        handleIncomingMessage(message)
    }

    // ─── دورة الاتصال ────────────────────────────────────────────

    private fun connect() {
        if (!listening || intentionallyStopped || connectInFlight) return
        // دفاع مزدوج: أي نداء اتصال (rearm/backoff) يتوقف فور تعطيل المفتاح.
        if (!isEnabled()) {
            stop()
            return
        }
        val token = preferences.getAuthToken()
        // التوكن المحلي يفتح التطبيق فقط — ليس Bearer صالحاً للـ Worker.
        if (token.isNullOrBlank() || LocalAdminAuth.isLocalAdminToken(token)) {
            noteSocketIssue("connect skipped (no worker token yet)")
            scheduleReconnect()
            return
        }
        pendingToken = token
        candidateQueue = runCatching {
            endpoints.candidatesFor(URI(endpoints.active))
        }.getOrElse { listOfNotNull(runCatching { URI(endpoints.active) }.getOrNull()) }
        connectNext()
    }

    private fun connectNext() {
        val token = pendingToken ?: return
        val base = candidateQueue.firstOrNull()
        if (base == null) {
            scheduleReconnect()
            return
        }
        candidateQueue = candidateQueue.drop(1)
        if (!listening || intentionallyStopped) return

        connectAttempts++
        connectInFlight = true
        publishState()
        currentBase = base
        val request = Request.Builder()
            .url(buildRealtimeUrl(base.toString(), preferences.getDeviceId()))
            .header("Authorization", "Bearer $token")
            .build()
        val socket = socketClient.newWebSocket(request, listener)
        webSocket = socket
        // مهلة إنشاء الاتصال: مقبس شبه مفتوح على شبكة محجوبة كان يعلّق
        // connectInFlight للأبد فتتوقف كل محاولات إعادة الاتصال (Dart).
        watchdogJob?.cancel()
        watchdogJob = scope.launch {
            delay(REALTIME_CONNECT_TIMEOUT_MS)
            if (webSocket === socket && !isConnected()) {
                noteSocketIssue("connect timeout (${REALTIME_CONNECT_TIMEOUT_MS / 1000}s)")
                onSocketDown(socket)
            }
        }
    }

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            if (webSocket !== this@CloudflareRealtimeClient.webSocket) return
            watchdogJob?.cancel()
            watchdogJob = null
            connectInFlight = false
            reconnectAttempt = 0
            rearmJob?.cancel()
            rearmJob = null
            lastConnectedAt = System.currentTimeMillis()
            pushState { it.copy(connected = true, reconnecting = false, connectAttempts = connectAttempts) }
            currentBase?.let { endpoints.reportSuccess(it) }
            // استرداد ما فات أثناء الانقطاع: حدث واحد يطلق سحب دلتا.
            if (recoveryPullPending) {
                recoveryPullPending = false
                scheduler.onRemoteChange()
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            if (webSocket !== this@CloudflareRealtimeClient.webSocket) return
            handleMessageText(text)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            if (webSocket !== this@CloudflareRealtimeClient.webSocket) return
            noteSocketIssue(
                if (reason.isBlank()) "closed $code" else "closed $code: $reason"
            )
            onSocketDown(webSocket)
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            if (webSocket !== this@CloudflareRealtimeClient.webSocket) return
            noteSocketIssue(t.message ?: t.javaClass.simpleName)
            onSocketDown(webSocket)
        }
    }

    /** انقطاع/فشل المقبس الحالي — تدوير مرشّح ثم إعادة اتصال مؤجلة. */
    private fun onSocketDown(socket: WebSocket) {
        watchdogJob?.cancel()
        watchdogJob = null
        connectInFlight = false
        if (webSocket === socket) webSocket = null
        pushState { it.copy(connected = false) }
        currentBase?.let { endpoints.reportFailure(it) }
        if (intentionallyStopped || !listening) return
        // انقطاع غير مقصود — استرداد عند أول اتصال ناجح + إعادة اتصال.
        recoveryPullPending = true
        if (candidateQueue.isNotEmpty()) {
            connectNext()
        } else {
            scheduleReconnect()
        }
    }

    private fun scheduleReconnect() {
        if (intentionallyStopped || !listening) return
        if (reconnectJob != null || connectInFlight) return
        if (reconnectAttempt >= REALTIME_MAX_RECONNECT_ATTEMPTS) {
            // استسلام الاتصال ليس استسلاماً دائماً: إعادة تسليح دورية خفيفة
            // (نداء واحد كل دقيقتين) — أول نجاح يصفّر العداد ويُلغي المؤقت.
            if (rearmJob == null) {
                rearmJob = scope.launch {
                    while (true) {
                        delay(REALTIME_REARM_INTERVAL_MS)
                        if (intentionallyStopped || !listening) {
                            rearmJob = null
                            return@launch
                        }
                        if (isConnected() || connectInFlight || reconnectJob != null) continue
                        reconnectAttempt = 0
                        connect()
                    }
                }
            }
            pushState { it.copy(reconnecting = true) }
            return
        }
        val delayMs = realtimeBackoffDelayMs(reconnectAttempt)
        reconnectAttempt++
        pushState { it.copy(reconnecting = true) }
        reconnectJob = scope.launch {
            delay(delayMs)
            reconnectJob = null
            connect()
        }
    }

    private suspend fun executeTriggeredPull(): Boolean {
        // بلا مسار سحب موصول لا معنى لإعادة الجدولة: نستهلك الحدث بدل حلقة
        // تهدئة لا نهائية كل 15 ثانية (يُوصَل المسار من AutoSyncEngine.start()).
        val trigger = pullTrigger ?: return true
        val succeeded = trigger()
        if (succeeded) clearRemoteChanges()
        return succeeded
    }

    // ─── تشخيصات ─────────────────────────────────────────────────

    private fun isConnected(): Boolean = _realtimeState.value.connected

    private fun noteSocketIssue(detail: String?) {
        lastError = shortenRealtimeError(detail)
        lastErrorAt = System.currentTimeMillis()
        publishState()
    }

    private fun publishState() {
        pushState { it }
    }

    private fun pushState(transform: (RealtimeSyncState) -> RealtimeSyncState) {
        _realtimeState.update { current ->
            transform(
                current.copy(
                    enabled = isEnabled(),
                    connectAttempts = connectAttempts,
                    lastConnectedAt = lastConnectedAt,
                    lastEventAt = lastEventAt,
                    lastError = lastError,
                    lastErrorAt = lastErrorAt
                )
            )
        }
    }

    /** للاختبارات: حقن خطأ اصطناعي بلا شبكة. */
    internal fun noteSocketIssueForTest(detail: String?) = noteSocketIssue(detail)

    /**
     * للاختبارات: محاولة اتصال بلا شبكة. مع غياب توكن Worker يخرج المسار
     * قبل أي `newWebSocket` — آمن تماماً ولا يلمس الشبكة.
     */
    internal fun connectForTest() = connect()

    /** للاختبارات: هل الاستماع قائم؟ */
    internal val isListeningForTest: Boolean get() = listening

    /** للاختبارات: هل هناك سحب مُجدول/جارٍ في طابور الأحداث؟ */
    internal fun cooldownRemainingForTest(): Long = scheduler.cooldownRemainingMs()
}
