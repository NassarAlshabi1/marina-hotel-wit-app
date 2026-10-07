package com.marina.marina.data.local

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import com.google.gson.JsonParser
import com.marina.marina.data.local.entity.FinanceSnapshotEntity
import com.marina.marina.di.DatabaseModule
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FinancialMigrationTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test
    fun schemaConstantMatchesTheDatabaseRoomActuallyCreates() {
        val room = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries().build()
        try {
            // Parity unification: bumped 76 → 77 to add idempotency_log TTL index
            // + finance_snapshots table + governance indexes.
            assertEquals(77, AppDatabase.SCHEMA_VERSION)
            assertEquals(AppDatabase.SCHEMA_VERSION, room.openHelper.writableDatabase.version)
        } finally { room.close() }
    }

    private fun assertSalaryUuidIndexes(db: SupportSQLiteDatabase) {
        for ((table, index) in listOf(
            "salary_withdrawals" to "idx_salary_wd_employee_uuid",
            "salary_cycles" to "idx_salary_cycles_employee_uuid",
            "salary_payments" to "idx_salary_payments_employee_uuid"
        )) {
            db.query("EXPLAIN QUERY PLAN SELECT * FROM $table WHERE employee_uuid = 'fixture'").use {
                assertTrue(it.moveToFirst())
                assertTrue("$table must use $index", it.getString(3).contains(index))
            }
        }
    }

    @Test
    fun freshDatabaseUsesSalaryUuidIndexes() {
        val room = Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java)
            .allowMainThreadQueries().build()
        try { assertSalaryUuidIndexes(room.openHelper.writableDatabase) }
        finally { room.close() }
    }

    @Test
    fun migrate73To74ValidatesRoomAndPreservesFinancialRows() {
        val name = "migration-73-74.db"
        createV70(name)
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
                .callback(object : SupportSQLiteOpenHelper.Callback(73) {
                    override fun onCreate(db: SupportSQLiteDatabase) = Unit
                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                        DatabaseModule.MIGRATION_70_71.migrate(db)
                        DatabaseModule.MIGRATION_71_72.migrate(db)
                        DatabaseModule.MIGRATION_72_73.migrate(db)
                    }
                }).build()
        )
        helper.writableDatabase
        helper.close()
        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_73_74, DatabaseModule.MIGRATION_74_75, DatabaseModule.MIGRATION_75_76, DatabaseModule.MIGRATION_76_77).allowMainThreadQueries().build()
            try {
                val db = room.openHelper.writableDatabase
                assertSalaryUuidIndexes(db)
                db.query("SELECT amount FROM salary_withdrawals").use {
                    assertTrue(it.moveToFirst()); assertEquals(12345.0, it.getDouble(0), 0.0)
                }
                db.query("SELECT COUNT(*) FROM outbox").use { assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0)) }
            } finally { room.close() }
        } finally { context.deleteDatabase(name) }
    }

    @Test
    fun migrate74To75ClassifiesEvidenceAndFlagsAmbiguousHistoryWithoutTouchingMoney() {
        for ((note, expected) in listOf("قسط سلفة قديم" to "salary_installment", "وصف قديم مجهول" to "unclassified")) {
            val name = "expense-kind-migration.db"
            createV70(name)
            val helper = FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
                    .callback(object : SupportSQLiteOpenHelper.Callback(74) {
                        override fun onCreate(db: SupportSQLiteDatabase) = Unit
                        override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                            DatabaseModule.MIGRATION_70_71.migrate(db)
                            DatabaseModule.MIGRATION_71_72.migrate(db)
                            DatabaseModule.MIGRATION_72_73.migrate(db)
                            DatabaseModule.MIGRATION_73_74.migrate(db)
                        }
                    }).build())
            helper.writableDatabase.execSQL("UPDATE expenses SET expense_type = 'خصم من الراتب', is_auto_generated = 1, description = ?", arrayOf(note))
            helper.close()
            try {
                val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                    .addMigrations(DatabaseModule.MIGRATION_74_75, DatabaseModule.MIGRATION_75_76, DatabaseModule.MIGRATION_76_77).allowMainThreadQueries().build()
                try {
                    val db = room.openHelper.writableDatabase
                    db.query("SELECT expense_kind, amount, updated_at FROM expenses").use {
                        assertTrue(it.moveToFirst()); assertEquals(expected, it.getString(0))
                        assertEquals(12345.0, it.getDouble(1), 0.0); assertEquals(0L, it.getLong(2))
                    }
                    db.query("SELECT COUNT(*) FROM outbox").use { assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0)) }
                } finally { room.close() }
            } finally { context.deleteDatabase(name) }
        }
    }

    /**
     * ✅ (2026-10-06) 75→76: أعمدة خادمية كانت تُسقَط صامتة عند السحب.
     *
     * المخطط الكامل يُتحقق تلقائياً عند فتح Room (Room يقارن كل عمود: الاسم
     * والنوع والـNOT NULL) — فالاختبار يفشل لو اختلف أي `ALTER TABLE` عن
     * تعريف الكيان. ويُضاف فوقه: القيم الافتراضية للصفوف القائمة، وبقاء
     * صف الحجر القديم، وسلامة المال.
     */
    @Test
    fun migrate75To76AddsDroppedServerColumnsWithoutTouchingExistingRows() {
        val name = "migration-75-76.db"
        createV70(name)
        // ترقية الملف إلى 75 بالترحيلات الحقيقية ثم إدخال صف حجر قديم.
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
                .callback(object : SupportSQLiteOpenHelper.Callback(75) {
                    override fun onCreate(db: SupportSQLiteDatabase) = Unit
                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                        DatabaseModule.MIGRATION_70_71.migrate(db)
                        DatabaseModule.MIGRATION_71_72.migrate(db)
                        DatabaseModule.MIGRATION_72_73.migrate(db)
                        DatabaseModule.MIGRATION_73_74.migrate(db)
                        DatabaseModule.MIGRATION_74_75.migrate(db)
                    }
                }).build()
        )
        helper.writableDatabase.execSQL(
            "INSERT INTO sync_quarantine (entity, recordKey, payload, reason) VALUES ('rooms', 'uuid:legacy', '{\"a\":1}', 'legacy')"
        )
        helper.close()

        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_75_76, DatabaseModule.MIGRATION_76_77).allowMainThreadQueries().build()
            try {
                val db = room.openHelper.writableDatabase
                assertEquals(77, db.version)
                // Parity unification: 76→77 adds idempotency_log TTL index + finance_snapshots table.

                // الأعمدة الثمانية الجديدة موجودة، وبقيم افتراضية سليمة.
                fun columnInfo(table: String, column: String): Triple<Boolean, String?, String>? =
                    db.query("PRAGMA table_info($table)").use { cursor ->
                        while (cursor.moveToNext()) {
                            if (cursor.getString(1) == column) {
                                return@use Triple(cursor.getInt(3) == 1, cursor.getString(4), cursor.getString(2))
                            }
                        }
                        null
                    }

                val expectedNotNull = mapOf(
                    "expenses" to setOf("employee_link_cleared"),
                    "inventory_items" to setOf("is_active"),
                    "sync_quarantine" to setOf("attempts", "firstSeen")
                )
                val expectedNullable = mapOf(
                    "salary_withdrawals" to listOf("expense_id"),
                    "inventory_transactions" to listOf("item_local_uuid", "user_id", "user_name"),
                    "blacklist_entries" to listOf("added_by", "added_date")
                )
                for ((table, columns) in expectedNotNull) {
                    for (column in columns) {
                        val info = columnInfo(table, column)
                        assertTrue("عمود مفقود: $table.$column", info != null)
                        assertTrue("يجب NOT NULL: $table.$column", info!!.first)
                    }
                }
                for ((table, columns) in expectedNullable) {
                    for (column in columns) {
                        val info = columnInfo(table, column)
                        assertTrue("عمود مفقود: $table.$column", info != null)
                        assertTrue("يجب nullable: $table.$column", !info!!.first)
                    }
                }
                // صفوف قائمة فعلية: الافتراضي يُملأ بلا إعادة كتابة بيانات.
                db.query("SELECT employee_link_cleared FROM expenses").use {
                    assertTrue(it.moveToFirst()); assertEquals(0L, it.getLong(0))
                }
                db.query("SELECT expense_id FROM salary_withdrawals").use {
                    assertTrue(it.moveToFirst()); assertTrue(it.isNull(0))
                }

                // صف الحجر القديم: الحمولة والسبب كما هما، والعدّادان الجديدان بقيمهما الافتراضية.
                db.query("SELECT payload, reason, attempts, firstSeen FROM sync_quarantine").use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals("{\"a\":1}", cursor.getString(0))
                    assertEquals("legacy", cursor.getString(1))
                    assertEquals(1L, cursor.getLong(2))
                    assertEquals(0L, cursor.getLong(3))
                }

                // المال وسجل الصادر لم يُمسّا.
                db.query("SELECT amount FROM expenses").use {
                    assertTrue(it.moveToFirst()); assertEquals(12345.0, it.getDouble(0), 0.0)
                }
                db.query("SELECT payload FROM outbox").use {
                    assertTrue(it.moveToFirst()); assertTrue(it.getString(0).contains("not_delivered"))
                }
            } finally { room.close() }
        } finally { context.deleteDatabase(name) }
    }

    /**
     * ✅ (2026-10-07) 76→77: جدول `finance_snapshots` + فهرسا الحوكمة.
     *
     * كان هذا الترحيل مُوصى به بلا اختبار (تقرير التكافؤ §4.5/§8 بند 4)،
     * وهذه الحالة تسدّ ذلك على JVM/Robolectric (مسار التحقق نفسه الذي يشغّله
     * Room في الإنتاج: `onValidateSchema` بعد كل ترحيل) — بلا حاجة إلى
     * محاكي `androidTest` لا يشغّله CI.
     *
     * تُثبت: (أ) بقاء بيانات ما قبل الترقية، (ب) عقد الأعمدة الـ14
     * (الأنواع/`NOT NULL`/الافتراضيات) بعد الترحيل، (ج) الفهرسين بأعمدتهما
     * وبترتيب ASC في Room (D1 ينشئهما DESC — فرق موثَّق بلا أثر وظيفي)،
     * (د) أن DEFAULT في SQL فعّالة و`NOT NULL` يرفض، (هـ) أن الـDAO يقرأ
     * ويكتب فعلاً على الجدول المُنشأ بالترحيل مع ترتيب `approved_at DESC`.
     */
    @Test
    fun migrate76To77CreatesFinanceSnapshotsWithExactContract() {
        val name = "migration-76-77.db"
        createV70(name)
        // ترقية الملف إلى 76 بالترحيلات الحقيقية ثم إدخال صف قائم (بقاء البيانات).
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
                .callback(object : SupportSQLiteOpenHelper.Callback(76) {
                    override fun onCreate(db: SupportSQLiteDatabase) = Unit
                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                        DatabaseModule.MIGRATION_70_71.migrate(db)
                        DatabaseModule.MIGRATION_71_72.migrate(db)
                        DatabaseModule.MIGRATION_72_73.migrate(db)
                        DatabaseModule.MIGRATION_73_74.migrate(db)
                        DatabaseModule.MIGRATION_74_75.migrate(db)
                        DatabaseModule.MIGRATION_75_76.migrate(db)
                    }
                }).build()
        )
        helper.writableDatabase.execSQL(
            "INSERT INTO sync_quarantine (entity, recordKey, payload, reason) " +
                "VALUES ('rooms', 'uuid:pre-77', '{\"a\":1}', 'pre-77')"
        )
        helper.close()

        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_76_77).allowMainThreadQueries().build()
            try {
                // فتح القاعدة يشغّل تحقق Room الكامل للمخطط (كل عمود/فهرس/افتراضي)
                // — أي انحراف عن تعريف الكيان يُفشل هذا السطر.
                val db = room.openHelper.writableDatabase
                assertEquals(77, db.version)

                // (أ) الصف القائم قبل الترقية لم يُمس.
                db.query("SELECT reason FROM sync_quarantine WHERE recordKey = 'uuid:pre-77'").use {
                    assertTrue(it.moveToFirst())
                    assertEquals("pre-77", it.getString(0))
                }

                // (ب) عقد الأعمدة: الاسم → (type, notNull, dflt_value).
                val expected = mapOf(
                    "id" to Triple("INTEGER", true, null),
                    "label" to Triple("TEXT", true, "''"),
                    "scenario_key" to Triple("TEXT", true, "'base'"),
                    "scenario_json" to Triple("TEXT", true, "'{}'"),
                    "model_start" to Triple("TEXT", true, null),
                    "model_end" to Triple("TEXT", true, null),
                    "opening_balance" to Triple("REAL", true, "0"),
                    "total_inflow" to Triple("REAL", true, "0"),
                    "total_outflow" to Triple("REAL", true, "0"),
                    "financing_need" to Triple("REAL", true, "0"),
                    "weeks_below_threshold" to Triple("INTEGER", true, "0"),
                    "forecast_json" to Triple("TEXT", true, null),
                    "approved_by" to Triple("TEXT", true, "''"),
                    "approved_at" to Triple("INTEGER", true, null)
                )
                val seen = mutableSetOf<String>()
                db.query("PRAGMA table_info(finance_snapshots)").use { cursor ->
                    while (cursor.moveToNext()) {
                        val column = cursor.getString(1)
                        seen += column
                        val spec = requireNotNull(expected[column]) { "عمود غير متوقع: $column" }
                        assertEquals("نوع مختلف: $column", spec.first, cursor.getString(2))
                        assertEquals("NOT NULL مختلف: $column", spec.second, cursor.getInt(3) == 1)
                        assertEquals("افتراضي مختلف: $column", spec.third, cursor.getString(4))
                    }
                }
                assertEquals("أعمدة ناقصة: ${expected.keys - seen}", expected.keys, seen)

                // (ج) الفهرسان بأعمدتهما — وASC مقصود في Room (@Index لا يقبل
                // ترتيباً) بينما D1 ينشئهما DESC؛ الفرق موثَّق وبلا أثر وظيفي.
                val indexes = mutableMapOf<String, MutableList<String>>()
                db.query("PRAGMA index_list(finance_snapshots)").use { cursor ->
                    while (cursor.moveToNext()) {
                        val indexName = cursor.getString(1)
                        if (cursor.getInt(2) != 0) continue // فهرس فريد لا نتوقعه هنا
                        indexes[indexName] = mutableListOf()
                    }
                }
                assertEquals(
                    setOf("idx_finance_snapshots_approved", "idx_finance_snapshots_scenario"),
                    indexes.keys
                )
                for (indexName in indexes.keys) {
                    db.query("PRAGMA index_info($indexName)").use { cursor ->
                        while (cursor.moveToNext()) indexes.getValue(indexName) += cursor.getString(2)
                    }
                    db.query("PRAGMA index_xinfo($indexName)").use { cursor ->
                        while (cursor.moveToNext()) {
                            if (cursor.getInt(5) == 0) continue // صفوف غير مفتاحية (aux)
                            assertEquals("يجب ASC: $indexName", 0, cursor.getInt(3))
                        }
                    }
                }
                assertEquals(listOf("approved_at"), indexes.getValue("idx_finance_snapshots_approved"))
                assertEquals(
                    listOf("scenario_key", "approved_at"),
                    indexes.getValue("idx_finance_snapshots_scenario")
                )

                // (د) الافتراضيون في SQL نفسها: إدراج خام بأعمدة الحوكمة
                // الإلزامية الأربعة فقط ⇒ بقية الأعمدة تأخذ DEFAULT من الجدول
                // (وإدراج الـDAO يمرّر كل الأعمدة بقيم كوتلن، فلا يختبر DEFAULT).
                db.execSQL(
                    "INSERT INTO finance_snapshots " +
                        "(model_start, model_end, forecast_json, approved_at) " +
                        "VALUES ('2026-W40', '2027-W01', '[]', 1760000000)"
                )
                // وقيد NOT NULL حقيقي: صف بلا model_start يُرفض.
                try {
                    db.execSQL(
                        "INSERT INTO finance_snapshots (model_end, forecast_json, approved_at) " +
                            "VALUES ('2027-W01', '[]', 1)"
                    )
                    throw AssertionError("قبلت القاعدة صفاً بلا model_start — قيد NOT NULL مفقود")
                } catch (expected: android.database.sqlite.SQLiteConstraintException) {
                    // متوقع: NOT NULL على model_start
                }

                // (هـ) مسار البيانات على الجدول المُنشأ بالترحيل: قراءة الصف الخام
                // بالافتراضيات، ثم كتابة الـDAO، ثم العدّ والترتيب والقراءة بالفهرس.
                runBlocking {
                    val dao = room.financeSnapshotsDao()
                    val raw = requireNotNull(dao.latest())
                    assertEquals(1L, raw.id)
                    assertEquals("", raw.label)
                    assertEquals("base", raw.scenarioKey)
                    assertEquals("{}", raw.scenarioJson)
                    assertEquals("", raw.approvedBy)
                    assertEquals(0.0, raw.openingBalance, 0.0)
                    assertEquals(0.0, raw.totalInflow, 0.0)
                    assertEquals(0.0, raw.totalOutflow, 0.0)
                    assertEquals(0.0, raw.financingNeed, 0.0)
                    assertEquals(0, raw.weeksBelowThreshold)
                    assertEquals("[]", raw.forecastJson)
                    assertEquals(1_760_000_000L, raw.approvedAt)

                    dao.upsert(
                        FinanceSnapshotEntity(
                            modelStart = "2027-W01",
                            modelEnd = "2027-W14",
                            forecastJson = "[]",
                            approvedAt = 1_770_000_000L
                        )
                    )
                    assertEquals(2, dao.count())
                    // approved_at DESC (الفهرس نفسه هو المسار في listByScenario).
                    assertEquals(1_770_000_000L, requireNotNull(dao.latest()).approvedAt)
                    assertEquals(2, dao.listByScenario("base", 10).size)
                    assertEquals("2026-W40", requireNotNull(dao.getById(1L)).modelStart)
                }
            } finally {
                room.close()
            }
        } finally {
            context.deleteDatabase(name)
        }
    }

    private fun createV70(name: String) {
        context.deleteDatabase(name)
        val stream = requireNotNull(javaClass.classLoader!!.getResourceAsStream(
            "com.marina.marina.data.local.AppDatabase/70.json"
        ))
        val schema = stream.bufferedReader().use { JsonParser.parseReader(it).asJsonObject }
            .getAsJsonObject("database")
        val file = context.getDatabasePath(name)
        file.parentFile!!.mkdirs()
        SQLiteDatabase.openOrCreateDatabase(file, null).use { db ->
            schema.getAsJsonArray("entities").forEach { value ->
                val entity = value.asJsonObject
                val table = entity["tableName"].asString
                fun expand(sql: String) = sql.replace("\${TABLE_NAME}", table)
                db.execSQL(expand(entity["createSql"].asString))
                entity.getAsJsonArray("indices").forEach { db.execSQL(expand(it.asJsonObject["createSql"].asString)) }
                if (table in setOf("employees", "expenses", "salary_withdrawals", "outbox")) {
                    val values = ContentValues()
                    entity.getAsJsonArray("fields").forEach { fieldValue ->
                        val field = fieldValue.asJsonObject
                        val column = field["columnName"].asString
                        if (column != "id" && field["notNull"].asBoolean) {
                            if (field["affinity"].asString == "TEXT") values.put(column, "")
                            else values.put(column, 0L)
                        }
                    }
                    values.put("local_uuid", "$table-preserved")
                    if (table == "expenses" || table == "salary_withdrawals") values.put("amount", 12345.0)
                    if (table == "outbox") values.put("payload", "{\"not_delivered\":true}")
                    db.insertOrThrow(table, null, values)
                }
            }
            schema.getAsJsonArray("setupQueries").forEach { db.execSQL(it.asString) }
            db.version = 70
        }
    }

    @Test
    fun migrate70To73PreservesMoneyAndUndeliveredOutboxAndValidatesRoomSchema() {
        val name = "migration-70-72.db"
        createV70(name)
        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_70_71, DatabaseModule.MIGRATION_71_72, DatabaseModule.MIGRATION_72_73, DatabaseModule.MIGRATION_73_74, DatabaseModule.MIGRATION_74_75, DatabaseModule.MIGRATION_75_76, DatabaseModule.MIGRATION_76_77)
                .allowMainThreadQueries().build()
            try {
                    // Opening invokes Room's generated full schema validation, not just column checks.
                    val db = room.openHelper.writableDatabase
                    assertEquals(77, db.version)
                    // Parity unification: 76→77 adds idempotency_log TTL index + finance_snapshots table.
                    for (table in listOf("expenses", "salary_withdrawals")) {
                        db.query("SELECT amount FROM $table").use { cursor ->
                            assertTrue(cursor.moveToFirst())
                            assertEquals(12345.0, cursor.getDouble(0), 0.0)
                        }
                    }
                    db.query("SELECT payload FROM outbox").use {
                        assertTrue(it.moveToFirst())
                        assertEquals("{\"not_delivered\":true}", it.getString(0))
                    }
                    db.query("SELECT expense_uuid FROM salary_withdrawals").use {
                        assertTrue(it.moveToFirst())
                        assertTrue(it.isNull(0)) // No guessed historical relationship.
                    }
                    db.query("SELECT COUNT(*) FROM sync_quarantine").use {
                        assertTrue(it.moveToFirst())
                        assertEquals(0, it.getInt(0))
                    }
                    db.query("SELECT COUNT(*) FROM pending_sync_links").use {
                        assertTrue(it.moveToFirst())
                        assertEquals(0, it.getInt(0))
                    }
            } finally { room.close() }
        } finally { context.deleteDatabase(name) }
    }

    @Test
    fun migrate71To73PreservesExistingUuidColumns() {
        val name = "migration-71-72.db"
        createV70(name)
        // Use the actual 70->71 migration to produce a version-71 file.
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
                .callback(object : SupportSQLiteOpenHelper.Callback(71) {
                    override fun onCreate(db: SupportSQLiteDatabase) = Unit
                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                        DatabaseModule.MIGRATION_70_71.migrate(db)
                    }
                }).build()
        )
        helper.writableDatabase
        helper.close()
        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_71_72, DatabaseModule.MIGRATION_72_73, DatabaseModule.MIGRATION_73_74, DatabaseModule.MIGRATION_74_75, DatabaseModule.MIGRATION_75_76, DatabaseModule.MIGRATION_76_77).allowMainThreadQueries().build()
            try { assertEquals(77, room.openHelper.writableDatabase.version) }
            finally { room.close() }
        } finally { context.deleteDatabase(name) }
    }

    @Test
    fun migrate72To73PreservesPendingLinksAndAddsQuarantine() {
        val name = "migration-72-73.db"
        createV70(name)
        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context).name(name)
                .callback(object : SupportSQLiteOpenHelper.Callback(72) {
                    override fun onCreate(db: SupportSQLiteDatabase) = Unit
                    override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                        DatabaseModule.MIGRATION_70_71.migrate(db)
                        DatabaseModule.MIGRATION_71_72.migrate(db)
                    }
                }).build()
        )
        helper.writableDatabase.execSQL("INSERT INTO pending_sync_links VALUES ('salary_payments', 'kept', '{}')")
        helper.close()
        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_72_73, DatabaseModule.MIGRATION_73_74, DatabaseModule.MIGRATION_74_75, DatabaseModule.MIGRATION_75_76, DatabaseModule.MIGRATION_76_77).allowMainThreadQueries().build()
            try {
                val db = room.openHelper.writableDatabase
                assertEquals(77, db.version)
                // Parity unification: 76→77 adds idempotency_log TTL index + finance_snapshots table.
                db.query("SELECT localUuid FROM pending_sync_links").use {
                    assertTrue(it.moveToFirst())
                    assertEquals("kept", it.getString(0))
                }
                db.query("SELECT COUNT(*) FROM sync_quarantine").use {
                    assertTrue(it.moveToFirst())
                    assertEquals(0, it.getInt(0))
                }
            } finally { room.close() }
        } finally { context.deleteDatabase(name) }
    }

    @Test
    fun unsupportedVersionFailsWithoutDeletingFinancialRows() {
        val name = "migration-unsupported.db"
        createV70(name)
        SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READWRITE).use {
            it.version = 69
        }
        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_70_71, DatabaseModule.MIGRATION_71_72, DatabaseModule.MIGRATION_72_73, DatabaseModule.MIGRATION_73_74, DatabaseModule.MIGRATION_74_75, DatabaseModule.MIGRATION_75_76, DatabaseModule.MIGRATION_76_77)
                .allowMainThreadQueries().build()
            try { assertTrue(runCatching { room.openHelper.writableDatabase }.isFailure) }
            finally { room.close() }
            SQLiteDatabase.openDatabase(context.getDatabasePath(name).path, null, SQLiteDatabase.OPEN_READONLY).use {
                it.rawQuery("SELECT amount FROM expenses", null).use { cursor ->
                    assertTrue(cursor.moveToFirst())
                    assertEquals(12345.0, cursor.getDouble(0), 0.0)
                }
            }
        } finally { context.deleteDatabase(name) }
    }
}
