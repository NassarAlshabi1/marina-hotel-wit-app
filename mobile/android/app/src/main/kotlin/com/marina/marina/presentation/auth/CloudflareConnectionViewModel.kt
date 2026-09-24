package com.marina.marina.presentation.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.remote.CloudflareConfig
import com.marina.marina.data.remote.CloudflareSyncService
import com.marina.marina.data.remote.WorkerEndpoints
import com.marina.marina.domain.repository.SyncRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * ✅ (2026-09-24) حالة شاشة «تسجيل الدخول إلى Cloudflare» — نقل 1:1 لحالة
 * cloudflare_login_screen.dart (فرع feat/cloudflare-sync-execution):
 *
 *  • الحقول تُملأ تلقائياً (override الفعّال إن وُجد وإلا admin/admin).
 *  • دخول تلقائي واحد عند الفتح: إن كانت المزامنة جاهزة تُعرض رسالة
 *    «✅ المزامنة جاهزة بالفعل — الدخول تلقائي» وإلا يُنفَّذ الدخول.
 *  • «تسجيل الدخول»: يحفظ الاعتمادات (كلمة مرور فارغة = إبقاء الحالية)
 *    ثم يسجّل الدخول (محاولتان — نفس loginAttempts: 2).
 *  • «فحص الاتصال»: /health بنفس نصوص النتيجة في Dart.
 *  • «الاعتمادات المدمجة»: يمسح overrides ويملأ الاسم الفعّال.
 *  • بطاقة الحالة: نفس حالات SyncStatus وأيقوناتها وألوانها ونصوصها.
 */
