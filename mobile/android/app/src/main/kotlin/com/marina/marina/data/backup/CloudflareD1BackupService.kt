package com.marina.marina.data.backup

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.gson.Gson
import com.marina.marina.data.remote.CloudflareConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * خدمة رفع البيانات المحلية إلى Cloudflare D1 (نسخة استشارية) — نقل
 * CloudflareD1Service من فرع Flutter (cloudflare_d1_service.dart) بنفس
 * القيود المُثبتة تجريبياً على الحساب:
 *
 *  • حد المعاملات: 100 لكل استعلام — نستخدم ≤ 96 هامشاً.
 *  • نقطة /query تقبل عبارات متعددة لكن **بدون** params (خطأ 7400).
 *  • الكتابة تتطلب توكناً بصلاحية D1 Edit وإلا رُفضت بـ SQLITE_AUTH.
 *
 * نطاق الرفع = CloudflareConfig.SYNC_ENTITIES (نظير d1BackupTables =
 * migrationOrder — 24 كياناً). القائمة السوداء بلا جدول محلي في Flutter
 * لكن في Kotlin لها جدول (blacklist_entries) — يُحوَّل إلى أعمدة جدول
 * blacklist في D1 بنفس شكل blacklistRowFromShiftNote. أما shift_notes
 * فيُستبعد منه أي صف موسوم created_by='blacklist' (توافق مع Dart).
 *
 * الإعدادات في DataStore (SharedPreferences → DataStore حسب خريطة
 * المشروع) والتوكن في التخزين المشفّر عبر CloudflareConfig.setD1ApiToken
 * (نفس مفتاح Flutter cf_d1_api_token).
 */
private val Context.d1BackupDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "cf_d1_backup_settings"
)

/** نظير CloudflareD1Settings في Dart — مفاتيح cf_d1_* نفسها. */
@Singleton
class D1BackupSettingsStore @Inject constructor(
    @ApplicationContext private val context: Context,
    private val cloudflareConfig: CloudflareConfig
) {
    companion object {
        val ACCOUNT_ID = stringPreferencesKey("cf_d1_account_id")
        val DATABASE_ID = stringPreferencesKey("cf_d1_database_id")
        val DEVICE_LABEL = stringPreferencesKey("cf_d1_device_label")

        /** القيم المعروفة من الحساب (افتراضيات الحقول — نفس Dart). */
        const val KNOWN_ACCOUNT_ID = CloudflareConfig.D1_ACCOUNT_ID
        const val KNOWN_DATABASE_ID = CloudflareConfig.D1_DATABASE_ID
    }

    data class D1Connection(
        val accountId: String,
        val databaseId: String,
        val apiToken: String,
        val deviceLabel: String
    ) {
        val isComplete: Boolean
            get() = accountId.trim().isNotEmpty() &&
                databaseId.trim().isNotEmpty() &&
                apiToken.trim().isNotEmpty()
    }

    /** القيم الحالية: من DataStore مع افتراضيات الحساب المعروفة. */
    suspend fun load(): D1Connection {
        val prefs = context.d1BackupDataStore.data.first()
        return D1Connection(
            accountId = prefs[ACCOUNT_ID] ?: KNOWN_ACCOUNT_ID,
            databaseId = prefs[DATABASE_ID] ?: KNOWN_DATABASE_ID,
            apiToken = cloudflareConfig.d1ApiToken ?: "",
            deviceLabel = prefs[DEVICE_LABEL] ?: ""
        )
    }

    val deviceLabelFlow: Flow<String> =
        context.d1BackupDataStore.data.map { it[DEVICE_LABEL] ?: "" }

    /** حفظ الإعدادات — التوكن يذهب للتخزين المشفّر (نظير FlutterSecureStorage). */
    suspend fun save(connection: D1Connection) {
        context.d1BackupDataStore.edit {
            it[ACCOUNT_ID] = connection.accountId.trim()
            it[DATABASE_ID] = connection.databaseId.trim()
            it[DEVICE_LABEL] = connection.deviceLabel.trim()
        }
        cloudflareConfig.setD1ApiToken(connection.apiToken.trim().ifEmpty { null })
    }
}

