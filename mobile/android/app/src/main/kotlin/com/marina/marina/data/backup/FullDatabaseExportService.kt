package com.marina.marina.data.backup

import android.content.Context
import android.net.Uri
import com.marina.marina.data.local.AppDatabase
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import javax.inject.Inject
import javax.inject.Singleton

/**
 * تصدير قاعدة البيانات كاملة إلى ملف Excel — نظير ExportService.
 * exportFullDatabase في فرع Flutter:
 *
 *  • ورقة لكل جدول مستخدم (اسم الورقة من اسم الجدول بعد التنظيف).
 *  • الصف الأول: أسماء الأعمدة، ثم الصفوف.
 *  • RTL: sheetView rightToLeft="1" (نظير sheet.isRTL = true).
 *  • اسم الملف: marina_hotel_database_yyyy-MM-dd_HHmm.xlsx (نفس النمط).
 *  • الملف يُكتب بصيغة OOXML صالحة (xlsx = حاوية zip) بلا مكتبات خارجية:
 *    خلايا نصية inline وعددية numeric — تتفتح في Excel/Sheets.
 */
@Singleton
class FullDatabaseExportService @Inject constructor(
    @ApplicationContext private val context: Context,
    private val db: AppDatabase
) {
    companion object {
        /** سقف صفوف الورقة في Excel (أقصى صف 1,048,576). */
        private const val MAX_ROWS = 1000000
        private const val MAX_COLS = 16384
    }

    /**
     * تصدير كل جداول المستخدم إلى xlsx داخل مجلد النسخ. يعيد الملف
     * الناتج (نظير Future<File> exportFullDatabase).
     */
    suspend fun exportFullDatabase(): File = withContext(Dispatchers.IO) {
        val backupServiceDir = File(
            context.getExternalFilesDir(null) ?: context.filesDir,
            LocalBackupService.BACKUP_FOLDER_NAME
        ).apply { if (!exists()) mkdirs() }

        val stamp = SimpleDateFormat("yyyy-MM-dd_HHmm", Locale.US).format(Date())
        val fileName = "marina_hotel_database_$stamp.xlsx"
        val outFile = File(backupServiceDir, fileName)

        val sq = db.openHelper.writableDatabase
        val tables = mutableListOf<String>()
        sq.query(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' " +
                "AND name NOT LIKE 'room_%' AND name != 'android_metadata'"
        ).use { c ->
            while (c.moveToNext()) tables.add(c.getString(0))
        }
        val userTables = tables.filter {
            it !in setOf(
                "outbox", "sync_remote_meta", "sync_log", "sync_queue",
                "sync_conflicts", "ancestor_cache", "app_sessions",
                "integrity_violations", "auto_fix_runs", "restore_fix_log"
            )
        }.sorted()

        ZipOutputStream(FileOutputStream(outFile)).use { zip ->
            writeStaticParts(zip, userTables.size)
            userTables.forEachIndexed { idx, table ->
                val sheetXml = buildSheetXml(table)
                zip.putNextEntry(ZipEntry("xl/worksheets/sheet${idx + 1}.xml"))
                zip.write(sheetXml.toByteArray(Charsets.UTF_8))
                zip.closeEntry()
            }

            // workbook.xml مع كل الأوراق
            val sheetsSb = StringBuilder()
            userTables.forEachIndexed { idx, table ->
                val name = sanitizeSheetName(table)
                sheetsSb.append(
                    "<sheet name=\"").append(escapeXml(name)).append("\" sheetId=\"")
                    .append(idx + 1).append("\" r:id=\"rId").append(idx + 1).append("\"/>"
                )
            }
            val workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>$sheetsSb</sheets></workbook>"""
            zip.putNextEntry(ZipEntry("xl/workbook.xml"))
            zip.write(workbook.toByteArray(Charsets.UTF_8))
            zip.closeEntry()

            // workbook rels
            val relsSb = StringBuilder()
            userTables.forEachIndexed { idx, _ ->
                relsSb.append(
                    "<Relationship Id=\"rId").append(idx + 1)
                    .append("\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet")
                    .append(idx + 1).append(".xml\"/>"
                )
            }
            val wbRels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$relsSb</Relationships>"""
            zip.putNextEntry(ZipEntry("xl/_rels/workbook.xml.rels"))
            zip.write(wbRels.toByteArray(Charsets.UTF_8))
            zip.closeEntry()
        }

        outFile
    }

    /** مشاركة ملف التصدير — نظير ExportService.shareFile مع subject. */
    suspend fun shareFile(file: File, subject: String) = withContext(Dispatchers.IO) {
        val cacheDir = File(context.cacheDir, "backups").apply { mkdirs() }
        val target = File(cacheDir, file.name)
        file.copyTo(target, overwrite = true)
        val uri: Uri = androidx.core.content.FileProvider.getUriForFile(
            context, context.packageName + ".fileprovider", target
        )
        val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
            type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            putExtra(android.content.Intent.EXTRA_STREAM, uri)
            putExtra(android.content.Intent.EXTRA_SUBJECT, subject)
            addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        intent.clipData = android.content.ClipData.newRawUri("export", uri)
        context.startActivity(
            android.content.Intent.createChooser(intent, subject)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    // ─── OOXML builders ──────────────────────────────────────────

    private fun writeStaticParts(zip: ZipOutputStream, sheetCount: Int) {
        val sheetOverrides = (1..sheetCount).joinToString("") {
            "<Override PartName=\"/xl/worksheets/sheet$it.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        zip.putNextEntry(ZipEntry("[Content_Types].xml"))
        zip.write(
            """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>$sheetOverrides
</Types>""".toByteArray(Charsets.UTF_8)
        )
        zip.closeEntry()

        zip.putNextEntry(ZipEntry("_rels/.rels"))
        zip.write(
            """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>""".toByteArray(Charsets.UTF_8)
        )
        zip.closeEntry()
    }

    /** بناء ورقة واحدة: صف العناوين + كل الصفوف (inline strings/numbers). */
    private fun buildSheetXml(table: String): String {
        val sq = db.openHelper.writableDatabase
        val sb = StringBuilder()
        sb.append(
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" +
                "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">" +
                "<sheetViews><sheetView rightToLeft=\"1\" workbookViewId=\"0\"/></sheetViews>" +
                "<sheetData>"
        )
        val safe = table.replace("\"", "\"\"")
        sq.query("SELECT * FROM \"$safe\" LIMIT $MAX_ROWS").use { c ->
            // صف العناوين
            sb.append("<row r=\"1\">")
            for (i in 0 until c.columnCount.coerceAtMost(MAX_COLS)) {
                val col = colName(i)
                sb.append("<c r=\"").append(col).append("1\" t=\"inlineStr\"><is><t>")
                    .append(escapeXml(c.getColumnName(i))).append("</t></is></c>")
            }
            sb.append("</row>")
            // الصفوف
            var rowIdx = 2
            while (c.moveToNext()) {
                sb.append("<row r=\"").append(rowIdx).append("\">")
                for (i in 0 until c.columnCount.coerceAtMost(MAX_COLS)) {
                    val col = colName(i)
                    when (c.getType(i)) {
                        android.database.Cursor.FIELD_TYPE_NULL -> {}
                        android.database.Cursor.FIELD_TYPE_INTEGER ->
                            sb.append("<c r=\"").append(col).append(rowIdx).append("\"><v>")
                                .append(c.getLong(i)).append("</v></c>")
                        android.database.Cursor.FIELD_TYPE_FLOAT ->
                            sb.append("<c r=\"").append(col).append(rowIdx).append("\"><v>")
                                .append(c.getDouble(i)).append("</v></c>")
                        android.database.Cursor.FIELD_TYPE_BLOB -> {}
                        else -> sb.append("<c r=\"").append(col).append(rowIdx)
                            .append("\" t=\"inlineStr\"><is><t>")
                            .append(escapeXml(c.getString(i) ?: "")).append("</t></is></c>")
                    }
                }
                sb.append("</row>")
                rowIdx++
            }
        }
        sb.append("</sheetData></worksheet>")
        return sb.toString()
    }

    /** فهرس عمود Excel: 0→A, 1→B, … 25→Z, 26→AA … */
    private fun colName(index: Int): String {
        var n = index
        val sb = StringBuilder()
        while (n >= 0) {
            sb.insert(0, ('A' + n % 26))
            n = n / 26 - 1
        }
        return sb.toString()
    }

    /** نظير _sanitizeSheetName: بلا أحرف ممنوعة وبطول ≤ 31. */
    private fun sanitizeSheetName(name: String): String {
        val cleaned = name.replace(Regex("[\\[\\]\\*:/?\\\\]"), "_")
        return cleaned.take(31)
    }

    private fun escapeXml(s: String): String = s
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
}
