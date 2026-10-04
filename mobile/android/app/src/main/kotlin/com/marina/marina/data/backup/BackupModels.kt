package com.marina.marina.data.backup

import com.google.gson.annotations.SerializedName

/**
 * نماذج النسخ الاحتياطي — نظير أنواع backup_provider.dart و
 * local_backup_service.dart من فرع Flutter (feat/cloudflare-sync-execution)
 * بنفس المفاتيح والقيم الافتراضية.
 */

/** نظير `enum BackupFormat` في local_backup_service.dart. */
enum class BackupFormat(val wireName: String) {
    @SerializedName("json") JSON("json"),
    @SerializedName("sqlite") SQLITE("sqlite");

    companion object {
        fun fromWireName(value: String?): BackupFormat =
            entries.firstOrNull { it.wireName == value || it.name == value } ?: SQLITE
    }
}

/** نظير `enum BackupStatus` في backup_provider.dart — نفس الأسماء. */
enum class BackupStatus {
    @SerializedName("idle") IDLE,
    @SerializedName("uploading") UPLOADING,
    @SerializedName("downloading") DOWNLOADING,
    @SerializedName("restoring") RESTORING,
    @SerializedName("success") SUCCESS,
    @SerializedName("error") ERROR,
    @SerializedName("checkingPermissions") CHECKING_PERMISSIONS,
    @SerializedName("importingFile") IMPORTING_FILE
}

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
    val status: BackupStatus = BackupStatus.IDLE,
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
        get() = status == BackupStatus.UPLOADING ||
            status == BackupStatus.DOWNLOADING ||
            status == BackupStatus.RESTORING ||
            status == BackupStatus.CHECKING_PERMISSIONS ||
            status == BackupStatus.IMPORTING_FILE
}

/** نظير `RestoreFixReport` في restore_fix_service.dart. */
data class RestoreFixReport(
    val success: Boolean,
    val bookingsFixed: Int,
    val roomsUpdated: Int,
    val paymentsRecalculated: Int,
    val error: String? = null
) {
    /** Imported data may exist, but a failed repair must never produce a success notification. */
    fun requireSuccess() {
        check(success) {
            "تم تحميل بيانات النسخة، لكن فشل الإصلاح اللاحق: ${error ?: "سبب غير معروف"}"
        }
    }
}

/** معلومات مجلد النسخ المحلي — نظير getBackupFolderInfo في Dart. */
data class BackupFolderInfo(
    val path: String,
    val backupsCount: Int,
    val totalSizeMb: String
)
