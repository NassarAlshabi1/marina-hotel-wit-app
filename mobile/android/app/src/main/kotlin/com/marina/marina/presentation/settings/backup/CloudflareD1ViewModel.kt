package com.marina.marina.presentation.settings.backup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.backup.D1BackupSettingsStore
import com.marina.marina.data.backup.D1ProbeBackupResult
import com.marina.marina.data.backup.D1SourceTable
import com.marina.marina.data.backup.D1UploadResult
import com.marina.marina.data.backup.CloudflareD1BackupService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/** حالة تبويب Cloudflare D1 — مرآة _CloudflareD1TabState في Dart. */
data class CloudflareD1UiState(
    val accountId: String = "",
    val databaseId: String = "",
    val apiToken: String = "",
    val deviceLabel: String = "",
    val obscureToken: Boolean = true,
    val loadingSettings: Boolean = true,
    val probing: Boolean = false,
    val loadingTables: Boolean = false,
    val uploading: Boolean = false,
    val probeResult: D1ProbeBackupResult? = null,
    val d1Tables: List<String>? = null,
    val localTables: List<CloudflareD1BackupService.LocalTableInfo> = emptyList(),
    val selected: Set<String> = emptySet(),
    val progress: Double = 0.0,
    val stage: String = "",
    val logs: List<String> = emptyList(),
    val result: D1UploadResult? = null,
    val outboxPending: Int = 0
) {
    val selectedRows: Int
        get() = localTables.filter { selected.contains(it.name) }.sumOf { it.rowCount }

    /** الجداول المحددة غير الموجودة في D1 (ستفشل) — نظير missingInD1. */
    fun missingInD1(): List<String> {
        val d1Set = d1Tables?.toSet() ?: return emptyList()
        return selected.filter { !d1Set.contains(it) }
    }
}

/**
 * نظير حالة تبويب Cloudflare D1 (cloudflare_d1_tab.dart) — نفس
 * الإجراءات والرسائل: حفظ/فحص/قائمة جداول/تأكيد ورفع/إيقاف.
 */
