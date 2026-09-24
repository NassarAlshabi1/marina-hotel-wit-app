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
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit
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
class D1BackupException(message: String, val details: String? = null) :
    Exception(if (details != null) "$message — $details" else message)

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
    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(90, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

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
        token: String,
        accountId: String
    ): Map<String, Any> = withContext(Dispatchers.IO) {
        val url = "https://api.cloudflare.com/client/v4$path"
        var lastError: Exception? = null
        // إعادة محاولة واحدة عند أعطال الشبكة — كل الكتابات idempotent.
        for (attempt in 0 until 2) {
            try {
                val builder = Request.Builder()
                    .url(url)
                    .header("Authorization", "Bearer $token")
                if (method == "GET") {
                    builder.get()
                } else {
                    builder.post(
                        (bodyJson ?: "{}").toRequestBody(
                            "application/json; charset=utf-8".toMediaType()
                        )
                    )
                }
                client.newCall(builder.build()).execute().use { resp ->
                    val text = resp.body?.string() ?: ""
                    val decoded = gson.fromJson<Map<String, Any>>(
                        text, object : com.google.gson.reflect.TypeToken<Map<String, Any>>() {}.type
                    ) ?: throw D1BackupException("فشل نداء Cloudflare (HTTP ${resp.code})")
                    if (decoded["success"] != true) {
                        throw D1BackupException(
                            "فشل نداء Cloudflare (HTTP ${resp.code})",
                            details = decoded["errors"]?.toString()
                        )
                    }
                    return@withContext decoded
                }
            } catch (e: D1BackupException) {
                throw e
            } catch (e: Exception) {
                lastError = e
                if (attempt == 0) continue
            }
        }
        throw D1BackupException("تعذر الاتصال بـ Cloudflare", details = lastError?.toString())
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
            token = token,
            accountId = accountId
        )
        val result = decoded["result"]
        return if (result is List<*>) {
            result.filterIsInstance<Map<String, Any>>()
        } else emptyList()
    }

    /** عبارات متعددة بلا معاملات في نداء واحد (نظير executeStatements). */
    private suspend fun executeStatements(
        statements: List<String>,
        token: String,
        accountId: String,
        databaseId: String
    ) {
        if (statements.isEmpty()) return
        query(
            statements.joinToString(";\n"),
            token = token, accountId = accountId, databaseId = databaseId
        )
    }

    // ─── الفحص والاكتشاف ─────────────────────────────────────────

    /**
     * فحص التوكن + الوصول للقاعدة + صلاحيات الكتابة — نظير probe()
     * في Dart حرفياً (DML عبر INSERT على جدول غير موجود، DDL عبر
     * إنشاء/حذف جدول اختبار).
     */
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
                token = token, accountId = conn.accountId
            )
            val result = verify["result"] as? Map<*, *>
            tokenValid = result?.get("status") == "active"
        } catch (e: D1BackupException) {
            // توكنات المستخدم (cfut_) تُفحص عبر /user/tokens/verify — نفس Dart
            try {
                val verify = call(
                    "GET", "/user/tokens/verify",
                    token = token, accountId = conn.accountId
                )
                val result = verify["result"] as? Map<*, *>
                tokenValid = result?.get("status") == "active"
            } catch (e2: Exception) {
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
                token = token, accountId = conn.accountId
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
            // DML: INSERT على جدول غير موجود — إن كان الخطأ no such table
            // فالعبارة اجتازت طبقة التصريح (لا يُكتب شيء فعلياً).
            try {
                query(
                    "INSERT INTO _cf_probe_missing_table (a) VALUES (1)",
                    token = token, accountId = conn.accountId, databaseId = conn.databaseId
                )
                dmlAllowed = true
            } catch (e: D1BackupException) {
                val blob = ("${e.message} ${e.details ?: ""}").lowercase()
                if (blob.contains("no such table") || blob.contains("sqlite_error")) {
                    dmlAllowed = true
                } else {
                    dmlError = "${e.message}${e.details?.let { " — $it" } ?: ""}"
                }
            }
            // DDL: إنشاء/حذف جدول اختبار حقيقي.
            try {
                executeStatements(
                    listOf(
                        "CREATE TABLE IF NOT EXISTS _cf_write_probe (id INTEGER)",
                        "DROP TABLE IF EXISTS _cf_write_probe"
                    ),
                    token = token, accountId = conn.accountId, databaseId = conn.databaseId
                )
                ddlAllowed = true
            } catch (e: D1BackupException) {
                ddlAllowed = false
            }
        }

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
    ): D1UploadResult = withContext(Dispatchers.IO) {
        cancelled = false
        val conn = settings.load()
        val startedAt = System.currentTimeMillis()
        var rowsUploaded = 0
        val errors = mutableListOf<String>()
        val warnings = mutableListOf<String>()
        val doneTables = mutableListOf<String>()
        var callCount = 0

        // 1) نقل المخطط (CREATE ... IF NOT EXISTS) — DDL قد يُرفض؛ ليس قاتلاً.
        val ddl = mutableListOf<String>()
        for (t in tables) {
            for (s in t.createSqlList) {
                toIfNotExists(s)?.let { ddl.add(it) }
            }
        }
        var i = 0
        while (i < ddl.size) {
            if (cancelled) break
            val chunk = ddl.subList(i, minOf(i + 40, ddl.size))
            try {
                executeStatements(
                    chunk, token = conn.apiToken,
                    accountId = conn.accountId, databaseId = conn.databaseId
                )
                callCount++
            } catch (e: D1BackupException) {
                warnings.add("تخطي نقل المخطط (DDL): ${e.message}")
                break
            }
            i += 40
        }

        // 2) بيانات الجداول.
        val totalTables = tables.size
        for (ti in 0 until totalTables) {
            if (cancelled) break
            val t = tables[ti]
            onProgress?.invoke(
                D1UploadProgress(
                    stage = "نقل المخطط والبيانات",
                    currentTable = t.name,
                    tableIndex = ti,
                    tableCount = totalTables,
                    rowsDone = 0,
                    rowsTotal = t.rowCount
                )
            )
            if (t.rowCount == 0) {
                doneTables.add(t.name)
                continue
            }
            try {
                var offset = 0
                var columns: List<String> = emptyList()
                var rowsForTable = 0
                while (offset < t.rowCount) {
                    if (cancelled) break
                    val chunk = t.readChunk(CHUNK_SIZE, offset)
                    if (chunk.isEmpty()) break
                    if (columns.isEmpty() && chunk.first().isNotEmpty()) {
                        columns = chunk.first().keys.toList()
                    }
                    val colCount = columns.size
                    if (colCount in 1..PARAMS_BUDGET) {
                        // نمط المعاملات الآمن: INSERT متعدد الصفوف ≤ 96 معاملاً.
                        val rowsPerCall = (PARAMS_BUDGET / colCount).coerceIn(1, CHUNK_SIZE)
                        var j = 0
                        while (j < chunk.size) {
                            if (cancelled) break
                            val part = chunk.subList(j, minOf(j + rowsPerCall, chunk.size))
                            val placeholders = List(part.size) {
                                "(${List(colCount) { "?" }.joinToString(",")})"
                            }.joinToString(",")
                            val sql =
                                "INSERT OR REPLACE INTO \"${quoteIdent(t.name)}\" " +
                                    "(${columns.joinToString(",") { quoteIdent(it) }}) " +
                                    "VALUES $placeholders"
                            val params = mutableListOf<Any?>()
                            for (row in part) for (c in columns) params.add(row[c])
                            query(
                                sql, params,
                                token = conn.apiToken,
                                accountId = conn.accountId,
                                databaseId = conn.databaseId
                            )
                            callCount++
                            rowsForTable += part.size
                            onProgress?.invoke(
                                D1UploadProgress(
                                    stage = "رفع البيانات",
                                    currentTable = t.name,
                                    tableIndex = ti,
                                    tableCount = totalTables,
                                    rowsDone = rowsForTable,
                                    rowsTotal = t.rowCount
                                )
                            )
                            j += rowsPerCall
                        }
                    } else {
                        // جداول عريضة (>96 عموداً): حرفية مُهربة، صف لكل عبارة.
                        val statements = mutableListOf<String>()
                        for (row in chunk) {
                            val values = columns.joinToString(",") { sqlLiteral(row[it]) }
                            statements.add(
                                "INSERT OR REPLACE INTO \"${quoteIdent(t.name)}\" " +
                                    "(${columns.joinToString(",") { quoteIdent(it) }}) " +
                                    "VALUES ($values)"
                            )
                        }
                        var k = 0
                        while (k < statements.size) {
                            if (cancelled) break
                            executeStatements(
                                statements.subList(k, minOf(k + 40, statements.size)),
                                token = conn.apiToken,
                                accountId = conn.accountId,
                                databaseId = conn.databaseId
                            )
                            callCount++
                            k += 40
                        }
                        rowsForTable += chunk.size
                        onProgress?.invoke(
                            D1UploadProgress(
                                stage = "رفع البيانات (نمط حرفي)",
                                currentTable = t.name,
                                tableIndex = ti,
                                tableCount = totalTables,
                                rowsDone = rowsForTable,
                                rowsTotal = t.rowCount
                            )
                        )
                    }
                    offset += chunk.size
                }
                rowsUploaded += rowsForTable
                doneTables.add(t.name)
            } catch (e: D1BackupException) {
                errors.add("${t.name}: ${e.message}${e.details?.let { " — $it" } ?: ""}")
            }
        }

        // 3) كتابة سجل metadata آخر عملية رفع (نظير _cf_backup_meta).
        if (!cancelled && errors.isEmpty() && doneTables.isNotEmpty()) {
            try {
                executeStatements(
                    listOf(
                        "CREATE TABLE IF NOT EXISTS _cf_backup_meta (id INTEGER PRIMARY KEY CHECK (id = 1), " +
                            "uploaded_at TEXT NOT NULL, tables_count INTEGER NOT NULL, " +
                            "rows_count INTEGER NOT NULL, device_label TEXT)"
                    ),
                    token = conn.apiToken, accountId = conn.accountId, databaseId = conn.databaseId
                )
                val nowIso = java.text.SimpleDateFormat(
                    "yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US
                ).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
                    .format(java.util.Date())
                executeStatements(
                    listOf(
                        "INSERT OR REPLACE INTO _cf_backup_meta (id, uploaded_at, tables_count, rows_count, device_label) " +
                            "VALUES (1, '$nowIso', ${doneTables.size}, $rowsUploaded, '${sqlLiteralValue(deviceLabel ?: "")}')"
                    ),
                    token = conn.apiToken, accountId = conn.accountId, databaseId = conn.databaseId
                )
                callCount++
            } catch (e: D1BackupException) {
                errors.add("_cf_backup_meta: ${e.message}")
            }
        }

        val elapsed = System.currentTimeMillis() - startedAt
        D1UploadResult(
            ok = errors.isEmpty() && !cancelled,
            cancelled = cancelled,
            tablesDone = doneTables.size,
            rowsUploaded = rowsUploaded,
            apiCalls = callCount,
            errors = errors,
            warnings = warnings,
            elapsedMs = elapsed
        )
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
        is ByteArray -> "X'${v.joinToString("") { String.format("%02x", it) }}'"
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
