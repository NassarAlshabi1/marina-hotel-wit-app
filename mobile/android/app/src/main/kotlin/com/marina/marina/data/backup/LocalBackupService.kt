package com.marina.marina.data.backup

import android.content.Context
import android.net.Uri
import android.os.Environment
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.marina.marina.data.local.AppDatabase
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import javax.inject.Inject
import javax.inject.Singleton

/**
 * خدمة النسخ الاحتياطي المحلي — نقل LocalBackupService من فرع Flutter
 * (mobile/lib/services/local_backup_service.dart) بنفس السلوك:
 *
 *  • مجلد النسخ: Documents/MarinaHotelBackups مع تراجع لمجلد التطبيق
 *    الخاص عند تعذّر الكتابة (نفس تراجع Dart).
 *  • نسخة JSON مضغوطة gz بنفس مغلف buildBackupDataMap (نفس المفاتيح
 *    الحرفية: metadata / rooms / bookings / ... / sync_state) — فتُقرأ
 *    نسخ Flutter على Kotlin والعكس.
 *  • نسخة SQLite خام (.db) بنسخ ملف قاعدة البيانات بعد wal_checkpoint —
 *    نظير SqliteBackupRestore.backupDatabase.
 *  • استعادة JSON: مسح الجداول ثم إدراج الصفوف داخل معاملة واحدة.
 *  • استعادة SQLite: استبدال ملف قاعدة البيانات (يُعاد تشغيل التطبيق
 *    بعد ذلك لفتح النسخة المستعادة).
 *  • سنة آخر نسخة في prefs بنفس مفتاح Dart (last_local_backup_timestamp).
 */