@HiltViewModel
class CloudflareD1ViewModel @Inject constructor(
    private val backupService: CloudflareD1BackupService,
    private val settingsStore: D1BackupSettingsStore
) : ViewModel() {

    private val _state = MutableStateFlow(CloudflareD1UiState())
    val state: StateFlow<CloudflareD1UiState> = _state.asStateFlow()

    private val _snackbars = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val snackbars: SharedFlow<String> = _snackbars.asSharedFlow()

    init {
        // نظير initState: _restoreSettings + _loadLocalTables + _loadOutboxInfo
        restoreSettings()
        loadLocalTables()
        loadOutboxInfo()
    }

    private fun restoreSettings() {
        viewModelScope.launch {
            try {
                val conn = settingsStore.load()
                _state.update {
                    it.copy(
                        accountId = conn.accountId,
                        databaseId = conn.databaseId,
                        apiToken = conn.apiToken,
                        deviceLabel = conn.deviceLabel,
                        loadingSettings = false
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loadingSettings = false) }
            }
        }
    }

    private fun loadOutboxInfo() {
        viewModelScope.launch {
            try {
                val pending = backupService.outboxPendingCount()
                _state.update { it.copy(outboxPending = pending) }
            } catch (e: Exception) {
                // معلومة استشارية فقط — لا تعطل الشاشة
            }
        }
    }

    /** نظير _save. */
    fun save() {
        viewModelScope.launch {
            val s = _state.value
            settingsStore.save(
                D1BackupSettingsStore.D1Connection(
                    accountId = s.accountId.trim(),
                    databaseId = s.databaseId.trim(),
                    apiToken = s.apiToken.trim(),
                    deviceLabel = s.deviceLabel.trim()
                )
            )
            _snackbars.emit("تم حفظ إعدادات Cloudflare D1")
        }
    }

    /** نظير _probe. */
    fun probe() {
        val s = _state.value
        val complete = s.accountId.trim().isNotEmpty() &&
            s.databaseId.trim().isNotEmpty() &&
            s.apiToken.trim().isNotEmpty()
        if (!complete) {
            viewModelScope.launch {
                _snackbars.emit("أكمل الحقول: معرف الحساب ومعرف القاعدة والتوكن")
            }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(probing = true, probeResult = null) }
            try {
                val result = backupService.probe()
                val d1Tables = try {
                    backupService.listD1Tables()
                } catch (e: Exception) {
                    emptyList()
                }
                _state.update {
                    it.copy(probeResult = result, d1Tables = d1Tables, probing = false)
                }
            } catch (e: Exception) {
                _state.update { it.copy(probeResult = null, probing = false) }
                _snackbars.emit("فشل الفحص: ${e.message}")
            }
        }
    }

    /** نظير _loadLocalTables. */
    fun loadLocalTables() {
        viewModelScope.launch {
            _state.update { it.copy(loadingTables = true) }
            try {
                val tables = backupService.loadLocalTables()
                _state.update {
                    it.copy(
                        localTables = tables,
                        selected = tables.map { t -> t.name }.toSet(),
                        loadingTables = false
                    )
                }
            } catch (e: Exception) {
                _state.update { it.copy(loadingTables = false) }
                _snackbars.emit("تعذر قراءة الجداول المحلية: $e")
            }
        }
    }

    /** تحديث حقول الاتصال من الحقول النصية. */
    fun updateConnection(accountId: String, databaseId: String, token: String, deviceLabel: String) {
        _state.update {
            it.copy(
                accountId = accountId,
                databaseId = databaseId,
                apiToken = token,
                deviceLabel = deviceLabel
            )
        }
    }

    fun toggleObscureToken() {
        _state.update { it.copy(obscureToken = !it.obscureToken) }
    }

    fun toggleTable(name: String) {
        _state.update {
            val selected = it.selected.toMutableSet()
            if (selected.contains(name)) selected.remove(name) else selected.add(name)
            it.copy(selected = selected)
        }
    }

    fun selectAll() {
        _state.update { it.copy(selected = it.localTables.map { t -> t.name }.toSet()) }
    }

    fun selectNone() {
        _state.update { it.copy(selected = emptySet()) }
    }

    /** نظير _confirmAndUpload — الحوار في الواجهة ثم الرفع هنا. */
    fun startUpload() {
        val s = _state.value
        if (s.selected.isEmpty()) {
            viewModelScope.launch { _snackbars.emit("اختر جدولاً واحداً على الأقل") }
            return
        }
        viewModelScope.launch {
            val sources = buildSources(s)
            _state.update {
                it.copy(
                    uploading = true,
                    progress = 0.0,
                    stage = "بدء الرفع...",
                    result = null,
                    logs = emptyList()
                )
            }
            try {
                val label = s.deviceLabel.trim()
                val result = backupService.uploadData(
                    tables = sources,
                    deviceLabel = label.ifEmpty { null }
                ) { p ->
                    _state.update {
                        it.copy(
                            progress = p.tableFraction.coerceIn(0.0, 1.0),
                            stage = "${p.currentTable} " +
                                "(${p.tableIndex + 1}/${p.tableCount}) — " +
                                "${p.rowsDone}/${p.rowsTotal} صف"
                        )
                    }
                }
                _state.update {
                    it.copy(
                        result = result,
                        uploading = false,
                        stage = if (result.cancelled) "أُوقف الرفع" else "اكتمل الرفع",
                        logs = result.errors.take(10)
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(uploading = false, stage = "فشل الرفع: ${e.message}")
                }
            }
        }
    }

    private suspend fun buildSources(s: CloudflareD1UiState): List<D1SourceTable> {
        val selectedTables = s.localTables.filter { s.selected.contains(it.name) }
        return backupService.buildSourceTables(selectedTables)
    }

    /** نظير زر «إيقاف». */
    fun cancelUpload() {
        backupService.cancelUpload()
    }
}
