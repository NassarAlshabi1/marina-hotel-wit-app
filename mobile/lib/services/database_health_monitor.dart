import 'package:drift/drift.dart';

import '../utils/debug_log.dart';
import 'database_fixer.dart';
import 'local_db.dart';

/// نظام مراقبة صحة قاعدة البيانات المستمر
class DatabaseHealthMonitor {
  DatabaseHealthMonitor(this.db, this.fixer);
  final AppDatabase db;
  final DatabaseFixer fixer;

  /// فحص سريع للصحة العامة (< 100ms)
  Future<HealthReport> quickScan() async {
    final start = DateTime.now();

    try {
      final metrics = await _collectQuickMetrics();

      final duration = DateTime.now().difference(start);

      return HealthReport(
        scannedAt: DateTime.now(),
        scanDuration: duration,
        invalidServerIds: metrics.invalidServerIds,
        orphanPayments: metrics.orphanPayments,
        orphanExpenses: metrics.orphanExpenses,
        healthScore: _calculateHealthScore(metrics),
        status: _determineStatus(metrics),
        scanType: ScanType.quick,
      );
    } catch (e) {
      return HealthReport.error(e.toString());
    }
  }

  /// فحص شامل ومفصل (في background)
  Future<HealthReport> deepScan() async {
    final start = DateTime.now();

    try {
      final validationReport = await fixer.validate();

      final metrics = HealthMetrics(
        invalidServerIds: validationReport.invalidServerIds,
        orphanPayments: validationReport.orphanPayments,
        orphanExpenses: validationReport.orphanExpenses,
      );

      final duration = DateTime.now().difference(start);

      final report = HealthReport(
        scannedAt: DateTime.now(),
        scanDuration: duration,
        invalidServerIds: metrics.invalidServerIds,
        orphanPayments: metrics.orphanPayments,
        orphanExpenses: metrics.orphanExpenses,
        healthScore: _calculateHealthScore(metrics),
        status: _determineStatus(metrics),
        scanType: ScanType.deep,
        details: validationReport.toString(),
      );

      await _saveToHistory(report);

      return report;
    } catch (e) {
      return HealthReport.error(e.toString());
    }
  }

  /// مراقبة مستمرة (Stream)
  Stream<HealthReport> watchHealth({
    Duration interval = const Duration(minutes: 5),
  }) async* {
    while (true) {
      yield await quickScan();
      await Future<void>.delayed(interval);
    }
  }

  /// جمع مقاييس سريعة بدون فحص عميق
  Future<HealthMetrics> _collectQuickMetrics() async {
    try {
      final results = await Future.wait([
        _countInvalidServerIds(),
        _countOrphanPayments(),
        _countOrphanExpenses(),
      ]);

      return HealthMetrics(
        invalidServerIds: results[0],
        orphanPayments: results[1],
        orphanExpenses: results[2],
      );
    } catch (e) {
      dlog(() => 'Error collecting metrics: $e');
      return HealthMetrics(
        invalidServerIds: 0,
        orphanPayments: 0,
        orphanExpenses: 0,
      );
    }
  }

  /// عد serverId الفاسدة (محسّن)
  Future<int> _countInvalidServerIds() async {
    try {
      final result = await db.customSelect('''
        SELECT 
          (SELECT COUNT(*) FROM rooms WHERE server_id LIKE '%-%') +
          (SELECT COUNT(*) FROM payments WHERE server_id LIKE '%-%') +
          (SELECT COUNT(*) FROM expenses WHERE server_id LIKE '%-%')
        as total
      ''').getSingle();

      return result.data['total'] as int? ?? 0;
    } catch (e) {
      dlog(() => 'Error counting invalid serverIds: $e');
      return 0;
    }
  }

  /// عد المدفوعات اليتيمة
  Future<int> _countOrphanPayments() async {
    try {
      final result = await db.customSelect('''
        SELECT COUNT(*) as count
        FROM payments p
        LEFT JOIN bookings b ON p.booking_local_id = b.id
        WHERE p.booking_local_id IS NOT NULL 
          AND b.id IS NULL
          AND p.deleted_at IS NULL
      ''').getSingle();

      return result.data['count'] as int? ?? 0;
    } catch (e) {
      dlog(() => 'Error counting orphan payments: $e');
      return 0;
    }
  }