@Singleton
class LocalBackupService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val db: AppDatabase,
    private val settings: BackupSettingsStore
) {
    companion object {
        const val BACKUP_FOLDER_NAME = "MarinaHotelBackups"
        const val BACKUP_FILE_PREFIX = "marina_hotel_backup_"
        const val BACKUP_FILE_PREFIX_IMPORTED = "imported_backup_"
        const val PREFS_LAST_LOCAL_BACKUP_KEY = "last_local_backup_timestamp"
        const val PREFS_LOCAL_BACKUP_PATH_KEY = "local_backup_path"
        const val PREFS_BACKUP_FORMAT_KEY = "local_backup_format"

        /** مفاتيح مغلف النسخة JSON — نفس ترتيب Dart buildBackupDataMap. */
        val BACKUP_TABLE_KEYS = listOf(
            "rooms", "bookings", "booking_notes", "booking_nights",
            "hotel_day_ledger", "shift_notes", "employees", "expenses",
            "cash_transactions", "payments", "debts", "salary_cycles",
            "salary_payments", "price_adjustments", "booking_price_adjustments",
            "audit_logs", "payment_voids", "guest_infos", "salary_withdrawals",
            "salary_carry_over_logs", "inventory_items", "inventory_transactions"
        )

        /** الجداول الداخلية المستبعدة من قائمة جداول المستخدم. */
        private val INTERNAL_TABLES = setOf(
            "android_metadata", "room_master_table", "outbox",
            "sync_remote_meta", "sync_state", "sync_log", "sync_queue",
            "sync_conflicts", "ancestor_cache", "app_sessions",
            "integrity_violations", "auto_fix_runs", "restore_fix_log"
        )
    }

    private val gson = Gson()

    // ─── مجلد النسخ والأذونات ────────────────────────────────────

    /** نظير checkPermissions: إمكانية الكتابة في مجلد النسخ. */
    suspend fun checkPermissions(): Boolean = withContext(Dispatchers.IO) {
        try {
            val dir = resolveBackupDirectory()
            if (!dir.exists()) dir.mkdirs()
            val probe = File(dir, ".perm_probe")
            probe.writeText("ok")
            probe.delete()
            true
        } catch (e: Exception) {
            // نظير Dart: التراجع إلى مجلد التطبيق الخاص يجعل الأذونات متاحة دائماً
            try {
                val fallback = appPrivateBackupDirectory()
                if (!fallback.exists()) fallback.mkdirs()
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    private fun appPrivateBackupDirectory(): File {
        val external = context.getExternalFilesDir(null)
        val base = external ?: context.filesDir
        return File(base, BACKUP_FOLDER_NAME)
    }

    /**
     * نظير getBackupDirectory في Dart: المسار العام
     * /storage/emulated/0/Documents/MarinaHotelBackups أولاً، وإن تعذّرت
     * الكتابة فمجلد التطبيق الخاص.
     */
    fun resolveBackupDirectory(): File {
        val publicDocs = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOCUMENTS
        )
        if (publicDocs != null) {
            val dir = File(publicDocs, BACKUP_FOLDER_NAME)
            return dir
        }
        return appPrivateBackupDirectory()
    }

    suspend fun getBackupDirectory(): File = withContext(Dispatchers.IO) {
        val dir = resolveBackupDirectory()
        try {
            if (!dir.exists()) dir.mkdirs()
            val probe = File(dir, ".perm_probe")
            probe.writeText("ok")
            probe.delete()
            dir
        } catch (e: Exception) {
            val fallback = appPrivateBackupDirectory()
            if (!fallback.exists()) fallback.mkdirs()
            fallback
        }
    }

    /** نظير getBackupFolderInfo: المسار + عدد النسخ + الحجم بالميجابايت. */
    suspend fun getBackupFolderInfo(): BackupFolderInfo = withContext(Dispatchers.IO) {
        val dir = getBackupDirectory()
        val files = listBackupFiles(dir)
        val totalBytes = files.sumOf { it.sizeBytes }
        BackupFolderInfo(
            path = dir.absolutePath,
            backupsCount = files.size,
            totalSizeMb = String.format(Locale.US, "%.1f", totalBytes / (1024.0 * 1024.0))
        )
    }

    // ─── إنشاء النسخ ─────────────────────────────────────────────

    /**
     * نظير createLocalBackup — الافتراضي sqlite (نسخة خام كاملة)،
     * و json نسخة مضغوطة بنفس مغلف Dart. يعيد مسار الملف الناتج.
     */
    suspend fun createLocalBackup(format: BackupFormat = BackupFormat.sqlite): String =
        withContext(Dispatchers.IO) {
            val backupDir = getBackupDirectory()
            val now = System.currentTimeMillis()
            val dayIso = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(now))
            val baseName = "$BACKUP_FILE_PREFIX${dayIso}_$now"
            val deviceLabel = "Android Local"

            val path = when (format) {
                BackupFormat.json -> {
                    val envelope = buildJsonBackupEnvelope(deviceLabel, now)
                    val jsonBytes = gson.toJson(envelope).toByteArray(Charsets.UTF_8)
                    val file = File(backupDir, "$baseName.json.gz")
                    GZIPOutputStream(FileOutputStream(file)).use { out ->
                        out.write(jsonBytes)
                    }
                    file.absolutePath
                }
                BackupFormat.sqlite -> {
                    val file = File(backupDir, "$baseName.db")
                    copySqliteDatabase(file)
                    // نظير Dart: ملف ميتاداتا جانبي للنسخة الخام.
                    val counts = collectRecordCounts()
                    val total = counts.values.sum()
                    val metadata = mapOf(
                        "app_version" to "1.2.0+3",
                        "database_version" to db.openHelper.writableDatabase.version,
                        "backup_timestamp" to isoTimestamp(now),
                        "total_records" to total,
                        "device_info" to deviceLabel
                    )
                    File(backupDir, "$baseName.metadata.json")
                        .writeText(gson.toJson(metadata))
                    file.absolutePath
                }
            }

            settings.setLastBackup(now, path)
            path
        }

    // ─── قائمة النسخ ─────────────────────────────────────────────

    /** نظير listLocalBackups: امسح المجلد واستخرج الميتاداتا. */
    suspend fun listLocalBackups(): List<LocalBackupFile> = withContext(Dispatchers.IO) {
        val dir = getBackupDirectory()
        listBackupFiles(dir)
    }

    private fun listBackupFiles(dir: File): List<LocalBackupFile> {
        if (!dir.exists()) return emptyList()
        val result = mutableListOf<LocalBackupFile>()
        val children = dir.listFiles() ?: return emptyList()
        for (f in children) {
            if (!f.isFile) continue
            val name = f.name
            val isSqlite = name.endsWith(".sqlite") || name.endsWith(".db")
            val isJson = name.endsWith(".json.gz") || name.endsWith(".json")
            if (!isSqlite && !isJson) continue
            if (name.endsWith(".metadata.json")) continue
            val format = if (isSqlite) BackupFormat.sqlite else BackupFormat.json
            val metadata = readMetadata(f, format)
            result.add(
                LocalBackupFile(
                    fileName = name,
                    filePath = f.absolutePath,
                    sizeBytes = f.length(),
                    createdTime = f.lastModified(),
                    format = format,
                    metadata = metadata
                )
            )
        }
        return result.sortedByDescending { it.createdTime }
    }

    private fun readMetadata(file: File, format: BackupFormat): BackupMetadata? {
        return try {
            when (format) {
                BackupFormat.json -> {
                    val json = if (file.name.endsWith(".gz")) {
                        GZIPInputStream(FileInputStream(file)).use { inp ->
                            inp.readBytes().toString(Charsets.UTF_8)
                        }
                    } else {
                        file.readText(Charsets.UTF_8)
                    }
                    val map = gson.fromJson<Map<String, Any>>(
                        json,
                        object : TypeToken<Map<String, Any>>() {}.type
                    )
                    gson.fromJson(gson.toJson(map["metadata"]), BackupMetadata::class.java)
                }
                BackupFormat.sqlite -> {
                    val sidecar = File(file.parentFile, removeExt(file.name) + ".metadata.json")
                    if (sidecar.exists()) {
                        gson.fromJson(sidecar.readText(), BackupMetadata::class.java)
                    } else null
                }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun removeExt(name: String): String =
        name.substringBeforeLast('.', name)

    // ─── مغلف JSON ───────────────────────────────────────────────

    /**
     * بناء مغلف النسخة بنفس مفاتيح Dart buildBackupDataMap — كل جدول
     * يُفرَّغ كقائمة صفوف (أسماء أعمدة SQLite → قيم).
     */
    private fun buildJsonBackupEnvelope(deviceLabel: String, now: Long): Map<String, Any> {
        val sq = db.openHelper.writableDatabase
        val envelope = linkedMapOf<String, Any>()
        val counts = mutableMapOf<String, Int>()

        for (key in BACKUP_TABLE_KEYS) {
            val rows = dumpTable(key)
            counts[key] = rows.size
            envelope[key] = rows
        }
        // القائمة السوداء — جدولها المحلي في Kotlin (blacklist_entries)
        val blacklistRows = dumpTable("blacklist_entries")
        counts["blacklist"] = blacklistRows.size
        envelope["blacklist"] = blacklistRows
        // حالة المزامنة (صف واحد)
        envelope["sync_state"] = dumpTable("sync_state")

        val total = counts.values.sum()
        val tablesJson = gson.toJson(envelope)
        val digest = java.security.MessageDigest.getInstance("SHA-256")
            .digest(tablesJson.toByteArray(Charsets.UTF_8))
            .joinToString("") { String.format("%02x", it) }

        val metadata = linkedMapOf<String, Any>(
            "app_version" to "1.2.0+3",
            "database_version" to sq.version,
            "backup_timestamp" to isoTimestamp(now),
            "total_records" to total,
            "device_info" to deviceLabel,
            "data_hash" to digest
        )
        val result = linkedMapOf<String, Any>()
        result["metadata"] = metadata
        for (e in envelope) result[e.key] = e.value
        return result
    }

    /** قراءة جدول محلي كقائمة صفوف خام (نفس شكل صفوف Dart toJson). */
    fun dumpTable(table: String): List<Map<String, Any?>> {
        val sq = db.openHelper.writableDatabase
        val rows = mutableListOf<Map<String, Any?>>()
        val safe = table.replace("\"", "\"\"")
        sq.query("SELECT * FROM \"$safe\"").use { cursor ->
            while (cursor.moveToNext()) {
                val row = linkedMapOf<String, Any?>()
                for (i in 0 until cursor.columnCount) {
                    row[cursor.getColumnName(i)] = when (cursor.getType(i)) {
                        android.database.Cursor.FIELD_TYPE_NULL -> null
                        android.database.Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(i)
                        android.database.Cursor.FIELD_TYPE_FLOAT -> cursor.getDouble(i)
                        android.database.Cursor.FIELD_TYPE_BLOB -> cursor.getBlob(i)
                        else -> cursor.getString(i)
                    }
                }
                rows.add(row)
            }
        }
        return rows
    }

    /** نسخ ملف قاعدة البيانات الخام — نظير SqliteBackupRestore.backupDatabase. */
    private fun copySqliteDatabase(dest: File) {
        val sq = db.openHelper.writableDatabase
        sq.query("PRAGMA wal_checkpoint(TRUNCATE)").use { it.moveToFirst() }
        val dbPath = sq.path
        val src = File(dbPath)
        FileInputStream(src).use { inp -> FileOutputStream(dest).use { out -> inp.copyTo(out) } }
    }

    private fun isoTimestamp(millis: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).format(Date(millis))

    // ─── الاستعادة ───────────────────────────────────────────────

    /**
     * نظير restoreFromLocalBackup — يتفرع حسب امتداد الملف:
     * .sqlite/.db استعادة خام (استبدال الملف)، .json/.gz استعادة بيانات.
     */
    suspend fun restoreFromLocalBackup(filePath: String) = withContext(Dispatchers.IO) {
        val name = filePath.substringAfterLast('/')
        if (name.endsWith(".sqlite") || name.endsWith(".db")) {
            restoreFromSqliteFile(filePath)
        } else {
            restoreFromJsonBackup(filePath)
        }
    }

    /** استعادة بيانات JSON: مسح ثم إدراج داخل معاملة واحدة. */
    private fun restoreFromJsonBackup(filePath: String) {
        val json = if (filePath.endsWith(".gz")) {
            GZIPInputStream(FileInputStream(filePath)).use { inp ->
                inp.readBytes().toString(Charsets.UTF_8)
            }
        } else {
            File(filePath).readText(Charsets.UTF_8)
        }
        val data = gson.fromJson<Map<String, Any>>(
            json, object : TypeToken<Map<String, Any>>() {}.type
        ) ?: throw Exception("ملف النسخة غير صالح")

        val sq = db.openHelper.writableDatabase
        sq.beginTransaction()
        try {
            for (key in BACKUP_TABLE_KEYS) {
                val rows = data[key] as? List<*> ?: continue
                clearAndInsertRows(key, rows)
            }
            // القائمة السوداء → جدولها المحلي
            (data["blacklist"] as? List<*>)?.let { rows ->
                clearAndInsertRows("blacklist_entries", rows)
            }
            // حالة المزامنة
            (data["sync_state"] as? List<*>)?.let { rows ->
                clearAndInsertRows("sync_state", rows)
            }
            sq.setTransactionSuccessful()
        } finally {
            sq.endTransaction()
        }
    }

    private fun clearAndInsertRows(table: String, rows: List<*>) {
        val sq = db.openHelper.writableDatabase
        val safe = table.replace("\"", "\"\"")
        sq.execSQL("DELETE FROM \"$safe\"")
        for (raw in rows) {
            @Suppress("UNCHECKED_CAST")
            val row = raw as? Map<String, Any?> ?: continue
            if (row.isEmpty()) continue
            val cols = row.keys.map { it.replace("\"", "\"\"") }
            val placeholders = cols.joinToString(",") { "?" }
            val values = Array(row.size) { idx ->
                val v = row[cols[idx].replace("\"\"", "\"")]
                when (v) {
                    is Boolean -> if (v) 1L else 0L
                    else -> v
                }
            }
            sq.execSQL(
                "INSERT OR REPLACE INTO \"$safe\" (${cols.joinToString(",") { "\"$it\"" }}) VALUES ($placeholders)",
                values
            )
        }
    }

    /**
     * استعادة ملف خام — نظير SqliteBackupRestore.restoreDatabase:
     * استبدال ملف قاعدة البيانات ثم إعادة تشغيل العملية لفتحها.
     */
    private fun restoreFromSqliteFile(sourcePath: String) {
        val sq = db.openHelper.writableDatabase
        val dbPath = sq.path ?: throw Exception("لا يمكن تحديد مسار قاعدة البيانات")
        // نسخة احتياطية قبل الاستبدال (أمان)
        sq.query("PRAGMA wal_checkpoint(TRUNCATE)").use { it.moveToFirst() }
        val current = File(dbPath)
        val safety = File(dbPath + ".pre_restore")
        FileInputStream(current).use { inp -> FileOutputStream(safety).use { out -> inp.copyTo(out) } }
        // استبدال الملف
        FileInputStream(File(sourcePath)).use { inp -> FileOutputStream(current).use { out -> inp.copyTo(out) } }
        File(dbPath + "-wal").delete()
        File(dbPath + "-shm").delete()
    }

    // ─── مشاركة / استيراد / حذف ─────────────────────────────────

    /** مشاركة نسخة عبر FileProvider — نظير shareBackup في Dart. */
    suspend fun shareBackup(filePath: String) = withContext(Dispatchers.IO) {
        val src = File(filePath)
        if (!src.exists()) throw Exception("الملف غير موجود")
        // انسخ إلى cache ليغطيه FileProvider (يغطي cache_path فقط)
        val cacheDir = File(context.cacheDir, "backups").apply { mkdirs() }
        val target = File(cacheDir, src.name)
        FileInputStream(src).use { inp -> FileOutputStream(target).use { out -> inp.copyTo(out) } }
        val uri = androidx.core.content.FileProvider.getUriForFile(
            context, context.packageName + ".fileprovider", target
        )
        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "application/octet-stream"
            putExtra(android.content.Intent.EXTRA_STREAM, uri)
            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        intent.clipData = android.content.ClipData.newRawUri("backup", uri)
        context.startActivity(
            android.content.Intent.createChooser(intent, "مشاركة النسخة الاحتياطية")
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    /** آخر وقت نسخ محلي — من DataStore (نظير getLastLocalBackupTime). */
    suspend fun getLastLocalBackupTime(): Long? = withContext(Dispatchers.IO) {
        settings.lastBackupTimeOnce()
    }

    /** نظير importBackupFromFile: نسخ ملف خارجي إلى مجلد النسخ. */
    suspend fun importBackupFromFile(uri: Uri): String = withContext(Dispatchers.IO) {
        val dir = getBackupDirectory()
        val stamp = System.currentTimeMillis()
        val pickedName = queryDisplayName(uri)
        val hasValidExt = pickedName != null && (
            pickedName.endsWith(".json.gz") ||
                pickedName.endsWith(".json") ||
                pickedName.endsWith(".sqlite") ||
                pickedName.endsWith(".db")
            )
        val safeName = if (hasValidExt) {
            "imported_backup_" + stamp + "_" + pickedName
        } else {
            "imported_backup_" + stamp + ".json.gz"
        }
        val dest = File(dir, safeName)
        context.contentResolver.openInputStream(uri)?.use { inp ->
            FileOutputStream(dest).use { out -> inp.copyTo(out) }
        } ?: throw Exception("تعذر قراءة الملف المحدد")
        dest.absolutePath
    }

    private fun queryDisplayName(uri: Uri): String? {
        return try {
            context.contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) c.getString(idx) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    /** حذف نسخة (مع ملف الميتاداتا الجانبي إن وجد). */
    suspend fun deleteLocalBackup(filePath: String) = withContext(Dispatchers.IO) {
        val f = File(filePath)
        if (f.exists()) f.delete()
        if (f.name.endsWith(".db") || f.name.endsWith(".sqlite")) {
            val sidecar = File(f.parentFile, removeExt(f.name) + ".metadata.json")
            if (sidecar.exists()) sidecar.delete()
        }
    }

    /** نظير estimateDatabaseSize في BackupDataService. */
    suspend fun estimateDatabaseSize(): Long = withContext(Dispatchers.IO) {
        try {
            File(db.openHelper.writableDatabase.path).length()
        } catch (e: Exception) {
            0L
        }
    }

    /** جداول المستخدم الحالية من sqlite_master (للتصدير الشامل). */
    fun userTableNames(): List<String> {
        val names = mutableListOf<String>()
        db.openHelper.writableDatabase
            .query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'room_%' AND name != 'android_metadata'")
            .use { c -> while (c.moveToNext()) names.add(c.getString(0)) }
        return names.filter { it !in INTERNAL_TABLES }
    }

    /** عدّ سجلات كل جدول — نظير _collectRecordCounts. */
    fun collectRecordCounts(): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()
        for (name in userTableNames()) {
            val safe = name.replace("\"", "\"\"")
            db.openHelper.writableDatabase
                .query("SELECT COUNT(*) AS n FROM \"$safe\"")
                .use { c -> if (c.moveToFirst()) counts[name] = c.getInt(0) }
        }
        return counts
    }
}
