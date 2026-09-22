package com.marina.marina.util

import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale

/**
 * Lightweight RTL Arabic PDF table exporter — the Kotlin counterpart of the
 * Flutter `ReportPdfBuilder` + `EnhancedPdfUtils` (hotel header banner,
 * period line, professional tables, stat boxes).
 *
 * Android's `Canvas.drawText` shapes Arabic correctly with the default
 * typeface; columns are laid out right-to-left.
 */
object PdfExporter {

    private const val PAGE_WIDTH = 595 // A4 @ 72dpi
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 28f
    private const val BOTTOM = PAGE_HEIGHT - MARGIN - 22f
    private const val HEADER_BLUE = 0xFF242476.toInt()
    private const val GOLD = 0xFFFABA3E.toInt()
    private const val LIGHT_BG = 0xFFF2F2F8.toInt()
    private const val TEXT_DARK = 0xFF0A0E2F.toInt()
    private const val BORDER = 0xFFD3D3E4.toInt()

    data class PdfTable(
        val title: String,
        val headers: List<String>,
        val rows: List<List<String>>,
        val totalRow: List<String>? = null,
        /** Relative weights, left-to-right in [headers] order. */
        val columnWeights: List<Float>? = null
    )

    /** Mutable page cursor shared by all drawing helpers. */
    private class PageCursor(val doc: PdfDocument) {
        var canvas: Canvas? = null
        var page: PdfDocument.Page? = null
        var y = 0f
        var pageNo = 0

        fun newPage() {
            finishPage()
            pageNo++
            page = doc.startPage(
                PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNo).create()
            )
            canvas = page!!.canvas
            y = MARGIN
        }

