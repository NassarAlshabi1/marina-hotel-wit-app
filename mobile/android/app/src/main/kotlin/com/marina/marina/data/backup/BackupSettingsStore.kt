package com.marina.marina.data.backup

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * مخزن إعدادات النسخ الاحتياطي — SharedPreferences → DataStore
 * (حسب خريطة التحويل للمشروع). نفس مفاتيح Dart السابقة للتوافق
 * المفاهيمي: last_local_backup_timestamp / local_backup_path /
 * local_backup_format.
 */
private val Context.backupDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "backup_settings"
)

@Singleton
class BackupSettingsStore @Inject constructor(
    @ApplicationContext private val context: Context
) {
    companion object {
        val LAST_BACKUP_TIME = longPreferencesKey("last_local_backup_timestamp")
        val LAST_BACKUP_PATH = stringPreferencesKey("local_backup_path")
        val BACKUP_FORMAT = stringPreferencesKey("local_backup_format")
    }

    val lastBackupTime: Flow<Long?> =
        context.backupDataStore.data.map { it[LAST_BACKUP_TIME]?.takeIf { v -> v > 0 } }

    val lastBackupPath: Flow<String?> =
        context.backupDataStore.data.map { it[LAST_BACKUP_PATH] }

    val backupFormat: Flow<BackupFormat> =
        context.backupDataStore.data.map {
            runCatching {
                BackupFormat.valueOf(it[BACKUP_FORMAT] ?: BackupFormat.sqlite.name)
            }.getOrDefault(BackupFormat.sqlite)
        }

    suspend fun setLastBackup(timeMillis: Long, path: String) {
        context.backupDataStore.edit {
            it[LAST_BACKUP_TIME] = timeMillis
            it[LAST_BACKUP_PATH] = path
        }
    }

    suspend fun setFormat(format: BackupFormat) {
        context.backupDataStore.edit { it[BACKUP_FORMAT] = format.name }
    }

    suspend fun lastBackupTimeOnce(): Long? = lastBackupTime.first()
}