  /// عد المصروفات اليتيمة (تقدير سريع)
  Future<int> _countOrphanExpenses() async {
    try {
      final result = await db.customSelect('''
        SELECT COUNT(*) as count
        FROM expenses
        WHERE related_id IS NOT NULL
          AND deleted_at IS NULL
      ''').getSingle();

      return result.data['count'] as int? ?? 0;
    } catch (e) {
      dlog(() => 'Error counting orphan expenses: $e');
      return 0;
    }
  }

  /// حساب نسبة الصحة (0-100)
  double _calculateHealthScore(HealthMetrics metrics) {
    final totalIssues = metrics.totalIssues;

    if (totalIssues == 0) {
      return 100.0;
    }
    if (totalIssues <= 5) {
      return 95.0;
    }
    if (totalIssues <= 10) {
      return 90.0;
    }
    if (totalIssues <= 20) {
      return 80.0;
    }
    if (totalIssues <= 50) {
      return 70.0;
    }

    return 50.0;
  }

  /// تحديد حالة الصحة
  HealthStatus _determineStatus(HealthMetrics metrics) {
    final score = _calculateHealthScore(metrics);

    if (score >= 95.0) {
      return HealthStatus.healthy;
    }
    if (score >= 80.0) {
      return HealthStatus.warning;
    }
    return HealthStatus.critical;
  }