@HiltViewModel
class CloudflareConnectionViewModel @Inject constructor(
    private val syncService: CloudflareSyncService,
    private val cloudflareConfig: CloudflareConfig,
    private val workerEndpoints: WorkerEndpoints,
    private val syncRepository: SyncRepository
) : ViewModel() {

    /** حالات المزامنة الأربع — نفس SyncStatus في Dart (switch بالأيقونة/اللون/النص). */
    enum class CfSyncStatus { SYNCING, SUCCESS, FAILED, IDLE }

    /** نوع رسالة البانر — يحدد اللون (نظير _messageColor في Dart). */
    enum class MessageKind { SUCCESS, DANGER, INFO }

    data class Banner(val text: String, val kind: MessageKind)

    data class CloudflareLoginUiState(
        // الحقول — تُملأ تلقائياً كما في initState في Dart.
        val usernameField: String = "",
        val passwordField: String = "",
        val obscurePassword: Boolean = true,
        // أزرار
        val isLoggingIn: Boolean = false,
        val isCheckingHealth: Boolean = false,
        // بانرات
        val message: Banner? = null,
        val healthResult: Banner? = null,
        // بطاقة الحالة
        val status: CfSyncStatus = CfSyncStatus.IDLE,
        val workerUrl: String = "",
        val account: String = CloudflareConfig.DEFAULT_USERNAME,
        // شارة وجود overrides (زر الاعتمادات المدمجة)
        val hasCredentialOverrides: Boolean = false,
        // خطأ تهيئة (نظير manager.initError)
        val initError: String? = null,
        // حارس الدخول التلقائي — يُنفَّذ مرة واحدة
        val autoLoginAttempted: Boolean = false
    )

    private val _state = MutableStateFlow(CloudflareLoginUiState())
    val state: StateFlow<CloudflareLoginUiState> = _state.asStateFlow()

    init {
        // ✅ الاسم يُملأ بالقيمة الفعّالة إن وُجدت overrides، وإلا admin —
        // وكلمة المرور تُملأ تلقائياً بـ admin (نفس initState في Dart).
        _state.value = _state.value.copy(
            usernameField = if (cloudflareConfig.hasCredentialOverrides) {
                cloudflareConfig.username
            } else {
                CloudflareConfig.DEFAULT_USERNAME
            },
            passwordField = CloudflareConfig.DEFAULT_PASSWORD,
            workerUrl = workerEndpoints.active,
            account = cloudflareConfig.username,
            hasCredentialOverrides = cloudflareConfig.hasCredentialOverrides
        )
        // حالة المزامنة الحية لبطاقة الحالة العلوية.
        viewModelScope.launch {
            syncRepository.syncState.collect { sync ->
                _state.value = _state.value.copy(
                    status = when {
                        sync.isSyncing -> CfSyncStatus.SYNCING
                        sync.isError -> CfSyncStatus.FAILED
                        sync.lastSyncAt > 0 -> CfSyncStatus.SUCCESS
                        else -> CfSyncStatus.IDLE
                    },
                    initError = if (sync.isError && sync.lastMessage.isNotBlank()) sync.lastMessage else null
                )
            }
        }
    }

    /** دخول تلقائي واحد عند فتح الشاشة إن لم تكن المزامنة جاهزة (Dart). */
    fun autoLoginIfNeeded() {
        val current = _state.value
        if (current.autoLoginAttempted) return
        _state.value = current.copy(autoLoginAttempted = true)
        if (syncService.hasWorkerToken()) {
            _state.value = _state.value.copy(
                message = Banner("✅ المزامنة جاهزة بالفعل — الدخول تلقائي", MessageKind.SUCCESS)
            )
            return
        }
        login()
    }

    /**
     * «تسجيل الدخول» — نفس _login في Dart: حفظ الاعتمادات (كلمة مرور
     * فارغة = إبقاء الحالية) ثم دخول، وعرض نتيجة عربية واضحة.
     */
    fun login() {
        val username = _state.value.usernameField
        val password = _state.value.passwordField
        _state.value = _state.value.copy(isLoggingIn = true, message = null, healthResult = null)
        viewModelScope.launch {
            try {
                // 1) حفظ الاعتمادات (فارغ = إبقاء) — تعمل فوراً على getters.
                cloudflareConfig.setCredentialOverrides(
                    username.takeIf { it.isNotBlank() },
                    password.takeIf { it.isNotEmpty() }
                )

                // 2) تسجيل دخول إجباري بالاعتمادات الجديدة (محاولتان).
                val result = syncService.login(username.trim(), password)

                if (result.isSuccess) {
                    _state.value = _state.value.copy(
                        isLoggingIn = false,
                        passwordField = "",
                        hasCredentialOverrides = cloudflareConfig.hasCredentialOverrides,
                        account = cloudflareConfig.username,
                        message = Banner("✅ تم تسجيل الدخول بنجاح — المزامنة جاهزة", MessageKind.SUCCESS)
                    )
                } else {
                    val initError = result.exceptionOrNull()?.message
                    _state.value = _state.value.copy(
                        isLoggingIn = false,
                        hasCredentialOverrides = cloudflareConfig.hasCredentialOverrides,
                        message = Banner(initError ?: "فشل تسجيل الدخول — راجع البيانات", MessageKind.DANGER)
                    )
                }
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    isLoggingIn = false,
                    message = Banner("خطأ: $e", MessageKind.DANGER)
                )
            }
        }
    }

    /** «فحص الاتصال» — /health بنفس نصوص _checkHealth في Dart. */
    fun checkHealth() {
        _state.value = _state.value.copy(isCheckingHealth = true, healthResult = null)
        viewModelScope.launch {
            val result = syncService.health()
            _state.value = _state.value.copy(
                isCheckingHealth = false,
                healthResult = if (result.isSuccess) {
                    Banner("✅ الاتصال بخادم المزامنة يعمل (${workerEndpoints.active})", MessageKind.SUCCESS)
                } else {
                    Banner(
                        "❌ تعذر الوصول للخادم: ${result.exceptionOrNull()?.message ?: "غير معروف"}",
                        MessageKind.DANGER
                    )
                }
            )
        }
    }

    /** «الاعتمادات المدمجة» — يمسح overrides ويملأ الاسم الفعّال (Dart). */
    fun resetOverrides() {
        viewModelScope.launch {
            cloudflareConfig.clearCredentialOverrides()
            _state.value = _state.value.copy(
                usernameField = cloudflareConfig.username,
                passwordField = "",
                hasCredentialOverrides = cloudflareConfig.hasCredentialOverrides,
                message = Banner("أُزيلت الاعتمادات المخصّصة — الرجوع للمدمجة", MessageKind.INFO)
            )
        }
    }

    // ─── تحديث الحقول ────────────────────────────────────────────

    fun onUsernameChange(text: String) {
        _state.value = _state.value.copy(usernameField = text)
    }

    fun onPasswordChange(text: String) {
        _state.value = _state.value.copy(passwordField = text)
    }

    fun toggleObscurePassword() {
        _state.value = _state.value.copy(obscurePassword = !_state.value.obscurePassword)
    }
}
