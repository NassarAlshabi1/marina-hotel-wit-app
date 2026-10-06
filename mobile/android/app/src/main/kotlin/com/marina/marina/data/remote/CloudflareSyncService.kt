package com.marina.marina.data.remote

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.marina.marina.data.auth.LocalAdminAuth
import com.marina.marina.di.EncryptedSharedPreferencesManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/**
 * ✅ (2026-09-24) أُعيدت كتابة الخدمة على العقد الحقيقي للـ Worker المنشور
 * (نفس مسار Flutter cloudflare_sync_manager.dart):
 *
 *  • login: POST /api/auth/login {username, password, device_id} →
 *    {token, user} — الاستجابة لا تحمل حقل success؛ وجود token = نجاح.
 *  • الدخول التلقائي: [ensureLoggedIn] يسجل الدخول بـ CloudflareConfig
 *    (admin/admin افتراضياً) عند غياب التوكن أو عندما يكون التوكن محلياً
 *    (local:admin-session من [LocalAdminAuth]) — الدخول المحلي يفتح
 *    التطبيق بلا شبكة، والمزامنة تُكمّل الدخول الشبكي كسولاً عند الحاجة.
 *  • pull: GET /api/sync/pull?cursor&limit&exclude_device — سحب دلتا
 *    عبر كل الجداول دفعة واحدة (كل سجل يحمل _entity) + epoch اختياري
 *    لإبطال المؤشر بعد استعادة/إعادة استيراد خادمية.
 *  • push: POST /api/sync/push {operations:[…]} — دفعة واحدة ≤100 عملية.
 */
