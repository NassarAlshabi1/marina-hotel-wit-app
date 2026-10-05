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
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import androidx.core.content.FileProvider
import androidx.core.content.res.ResourcesCompat
import com.a.a.R
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale

/** Native, vector A4/RTL counterpart of the reference ReportPdfBuilder. */
object PdfExporter {
    private const val PAGE_WIDTH = 595
    private const val PAGE_HEIGHT = 842
    private const val MARGIN = 32f
    private const val TOP = 42f
    private const val BOTTOM = PAGE_HEIGHT - 48f
    internal const val PRIMARY = 0xFFB46B00.toInt()
    private const val TEXT_DARK = 0xFF262626.toInt()
    private const val MUTED = 0xFF6B6B73.toInt()
    private const val STRIPE = 0xFFF4F4F6.toInt()
    private const val CARD = 0xFFFAFAFB.toInt()
    private const val BORDER = 0xFFD1D1D9.toInt()
    private const val WIDTH = PAGE_WIDTH - 2 * MARGIN

    data class PdfTable(
        val title: String,
        /** Logical order: first column is on the right. */
        val headers: List<String>,
        val rows: List<List<String>>,
        val totalRow: List<String>? = null,
        val columnWeights: List<Float>? = null
    )

    private class Fonts(context: Context) {
        val regular: Typeface = requireNotNull(ResourcesCompat.getFont(context, R.font.noto_naskh_arabic_regular))
        val bold: Typeface = requireNotNull(ResourcesCompat.getFont(context, R.font.noto_naskh_arabic_bold))
        fun paint(size: Float, bold: Boolean = false, color: Int = TEXT_DARK) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            this.color = color
            typeface = if (bold) this@Fonts.bold else regular
        }
    }

    // Measurement and drawing use the same layout. No bitmap or retained per-page
    // layouts; the first pass only counts pages for the reference "X of Y" footer.
    private class PageCursor(
        val doc: PdfDocument?, val fonts: Fonts, val stamp: String, val totalPages: Int = 0
    ) {
        var page: PdfDocument.Page? = null
        var y = TOP
        var pageNo = 0
        val canvas: Canvas? get() = page?.canvas
        fun newPage() {
            finishPage()
            pageNo++
            page = doc?.startPage(PdfDocument.PageInfo.Builder(PAGE_WIDTH, PAGE_HEIGHT, pageNo).create())
            y = TOP
        }
        fun finishPage() {
            page?.let { current ->
                canvas?.drawLine(MARGIN, BOTTOM + 8, PAGE_WIDTH - MARGIN, BOTTOM + 8, stroke())
                val labels = listOf("تاريخ الإنشاء: $stamp", "وثيقة داخلية", "صفحة $pageNo من $totalPages")
                labels.forEachIndexed { index, text ->
                    drawLayout(canvas, layout(text, fonts.paint(8f, color = MUTED), WIDTH / 3,
                        Layout.Alignment.ALIGN_CENTER), MARGIN + index * WIDTH / 3, BOTTOM + 12)
                }
                doc!!.finishPage(current)
            }
            page = null
        }
        fun ensureSpace(height: Float) {
            require(height <= BOTTOM - TOP) { "محتوى PDF أكبر من مساحة الصفحة" }
            if (y + height > BOTTOM) newPage()
        }
    }

    internal fun layout(
        text: String, paint: TextPaint, width: Float,
        alignment: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL, maxLines: Int = Int.MAX_VALUE
    ): StaticLayout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width.toInt().coerceAtLeast(1))
        .setTextDirection(TextDirectionHeuristics.RTL)
        .setAlignment(alignment)
        .setIncludePad(false)
        .setMaxLines(maxLines)
        .build()

    private fun drawLayout(canvas: Canvas?, text: StaticLayout, left: Float, top: Float) {
        if (canvas == null) return
        val saved = canvas.save()
        try {
            canvas.translate(left, top)
            canvas.clipRect(0, 0, text.width, text.height)
            text.draw(canvas)
        } finally {
            canvas.restoreToCount(saved)
        }
    }

    fun buildReport(
        context: Context,
        reportTitle: String,
        periodText: String?,
        infoRows: List<Pair<String, String>>,
        stats: List<Triple<String, String, Int>>,
        tables: List<PdfTable>,
        fileName: String,
        compactHeader: Boolean = false,
        statsAfterTables: Boolean = false
    ): File {
        val fonts = Fonts(context)
        val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).format(System.currentTimeMillis())
        fun render(cur: PageCursor) {
            cur.newPage()
            drawHeader(cur, reportTitle, periodText, compactHeader)
            infoRows.forEach { (label, value) ->
                val text = layout("$label: $value", fonts.paint(11f), WIDTH - 20)
                cur.ensureSpace(text.height + 12f)
                cur.canvas?.drawRect(RectF(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y + text.height + 12), fill(CARD))
                drawLayout(cur.canvas, text, MARGIN + 10, cur.y + 6)
                cur.y += text.height + 12
            }
            cur.y += 12
            if (!statsAfterTables) drawStats(cur, stats)
            tables.forEach { drawTable(cur, it) }
            if (statsAfterTables) drawStats(cur, stats)
            cur.finishPage()
        }
        val measurement = PageCursor(null, fonts, stamp)
        render(measurement)
        val file = File(context.cacheDir, fileName)
        val doc = PdfDocument()
        val cursor = PageCursor(doc, fonts, stamp, measurement.pageNo)
        try {
            render(cursor)
            file.outputStream().use { doc.writeTo(it) }
        } finally {
            cursor.finishPage()
            doc.close()
        }
        return file
    }

    private fun drawHeader(cur: PageCursor, title: String, period: String?, compact: Boolean) {
        val fonts = cur.fonts
        if (compact) {
            val half = (WIDTH - 36) / 2
            val rightTitle = layout(title, fonts.paint(11f, true, Color.WHITE), half)
            val rightPeriod = layout(period.orEmpty(), fonts.paint(7.5f, color = Color.WHITE), half)
            val leftTitle = layout("فندق مارينا بلازا", fonts.paint(11f, true, Color.WHITE), half)
            val leftStamp = layout("تاريخ الإنشاء: ${cur.stamp}", fonts.paint(7.5f, color = Color.WHITE), half)
            val height = maxOf(rightTitle.height + rightPeriod.height, leftTitle.height + leftStamp.height) + 14f
            cur.canvas?.drawRect(RectF(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y + height), fill(PRIMARY))
            drawLayout(cur.canvas, rightTitle, PAGE_WIDTH - MARGIN - 12 - half, cur.y + 6)
            drawLayout(cur.canvas, rightPeriod, PAGE_WIDTH - MARGIN - 12 - half, cur.y + 8 + rightTitle.height)
            drawLayout(cur.canvas, leftTitle, MARGIN + 12, cur.y + 6)
            drawLayout(cur.canvas, leftStamp, MARGIN + 12, cur.y + 8 + leftTitle.height)
            cur.y += height + 16
        } else {
            val lines = listOf(
                layout("فندق مارينا بلازا", fonts.paint(22f, true, Color.WHITE), WIDTH - 48, Layout.Alignment.ALIGN_CENTER),
                layout(title, fonts.paint(20f, true, Color.WHITE), WIDTH - 48, Layout.Alignment.ALIGN_CENTER),
                layout(period.orEmpty(), fonts.paint(12f, color = Color.WHITE), WIDTH - 48, Layout.Alignment.ALIGN_CENTER)
            )
            val height = lines.sumOf { it.height } + 64f
            cur.ensureSpace(height)
            cur.canvas?.drawRect(RectF(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y + height), fill(PRIMARY))
            var y = cur.y + 24
            lines.forEach { drawLayout(cur.canvas, it, MARGIN + 24, y); y += it.height + 8 }
            cur.y += height + 16
        }
    }

    private fun drawStats(cur: PageCursor, stats: List<Triple<String, String, Int>>) {
        // Up to four cards per row; do not shrink every card to unreadable widths.
        stats.chunked(4).forEach { group ->
            val width = (WIDTH - (group.size - 1) * 8) / group.size
            val layouts = group.map { (label, value, color) ->
                layout(label, cur.fonts.paint(11f), width - 20, Layout.Alignment.ALIGN_CENTER) to
                    layout(value, cur.fonts.paint(16f, true, color), width - 20, Layout.Alignment.ALIGN_CENTER)
            }
            val height = layouts.maxOf { it.first.height + it.second.height } + 24f
            cur.ensureSpace(height)
            group.forEachIndexed { i, stat ->
                val left = PAGE_WIDTH - MARGIN - width - i * (width + 8)
                val bounds = RectF(left, cur.y, left + width, cur.y + height)
                cur.canvas?.drawRoundRect(bounds, 4f, 4f, fill(CARD))
                cur.canvas?.drawRoundRect(bounds, 4f, 4f, stroke(stat.third, 0.7f))
                val (label, value) = layouts[i]
                drawLayout(cur.canvas, label, left + 10, cur.y + 10)
                drawLayout(cur.canvas, value, left + 10, cur.y + 14 + label.height)
            }
            cur.y += height + 12
        }
    }

    private fun drawTable(cur: PageCursor, table: PdfTable) {
        require(table.headers.isNotEmpty())
        val weights = table.columnWeights ?: List(table.headers.size) { 1f }
        require(weights.size == table.headers.size && weights.all { it.isFinite() && it > 0 })
        require(weights.sum().isFinite())
        require(table.rows.all { it.size == table.headers.size } &&
            (table.totalRow == null || table.totalRow.size == table.headers.size))
        val widths = weights.map { it / weights.sum() * WIDTH }
        fun cells(values: List<String>, header: Boolean) = values.mapIndexed { i, value ->
            // Reference buildProfessionalTable: 11pt header, 12pt bold cells, two lines.
            layout(value, cur.fonts.paint(if (header) 11f else 12f, true,
                if (header) Color.WHITE else TEXT_DARK), widths[i] - 8, maxLines = 2)
        }
        val headers = cells(table.headers, true)
        fun height(cells: List<StaticLayout>, padding: Float) = cells.maxOf { it.height } + padding * 2
        val headerHeight = height(headers, 6f)
        fun row(cells: List<StaticLayout>, rowHeight: Float, color: Int, padding: Float) {
            cur.canvas?.drawRect(RectF(MARGIN, cur.y, PAGE_WIDTH - MARGIN, cur.y + rowHeight), fill(color))
            var right = PAGE_WIDTH - MARGIN
            cells.forEachIndexed { i, cell ->
                drawLayout(cur.canvas, cell, right - widths[i] + 4, cur.y + padding)
                cur.canvas?.drawRect(RectF(right - widths[i], cur.y, right, cur.y + rowHeight), stroke())
                right -= widths[i]
            }
            cur.y += rowHeight
        }
        val title = layout(table.title, cur.fonts.paint(13f, true, PRIMARY), WIDTH)
        val first = table.rows.firstOrNull() ?: table.totalRow
        val firstHeight = first?.let { height(cells(it, false), 5f) } ?: 0f
        cur.ensureSpace(title.height + 8 + headerHeight + firstHeight)
        drawLayout(cur.canvas, title, MARGIN, cur.y)
        cur.y += title.height + 8
        row(headers, headerHeight, PRIMARY, 6f)
        val count = table.rows.size + if (table.totalRow != null) 1 else 0
        for (index in 0 until count) {
            val values = if (index < table.rows.size) table.rows[index] else table.totalRow!!
            val text = cells(values, false)
            val rowHeight = height(text, 5f)
            require(rowHeight + headerHeight <= BOTTOM - TOP)
            if (cur.y + rowHeight > BOTTOM) {
                cur.newPage()
                row(headers, headerHeight, PRIMARY, 6f)
            }
            row(text, rowHeight, if (index % 2 == 0) STRIPE else CARD, 5f)
        }
        cur.y += 12
    }

    private fun fill(color: Int) = Paint().apply { this.color = color; style = Paint.Style.FILL }
    private fun stroke(color: Int = BORDER, width: Float = 0.55f) = Paint().apply {
        this.color = color; style = Paint.Style.STROKE; strokeWidth = width
    }

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
