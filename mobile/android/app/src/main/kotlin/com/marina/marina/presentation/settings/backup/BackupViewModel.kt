package com.marina.marina.presentation.settings.backup

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.marina.marina.data.backup.BackupFormat
import com.marina.marina.data.backup.BackupState
import com.marina.marina.data.backup.BackupStatus
import com.marina.marina.data.backup.FileSizeFormatter
import com.marina.marina.data.backup.FullDatabaseExportService
import com.marina.marina.data.backup.LocalBackupService
import com.marina.marina.data.backup.RestoreFixService
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

/** حدث سناك-بار بلون حاوية صريح — نظير SnackBars في Dart. */
data class BackupSnackbar(val text: String, val containerColorArgb: Long?)

/**
 * نظير BackupStatusNotifier في backup_provider.dart — ViewModel
 * شاشة النسخ الاحتياطي المحلي واستعادته بنفس العقد والرسائل.
 */
@HiltViewModel
class BackupViewModel @Inject constructor(
    private val localBackupService: LocalBackupService,
    private val restoreFixService: RestoreFixService,
    private val exportService: FullDatabaseExportService
) : ViewModel() {

    private val _state = MutableStateFlow(BackupState())
    val state: StateFlow<BackupState> = _state.asStateFlow()

    private val _snackbars = MutableSharedFlow<BackupSnackbar>(extraBufferCapacity = 8)
    val snackbars: SharedFlow<BackupSnackbar> = _snackbars.asSharedFlow()

    init {
        // نظير _initialize: أذونات + قائمة النسخ + آخر نسخة + حجم القاعدة
        checkStoragePermissions()
        viewModelScope.launch {
            _state.update {
                it.copy(
                    lastLocalBackupTime = localBackupService.getLastLocalBackupTime(),
                    databaseSizeBytes = localBackupService.estimateDatabaseSize()
                )
            }
        }
    }

    /** نظير checkStoragePermissions. */
    fun checkStoragePermissions() {
        viewModelScope.launch {
            _state.update {
                it.copy(
                    status = BackupStatus.checkingPermissions,
                    message = "التحقق من أذونات التخزين..."
                )
            }
            try {
                val hasPermission = localBackupService.checkPermissions()
                if (hasPermission) {
                    val folderInfo = localBackupService.getBackupFolderInfo()
                    val localBackups = localBackupService.listLocalBackups()
                    _state.update {
                        it.copy(
                            status = BackupStatus.success,
                            message = "تم الحصول على أذونات التخزين",
                            hasStoragePermission = hasPermission,
                            backupFolderPath = folderInfo.path,
                            backupsCount = folderInfo.backupsCount,
                            totalSizeMb = folderInfo.totalSizeMb,
                            localBackups = localBackups
                        )
                    }
                } else {
                    _state.update {
                        it.copy(
                            status = BackupStatus.error,
                            message = "لا توجد أذونات للوصول للتخزين المحلي",
                            hasStoragePermission = false
                        )
                    }
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        status = BackupStatus.error,
                        message = "خطأ في التحقق من الأذونات: $e",
                        hasStoragePermission = false
                    )
                }
            }
        }
    }

    /** نظير createLocalBackup + سناك-بار النتيجة. */
    fun createLocalBackup() {
        viewModelScope.launch {
            if (!_state.value.hasStoragePermission) {
                _state.update {
                    it.copy(
                        status = BackupStatus.error,
                        message = "لا توجد أذونات للوصول للتخزين المحلي"
                    )
                }
                _snackbars.emit(
                    BackupSnackbar("لا توجد أذونات للوصول للتخزين المحلي", GREEN)
                )
                return@launch
            }
            _state.update {
                it.copy(
                    status = BackupStatus.uploading,
                    message = "إنشاء نسخة احتياطية محلية...",
                    progress = 0.0
                )
            }
            try {
                val backupPath = localBackupService.createLocalBackup(BackupFormat.sqlite)
                _state.update { it.copy(message = "تحديث قائمة النسخ...", progress = 0.8) }
                refreshList()

                _state.update {
                    it.copy(
                        status = BackupStatus.success,
                        message = "تم إنشاء النسخة الاحتياطية المحلية بنجاح في: $backupPath",
                        progress = 1.0
                    )
                }
                _snackbars.emit(BackupSnackbar("تم إنشاء النسخة", GREEN))
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        status = BackupStatus.error,
                        message = "خطأ في إنشاء النسخة الاحتياطية المحلية: $e"
                    )
                }
                _snackbars.emit(BackupSnackbar("حدث خطأ", RED))
            }
        }
    }

    /** نظير restoreFromLocalBackup + الإصلاح التلقائي بعدها. */
    fun restoreFromLocalBackup(filePath: String) {
        viewModelScope.launch {
            _state.update {
                it.copy(
                    status = BackupStatus.restoring,
                    message = "استعادة النسخة الاحتياطية المحلية...",
                    progress = 0.0
                )
            }
            try {
                localBackupService.restoreFromLocalBackup(filePath)

                // تشغيل الإصلاح التلقائي — نظير RestoreFixService.runAutoFixAfterRestore
                _state.update {
                    it.copy(
                        status = BackupStatus.restoring,
                        message = "تشغيل عملية الإصلاح التلقائي...",
                        progress = 0.5
                    )
                }
                val fixReport = restoreFixService.runAutoFixAfterRestore()

                _state.update {
                    it.copy(
                        status = BackupStatus.success,
                        message = "تم استعادة البيانات من النسخة المحلية بنجاح",
                        progress = 1.0
                    )
                }
                _snackbars.emit(
                    BackupSnackbar(
                        "تمت الاستعادة بنجاح - سيتم تحديث البيانات",
                        GREEN
                    )
                )
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        status = BackupStatus.error,
                        message = "خطأ في استعادة البيانات: $e"
                    )
                }
                _snackbars.emit(BackupSnackbar("فشلت الاستعادة", RED))
            }
        }
    }

    /** نظير shareLocalBackup. */
    fun shareLocalBackup(filePath: String) {
        viewModelScope.launch {
            try {
                localBackupService.shareBackup(filePath)
                _state.update {
                    it.copy(
                        status = BackupStatus.success,
                        message = "تم مشاركة النسخة الاحتياطية"
                    )
                }
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        status = BackupStatus.error,
                        message = "خطأ في مشاركة النسخة الاحتياطية: $e"
                    )
                }
                _snackbars.emit(BackupSnackbar("حدث خطأ", RED))
            }
        }
    }

    /** نظير importBackupFromFile — من منتقي ملفات النظام. */
    fun importBackupFromFile(uri: Uri) {
        viewModelScope.launch {
            _state.update {
                it.copy(
                    status = BackupStatus.importingFile,
                    message = "استيراد ملف النسخة الاحتياطية...",
                    progress = 0.0
                )
            }
            try {
                val importedPath = localBackupService.importBackupFromFile(uri)
                _state.update { it.copy(message = "تحديث قائمة النسخ...", progress = 0.8) }
                refreshList()
                _state.update {
                    it.copy(
                        status = BackupStatus.success,
                        message = "تم استيراد النسخة الاحتياطية من: $importedPath",
                        progress = 1.0
                    )
                }
                _snackbars.emit(BackupSnackbar("تم الاستيراد", GREEN))
            } catch (e: Exception) {
                _state.update {
                    it.copy(
                        status = BackupStatus.error,
                        message = "خطأ في استيراد النسخة: $e"
                    )
                }
                _snackbars.emit(BackupSnackbar("حدث خطأ", RED))
            }
        }
    }

    /** نظير _deleteBackup في التبويب — برسالة برتقالية ثابتة. */
    fun deleteLocalBackup(filePath: String) {
        viewModelScope.launch {
            localBackupService.deleteLocalBackup(filePath)
            refreshList()
            _snackbars.emit(BackupSnackbar("تم حذف النسخة الاحتياطية", ORANGE))
        }
    }

    /**
     * نظير _exportDatabaseToExcel — تصدير كامل ثم مشاركة برسالة
     * «تم إنشاء الملف: … — اختر مكان المشاركة».
     */
    fun exportDatabaseToExcel() {
        viewModelScope.launch {
            _state.update { it.copy(isExportingExcel = true) }
            try {
                val file = exportService.exportFullDatabase()
                _snackbars.emit(
                    BackupSnackbar(
                        "تم إنشاء الملف: ${file.name} — اختر مكان المشاركة",
                        GREEN
                    )
                )
                exportService.shareFile(file, subject = "قاعدة بيانات فندق مارينا")
            } catch (e: Exception) {
                _snackbars.emit(BackupSnackbar("فشل التصدير: $e", RED))
            } finally {
                _state.update { it.copy(isExportingExcel = false) }
            }
        }
    }

    private suspend fun refreshList() {
        val localBackups = localBackupService.listLocalBackups()
        val folderInfo = localBackupService.getBackupFolderInfo()
        val lastTime = localBackupService.getLastLocalBackupTime()
        _state.update {
            it.copy(
                localBackups = localBackups,
                backupFolderPath = folderInfo.path,
                backupsCount = folderInfo.backupsCount,
                totalSizeMb = folderInfo.totalSizeMb,
                lastLocalBackupTime = lastTime
            )
        }
    }

    /** تنسيق وقت نسبي للبطاقة الأخيرة — نفس نصوص Dart. */
    fun relativeTime(lastBackupTime: Long): String {
        val diff = System.currentTimeMillis() - lastBackupTime
        val minutes = diff / 60000
        val hours = diff / 3600000
        val days = diff / 86400000
        return when {
            minutes < 1 -> "الآن"
            minutes < 60 -> "منذ $minutes دقيقة"
            hours < 24 -> "منذ $hours ساعة"
            else -> "منذ $days يوم"
        }
    }

    fun formatSize(bytes: Long): String = FileSizeFormatter.formatBytes(bytes)

    companion object {
        const val GREEN = 0xFF4CAF50L
        const val RED = 0xFFF44336L
        const val ORANGE = 0xFFFF9800L
    }
}