        fun finishPage() {
            page?.let {
                val label = "صفحة $pageNo"
                val p = paint(9f, false, Color.GRAY)
                canvas?.drawText(label, (PAGE_WIDTH - p.measureText(label)) / 2f, PAGE_HEIGHT - 12f, p)
                doc.finishPage(it)
            }
            page = null
            canvas = null
        }
    }

    private fun paint(size: Float, bold: Boolean, color: Int): Paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = size
        this.color = color
        typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
    }

    /**
     * Builds a paginated RTL PDF with the hotel banner, a period line, info
     * rows, stat boxes and auto-paginating tables. Returns the cache file.
     */
    fun buildReport(
        context: Context,
        reportTitle: String,
        periodText: String?,
        infoRows: List<Pair<String, String>>,
        stats: List<Triple<String, String, Int>>,
        tables: List<PdfTable>,
        fileName: String
    ): File {
        val doc = PdfDocument()
        val cur = PageCursor(doc)
        cur.newPage()

        // Banner ----------------------------------------------------------------
        val c = cur.canvas!!
        c.drawRect(RectF(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y + 34f), fill(HEADER_BLUE))
        c.drawRect(RectF(MARGIN, cur.y + 30f, PAGE_WIDTH - MARGIN, cur.y + 34f), fill(GOLD))
        drawRight(cur, "فندق مارينا بلازا", cur.y + 16f, paint(13f, true, Color.WHITE))
        cur.y += 46f
        drawRight(cur, reportTitle, cur.y, paint(16f, true, TEXT_DARK))
        cur.y += 18f
        periodText?.let {
            drawRight(cur, it, cur.y, paint(10f, false, TEXT_DARK))
            cur.y += 15f
        }
        val stamp = SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.US).format(System.currentTimeMillis())
        drawRight(cur, "تاريخ الإنشاء: $stamp", cur.y, paint(10f, false, Color.GRAY))
        cur.y += 22f

        // Info rows --------------------------------------------------------------
        infoRows.forEach { (label, value) ->
            ensureSpace(cur, 16f)
            drawRight(cur, "$label: $value", cur.y, paint(10f, false, TEXT_DARK))
            cur.y += 15f
        }
        if (infoRows.isNotEmpty()) cur.y += 6f

        // Stat boxes ---------------------------------------------------------------
        if (stats.isNotEmpty()) {
            ensureSpace(cur, 60f)
            val boxW = (PAGE_WIDTH - 2 * MARGIN - (stats.size - 1) * 8f) / stats.size
            stats.forEachIndexed { i, (label, value, color) ->
                val left = MARGIN + i * (boxW + 8f)
                cur.canvas!!.drawRect(RectF(left, cur.y, left + boxW, cur.y + 52f), fill(LIGHT_BG))
                cur.canvas!!.drawRect(RectF(left, cur.y, left + boxW, cur.y + 3f), fill(color))
                val valuePaint = paint(13f, true, color)
                cur.canvas!!.drawText(value, left + boxW - 8f - valuePaint.measureText(value), cur.y + 26f, valuePaint)
                cur.canvas!!.drawText(label, left + boxW - 8f - paint(10f, false, TEXT_DARK).measureText(label), cur.y + 42f, paint(10f, false, TEXT_DARK))
            }
            cur.y += 64f
        }

        // Tables --------------------------------------------------------------------
        tables.forEach { table -> drawTable(cur, table) }

        cur.finishPage()
        val file = File(context.cacheDir, fileName)
        file.outputStream().use { doc.writeTo(it) }
        doc.close()
        return file
    }

    // -------------------------------------------------------------------------

    private fun fill(color: Int): Paint = Paint().apply { style = Paint.Style.FILL; this.color = color }

    private fun ensureSpace(cur: PageCursor, needed: Float) {
        if (cur.y + needed > BOTTOM) cur.newPage()
    }

    private fun drawRight(cur: PageCursor, text: String, top: Float, p: Paint, right: Float = PAGE_WIDTH - MARGIN) {
        cur.canvas?.drawText(text, right - p.measureText(text), top, p)
    }

    private fun drawTable(cur: PageCursor, table: PdfTable) {
        ensureSpace(cur, 60f)
        drawRight(cur, table.title, cur.y, paint(12f, true, TEXT_DARK))
        cur.y += 16f

        val weights = table.columnWeights ?: List(table.headers.size) { 1f }
        val total = weights.sum()
        val tableW = PAGE_WIDTH - 2 * MARGIN
        // Column widths in header order (left→right); RTL x-positions start at right.
        val colW = weights.map { it / total * tableW }
        val colRight = FloatArray(colW.size)
        var x = PAGE_WIDTH - MARGIN
        for (i in colW.indices) {
            colRight[i] = x
            x -= colW[i]
        }

        val allRows = table.rows + listOfNotNull(table.totalRow)

        var rowIndex = 0
        while (rowIndex <= allRows.size) {
            ensureSpace(cur, 46f)
            val c = cur.canvas!!

            // Header row (repeated on every page).
            c.drawRect(RectF(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y + 22f), fill(HEADER_BLUE))
            val hp = paint(9.5f, true, Color.WHITE)
            table.headers.forEachIndexed { i, h ->
                c.drawText(h, colRight[i] - colW[i] / 2f - hp.measureText(h) / 2f, cur.y + 15f, hp)
            }
            cur.y += 22f

            var drawn = 0
            while (rowIndex < allRows.size && cur.y + 22f <= BOTTOM) {
                val row = allRows[rowIndex]
                val isTotal = table.totalRow != null && rowIndex == allRows.size - 1
                if (rowIndex % 2 == 1 && !isTotal) {
                    c.drawRect(RectF(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y + 20f), fill(LIGHT_BG))
                }
                row.forEachIndexed { i, cell ->
                    val p = if (isTotal) paint(10f, true, HEADER_BLUE) else paint(9.5f, false, TEXT_DARK)
                    c.drawText(cell, colRight[i] - colW[i] / 2f - p.measureText(cell) / 2f, cur.y + 14f, p)
                }
                c.drawLine(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y, stroke())
                cur.y += 20f
                rowIndex++
                drawn++
            }
            // Table border around what we drew on this page.
            c.drawRect(
                RectF(MARGIN, cur.y - 22f - drawn * 20f, PAGE_WIDTH - MARGIN, cur.y),
                stroke()
            )
            if (rowIndex >= allRows.size) break
            // Continue on a fresh page.
            cur.newPage()
        }
        cur.y += 12f
    }

    private fun stroke(): Paint = Paint().apply {
        style = Paint.Style.STROKE; color = BORDER; strokeWidth = 0.8f
    }

    // -------------------------------------------------------------------------

    /** Shares a PDF file through the OS share sheet (Dart `Printing.sharePdf`). */
    fun sharePdf(context: Context, file: File, title: String) {
        val uri: Uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, title))
    }

    /** Shares plain text (CSV / WhatsApp) through the OS share sheet. */
    fun shareText(context: Context, text: String, title: String, mime: String = "text/plain") {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mime
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra(Intent.EXTRA_SUBJECT, title)
        }
        context.startActivity(Intent.createChooser(intent, title))
    }

    /** Dart `_sendStatementViaWhatsAppText` — opens wa.me with encoded text. */
    fun openWhatsAppText(context: Context, phoneE164: String?, message: String) {
        val encoded = Uri.encode(message)
        val url = if (phoneE164.isNullOrBlank()) {
            "https://wa.me/?text=$encoded"
        } else {
            "https://wa.me/$phoneE164?text=$encoded"
        }
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (_: Exception) {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("whatsapp://send?text=$encoded")))
        }
    }

    /** Report file name — Dart `generateFileName` contract. */
    fun generateFileName(title: String): String {
        val cleaned = title.trim().replace(Regex("\\s+"), "-")
        val stamp = SimpleDateFormat("yyyyMMdd_HHmm", Locale.US).format(System.currentTimeMillis())
        return "$cleaned-$stamp.pdf"
    }
}
