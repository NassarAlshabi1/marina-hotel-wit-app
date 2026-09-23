package com.marina.marina.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareD1Service
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.D1ProbeResult
import com.marina.marina.data.remote.WorkerEndpoints
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ✅ (2026-09-24) حالة شاشة اتصال Cloudflare — نقل تجربة
 * cloudflare_login_screen.dart (Flutter):
 *  • عرض النقطة الفعّالة (نطاق مخصّص أو workers.dev) + حالة الدخول.
 *  • تعبئة admin/admin تلقائياً + دخول تلقائي واحد عند الفتح.
 *  • «فحص الاتصال» → /health.
 *  • حفظ اعتمادات بديلة (overrides تعمل فوراً على getters).
 *  • ضبط نطاق worker مخصّص (شبكات اليمن تحجب workers.dev).
 *  • فحص/حفظ توكن D1 REST المباشر (cfut_…).
 */
@HiltViewModel
class CloudflareConnectionViewModel @Inject constructor(
    private val syncService: CloudflareSyncService,
    private val cloudflareConfig: CloudflareConfig,
    private val workerEndpoints: WorkerEndpoints,
    private val d1Service: CloudflareD1Service
) : ViewModel() {

    data class ConnectionState(
        val isCheckingHealth: Boolean = false,
        val healthMessage: String? = null,
        val isHealthOk: Boolean? = null,
        val isProbingD1: Boolean = false,
        val d1Message: String? = null,
        val isD1Ok: Boolean? = null,
        val isSaving: Boolean = false,
        val savedMessage: String? = null,
        val customUrlError: String? = null
    )

    private val _state = MutableStateFlow(ConnectionState())
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    /** اسم المستخدم الفعّال (override إن وُضع وإلا admin). */
    val effectiveUsername: String get() = cloudflareConfig.username

    /** هل وُضعت اعتمادات بديلة؟ (لعرض «الرجوع للاعتمادات المدمجة»). */
    val hasCredentialOverrides: Boolean get() = cloudflareConfig.hasCredentialOverrides

    /** النقطة الفعّالة — للعرض في الشاشة. */
    val activeEndpoint: String get() = workerEndpoints.active

    /** النطاق المخصّص الحالي (null = المدمج فقط). */
    val customEndpoint: String? get() = workerEndpoints.custom

    /** التوكن الشبكي متاح؟ (يعرض «متصل» مقابل «غير متصل»). */
    val hasWorkerToken: Boolean get() = syncService.hasWorkerToken()

    /** توكن D1 المباشر المحفوظ (لعرض وجوده فقط). */
    val hasD1Token: Boolean get() = d1Service.isConfigured

    /** دخول شبكي باعتمادات معطاة (يحفظ override ويسجّل الدخول). */
    fun login(username: String, password: String) {
        viewModelScope.launch {
            cloudflareConfig.setCredentialOverrides(
                username.takeIf { it.isNotBlank() },
                password.takeIf { it.isNotBlank() }
            )
            syncService.login(username, password)
                .onSuccess { _state.value = _state.value.copy(savedMessage = "✅ تم تسجيل الدخول — المزامنة جاهزة") }
                .onFailure {
                    _state.value = _state.value.copy(
                        savedMessage = "⚠️ فشل الدخول: ${it.message ?: "تحقق من الشبكة والاعتمادات"}"
                    )
                }
        }
    }

    /** فحص اتصال حي: /health على النقطة الفعّالة. */
    fun checkHealth() {
        viewModelScope.launch {
            _state.value = _state.value.copy(isCheckingHealth = true, healthMessage = null)
            syncService.health()
                .onSuccess { body ->
                    _state.value = _state.value.copy(
                        isCheckingHealth = false,
                        isHealthOk = body.status == "ok",
                        healthMessage = if (body.status == "ok") {
                            "✅ الخادم حي (الإصدار ${body.version ?: "?"})"
                        } else {
                            "⚠️ استجابة غير متوقعة: ${body.status ?: "?"}"
                        }
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isCheckingHealth = false,
                        isHealthOk = false,
                        healthMessage = "❌ تعذر الوصول: ${it.message ?: "شبكة محجوبة؟"}"
                    )
                }
        }
    }

    /** ضبط نطاق مخصّص (null/فارغ = مسح والرجوع لـ workers.dev). */
    fun setCustomUrl(raw: String?) {
        viewModelScope.launch {
            try {
                val normalized = workerEndpoints.setCustomUrl(raw)
                _state.value = _state.value.copy(
                    customUrlError = null,
                    savedMessage = if (normalized != null) {
                        "✅ النطاق المخصّص: $normalized"
                    } else {
                        "✅ رجعنا للنطاق المدمج workers.dev"
                    }
                )
            } catch (e: IllegalArgumentException) {
                _state.value = _state.value.copy(customUrlError = e.message)
            }
        }
    }

    /** حفظ توكن D1 المباشر + فحص فوري. */
    fun saveD1TokenAndProbe(token: String?) {
        viewModelScope.launch {
            cloudflareConfig.setD1ApiToken(token?.takeIf { it.isNotBlank() })
            if (!d1Service.isConfigured) {
                _state.value = _state.value.copy(
                    d1Message = "أُلغي التوكن المباشر — المسار السحابي عبر الـ worker يبقى هو الأساس",
                    isD1Ok = null
                )
                return@launch
            }
            _state.value = _state.value.copy(isProbingD1 = true, d1Message = null)
            d1Service.probe()
                .onSuccess { result: D1ProbeResult ->
                    val ok = result.tokenValid && result.databaseReachable
                    _state.value = _state.value.copy(
                        isProbingD1 = false,
                        isD1Ok = ok,
                        d1Message = when {
                            !result.tokenValid -> "❌ التوكن غير صالح أو منتهي"
                            !result.databaseReachable -> "⚠️ التوكن صالح لكن القاعدة غير قابلة للوصول — ${result.fatalError ?: ""}"
                            !result.dmlAllowed -> "⚠️ قراءة فقط (بلا صلاحية كتابة DML)"
                            else -> "✅ توكن صالح + قاعدة حية + كتابة مسموحة"
                        }
                    )
                }
                .onFailure {
                    _state.value = _state.value.copy(
                        isProbingD1 = false,
                        isD1Ok = false,
                        d1Message = "❌ فشل الفحص: ${it.message}"
                    )
                }
        }
    }

    /** الرجوع للاعتمادات المدمجة (admin/admin). */
    fun clearCredentialOverrides() {
        viewModelScope.launch {
            cloudflareConfig.clearCredentialOverrides()
            _state.value = _state.value.copy(savedMessage = "✅ رجعنا للاعتمادات المدمجة (admin)")
        }
    }

    fun consumeSavedMessage() {
        _state.value = _state.value.copy(savedMessage = null)
    }
}
