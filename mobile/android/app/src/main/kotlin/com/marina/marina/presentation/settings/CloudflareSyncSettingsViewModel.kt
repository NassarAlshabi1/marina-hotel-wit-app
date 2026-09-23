package com.marina.marina.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.SyncPreferences
import com.marina.marina.data.remote.WorkerEndpoints
import com.marina.marina.domain.repository.SyncRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * ✅ (2026-09-24) حالة شاشة «إعدادات المزامنة» — نقل 1:1 لـ
 * unified_sync_settings_screen.dart (فرع feat/cloudflare-sync-execution):
 *
 *  • نظرة عامة: آخر مزامنة (وقت نسبي) + حالة الاتصال + عناصر معلّقة.
 *  • تسجيل الدخول إلى Cloudflare: حالة الحساب + اسم المستخدم + آخر خطأ.
 *  • الإعدادات العامة: مزامنة تلقائية · عند بدء التشغيل · فترة المزامنة
 *    (بنفس مفاتيح SharedPreferences ورسائل النجاح حرفياً).
 *  • الأداء والبطارية: تحسين البطارية · WiFi فقط.
 *  • المزامنة الذكية · Cloudflare Sync (تفعيل + Realtime).
 *  • نطاق Worker مخصّص: تطبيع + حفظ/مسح + فحص اتصال /api/ping بمهلة 8s.
 *  • أدوات المزامنة اليدوية: سحب دلتا · سحب كامل (تصفير المؤشر) · رفع
 *    محلي — بنفس حواجز Dart (outbox غير فارغ يحجب السحب) ورسائلها.
 */