  /// حفظ التقرير في السجل
  Future<void> _saveToHistory(HealthReport report) async {
    try {
      await db.customInsert(
        '''
        INSERT INTO database_health_log 
        (scanned_at, health_score, invalid_server_ids, orphan_payments, 
         orphan_expenses, total_issues, status, scan_duration_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        variables: [
          Variable.withInt(report.scannedAt.millisecondsSinceEpoch ~/ 1000),
          Variable.withReal(report.healthScore),
          Variable.withInt(report.invalidServerIds),
          Variable.withInt(report.orphanPayments),
          Variable.withInt(report.orphanExpenses),
          Variable.withInt(report.totalIssues),
          Variable.withString(report.status.name),
          Variable.withInt(report.scanDuration.inMilliseconds),
        ],
      );

      await _cleanOldHistory();
    } catch (e) {
      dlog(() => 'Error saving health history: $e');
    }
  }

  /// تنظيف السجل القديم (الاحتفاظ بآخر 90 يوم)
  Future<void> _cleanOldHistory() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: 90));
      await db.customUpdate(
        'DELETE FROM database_health_log WHERE scanned_at < ?',
        variables: [Variable.withInt(cutoff.millisecondsSinceEpoch ~/ 1000)],
      );
    } catch (e) {
      dlog(() => 'Error cleaning old history: $e');
    }
  }

  /// الحصول على السجل (آخر 30 يوم)
  Future<List<HealthSnapshot>> getHistory({int days = 30}) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final rows = await db
          .customSelect(
            '''
        SELECT scanned_at, health_score, total_issues, status
        FROM database_health_log
        WHERE scanned_at > ?
        ORDER BY scanned_at DESC
        LIMIT 100
        ''',
            variables: [
              Variable.withInt(cutoff.millisecondsSinceEpoch ~/ 1000),
            ],
          )
          .get();

      return rows.map((row) {
        return HealthSnapshot(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (row.data['scanned_at'] as int) * 1000,
          ),
          healthScore: row.data['health_score'] as double,
          totalIssues: row.data['total_issues'] as int,
          status: row.data['status'] as String,
        );
      }).toList();
    } catch (e) {
      dlog(() => 'Error getting history: $e');
      return [];
    }
  }

  /// تحليل الاتجاه
  Future<HealthTrend> analyzeTrend({int days = 30}) async {
    final history = await getHistory(days: days);

    if (history.length < 2) {
      return HealthTrend(improving: true, changeRate: 0.0, concerns: []);
    }

    final latest = history.first.healthScore;
    final oldest = history.last.healthScore;
    final change = latest - oldest;

    final concerns = <String>[];
    if (history.any((h) => h.totalIssues > 10)) {
      concerns.add('مشاكل متكررة تتجاوز 10');
    }
    if (change < -5) {
      concerns.add('تدهور في الصحة بنسبة ${change.abs()}%');
    }

    return HealthTrend(
      improving: change >= 0,
      changeRate: change,
      concerns: concerns,
    );
  }
}

/// تقرير صحة قاعدة البيانات
class HealthReport {
  HealthReport({
    required this.scannedAt,
    required this.scanDuration,
    required this.invalidServerIds,
    required this.orphanPayments,
    required this.orphanExpenses,
    required this.healthScore,
    required this.status,
    required this.scanType,
    this.details,
    this.error,
  });

  factory HealthReport.error(String error) {
    return HealthReport(
      scannedAt: DateTime.now(),
      scanDuration: Duration.zero,
      invalidServerIds: 0,
      orphanPayments: 0,
      orphanExpenses: 0,
      healthScore: 0,
      status: HealthStatus.critical,
      scanType: ScanType.quick,
      error: error,
    );
  }
  final DateTime scannedAt;
  final Duration scanDuration;
  final int invalidServerIds;
  final int orphanPayments;
  final int orphanExpenses;
  final double healthScore;
  final HealthStatus status;
  final ScanType scanType;
  final String? details;
  final String? error;

  int get totalIssues => invalidServerIds + orphanPayments + orphanExpenses;

  bool get isHealthy => status == HealthStatus.healthy;
  bool get hasIssues => totalIssues > 0;
  bool get isCritical => status == HealthStatus.critical;

  String get statusEmoji {
    switch (status) {
      case HealthStatus.healthy:
        return '✅';
      case HealthStatus.warning:
        return '⚠️';
      case HealthStatus.critical:
        return '❌';
    }
  }

  @override
  String toString() {
    if (error != null) {
      return '❌ خطأ في الفحص: $error';
    }

    return '''
$statusEmoji صحة قاعدة البيانات: ${healthScore.toStringAsFixed(1)}%
📊 المشاكل المكتشفة: $totalIssues
  • serverId فاسدة: $invalidServerIds
  • مدفوعات يتيمة: $orphanPayments
  • مصروفات يتيمة: $orphanExpenses
⏱️ مدة الفحص: ${scanDuration.inMilliseconds}ms
    ''';
  }
}

/// مقاييس الصحة
class HealthMetrics {
  HealthMetrics({
    required this.invalidServerIds,
    required this.orphanPayments,
    required this.orphanExpenses,
  });
  final int invalidServerIds;
  final int orphanPayments;
  final int orphanExpenses;

  int get totalIssues => invalidServerIds + orphanPayments + orphanExpenses;
}

/// لقطة سجل الصحة
class HealthSnapshot {
  HealthSnapshot({
    required this.timestamp,
    required this.healthScore,
    required this.totalIssues,
    required this.status,
  });
  final DateTime timestamp;
  final double healthScore;
  final int totalIssues;
  final String status;
}

/// اتجاه الصحة
class HealthTrend {
  HealthTrend({
    required this.improving,
    required this.changeRate,
    required this.concerns,
  });
  final bool improving;
  final double changeRate;
  final List<String> concerns;

  String get emoji => improving ? '📈' : '📉';

  @override
  String toString() {
    final direction = improving ? 'تحسن' : 'تدهور';
    final rate = changeRate.abs().toStringAsFixed(1);

    if (concerns.isEmpty) {
      return '$emoji $direction بمعدل $rate%';
    }

    return '''
$emoji $direction بمعدل $rate%
⚠️ مخاوف:
${concerns.map((c) => '  • $c').join('\n')}
    ''';
  }
}

enum HealthStatus { healthy, warning, critical }

enum ScanType { quick, deep, scheduled }
