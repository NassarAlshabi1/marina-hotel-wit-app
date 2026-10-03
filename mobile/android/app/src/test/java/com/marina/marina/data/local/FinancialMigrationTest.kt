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
import com.marina.marina.di.DatabaseModule
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class FinancialMigrationTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

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
                .addMigrations(DatabaseModule.MIGRATION_70_71, DatabaseModule.MIGRATION_71_72, DatabaseModule.MIGRATION_72_73)
                .allowMainThreadQueries().build()
            try {
                    // Opening invokes Room's generated full schema validation, not just column checks.
                    val db = room.openHelper.writableDatabase
                    assertEquals(73, db.version)
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
                .addMigrations(DatabaseModule.MIGRATION_71_72, DatabaseModule.MIGRATION_72_73).allowMainThreadQueries().build()
            try { assertEquals(73, room.openHelper.writableDatabase.version) }
            finally { room.close() }
        } finally { context.deleteDatabase(name) }
    }

    @Test
    fun migrate72To73PreservesOriginalAndAddsNullableAuditLinks() {
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
        helper.writableDatabase
        helper.close()
        try {
            val room = Room.databaseBuilder(context, AppDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_72_73).allowMainThreadQueries().build()
            try {
                val db = room.openHelper.writableDatabase
                assertEquals(73, db.version)
                for (table in listOf("expenses", "salary_withdrawals")) {
                    db.query("SELECT amount, reversal_of_uuid, reversal_reason, reversal_actor FROM $table").use {
                        assertTrue(it.moveToFirst())
                        assertEquals(12345.0, it.getDouble(0), 0.0)
                        assertTrue(it.isNull(1) && it.isNull(2) && it.isNull(3))
                    }
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
                .addMigrations(DatabaseModule.MIGRATION_70_71, DatabaseModule.MIGRATION_71_72, DatabaseModule.MIGRATION_72_73)
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
