import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' hide PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../utils/enhanced_pdf_utils.dart';
import '../daos/sync_log_dao.dart';
import '../monitoring/sync_monitoring_system.dart';

/// تقرير أداء المزامنة الشامل
class SyncPerformanceReport {
  SyncPerformanceReport({
    required this.stats,
    required this.recentLogs,
    required this.errorLogs,
    required this.generatedAt,
    required this.dateRange,
    this.deviceId,
    this.pendingChanges,
    this.conflicts,
  });

  final SyncStats stats;
  final List<SyncLogEntry> recentLogs;
  final List<SyncLogEntry> errorLogs;
  final DateTime generatedAt;
  final DateTimeRange dateRange;
  final String? deviceId;
  final int? pendingChanges;
  final List<ConflictSummary>? conflicts;
}

/// ملخص التضاربات
class ConflictSummary {
  ConflictSummary({
    required this.table,
    required this.count,
    required this.lastOccurrence,
    this.resolution,
  });

  final String table;
  final int count;
  final DateTime lastOccurrence;
  final String? resolution;
}

/// نطاق زمني
class DateTimeRange {
  DateTimeRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}

/// مولد تقارير المزامنة
class SyncReportGenerator {
  /// إنشاء تقرير أداء المزامنة بصيغة PDF
  static Future<Uint8List> generatePdfBytes({
    required SyncPerformanceReport report,
  }) async {
    final fonts = await EnhancedPdfUtils.loadArabicFonts();
    final logo = await EnhancedPdfUtils.loadLogoImage();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        header: (context) => pw.Column(
          children: [
            EnhancedPdfUtils.buildProfessionalHeader(
              fonts: fonts,
              logo: logo,
              title: 'تقرير أداء المزامنة',
              subtitle: 'Sync Performance Report',
            ),
            pw.SizedBox(height: 20),
          ],
        ),
        build: (context) => [
          // معلومات التقرير
          EnhancedPdfUtils.buildInfoCard(
            title: '📊 معلومات التقرير',
            fonts: fonts,
            content: [
              pw.Text(
                'تاريخ الإنشاء: ${EnhancedPdfUtils.formatDateTime(report.generatedAt)}',
                style: PdfTextStyles.body(fonts.regular),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'الفترة: ${EnhancedPdfUtils.formatDateTime(report.dateRange.start)} - ${EnhancedPdfUtils.formatDateTime(report.dateRange.end)}',
                style: PdfTextStyles.body(fonts.regular),
              ),
              if (report.deviceId != null) ...[
                pw.SizedBox(height: 6),
                pw.Text(
                  'الجهاز: ${report.deviceId}',
                  style: PdfTextStyles.body(fonts.regular),
                ),
              ],
            ],
          ),

          pw.SizedBox(height: 20),

          // الإحصائيات الرئيسية
          pw.Text(
            '📈 الإحصائيات الرئيسية',
            style: PdfTextStyles.heading2(fonts.bold),
          ),
          pw.SizedBox(height: 12),

          // صف الإحصائيات الأول
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildStatBox(
                  title: 'إجمالي المزامنات',
                  value: report.stats.totalSyncs.toString(),
                  fonts: fonts,
                  color: PdfColors.info,
                  icon: '🔄',
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildStatBox(
                  title: 'معدل النجاح',
                  value: '${report.stats.successRate.toStringAsFixed(1)}%',
                  fonts: fonts,
                  color: report.stats.successRate >= 80
                      ? PdfColors.success
                      : report.stats.successRate >= 50
                          ? PdfColors.warning
                          : PdfColors.danger,
                  icon: report.stats.successRate >= 80 ? '✅' : '⚠️',
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          // صف الإحصائيات الثاني
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildStatBox(
                  title: 'مزامنة ناجحة',
                  value: report.stats.successfulSyncs.toString(),
                  fonts: fonts,
                  color: PdfColors.success,
                  icon: '✓',
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildStatBox(
                  title: 'مزامنة فاشلة',
                  value: report.stats.failedSyncs.toString(),
                  fonts: fonts,
                  color: PdfColors.danger,
                  icon: '✗',
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 12),

          // صف الإحصائيات الثالث
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildStatBox(
                  title: 'السجلات المسحوبة',
                  value: EnhancedPdfUtils.formatNumber(
                      report.stats.totalRecordsPulled.toDouble()),
                  fonts: fonts,
                  color: PdfColors.accent,
                  icon: '📥',
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildStatBox(
                  title: 'السجلات المرفوعة',
                  value: EnhancedPdfUtils.formatNumber(
                      report.stats.totalRecordsPushed.toDouble()),
                  fonts: fonts,
                  color: PdfColors.secondary,
                  icon: '📤',
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // الأداء
          pw.Text(
            '⏱️ مؤشرات الأداء',
            style: PdfTextStyles.heading2(fonts.bold),
          ),
          pw.SizedBox(height: 12),

          pw.Row(
            children: [
              pw.Expanded(
                child: _buildStatBox(
                  title: 'متوسط المدة',
                  value: '${report.stats.averageDurationMs}ms',
                  fonts: fonts,
                  color: PdfColors.info,
                  icon: '⏰',
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildStatBox(
                  title: 'التغييرات المعلقة',
                  value: report.pendingChanges?.toString() ?? '0',
                  fonts: fonts,
                  color: report.pendingChanges != null && report.pendingChanges! > 10
                      ? PdfColors.warning
                      : PdfColors.info,
                  icon: '⏳',
                ),
              ),
            ],
          ),

          pw.SizedBox(height: 20),

          // آخر المزامنات
          if (report.recentLogs.isNotEmpty) ...[
            pw.Text(
              '📋 آخر عمليات المزامنة',
              style: PdfTextStyles.heading2(fonts.bold),
            ),
            pw.SizedBox(height: 12),
            _buildSyncLogsTable(report.recentLogs.take(10).toList(), fonts),
            pw.SizedBox(height: 20),
          ],

          // الأخطاء الأخيرة
          if (report.errorLogs.isNotEmpty) ...[
            pw.Text(
              '❌ آخر الأخطاء',
              style: PdfTextStyles.heading2(fonts.bold),
            ),
            pw.SizedBox(height: 12),
            _buildErrorLogsTable(report.errorLogs.take(10).toList(), fonts),
            pw.SizedBox(height: 20),
          ],

          // التضاربات
          if (report.conflicts != null && report.conflicts!.isNotEmpty) ...[
            pw.Text(
              '⚔️ التضاربات',
              style: PdfTextStyles.heading2(fonts.bold),
            ),
            pw.SizedBox(height: 12),
            _buildConflictsTable(report.conflicts!, fonts),
            pw.SizedBox(height: 20),
          ],

          // تذييل
          EnhancedPdfUtils.buildContactFooter(fonts: fonts),
        ],
      ),
    );

    return pdf.save();
  }

  /// مشاركة التقرير كملف PDF
  static Future<void> shareReport({
    required SyncPerformanceReport report,
    String? customFilename,
  }) async {
    final bytes = await generatePdfBytes(report: report);
    final filename = customFilename ??
        'sync-report-${DateFormat('yyyy-MM-dd-HHmm').format(DateTime.now())}.pdf';

    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  /// بناء صندوق إحصائيات
  static pw.Widget _buildStatBox({
    required String title,
    required String value,
    required ArabicPdfFonts fonts,
    required PdfColor color,
    required String icon,
  }) {
    return EnhancedPdfUtils.buildStatisticsBox(
      title: title,
      value: value,
      fonts: fonts,
      color: color,
      icon: icon,
    );
  }

  /// بناء جدول سجلات المزامنة
  static pw.Widget _buildSyncLogsTable(
    List<SyncLogEntry> logs,
    ArabicPdfFonts fonts,
  ) {
    final headers = ['الوقت', 'النوع', 'الحالة', 'السجلات', 'المدة'];
    final data = logs.map((log) {
      return [
        _formatTime(log.createdAt),
        log.direction == 'pull' ? 'سحب' : 'رفع',
        log.status == 'success' ? '✓ نجح' : log.status == 'partial' ? '⚠ جزئي' : '✗ فشل',
        log.recordsCount?.toString() ?? '-',
        log.durationMs != null ? '${log.durationMs}ms' : '-',
      ];
    }).toList();

    return EnhancedPdfUtils.buildProfessionalTable(
      headers: headers,
      data: data,
      fonts: fonts,
      columnWidths: [80, 60, 60, 50, 50],
    );
  }

  /// بناء جدول الأخطاء
  static pw.Widget _buildErrorLogsTable(
    List<SyncLogEntry> logs,
    ArabicPdfFonts fonts,
  ) {
    return pw.Column(
      children: logs.map((log) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 8),
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColor(1.0, 0.95, 0.95),
            border: pw.Border.all(color: PdfColors.danger),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    log.direction == 'pull' ? '📥 سحب' : '📤 رفع',
                    style: PdfTextStyles.bodyBold(fonts.bold),
                  ),
                  pw.Text(
                    _formatDateTime(log.createdAt),
                    style: PdfTextStyles.caption(fonts.regular),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                log.errorMessage ?? 'خطأ غير معروف',
                style: pw.TextStyle(
                  font: fonts.regular,
                  fontSize: 10,
                  color: PdfColors.danger,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// بناء جدول التضاربات
  static pw.Widget _buildConflictsTable(
    List<ConflictSummary> conflicts,
    ArabicPdfFonts fonts,
  ) {
    final headers = ['الجدول', 'العدد', 'آخر حدوث', 'الحل'];
    final data = conflicts.map((c) {
      return [
        c.table,
        c.count.toString(),
        _formatDateTime(c.lastOccurrence),
        c.resolution ?? 'غير محدد',
      ];
    }).toList();

    return EnhancedPdfUtils.buildProfessionalTable(
      headers: headers,
      data: data,
      fonts: fonts,
      columnWidths: [80, 50, 80, 80],
    );
  }

  /// تنسيق الوقت
  static String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  /// تنسيق التاريخ والوقت
  static String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}/${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

/// مزود بيانات تقرير المزامنة
class SyncReportDataProvider {
  /// جمع بيانات التقرير من قاعدة البيانات
  static Future<SyncPerformanceReport> gatherReportData({
    required SyncLogDao syncLogDao,
    DateTime? startDate,
    DateTime? endDate,
    String? deviceId,
    int maxLogs = 100,
  }) async {
    final now = DateTime.now();
    final start = startDate ?? now.subtract(const Duration(days: 7));
    final end = endDate ?? now;

    // جمع الإحصائيات
    final stats = await syncLogDao.getSyncStats(since: start);

    // جمع السجلات الأخيرة
    final recentLogs = await syncLogDao.getSyncHistory(
      limit: maxLogs,
      direction: null,
      status: null,
    );

    // جمع سجلات الأخطاء
    final errorLogs = await syncLogDao.getSyncHistory(
      limit: 50,
      direction: null,
      status: 'failed',
    );

    return SyncPerformanceReport(
      stats: stats,
      recentLogs: recentLogs,
      errorLogs: errorLogs,
      generatedAt: now,
      dateRange: DateTimeRange(start: start, end: end),
      deviceId: deviceId,
    );
  }

  /// جمع بيانات التقرير من نظام المراقبة
  static SyncPerformanceReport gatherFromMonitoringSystem({
    required SyncMonitoringSystem monitoringSystem,
    int maxLogs = 100,
  }) {
    final now = DateTime.now();
    final events = monitoringSystem.events;

    // حساب الإحصائيات من الأحداث
    final completedEvents =
        events.where((e) => e.type == SyncEventType.completed).toList();
    final failedEvents =
        events.where((e) => e.type == SyncEventType.failed).toList();
    final conflictEvents =
        events.where((e) => e.type == SyncEventType.conflict).toList();

    final totalSyncs = completedEvents.length + failedEvents.length;
    final successRate =
        totalSyncs > 0 ? (completedEvents.length / totalSyncs) * 100 : 0.0;

    // حساب متوسط المدة
    final durations = completedEvents
        .where((e) => e.metadata?['duration_seconds'] != null)
        .map((e) => (e.metadata!['duration_seconds'] as int) * 1000)
        .toList();
    final avgDuration =
        durations.isNotEmpty ? durations.reduce((a, b) => a + b) ~/ durations.length : 0;

    // حساب السجلات المتزامنة
    int totalPulled = 0;
    int totalPushed = 0;
    for (final event in completedEvents) {
      totalPulled += (event.metadata?['records_synced'] as int?) ?? 0;
      totalPushed += (event.metadata?['records_pushed'] as int?) ?? 0;
    }

    final stats = SyncStats(
      totalSyncs: totalSyncs,
      successfulSyncs: completedEvents.length,
      failedSyncs: failedEvents.length,
      successRate: successRate,
      totalRecordsPulled: totalPulled,
      totalRecordsPushed: totalPushed,
      lastSync: completedEvents.isNotEmpty ? completedEvents.last.timestamp : null,
      averageDurationMs: avgDuration,
    );

    // تحويل الأحداث إلى سجلات
    final recentLogs = events.take(maxLogs).map((e) {
      return SyncLogEntry(
        id: e.id.hashCode,
        syncId: e.id,
        direction: e.metadata?['direction'] as String? ?? 'unknown',
        deviceId: e.metadata?['device_id'] as String? ?? 'unknown',
        status: e.type == SyncEventType.completed ? 'success' : 'failed',
        createdAt: e.timestamp,
        completedAt: e.timestamp,
        recordsCount: e.metadata?['records_synced'] as int?,
        errorMessage: e.message,
        durationMs: e.metadata?['duration_seconds'] != null
            ? (e.metadata!['duration_seconds'] as int) * 1000
            : null,
        target: e.metadata?['target'] as String?,
      );
    }).toList();

    // سجلات الأخطاء
    final errorLogs = failedEvents.map((e) {
      return SyncLogEntry(
        id: e.id.hashCode,
        syncId: e.id,
        direction: e.metadata?['direction'] as String? ?? 'unknown',
        deviceId: e.metadata?['device_id'] as String? ?? 'unknown',
        status: 'failed',
        createdAt: e.timestamp,
        completedAt: e.timestamp,
        errorMessage: e.message,
        durationMs: e.metadata?['duration_seconds'] != null
            ? (e.metadata!['duration_seconds'] as int) * 1000
            : null,
        target: e.metadata?['target'] as String?,
      );
    }).toList();

    // التضاربات
    final conflicts = conflictEvents.map((e) {
      return ConflictSummary(
        table: e.metadata?['table'] as String? ?? 'unknown',
        count: 1,
        lastOccurrence: e.timestamp,
        resolution: e.metadata?['resolution'] as String?,
      );
    }).toList();

    return SyncPerformanceReport(
      stats: stats,
      recentLogs: recentLogs,
      errorLogs: errorLogs,
      generatedAt: now,
      dateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
      conflicts: conflicts,
    );
  }
}