/** نتيجة فحص الاتصال — نظير CloudflareD1ProbeResult بنفس الحقول. */
data class D1ProbeBackupResult(
    val tokenValid: Boolean,
    val accountReachable: Boolean,
    val databaseReachable: Boolean,
    val databaseName: String?,
    val dmlAllowed: Boolean,
    val ddlAllowed: Boolean,
    val dmlError: String?,
    val fatalError: String?
)

/** تقدم الرفع — نظير CloudflareD1Progress. */
data class D1UploadProgress(
    val stage: String,
    val currentTable: String,
    val tableIndex: Int,
    val tableCount: Int,
    val rowsDone: Int,
    val rowsTotal: Int
) {
    /** نظير tableFraction في Dart. */
    val tableFraction: Double
        get() = if (tableCount == 0) 0.0
        else (tableIndex + if (rowsTotal > 0) (rowsDone.toDouble() / rowsTotal) else 1.0) / tableCount
}

/** نتيجة الرفع — نظير CloudflareD1UploadResult. */
data class D1UploadResult(
    val ok: Boolean,
    val cancelled: Boolean,
    val tablesDone: Int,
    val rowsUploaded: Int,
    val apiCalls: Int,
    val errors: List<String>,
    val warnings: List<String>,
    val elapsedMs: Long
)

/** جدول مصدر للرفع — نظير CloudflareD1SourceTable. */
class D1SourceTable(
    val name: String,
    val rowCount: Int,
    val createSqlList: List<String>,
    /** قراءة دفعة صفوف (limit, offset) → صفوف خام عمود→قيمة. */
    val readChunk: suspend (limit: Int, offset: Int) -> List<Map<String, Any?>>
)

/** خطأ D1 مع تفاصيل — نظير CloudflareD1Exception. */
class D1BackupException(
    message: String,
    val details: String? = null,
    cause: Throwable? = null
) : Exception(if (details != null) "$message — $details" else message, cause)