@Singleton
class CloudflareSyncService @Inject constructor(
    private val api: CloudflareWorkerApi,
    private val config: CloudflareConfig,
    private val preferences: SyncPreferences
) {
    companion object {
        /** محاولات الدخول لأعطال الشبكة العابرة (DNS/socket) — نفس Flutter. */
        private const val LOGIN_ATTEMPTS = 2

        /** مهلة فحص ping — نفس 8s في _probeCustomEndpoint بـ Dart. */
        private const val PING_TIMEOUT_MS = 8_000L
    }

    /** كائن المستخدم من آخر دخول ناجح (id/username/role) — يستخدمه AuthRepository
     * لبناء هوية RBAC الحقيقية (Dart auth_local_store.dart l.355-412). */
    var lastLoginUser: WorkerLoginUser? = null
        private set

    // ─── Login ───────────────────────────────────────────────────

    /**
     * تسجيل دخول صريح باعتمادات معطاة. نجاح = استجابة تحمل token.
     * يُعيد التوكن ويحفظه (نفس عقد Flutter: _token + تخزين دائم).
     */
    suspend fun login(username: String, password: String): Result<String> =
        withContext(Dispatchers.IO) {
            val deviceId = ensureDeviceId()
            var lastError: Exception? = null
            repeat(LOGIN_ATTEMPTS) {
                try {
                    val response = api.login(
                        WorkerLoginRequest(username.trim(), password, deviceId)
                    ).execute()
                    val body = response.body()
                    if (response.isSuccessful && !body?.token.isNullOrEmpty()) {
                        val token = body!!.token!!
                        lastLoginUser = body.user
                        preferences.saveAuthToken(token)
                        return@withContext Result.success(token)
                    }
                    // 401 واضح — لا معنى لإعادة المحاولة بنفس الاعتمادات.
                    if (response.code() == 401 || response.code() == 400) {
                        return@withContext Result.failure(
                            Exception(body?.user?.let { "Invalid credentials" }
                                ?: "Login failed: HTTP ${response.code()}")
                        )
                    }
                    lastError = Exception("Login failed: HTTP ${response.code()}")
                } catch (e: Exception) {
                    lastError = e
                }
            }
            Result.failure(lastError ?: Exception("Login failed"))
        }

    /**
     * الدخول التلقائي (طلب المستخدم 2026-09-11): يضمن توكن Worker صالحاً
     * قبل أي مزامنة. يعيد true عندما يكون التوكن الحالي JWT خادمياً أو
     * نجح الدخول بـ CloudflareConfig (admin/admin افتراضياً). يفشل بصمت
     * على الشبكات المحجوبة — دورة المزامنة تُبلَّغ وستعيد المحاولة لاحقاً.
     */
    suspend fun ensureLoggedIn(): Boolean {
        val current = preferences.getAuthToken()
        // التوكن المحلي (local:admin-session) يفتح التطبيق فقط — ليس Bearer
        // صالحاً لمسارات المزامنة؛ نحتاج JWT من الخادم.
        if (!current.isNullOrEmpty() && !LocalAdminAuth.isLocalAdminToken(current)) {
            return true
        }
        val result = login(config.username, config.password)
        return result.isSuccess
    }

    /** هل بين أيدينا JWT خادمي صالح للمزامنة؟ */
    fun hasWorkerToken(): Boolean {
        val token = preferences.getAuthToken()
        return !token.isNullOrEmpty() && !LocalAdminAuth.isLocalAdminToken(token)
    }

    // ─── Health / stats ──────────────────────────────────────────

    /** فحص حيوية الخادم — يُستخدم من زر «فحص الاتصال» في شاشة الدخول. */
    suspend fun health(): Result<WorkerHealthResponse> = withContext(Dispatchers.IO) {
        try {
            val response = api.health().execute()
            val body = response.body()
            if (response.isSuccessful && body != null) Result.success(body)
            else Result.failure(Exception("HTTP ${response.code()}"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * ✅ (2026-09-24) فحص ping خفيف — نقل `_probeCustomEndpoint` من
     * unified_sync_settings_screen.dart: GET /api/ping بمهلة 8 ثوانٍ —
     * عميل عادي بلا تدوير لنقيس العنوان نفسه. يعيد زمن الاستجابة بالمللي
     * ثانية عند النجاح.
     */
    suspend fun ping(): Result<Long> = withContext(Dispatchers.IO) {
        try {
            withTimeout(PING_TIMEOUT_MS) {
                val startedAt = System.currentTimeMillis()
                val response = api.ping().execute()
                val elapsed = System.currentTimeMillis() - startedAt
                val body = response.body()
                if (response.isSuccessful && body?.status == "ok") Result.success(elapsed)
                else Result.failure(Exception("HTTP ${response.code()}"))
            }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            Result.failure(Exception("انتهت المهلة (8s)"))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Bounded authenticated D1 + source-identity probe. It reads health and
     * protocol metadata only; no business rows, cursor, epoch, or outbox state
     * are modified. Expired JWTs are refreshed once.
     */
    suspend fun syncSourceHealth(): Result<WorkerD1HealthResponse> = withContext(Dispatchers.IO) {
        kotlinx.coroutines.withTimeoutOrNull(PING_TIMEOUT_MS) {
            suspend fun authenticate(): Boolean {
                val response = api.login(
                    WorkerLoginRequest(config.username, config.password, ensureDeviceId())
                ).awaitProbeResponse()
                val body = response.body()
                if (!response.isSuccessful || body?.token.isNullOrBlank()) return false
                preferences.saveAuthToken(body!!.token!!)
                lastLoginUser = body.user
                return true
            }

            try {
                if (!hasWorkerToken() && !authenticate()) {
                    return@withTimeoutOrNull Result.failure(Exception("Worker authentication failed"))
                }
                var response = api.d1Health().awaitProbeResponse()
                // Expired JWT: refresh once, not an infinite retry or a bootstrap operation.
                if (response.code() == 401) {
                    if (!authenticate()) {
                        return@withTimeoutOrNull Result.failure(Exception("Worker authentication failed"))
                    }
                    response = api.d1Health().awaitProbeResponse()
                }
                val body = response.body()
                if (response.isSuccessful && body?.status == "ok" && body.d1 == "ok") {
                    Result.success(body)
                } else {
                    Result.failure(Exception("Authenticated D1 health failed: HTTP ${response.code()}"))
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                Result.failure(error)
            }
        } ?: Result.failure(Exception("D1/source identity probe timed out after ${PING_TIMEOUT_MS}ms"))
    }

    /** Connection-only check retained for diagnostics; sync additionally requires a source identity. */
    suspend fun checkD1Connection(): Boolean = syncSourceHealth().isSuccess

    /** عدّادات كل الجداول في D1 — تشخيص حالة القاعدة السحابية. */
    suspend fun stats(): Result<Map<String, Int>> = withContext(Dispatchers.IO) {
        try {
            val response = api.stats().execute()
            val body = response.body()
            if (response.isSuccessful && body?.tables != null) {
                Result.success(body.tables.mapValues { it.value.toInt() })
            } else {
                Result.failure(Exception("HTTP ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // ─── Pull ────────────────────────────────────────────────────

    /**
     * سحب دلتا (أو سحب كامل عند cursor=0). excludeDevice يمنع صدى
     * سجلات الجهاز نفسه (خطة 2.5) — ⚠️ (2026-09-25) السحب الكامل وحده
     * لا يمرره إطلاقاً (عقد Dart: excludeOwnDevice: !wasFullSync —
     * الجهاز يجب أن يتعلم ظلّ server_id لصفوفه هو). المؤشر المرجَع
     * دائماً هو مؤشر الخادم (updated_at المُخصص من sync_clock).
     */
    suspend fun pull(
        cursor: Long,
        limit: Int = CloudflareConfig.DELTA_PULL_BATCH_SIZE,
        excludeDevice: String? = null,
        includeRemaining: Boolean? = null,
        normalizeTimestamps: Boolean? = null
    ): Result<WorkerPullResponse> = withContext(Dispatchers.IO) {
        try {
            val response = api.pull(
                cursor, limit, excludeDevice,
                includeRemaining, normalizeTimestamps
            ).execute()
            val body = response.body()
            when {
                response.isSuccessful && body != null -> Result.success(body)
                else -> Result.failure(Exception("HTTP ${response.code()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // ─── Push ────────────────────────────────────────────────────

    /**
     * دفع دفعة عمليات. الاستدعاء مسؤول عن احترام سقف 100 عملية/نداء.
     * عقد النتيجة: نجاح الاستدعاء ≠ نجاح كل عملية — يُقرأ results لكل
     * عملية على حدة (success/skipped/status).
     */
    suspend fun push(operations: List<WorkerPushOperation>): Result<WorkerPushResponse> =
        withContext(Dispatchers.IO) {
            if (operations.isEmpty()) {
                return@withContext Result.success(
                    WorkerPushResponse(results = emptyList(), summary = WorkerPushSummary(0, 0, 0, 0))
                )
            }
            if (operations.size > CloudflareConfig.PUSH_BATCH_SIZE) {
                return@withContext Result.failure(
                    Exception("Max ${CloudflareConfig.PUSH_BATCH_SIZE} operations per batch")
                )
            }
            try {
                if (operations.any { it.entity == "expenses" && it.operation != "delete" && it.data["expense_kind"] != null }) {
                    // An older Worker silently filters unknown columns. Never
                    // send a typed financial edit until server AND schema opt in.
                    val health = withTimeout(8_000L) { api.d1Health().awaitProbeResponse() }
                    val capability = health.body()
                    check(health.isSuccessful && capability?.status == "ok" && capability.d1 == "ok" &&
                        capability.expenseKindSupported == true) {
                        "يلزم تحديث Worker وترحيل D1 رقم 0015 قبل رفع أنواع المصروفات؛ بقيت التغييرات محلياً"
                    }
                }
                val response = api.push(WorkerPushRequest(operations)).execute()
                val body = response.body()
                when {
                    response.isSuccessful && body != null -> Result.success(body)
                    else -> Result.failure(Exception("HTTP ${response.code()}"))
                }
            } catch (e: Exception) {
                Result.failure(e)
            }
        }

    // ─── Device identity ─────────────────────────────────────────

    private fun ensureDeviceId(): String {
        val existing = preferences.getDeviceId()
        if (!existing.isNullOrEmpty()) return existing
        val deviceId = "cf_dev_${System.currentTimeMillis()}"
        preferences.saveDeviceId(deviceId)
        return deviceId
    }
}

/** تفاصيل آمنة ومحدودة لخطأ مزامنة محفوظ محلياً لعرضه في شاشة التشخيص. */
data class SyncErrorRecord(
    val id: String = "",
    val occurredAtMillis: Long = 0L,
    val operation: String = "sync",
    val message: String = "",
    val pullCursor: Long = 0L,
    val deviceId: String? = null
)

/**
 * تخزين حالة المزامنة (توكن/مؤشرات/جهاز) — نفس المفاتيح السابقة مع
 * إضافة مؤشر السحب العام (last pull cursor) الذي يفرضه عقد الخادم.
 */
@Singleton
class SyncPreferences @Inject constructor(
    private val preferencesManager: EncryptedSharedPreferencesManager
) {
    companion object {
        private const val KEY_AUTH_TOKEN = "auth_token"
        private const val KEY_LAST_PULL = "last_pull_ts"
        private const val KEY_LAST_PUSH = "last_push_ts"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_FULL_SYNC_COMPLETE = "full_sync_complete"
        private const val KEY_CURRENT_USER = "current_user_json"
        private const val KEY_LAST_PULL_CURSOR = "last_pull_cursor"
        private const val KEY_FULL_REPLAY_PENDING = "cf_full_replay_pending"
        private const val KEY_SYNC_EPOCH = "cf_sync_epoch"
        private const val KEY_SYNC_SOURCE_ID = "sync_source_id"
        private const val KEY_SYNC_ERROR_HISTORY = "cf_sync_error_history"
        private const val MAX_SYNC_ERROR_RECORDS = 40
        private const val MAX_SYNC_ERROR_MESSAGE_LENGTH = 2_500

        // ✅ (2026-09-24) مفاتيح إعدادات المزامنة — نفس سلاسل Dart حرفياً
        // (unified_sync_settings_screen.dart l.59-68) لضمان التوافق.
        private const val KEY_AUTO_SYNC_ENABLED = "appwrite_auto_sync_enabled"
        private const val KEY_SYNC_ON_STARTUP = "appwrite_sync_on_startup"
        private const val KEY_BATTERY_OPTIMIZATION = "battery_optimization_enabled"
        private const val KEY_WIFI_ONLY = "wifi_only_sync"
        private const val KEY_SMART_SYNC = "smart_sync_enabled"
        private const val KEY_CLOUDFLARE_SYNC = "appwrite_sync_enabled"
        private const val KEY_REALTIME_SYNC = "appwrite_realtime_sync_enabled"
        private const val KEY_SYNC_INTERVAL = "appwrite_sync_interval_minutes"

        /** ✅ (2026-09-24) تفضيل «تذكرني» — نظير AuthLocalStore في Dart. */
        private const val KEY_REMEMBER_ME = "remember_me"

        /** ✅ (2026-09-25) علم تطبيع الطوابع الخادمي (normalize_timestamps مرة واحدة). */
        private const val KEY_TS_NORMALIZATION_DONE = "cf_timestamp_normalization_done"
    }

    private val syncErrorHistoryGson = Gson()
    private val syncErrorHistoryType = object : TypeToken<List<SyncErrorRecord>>() {}.type

    /** حفظ آخر الأخطاء محلياً؛ لا تُخزّن حمولة السجلات أو رموز الدخول. */
    @Synchronized
    fun recordSyncError(
        operation: String,
        message: String,
        pullCursor: Long,
        deviceId: String?
    ) {
        val safeMessage = message
            .replace(Regex("(?i)bearer\\s+[^\\s,;]+"), "Bearer [محذوف]")
            .take(MAX_SYNC_ERROR_MESSAGE_LENGTH)
        val entry = SyncErrorRecord(
            id = UUID.randomUUID().toString(),
            occurredAtMillis = System.currentTimeMillis(),
            operation = operation.take(40),
            message = safeMessage,
            pullCursor = pullCursor,
            deviceId = deviceId?.take(100)
        )
        val updated = (listOf(entry) + getSyncErrorHistory()).take(MAX_SYNC_ERROR_RECORDS)
        preferencesManager.saveString(KEY_SYNC_ERROR_HISTORY, syncErrorHistoryGson.toJson(updated))
    }

    fun getSyncErrorHistory(): List<SyncErrorRecord> {
        val serialized = preferencesManager.getString(KEY_SYNC_ERROR_HISTORY) ?: return emptyList()
        return runCatching {
            syncErrorHistoryGson.fromJson<List<SyncErrorRecord>>(serialized, syncErrorHistoryType)
                .orEmpty()
        }.getOrDefault(emptyList())
    }

    @Synchronized
    fun clearSyncErrorHistory() {
        preferencesManager.saveString(KEY_SYNC_ERROR_HISTORY, "[]")
    }

    /** يثبّت المستخدم الداخل (JSON) كي تحتفظ استعادة الجلسة بالهوية الحقيقية. */
    fun saveCurrentUserJson(json: String) {
        preferencesManager.saveString(KEY_CURRENT_USER, json)
    }

    fun getCurrentUserJson(): String? {
        return preferencesManager.getString(KEY_CURRENT_USER)
    }

    fun clearCurrentUser() {
        preferencesManager.saveString(KEY_CURRENT_USER, "")
    }

    fun saveAuthToken(token: String) {
        preferencesManager.saveString(KEY_AUTH_TOKEN, token)
    }

    fun getAuthToken(): String? {
        return preferencesManager.getString(KEY_AUTH_TOKEN)
    }

    fun saveLastPullTs(ts: Long) {
        preferencesManager.saveLong(KEY_LAST_PULL, ts)
    }

    fun getLastPullTs(): Long {
        return preferencesManager.getLong(KEY_LAST_PULL, 0L)
    }

    fun saveLastPushTs(ts: Long) {
        preferencesManager.saveLong(KEY_LAST_PUSH, ts)
    }

    fun getLastPushTs(): Long {
        return preferencesManager.getLong(KEY_LAST_PUSH, 0L)
    }

    fun saveDeviceId(deviceId: String) {
        preferencesManager.saveString(KEY_DEVICE_ID, deviceId)
    }

    fun getDeviceId(): String? {
        return preferencesManager.getString(KEY_DEVICE_ID)
    }

    fun isFullSyncComplete(): Boolean {
        return preferencesManager.getBoolean(KEY_FULL_SYNC_COMPLETE, false)
    }

    fun setFullSyncComplete(complete: Boolean) {
        preferencesManager.putBoolean(KEY_FULL_SYNC_COMPLETE, complete)
    }

    // ─── مؤشر السحب العام (عقد worker: cursor updated_at) ───────

    fun prepareForLocalRestore(sourceIdFromBackup: String? = null) {
        val values = mutableMapOf<String, Any>(
            KEY_CLOUDFLARE_SYNC to false,
            KEY_LAST_PULL_CURSOR to 0L,
            KEY_LAST_PULL to 0L,
            KEY_FULL_REPLAY_PENDING to true,
            KEY_FULL_SYNC_COMPLETE to false,
            KEY_TS_NORMALIZATION_DONE to false
        )
        sourceIdFromBackup?.trim()?.takeIf { it.isNotEmpty() }?.let {
            values[KEY_SYNC_SOURCE_ID] = it.lowercase()
        }
        preferencesManager.commitValues(values)
    }

    fun saveLastPullCursor(cursor: Long) {
        preferencesManager.saveLong(KEY_LAST_PULL_CURSOR, cursor)
    }

    fun getLastPullCursor(): Long {
        return preferencesManager.getLong(KEY_LAST_PULL_CURSOR, 0L)
    }

    fun isFullReplayPending(): Boolean = preferencesManager.getBoolean(KEY_FULL_REPLAY_PENDING, false)

    fun setFullReplayPending(pending: Boolean) {
        preferencesManager.putBoolean(KEY_FULL_REPLAY_PENDING, pending)
    }

    /** آخر جيل خادمي معتمد؛ null قبل أول استجابة Worker تحمل epoch. */
    fun getSyncEpoch(): String? =
        preferencesManager.getString(KEY_SYNC_EPOCH)?.trim()?.takeIf { it.isNotEmpty() }

    fun saveSyncEpoch(epoch: String) {
        preferencesManager.saveString(KEY_SYNC_EPOCH, epoch.trim())
    }

    /** Stable per-installation source binding, independent of cursor/epoch. */
    fun getSyncSourceId(): String? =
        preferencesManager.getString(KEY_SYNC_SOURCE_ID)?.trim()?.takeIf { it.isNotEmpty() }

    fun saveSyncSourceId(sourceId: String) {
        preferencesManager.saveString(KEY_SYNC_SOURCE_ID, sourceId.trim().lowercase())
    }

    // ─── ✅ (2026-09-25) علم تطبيع الطوابع الخادمي ───────────────
    //
    // normalize_timestamps=1 يُطلب في أول صفحة من أول سحب كامل فقط
    // (شفاء خادمي لطوابع المللي القديمة — عقد Dart
    // _timestampNormalizationDone) — الطلب في كل دورة يضاعف زمن السحب.

    fun isTimestampNormalizationDone(): Boolean =
        preferencesManager.getBoolean(KEY_TS_NORMALIZATION_DONE, false)

    fun setTimestampNormalizationDone(done: Boolean) {
        preferencesManager.putBoolean(KEY_TS_NORMALIZATION_DONE, done)
    }

    // ─── ✅ (2026-09-24) إعدادات المزامنة — نفس مفاتيح Dart ─────
    //
    // نقل 1:1 لمفاتيح unified_sync_settings_screen.dart (فرع
    // feat/cloudflare-sync-execution) — «هذه المفاتيح متوافقة مع
    // القارئات الحقيقية في sync_performance_optimizer.dart و
    // smart_sync_manager.dart — لا مفاتيح ميتة» (تعليق Dart P0).

    /** تفعيل المزامنة التلقائية (appwrite_auto_sync_enabled — افتراضياً true). */
    fun getAutoSyncEnabled(): Boolean =
        preferencesManager.getBoolean(KEY_AUTO_SYNC_ENABLED, true)

    fun setAutoSyncEnabled(enabled: Boolean) {
        preferencesManager.putBoolean(KEY_AUTO_SYNC_ENABLED, enabled)
    }

    /** المزامنة عند بدء التشغيل (appwrite_sync_on_startup — افتراضياً true). */
    fun getSyncOnStartup(): Boolean =
        preferencesManager.getBoolean(KEY_SYNC_ON_STARTUP, true)

    fun setSyncOnStartup(enabled: Boolean) {
        preferencesManager.putBoolean(KEY_SYNC_ON_STARTUP, enabled)
    }

    /** تحسين البطارية (battery_optimization_enabled — افتراضياً true). */
    fun getBatteryOptimization(): Boolean =
        preferencesManager.getBoolean(KEY_BATTERY_OPTIMIZATION, true)

    fun setBatteryOptimization(enabled: Boolean) {
        preferencesManager.putBoolean(KEY_BATTERY_OPTIMIZATION, enabled)
    }

    /** WiFi فقط (wifi_only_sync — افتراضياً false). */
    fun getWifiOnly(): Boolean =
        preferencesManager.getBoolean(KEY_WIFI_ONLY, false)

    fun setWifiOnly(enabled: Boolean) {
        preferencesManager.putBoolean(KEY_WIFI_ONLY, enabled)
    }

    /** المزامنة الذكية (smart_sync_enabled — افتراضياً true). */
    fun getSmartSyncEnabled(): Boolean =
        preferencesManager.getBoolean(KEY_SMART_SYNC, true)

    fun setSmartSyncEnabled(enabled: Boolean) {
        preferencesManager.putBoolean(KEY_SMART_SYNC, enabled)
    }

    /** تفعيل مزامنة Cloudflare (appwrite_sync_enabled — افتراضياً true). */
    fun getCloudflareSyncEnabled(): Boolean =
        preferencesManager.getBoolean(KEY_CLOUDFLARE_SYNC, true)

    fun setCloudflareSyncEnabled(enabled: Boolean) {
        preferencesManager.putBoolean(KEY_CLOUDFLARE_SYNC, enabled)
    }

    /** المزامنة الفورية Realtime (appwrite_realtime_sync_enabled — افتراضياً true). */
    fun getRealtimeSyncEnabled(): Boolean =
        preferencesManager.getBoolean(KEY_REALTIME_SYNC, true)

    fun setRealtimeSyncEnabled(enabled: Boolean) {
        preferencesManager.putBoolean(KEY_REALTIME_SYNC, enabled)
    }

    /** فترة المزامنة بالدقائق (appwrite_sync_interval_minutes — افتراضياً 15). */
    fun getSyncIntervalMinutes(): Int =
        preferencesManager.getLong(KEY_SYNC_INTERVAL, 15L).toInt()

    fun setSyncIntervalMinutes(minutes: Int) {
        preferencesManager.saveLong(KEY_SYNC_INTERVAL, minutes.toLong())
    }

    /** ✅ «تذكرني» — الافتراضي true مثل Dart (_rememberMe = true). */
    fun getRememberMe(): Boolean = preferencesManager.getBoolean(KEY_REMEMBER_ME, true)

    fun setRememberMe(value: Boolean) {
        preferencesManager.putBoolean(KEY_REMEMBER_ME, value)
    }
}
