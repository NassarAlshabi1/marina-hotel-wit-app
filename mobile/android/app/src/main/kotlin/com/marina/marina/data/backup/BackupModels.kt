package com.marina.marina.data.backup

import com.google.gson.annotations.SerializedName

/**
 * نماذج النسخ الاحتياطي — نظير أنواع backup_provider.dart و
 * local_backup_service.dart من فرع Flutter (feat/cloudflare-sync-execution)
 * بنفس المفاتيح والقيم الافتراضية.
 */

/** نظير `enum BackupFormat` في local_backup_service.dart. */
enum class BackupFormat { json, sqlite }

/** نظير `enum BackupStatus` في backup_provider.dart — نفس الأسماء. */
enum class BackupStatus { idle, uploading, downloading, restoring, success, error, checkingPermissions, importingFile }

/**
 * نظير `BackupMetadata` في local_backup_service.dart — نفس مفاتيح JSON
 * (app_version / database_version / backup_timestamp / total_records /
 * device_info / data_hash) حتى تُقرأ نسخ Flutter من Kotlin والعكس.
 */
data class BackupMetadata(
    @SerializedName("app_version") val appVersion: String = "1.2.0+3",
    @SerializedName("database_version") val databaseVersion: Int = 0,
    @SerializedName("backup_timestamp") val backupTimestamp: String = "",
    @SerializedName("total_records") val totalRecords: Int = 0,
    @SerializedName("device_info") val deviceInfo: String = "",
    @SerializedName("data_hash") val dataHash: String? = null
)

/**
 * نظير `LocalBackupFile` في local_backup_service.dart — صف في قائمة
 * النسخ المحلية (اسم الملف/المسار/الحجم/وقت الإنشاء/الصيغة + الميتاداتا).
 */
data class LocalBackupFile(
    val fileName: String,
    val filePath: String,
    val sizeBytes: Long,
    val createdTime: Long,
    val format: BackupFormat,
    val metadata: BackupMetadata?
)

/**
 * نظير `BackupState` في backup_provider.dart — حالة شاشة النسخ
 * الاحتياطي التي تراقبها الواجهة.
 */
data class BackupState(
    val status: BackupStatus = BackupStatus.idle,
    val message: String? = null,
    val progress: Double? = null,
    val localBackups: List<LocalBackupFile> = emptyList(),
    val lastLocalBackupTime: Long? = null,
    val databaseSizeBytes: Long? = null,
    val hasStoragePermission: Boolean = false,
    val backupFolderPath: String? = null,
    val backupsCount: Int = 0,
    val totalSizeMb: String = "0",
    val isExportingExcel: Boolean = false
) {
    /** نظير `isWorking` في Dart — يجمّد الأزرار أثناء العملية. */
    val isWorking: Boolean
        get() = status == BackupStatus.uploading ||
            status == BackupStatus.downloading ||
            status == BackupStatus.restoring ||
            status == BackupStatus.checkingPermissions ||
            status == BackupStatus.importingFile
}

/** نظير `RestoreFixReport` في restore_fix_service.dart. */
data class RestoreFixReport(
    val success: Boolean,
    val bookingsFixed: Int,
    val roomsUpdated: Int,
    val paymentsRecalculated: Int,
    val error: String? = null
)

/** معلومات مجلد النسخ المحلي — نظير getBackupFolderInfo في Dart. */
data class BackupFolderInfo(
    val path: String,
    val backupsCount: Int,
    val totalSizeMb: String
)

/** تنسيق أحجام الملفات بالعربية — نظير FileSizeFormatter.formatBytes. */
object FileSizeFormatter {
    fun formatBytes(bytes: Long, decimals: Int = 2): String {
        if (bytes <= 0) return "0 بايت"
        val suffixes = arrayOf("بايت", "كيلوبايت", "ميجابايت", "جيجابايت", "تيرابايت")
        val i = (63 - java.lang.Long.numberOfLeadingZeros(bytes)) / 10
        if (i >= suffixes.size) {
            return String.format(
                "%.${decimals}f ${suffixes.last()}",
                bytes / Math.pow(1024.0, (suffixes.size - 1).toDouble())
            )
        }
        return String.format("%.${decimals}f ${suffixes[i]}", bytes / Math.pow(1024.0, i.toDouble()))
    }
}