@Singleton
class CloudflareD1BackupService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val db: com.marina.marina.data.local.AppDatabase,
    private val settings: D1BackupSettingsStore,
    private val cloudflareConfig: CloudflareConfig
) {
    companion object {
        /** حد المعاملات المُثبت تجريبياً على الحساب (نفس Dart). */
        const val MAX_PARAMS_PER_QUERY = 100
        private const val PARAM_SAFETY_MARGIN = 4

        /** الميزانية الفعلية للمعاملات في نداء واحد (96). */
        const val PARAMS_BUDGET = MAX_PARAMS_PER_QUERY - PARAM_SAFETY_MARGIN

        /** حجم دفعة القراءة المحلية (نظير _chunkSize = 400). */
        private const val CHUNK_SIZE = 400

        /** استعلام مصدر صفوف shift_notes الحقيقية — نفس Dart shiftNotesSourceSql. */
        const val SHIFT_NOTES_SOURCE_SQL =
            "SELECT * FROM shift_notes WHERE created_by != 'blacklist'"
    }

    private val gson = Gson()
    private val http = D1HttpClient()

    @Volatile
    private var cancelled = false

    /** طلب إيقاف الرفع — يُفحص بين الدفعات (نظير cancel()). */
    fun cancelUpload() {
        cancelled = true
    }

    // ─── طبقة HTTP ───────────────────────────────────────────────

    private suspend fun call(
        method: String,
        path: String,
        bodyJson: String? = null,
        token: String
    ): Map<String, Any> = withContext(Dispatchers.IO) {
        http.call(method, path, bodyJson, token)
    }

    /** تنفيذ SQL وإرجاع مجموعات النتائج (نظير _query). */
    private suspend fun query(
        sql: String,
        params: List<Any?>? = null,
        token: String,
        accountId: String,
        databaseId: String
    ): List<Map<String, Any>> {
        val body = linkedMapOf<String, Any>("sql" to sql)
        if (params != null) body["params"] = params
        val decoded = call(
            "POST",
            "/accounts/$accountId/d1/database/$databaseId/query",
            gson.toJson(body),
            token = token
        )
        val result = decoded["result"]
        return if (result is List<*>) {
            result.filterIsInstance<Map<String, Any>>()
        } else emptyList()
    }

    /** Read-only token/database probe. Never test permissions by writing SQL. */
    suspend fun probe(): D1ProbeBackupResult = withContext(Dispatchers.IO) {
        val conn = settings.load()
        val token = conn.apiToken
        var tokenValid = false
        var accountReachable = false
        var databaseReachable = false
        var databaseName: String? = null
        var dmlAllowed = false
        var ddlAllowed = false
        var dmlError: String? = null
        var fatalError: String? = null

        if (token.isBlank()) {
            return@withContext D1ProbeBackupResult(
                tokenValid = false, accountReachable = false, databaseReachable = false,
                databaseName = null, dmlAllowed = false, ddlAllowed = false,
                dmlError = null, fatalError = "التوكن غير صالح: لا يوجد توكن محفوظ"
            )
        }

        try {
            val verify = call(
                "GET", "/accounts/${conn.accountId}/tokens/verify",
                token = token
            )
            val result = verify["result"] as? Map<*, *>
            tokenValid = result?.get("status") == "active"
        } catch (e: D1BackupException) {
            // توكنات المستخدم (cfut_) تُفحص عبر /user/tokens/verify — نفس Dart
            try {
                val verify = call(
                    "GET", "/user/tokens/verify",
                    token = token
                )
                val result = verify["result"] as? Map<*, *>
                tokenValid = result?.get("status") == "active"
            } catch (e2: D1BackupException) {
                return@withContext D1ProbeBackupResult(
                    tokenValid = false, accountReachable = false, databaseReachable = false,
                    databaseName = null, dmlAllowed = false, ddlAllowed = false,
                    dmlError = null,
                    fatalError = "التوكن غير صالح: ${e.message} / $e2"
                )
            }
        }

        try {
            val list = call(
                "GET", "/accounts/${conn.accountId}/d1/database?per_page=50",
                token = token
            )
            accountReachable = true
            val result = list["result"]
            val rows: List<*> = when (result) {
                is Map<*, *> -> result["results"] as? List<*> ?: emptyList<Any>()
                is List<*> -> result
                else -> emptyList<Any>()
            }
            for (row in rows) {
                if (row is Map<*, *>) {
                    if (row["uuid"]?.toString() == conn.databaseId) {
                        databaseReachable = true
                        databaseName = row["name"]?.toString()
                    }
                }
            }
        } catch (e: D1BackupException) {
            fatalError = fatalError ?: "تعذر عرض قواعد D1: ${e.message}"
        }

        if (databaseReachable) {
            try {
                query("SELECT 1 AS ok", token = token, accountId = conn.accountId, databaseId = conn.databaseId)
            } catch (e: D1BackupException) {
                databaseReachable = false
                fatalError = e.message
            }
        }
        dmlError = "الرفع المباشر موقوف لحماية هوية البيانات؛ استخدم مزامنة Worker"

        D1ProbeBackupResult(
            tokenValid = tokenValid,
            accountReachable = accountReachable,
            databaseReachable = databaseReachable,
            databaseName = databaseName,
            dmlAllowed = dmlAllowed,
            ddlAllowed = ddlAllowed,
            dmlError = dmlError,
            fatalError = fatalError
        )
    }

    /** أسماء الجداول الموجودة في D1 (نظير listD1Tables). */
    suspend fun listD1Tables(): List<String> = withContext(Dispatchers.IO) {
        val conn = settings.load()
        val sets = query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
            token = conn.apiToken, accountId = conn.accountId, databaseId = conn.databaseId
        )
        if (sets.isEmpty()) return@withContext emptyList()
        @Suppress("UNCHECKED_CAST")
        val rows = (sets.first()["results"] as? List<Map<String, Any>>) ?: emptyList()
        rows.mapNotNull { it["name"]?.toString() }
    }

    // ─── بناء جداول المصدر من القاعدة المحلية ────────────────────

    /**
     * نطاق الرفع: SYNC_ENTITIES ∩ الجداول الموجودة محلياً (نظير
     * scopeSyncTables) + تجسيد blacklist من جدولها المحلي
     * blacklist_entries (نظير التجسيد من shift_notes في Dart).
     */
    fun scopeSyncTables(existingTables: Set<String>): List<String> =
        CloudflareConfig.SYNC_ENTITIES.filter { existingTables.contains(it) }

    data class LocalTableInfo(
        val name: String,
        val rowCount: Int,
        val createSqlList: List<String>
    )

    /** نظير _loadLocalTables: جداول النطاق + عدودها + DDL + blacklist. */
    suspend fun loadLocalTables(): List<LocalTableInfo> = withContext(Dispatchers.IO) {
        val sq = db.openHelper.writableDatabase
        val allTables = mutableListOf<String>()
        sq.query("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
            .use { c -> while (c.moveToNext()) allTables.add(c.getString(0)) }
        val names = scopeSyncTables(allTables.toSet())

        // جلب DDL (جداول + فهارس) مرتبة: الجداول أولاً ثم فهارسها.
        val ddlByTable = linkedMapOf<String, MutableList<String>>()
        sq.query(
            "SELECT type, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL " +
                "AND name NOT LIKE 'sqlite_%' AND type IN ('table','index') " +
                "ORDER BY CASE type WHEN 'table' THEN 0 ELSE 1 END"
        ).use { c ->
            while (c.moveToNext()) {
                val tbl = c.getString(1) ?: ""
                val sql = c.getString(2) ?: ""
                if (tbl.isEmpty() || sql.isEmpty()) continue
                ddlByTable.getOrPut(tbl) { mutableListOf() }.add(sql)
            }
        }

        val tables = mutableListOf<LocalTableInfo>()
        for (n in names) {
            // shift_notes: العدّ يستبعد صفوف القائمة السوداء الموسومة.
            val countSql = if (n == "shift_notes")
                "SELECT COUNT(*) AS n FROM shift_notes WHERE created_by != 'blacklist'"
            else
                "SELECT COUNT(*) AS n FROM \"${n.replace("\"", "\"\"")}\""
            val count = sq.query(countSql).use { c ->
                if (c.moveToFirst()) c.getInt(0) else 0
            }
            tables.add(LocalTableInfo(n, count, ddlByTable[n] ?: emptyList()))
        }

        // تجسيد blacklist — في Kotlin مصدرها جدول blacklist_entries المحلي
        // (نفس أعمدة جدول D1 في worker/schema.sql).
        val blCount = sq.query("SELECT COUNT(*) AS n FROM blacklist_entries").use { c ->
            if (c.moveToFirst()) c.getInt(0) else 0
        }
        tables.add(LocalTableInfo("blacklist", blCount, emptyList()))
        tables
    }

    /** بناء مصادر الرفع للجداول المحددة (نظير _upload sources). */
    fun buildSourceTables(tables: List<LocalTableInfo>): List<D1SourceTable> {
        val sq = db.openHelper.writableDatabase
        return tables.map { t ->
            D1SourceTable(
                name = t.name,
                rowCount = t.rowCount,
                createSqlList = t.createSqlList,
                readChunk = { limit, offset ->
                    withContext(Dispatchers.IO) {
                        // blacklist: مصدره جدول blacklist_entries المحلي
                        // (نظير التجسيد من shift_notes الموسومة في Dart —
                        // أعمدته تطابق أعمدة جدول blacklist في D1 مباشرة).
                        val sourceSql = when (t.name) {
                            "blacklist" -> "SELECT * FROM blacklist_entries"
                            "shift_notes" -> SHIFT_NOTES_SOURCE_SQL
                            else -> "SELECT * FROM \"${t.name.replace("\"", "\"\"")}\""
                        }
                        val sql = "$sourceSql LIMIT ? OFFSET ?"
                        val rows = mutableListOf<Map<String, Any?>>()
                        sq.query(sql, arrayOf(limit, offset)).use { c ->
                            while (c.moveToNext()) {
                                val row = linkedMapOf<String, Any?>()
                                for (i in 0 until c.columnCount) {
                                    row[c.getColumnName(i)] = when (c.getType(i)) {
                                        android.database.Cursor.FIELD_TYPE_NULL -> null
                                        android.database.Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
                                        android.database.Cursor.FIELD_TYPE_FLOAT -> c.getDouble(i)
                                        android.database.Cursor.FIELD_TYPE_BLOB -> c.getBlob(i)
                                        else -> c.getString(i)
                                    }
                                }
                                rows.add(row)
                            }
                        }
                        // blacklist: مصدره جدول blacklist_entries المحلي —
                        // أعمدته تطابق أعمدة جدول blacklist في D1 مباشرة.
                        rows
                    }
                }
            )
        }
    }

    // ─── الرفع ───────────────────────────────────────────────────

    /**
     * رفع الجداول المحددة إلى D1 (مخطط + بيانات) بأسلوب INSERT OR
     * REPLACE — نظير uploadData في Dart بنفس المراحل والقيود.
     */
    suspend fun uploadData(
        tables: List<D1SourceTable>,
        deviceLabel: String?,
        onProgress: ((D1UploadProgress) -> Unit)? = null
    ): D1UploadResult {
        // Fail before reading credentials, generating DDL, or making any HTTP call.
        error("الرفع المباشر إلى D1 موقوف: المعرّفات المحلية لا تصلح للمشاركة بين الأجهزة. استخدم رفع التغييرات عبر Worker.")
    }

    // ─── أدوات مساعدة (نظائر Dart) ───────────────────────────────

    private fun quoteIdent(name: String): String = name.replace("\"", "\"\"")

    /** قيمة SQLite خام → literal آمن (للجداول العريضة فقط). */
    private fun sqlLiteral(v: Any?): String = when (v) {
        null -> "NULL"
        is Int -> v.toString()
        is Long -> v.toString()
        is Double -> if (v.isNaN() || v.isInfinite()) "NULL" else v.toString()
        is Boolean -> if (v) "1" else "0"
        is ByteArray -> "X'${v.joinToString("") { String.format(java.util.Locale.ROOT, "%02x", it) }}'"
        else -> "'${v.toString().replace("'", "''")}'"
    }

    private fun sqlLiteralValue(s: String): String = s.replace("'", "''")

    /** إعادة صياغة CREATE → CREATE ... IF NOT EXISTS (نظير _toIfNotExists). */
    private fun toIfNotExists(ddl: String): String? {
        val regex = Regex(
            pattern = "^\\s*CREATE\\s+(TABLE|UNIQUE\\s+INDEX|INDEX|VIEW|TRIGGER)\\s+(IF\\s+NOT\\s+EXISTS\\s+)?",
            options = setOf(RegexOption.IGNORE_CASE)
        )
        val m = regex.find(ddl) ?: return null
        if (m.groupValues[2].isNotEmpty()) return ddl.trim()
        return "CREATE ${m.groupValues[1]} IF NOT EXISTS ${ddl.substring(m.range.last + 1)}".trim()
    }

    /** عدّ العمليات غير المُسلّمة في outbox — التنبيه الاستشاري بالشاشة. */
    suspend fun outboxPendingCount(): Int = withContext(Dispatchers.IO) {
        db.openHelper.writableDatabase
            .query("SELECT COUNT(*) FROM outbox WHERE delivered_to_primary = 0")
            .use { c -> if (c.moveToFirst()) c.getInt(0) else 0 }
    }
}