@HiltViewModel
class CloudflareSyncSettingsViewModel @Inject constructor(
    private val syncPreferences: SyncPreferences,
    private val syncRepository: SyncRepository,
    private val syncService: CloudflareSyncService,
    private val cloudflareConfig: CloudflareConfig,
    private val workerEndpoints: WorkerEndpoints
) : ViewModel() {

    /** رسالة سناك-بار مع لون النتيجة (نظير _showSyncResultSnack في Dart). */
    data class SnackbarMessage(val text: String, val success: Boolean)

    data class CloudflareSyncSettingsUiState(
        // ─── الإعدادات العامة ────────────────────────────────────
        val autoSyncEnabled: Boolean = true,
        val syncOnStartup: Boolean = true,
        val syncIntervalMinutes: Int = 15,
        // ─── الأداء والبطارية ────────────────────────────────────
        val batteryOptimization: Boolean = true,
        val wifiOnly: Boolean = false,
        // ─── المزامنة الذكية ─────────────────────────────────────
        val smartSyncEnabled: Boolean = true,
        // ─── Cloudflare Sync ─────────────────────────────────────
        val cloudflareSyncEnabled: Boolean = true,
        val realtimeSyncEnabled: Boolean = true,
        // ─── نظرة عامة (حالة المزامنة) ───────────────────────────
        val lastSyncText: String = "لم تُنفَّذ مزامنة بعد",
        val isConnected: Boolean? = null,
        val pendingCount: Int = 0,
        // ─── تسجيل الدخول إلى Cloudflare ─────────────────────────
        val loggedIn: Boolean = false,
        val username: String = CloudflareConfig.DEFAULT_USERNAME,
        val lastError: String? = null,
        // ─── نطاق Worker مخصّص ───────────────────────────────────
        val activeHost: String = "",
        val customUrlField: String = "",
        val hasCustomEndpoint: Boolean = false,
        val isProbingEndpoint: Boolean = false,
        val endpointProbeResult: String? = null,
        val endpointProbeOk: Boolean? = null,
        // ─── حالة عامة ───────────────────────────────────────────
        val isSaving: Boolean = false,
        val isManualSyncing: Boolean = false,
        val isSyncing: Boolean = false,
        val snackbar: SnackbarMessage? = null
    )

    private val _state = MutableStateFlow(CloudflareSyncSettingsUiState())
    val state: StateFlow<CloudflareSyncSettingsUiState> = _state.asStateFlow()

    init {
        loadSettings()
        observePendingCount()
        observeSyncState()
        refreshConnection()
    }

    // ─── التحميل الأولي ──────────────────────────────────────────

    /** تحميل كل المفاتيح — نفس _loadSettings في Dart (نفس الافتراضيات). */
    private fun loadSettings() {
        _state.value = _state.value.copy(
            autoSyncEnabled = syncPreferences.getAutoSyncEnabled(),
            syncOnStartup = syncPreferences.getSyncOnStartup(),
            syncIntervalMinutes = syncPreferences.getSyncIntervalMinutes(),
            batteryOptimization = syncPreferences.getBatteryOptimization(),
            wifiOnly = syncPreferences.getWifiOnly(),
            smartSyncEnabled = syncPreferences.getSmartSyncEnabled(),
            cloudflareSyncEnabled = syncPreferences.getCloudflareSyncEnabled(),
            realtimeSyncEnabled = syncPreferences.getRealtimeSyncEnabled(),
            loggedIn = syncService.hasWorkerToken(),
            username = cloudflareConfig.username,
            customUrlField = workerEndpoints.custom ?: "",
            hasCustomEndpoint = workerEndpoints.hasCustom,
            activeHost = hostOf(workerEndpoints.active)
        )
    }

    /** عدّ المعلّق الحي من قاعدة البيانات — نفس outboxCountProvider في Dart. */
    private fun observePendingCount() {
        syncRepository.pendingCount().onEach { pending ->
            _state.value = _state.value.copy(pendingCount = pending)
        }.launchIn(viewModelScope)
    }

    /** حالة المزامنة الحية (isSyncing/آخر رسالة/آخر وقت نجاح). */
    private fun observeSyncState() {
        syncRepository.syncState.onEach { sync ->
            val lastError = if (sync.isError && sync.lastMessage.isNotBlank()) sync.lastMessage else null
            _state.value = _state.value.copy(
                isSyncing = sync.isSyncing,
                lastError = lastError,
                lastSyncText = if (sync.lastSyncAt > 0) relativeTimeAr(sync.lastSyncAt)
                else _state.value.lastSyncText
            )
        }.launchIn(viewModelScope)
    }

    // ─── نظرة عامة ───────────────────────────────────────────────

    /**
     * فحص اتصال حي — النظير العملي لـ checkConnection في Dart
     * (manager.isAvailable && manager.lastError == null). بمهلة 15s حتى
     * لا يعلّق الفحص على شبكات محجوبة.
     */
    fun refreshConnection() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isConnected = null)
            val ok = try {
                withTimeout(15_000L) {
                    syncService.health().map { it.status == "ok" }.getOrDefault(false)
                }
            } catch (e: TimeoutCancellationException) {
                false
            } catch (e: Exception) {
                false
            }
            _state.value = _state.value.copy(isConnected = ok)
        }
    }

    // ─── الإعدادات العامة (Switches — نفس رسائل Dart) ───────────

    fun setAutoSyncEnabled(enabled: Boolean) = saveBoolSetting(
        persist = { syncPreferences.setAutoSyncEnabled(enabled) },
        update = { copy(autoSyncEnabled = enabled) },
        successMessage = if (enabled) "تم تفعيل المزامنة التلقائية" else "تم إيقاف المزامنة التلقائية"
    )

    fun setSyncOnStartup(enabled: Boolean) = saveBoolSetting(
        persist = { syncPreferences.setSyncOnStartup(enabled) },
        update = { copy(syncOnStartup = enabled) },
        successMessage = if (enabled) "ستعمل المزامنة عند بدء التطبيق" else "لن تعمل المزامنة تلقائياً عند البدء"
    )

    fun setBatteryOptimization(enabled: Boolean) = saveBoolSetting(
        persist = { syncPreferences.setBatteryOptimization(enabled) },
        update = { copy(batteryOptimization = enabled) },
        successMessage = if (enabled) "تم تفعيل تحسين البطارية" else "تم إيقاف تحسين البطارية"
    )

    fun setWifiOnly(enabled: Boolean) = saveBoolSetting(
        persist = { syncPreferences.setWifiOnly(enabled) },
        update = { copy(wifiOnly = enabled) },
        successMessage = if (enabled) "ستقتصر المزامنة على WiFi" else "ستعمل المزامنة على جميع الشبكات"
    )

    fun setSmartSyncEnabled(enabled: Boolean) = saveBoolSetting(
        persist = { syncPreferences.setSmartSyncEnabled(enabled) },
        update = { copy(smartSyncEnabled = enabled) },
        successMessage = if (enabled) "تم تفعيل المزامنة الذكية" else "تم إيقاف المزامنة الذكية"
    )

    fun setCloudflareSyncEnabled(enabled: Boolean) = saveBoolSetting(
        persist = { syncPreferences.setCloudflareSyncEnabled(enabled) },
        update = { copy(cloudflareSyncEnabled = enabled) },
        successMessage = if (enabled) "تم تفعيل مزامنة Cloudflare" else "تم إيقاف مزامنة Cloudflare"
    )

    fun setRealtimeSyncEnabled(enabled: Boolean) = saveBoolSetting(
        persist = { syncPreferences.setRealtimeSyncEnabled(enabled) },
        update = { copy(realtimeSyncEnabled = enabled) },
        successMessage = if (enabled) "تم تفعيل المزامنة الفورية" else "تم إيقاف المزامنة الفورية"
    )

    /** نفس _selectSyncInterval في Dart: حفظ + إشعار بالقيمة الجديدة. */
    fun selectSyncInterval(minutes: Int) {
        if (_state.value.isSaving) return
        viewModelScope.launch {
            try {
                syncPreferences.setSyncIntervalMinutes(minutes)
                _state.value = _state.value.copy(
                    isSaving = false,
                    syncIntervalMinutes = minutes,
                    snackbar = SnackbarMessage("تم ضبط فترة المزامنة على كل $minutes دقيقة", success = true)
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    snackbar = SnackbarMessage("تعذر تحديث فترة المزامنة. حاول مرة أخرى.", success = false)
                )
            }
        }
    }

    private fun saveBoolSetting(
        persist: () -> Unit,
        update: CloudflareSyncSettingsUiState.() -> CloudflareSyncSettingsUiState,
        successMessage: String
    ) {
        if (_state.value.isSaving) return
        viewModelScope.launch {
            try {
                persist()
                _state.value = _state.value.update().copy(
                    isSaving = false,
                    snackbar = SnackbarMessage(successMessage, success = true)
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    snackbar = SnackbarMessage("تعذر حفظ الإعداد. حاول مرة أخرى.", success = false)
                )
            }
        }
    }

    // ─── نطاق Worker مخصّص (نفس _buildWorkerEndpointSection) ─────

    fun onCustomUrlFieldChange(text: String) {
        _state.value = _state.value.copy(customUrlField = text)
    }

    /**
     * حفظ النطاق المُدخل (تطبيع + تخزين) ثم فحص فوري — نفس
     * _saveCustomEndpoint في Dart مع رسائله حرفياً.
     */
    fun saveCustomEndpoint() {
        viewModelScope.launch {
            val normalized = try {
                workerEndpoints.setCustomUrl(_state.value.customUrlField)
            } catch (e: IllegalArgumentException) {
                _state.value = _state.value.copy(
                    snackbar = SnackbarMessage(e.message ?: "رابط غير صالح", success = false)
                )
                return@launch
            }
            _state.value = _state.value.copy(
                customUrlField = normalized ?: "",
                hasCustomEndpoint = workerEndpoints.hasCustom,
                activeHost = hostOf(workerEndpoints.active),
                endpointProbeResult = null,
                endpointProbeOk = null,
                snackbar = SnackbarMessage(
                    if (normalized == null) "تم مسح النطاق المخصّص — الرجوع للنطاق المدمج"
                    else "تم حفظ النطاق: $normalized",
                    success = true
                )
            )
            if (normalized != null) probeCustomEndpoint()
        }
    }

    /** مسح النطاق المخصّص والرجوع للمدمج — نفس _clearCustomEndpoint. */
    fun clearCustomEndpoint() {
        viewModelScope.launch {
            try {
                workerEndpoints.setCustomUrl(null)
                _state.value = _state.value.copy(
                    customUrlField = "",
                    hasCustomEndpoint = false,
                    activeHost = hostOf(workerEndpoints.active),
                    endpointProbeResult = null,
                    endpointProbeOk = null,
                    snackbar = SnackbarMessage("تم المسح — الرجوع للنطاق المدمج workers.dev", success = true)
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    snackbar = SnackbarMessage("تعذر المسح: $e", success = false)
                )
            }
        }
    }

    /**
     * فحص صريح للنطاق المُدخل (أو الفعّال إن كان الحقل فارغاً):
     * GET /api/ping بمهلة 8s — نفس _probeCustomEndpoint في Dart.
     */
    fun probeCustomEndpoint() {
        viewModelScope.launch {
            val raw = _state.value.customUrlField.trim().ifEmpty { workerEndpoints.active }
            val normalized = try {
                workerEndpoints.normalizeCustomUrl(raw)
            } catch (e: IllegalArgumentException) {
                _state.value = _state.value.copy(endpointProbeOk = false, endpointProbeResult = e.message)
                return@launch
            }
            if (normalized == null) {
                _state.value = _state.value.copy(
                    endpointProbeOk = false,
                    endpointProbeResult = "أدخل نطاقاً أولاً"
                )
                return@launch
            }

            _state.value = _state.value.copy(isProbingEndpoint = true)
            syncService.ping().fold(
                onSuccess = { elapsedMs ->
                    _state.value = _state.value.copy(
                        isProbingEndpoint = false,
                        endpointProbeOk = true,
                        endpointProbeResult = "نجح الاتصال (200) في ${elapsedMs}ms"
                    )
                },
                onFailure = { error ->
                    val message = error.message ?: error.toString()
                    val friendly = when {
                        message.contains("انتهت المهلة") ->
                            "انتهت المهلة (8s) — النطاق غير قابل للوصول من هذه الشبكة"
                        message.startsWith("HTTP") ->
                            "استجابة غير متوقعة: $message"
                        else -> "فشل الاتصال: $message"
                    }
                    _state.value = _state.value.copy(
                        isProbingEndpoint = false,
                        endpointProbeOk = false,
                        endpointProbeResult = friendly
                    )
                }
            )
        }
    }

    // ─── أدوات المزامنة اليدوية (نفس _buildManualActionsSection) ─

    /**
     * «سحب التغييرات الآن» — سحب دلتا فقط: يُحجب إن وُجدت سجلات محلية
     * غير مُسلّمة في outbox (يجب رفعها أولاً) — نفس عقد Dart.
     */
    fun runPullNow() {
        if (_state.value.isManualSyncing) return
        _state.value = _state.value.copy(isManualSyncing = true)
        viewModelScope.launch {
            try {
                if (!_state.value.cloudflareSyncEnabled) {
                    showSyncSnack(false, "❌ مزامنة Cloudflare معطّلة — فعّلها من قسم Cloudflare Sync أعلاه")
                    return@launch
                }
                // 1) فحص outbox المحلي (عدّ حقيقي من قاعدة البيانات).
                val pending = syncRepository.pendingCount().first()
                if (pending > 0) {
                    showSyncSnack(
                        false,
                        "⬆️ يوجد $pending تغييراً محلياً غير مرفوع — استخدم «رفع التغييرات المحلية» أدناه أولاً"
                    )
                    return@launch
                }

                // 2) فحص الاتصال بالـ Worker.
                if (!ensureCloudflareConnected()) return@launch

                // 3) السحب — المدير يصادم الحماية داخلياً (isSyncing).
                val pulled = syncRepository.pullOnly()
                when {
                    pulled == -1 -> showSyncSnack(
                        false,
                        "❌ تعذر السحب: ${friendlySyncError(syncRepository.syncState.value.lastMessage)}"
                    )
                    pulled == 0 -> showSyncSnack(true, "✅ اكتمل السحب — لا توجد تغييرات جديدة على السيرفر")
                    else -> showSyncSnack(true, "✅ اكتمل السحب — استُلم $pulled سجل")
                }
            } catch (e: Exception) {
                showSyncSnack(false, "❌ خطأ غير متوقع أثناء السحب: $e")
            } finally {
                _state.value = _state.value.copy(isManualSyncing = false)
            }
        }
    }

    /**
     * «السحب الكامل من السيرفر» — fullSync(push: false): تصفير مؤشر
     * السحب + سحب كل البيانات من الصفر — سحب فقط بدون أي رفع.
     * (التأكيد يتم في الشاشة قبل الاستدعاء — نفس _confirmFullSync.)
     */
    fun runFullPull() {
        if (_state.value.isManualSyncing) return
        _state.value = _state.value.copy(isManualSyncing = true)
        viewModelScope.launch {
            try {
                if (!_state.value.cloudflareSyncEnabled) {
                    showSyncSnack(false, "❌ مزامنة Cloudflare معطّلة — فعّلها من قسم Cloudflare Sync أعلاه")
                    return@launch
                }
                if (!ensureCloudflareConnected()) return@launch

                val pulled = syncRepository.fullPull()
                when {
                    pulled == -1 -> showSyncSnack(
                        false,
                        "❌ فشل السحب الكامل: ${friendlySyncError(syncRepository.syncState.value.lastMessage)}"
                    )
                    else -> showSyncSnack(
                        true,
                        "✅ اكتمل السحب الكامل — سُحب $pulled سجل من السيرفر (بدون رفع)"
                    )
                }
            } catch (e: Exception) {
                showSyncSnack(false, "❌ خطأ غير متوقع أثناء السحب الكامل: $e")
            } finally {
                _state.value = _state.value.copy(isManualSyncing = false)
            }
        }
    }

    /** «رفع التغييرات المحلية» — رفع فقط بدون سحب (نفس _runPushNow). */
    fun runPushNow() {
        if (_state.value.isManualSyncing) return
        _state.value = _state.value.copy(isManualSyncing = true)
        viewModelScope.launch {
            try {
                if (!_state.value.cloudflareSyncEnabled) {
                    showSyncSnack(false, "❌ مزامنة Cloudflare معطّلة — فعّلها من قسم Cloudflare Sync أعلاه")
                    return@launch
                }
                if (!ensureCloudflareConnected()) return@launch

                val pushed = syncRepository.pushOnly()
                when {
                    pushed == -1 -> showSyncSnack(
                        false,
                        "❌ تعذر الرفع: ${friendlySyncError(syncRepository.syncState.value.lastMessage)}"
                    )
                    pushed == 0 -> showSyncSnack(true, "✅ لا توجد تغييرات محلية معلّقة للرفع")
                    else -> showSyncSnack(true, "✅ اكتمل الرفع — رُفع $pushed سجل إلى السيرفر")
                }
            } catch (e: Exception) {
                showSyncSnack(false, "❌ خطأ غير متوقع أثناء الرفع: $e")
            } finally {
                _state.value = _state.value.copy(isManualSyncing = false)
            }
        }
    }

    /** فحص اتصال حقيقي بالـ Worker قبل أي عملية مزامنة يدوية (نفس Dart). */
    private suspend fun ensureCloudflareConnected(): Boolean {
        val ok = try {
            withTimeout(15_000L) {
                syncService.health().map { it.status == "ok" }.getOrDefault(false)
            }
        } catch (e: TimeoutCancellationException) {
            false
        } catch (e: Exception) {
            false
        }
        _state.value = _state.value.copy(isConnected = ok)
        if (!ok) {
            showSyncSnack(false, "❌ لا يوجد اتصال بـ Cloudflare Worker — تحقق من الإنترنت")
        }
        return ok
    }

    private fun showSyncSnack(success: Boolean, message: String) {
        _state.value = _state.value.copy(snackbar = SnackbarMessage(message, success = success))
    }

    fun consumeSnackbar() {
        _state.value = _state.value.copy(snackbar = null)
    }

    // ─── مساعدات ─────────────────────────────────────────────────

    /** المضيف فقط من رابط فعّال — نفس عرض «النقطة الفعّالة الآن» في Dart. */
    private fun hostOf(url: String): String {
        return try {
            java.net.URI(url).host ?: url
        } catch (e: Exception) {
            url
        }
    }

    /**
     * ترجمة أخطاء المزامنة إلى رسائل عربية مفهومة — نقل _friendlySyncError
     * حرفياً مع مرادفات رسائل Kotlin المتقابلة.
     */
    private fun friendlySyncError(raw: String?): String {
        if (raw.isNullOrBlank()) return "سبب غير معروف — جرّب مجدداً"
        if (raw.contains("Not initialized") || raw.contains("فشل تسجيل الدخول")) {
            return "لم يتم تسجيل الدخول إلى سيرفر المزامنة. تحقق من بطاقة " +
                "الاتصال في الإعدادات ثم أعد المحاولة — التطبيق يجرّب تسجيل " +
                "الدخول تلقائياً مع كل مزامنة"
        }
        if (raw.contains("disabled remotely")) {
            return "مزامنة Cloudflare معطّلة مؤقتاً من الإعدادات البعيدة"
        }
        if (raw.contains("disabled locally") || raw.contains("معطّلة")) {
            return "مزامنة Cloudflare معطّلة — فعّلها من قسم Cloudflare Sync أعلاه"
        }
        if (raw.contains("already in progress") || raw.contains("مشغولة")) {
            return "توجد مزامنة جارية حالياً — انتظر انتهاءها ثم أعد المحاولة"
        }
        if (raw.contains("Partial sync failure")) {
            return raw.replaceFirst(
                "Partial sync failure — failed collections: ",
                "فشل جزئي أثناء المزامنة في: "
            )
        }
        // رسائل SyncManager الأصلية عربية مفهومة — تُعرض كما هي.
        return raw.removePrefix("فشل السحب: ").removePrefix("فشل الرفع: ")
            .removePrefix("فشل السحب الكامل: ")
    }

    // ─── companions ──────────────────────────────────────────────

    companion object {
        /** خيارات فترة المزامنة — نفس قيم حوار Dart (5/15/30/60 دقيقة). */
        val SYNC_INTERVAL_OPTIONS = listOf(5, 15, 30, 60)

        /**
         * وقت نسبي عربي — نقل getRelativeTime من date_time_formatter.dart
         * (نفس الشرائح ونفس الصياغة حرفياً).
         */
        fun relativeTimeAr(timestampMs: Long): String {
            if (timestampMs <= 0) return "لا يوجد"
            val differenceMs = System.currentTimeMillis() - timestampMs
            val seconds = differenceMs / 1000
            val minutes = seconds / 60
            val hours = minutes / 60
            val days = hours / 24
            return when {
                seconds < 60 -> "منذ لحظات"
                minutes < 60 -> "منذ $minutes ${if (minutes == 1L) "دقيقة" else "دقائق"}"
                hours < 24 -> "منذ $hours ${if (hours == 1L) "ساعة" else "ساعات"}"
                days < 7 -> "منذ $days ${if (days == 1L) "يوم" else "أيام"}"
                days < 30 -> {
                    val weeks = days / 7
                    "منذ $weeks ${if (weeks == 1L) "أسبوع" else "أسابيع"}"
                }
                days < 365 -> {
                    val months = days / 30
                    "منذ $months ${if (months == 1L) "شهر" else "أشهر"}"
                }
                else -> {
                    val years = days / 365
                    "منذ $years ${if (years == 1L) "سنة" else "سنوات"}"
                }
            }
        }
    }
}
