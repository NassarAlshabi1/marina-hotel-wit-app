import 'dart:async';

import 'local_db.dart';
import 'sync_integrity_checker.dart';
import 'database_fixer.dart';
import 'restore_fix_service.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// جدولة دورية لفحص سلامة البيانات وإصلاح المشاكل تلقائياً
class IntegrityCheckScheduler {
  IntegrityCheckScheduler(this.db) 
    : _checker = SyncIntegrityChecker.instance,
      _fixer = DatabaseFixer(db),
      _restoreFix = RestoreFixService(db);
  final AppDatabase db;
  final SyncIntegrityChecker _checker;
  final DatabaseFixer _fixer;
  final RestoreFixService _restoreFix;

  Timer? _timer;
  static const Duration _checkInterval = Duration(hours: 6);
  static const Duration _fullCheckInterval = Duration(days: 1);

  DateTime? _lastFullCheck;

  /// بدء المجدول الدوري
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_checkInterval, (_) => _runQuickCheck());
    _runQuickCheck(); // تشغيل فوري عند البداية
    dlog('✅ IntegrityCheckScheduler started (interval: ${_checkInterval.inHours}h)');
  }

  /// إيقاف المجدول
  void stop() {
    _timer?.cancel();
    _timer = null;
    dlog('🛑 IntegrityCheckScheduler stopped');
  }

  /// فحص سريع (كل 6 ساعات)
  Future<void> _runQuickCheck() async {
    try {
      dlog('🔍 بدء فحص سلامة سريع...');
      final report = await _checker.verify(db);

      if (report.hasIssues) {
        dlog('⚠️ تم العثور على ${report.issueCount} مشكلة (${report.criticalIssueCount} حرجة)');
        await _logIssues(report);

        // إصلاح المشاكل الحرجة تلقائياً
        if (report.hasCriticalIssues) {
          dlog('🔧 محاولة إصلاح المشاكل الحرجة تلقائياً...');
          for (final issue in report.issues.where((i) => i.isCritical)) {
            try {
              await _checker.fixIssue(db, issue);
              dlog('✅ تم إصلاح: ${issue.toString()}');
            } catch (e) {
              dlog('❌ فشل إصلاح ${issue.toString()}: $e');
            }
          }
        }
      } else {
        dlog('✅ فحص سلامة سريع: لا توجد مشاكل');
      }

      // تشغيل فحص شامل يومياً
      if (_lastFullCheck == null ||
          DateTime.now().difference(_lastFullCheck!) > _fullCheckInterval) {
        await _runFullCheck();
      }
    } catch (e, st) {
      dlog('❌ خطأ في فحص السلامة: $e\n$st');
    }
  }

  /// فحص شامل (يومياً)
  Future<void> _runFullCheck() async {
    try {
      dlog('🔍 بدء فحص سلامة شامل...');
      final report = await _checker.verify(db);

      if (report.hasIssues) {
        dlog('⚠️ الفحص الشامل: ${report.issueCount} مشكلة (${report.criticalIssueCount} حرجة)');
        await _logIssues(report);
      } else {
        dlog('✅ الفحص الشامل: لا توجد مشاكل');
      }

      _lastFullCheck = DateTime.now();

      // تشغيل خدمات الإصلاح التلقائي
      await _fixer.fixAllIssues();
      await _restoreFix.runAutoFixAfterRestore();
    } catch (e, st) {
      dlog('❌ خطأ في الفحص الشامل: $e\n$st');
    }
  }

  Future<void> _logIssues(IntegrityReport report) async {
    for (final issue in report.issues) {
      final db = db;
      await db.into(db.integrityViolations).insert(
        IntegrityViolationsCompanion(
          runId: const Value(0), // سيتم تحديثه عند وجود runId صحيح
          affectedTableName: Value(issue.table),
          recordUuid: issue.uuid != null ? Value(issue.uuid!) : const Value.absent(),
          violationType: Value(issue.type.toString()),
          details: Value(issue.description),
          isCritical: Value(issue.isCritical),
          createdAtIso: Value(DateTime.now().toIso8601String()),
          createdAtEpoch: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        ),
      );
    }
  }

  /// تشغيل فحص يدوي
  Future<IntegrityReport> runManualCheck() async {
    dlog('🔍 تشغيل فحص يدوي...');
    return _checker.verify(db);
  }
}