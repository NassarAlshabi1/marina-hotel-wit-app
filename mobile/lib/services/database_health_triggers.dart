import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_health_monitor.dart';
import 'database_fixer.dart';

/// نظام التشغيل التلقائي لفحص صحة قاعدة البيانات
class DatabaseHealthTriggers {
  final DatabaseHealthMonitor monitor;
  final DatabaseFixer fixer;

  DatabaseHealthTriggers(this.monitor, this.fixer);

  /// فحص عند إقلاع التطبيق
  Future<HealthReport?> onAppLaunch({bool quickScan = true}) async {
    debugPrint('🏥 [HealthTrigger] Running app launch scan...');

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastScan = prefs.getInt('health_last_scan') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final hoursSinceLastScan = (now - lastScan) / 3600;

      if (hoursSinceLastScan < 6) {
        debugPrint(
            '🏥 [HealthTrigger] Skipped (scanned ${hoursSinceLastScan.toStringAsFixed(1)}h ago)');
        return null;
      }

      final report =
          quickScan ? await monitor.quickScan() : await monitor.deepScan();

      await prefs.setInt('health_last_scan', now);

      if (report.isCritical) {
        debugPrint('❌ [HealthTrigger] CRITICAL health detected!');
        await _notifyCriticalHealth(report);
      } else if (!report.isHealthy) {
        debugPrint('⚠️ [HealthTrigger] Health issues detected');
      } else {
        debugPrint('✅ [HealthTrigger] Database is healthy');
      }

      return report;
    } catch (e) {
      debugPrint('❌ [HealthTrigger] Error: $e');
      return null;
    }
  }

  /// فحص قبل المزامنة
  Future<bool> preSyncValidation() async {
    debugPrint('🔄 [HealthTrigger] Pre-sync validation...');

    try {
      final report = await monitor.quickScan();

      if (report.isCritical) {
        debugPrint('❌ [HealthTrigger] CRITICAL - sync blocked');
        return false;
      }

      if (report.totalIssues > 0) {
        debugPrint('⚠️ [HealthTrigger] ${report.totalIssues} issues found');

        final prefs = await SharedPreferences.getInstance();
        final autoFix = prefs.getBool('health_auto_fix_before_sync') ?? false;

        if (autoFix) {
          debugPrint('🔧 [HealthTrigger] Auto-fixing...');
          final fixResult = await fixer.fixAllIssues();
          debugPrint('✅ [HealthTrigger] Fixed ${fixResult.totalFixed} issues');
        }
      }

      return true;
    } catch (e) {
      debugPrint('❌ [HealthTrigger] Validation failed: $e');
      return false;
    }
  }

  /// فحص بعد استعادة النسخة الاحتياطية
  Future<HealthReport> postRestoreScan() async {
    debugPrint('📥 [HealthTrigger] Post-restore scan...');

    try {
      final report = await monitor.deepScan();

      if (report.hasIssues) {
        debugPrint(
            '⚠️ [HealthTrigger] ${report.totalIssues} issues after restore');

        final prefs = await SharedPreferences.getInstance();
        final autoFix = prefs.getBool('health_auto_fix_after_restore') ?? true;

        if (autoFix) {
          debugPrint('🔧 [HealthTrigger] Auto-fixing after restore...');
          final fixResult = await fixer.fixAllIssues();
          debugPrint('✅ [HealthTrigger] Fixed ${fixResult.totalFixed} issues');

          return await monitor.quickScan();
        }
      }

      return report;
    } catch (e) {
      debugPrint('❌ [HealthTrigger] Post-restore scan failed: $e');
      return HealthReport.error(e.toString());
    }
  }

  /// فحص مجدول (يومي)
  Future<void> scheduledDailyScan({
    required TimeOfDay time,
  }) async {
    debugPrint(
        '⏰ [HealthTrigger] Scheduled scan at ${time.hour}:${time.minute}');

    try {
      final report = await monitor.deepScan();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'health_last_scheduled_scan', DateTime.now().toIso8601String());

      if (report.hasIssues) {
        final autoFix = prefs.getBool('health_auto_fix_scheduled') ?? false;

        if (autoFix && report.totalIssues <= 20) {
          debugPrint('🔧 [HealthTrigger] Auto-fixing scheduled issues...');
          await fixer.fixAllIssues();
        } else {
          await _notifyIssuesFound(report);
        }
      }
    } catch (e) {
      debugPrint('❌ [HealthTrigger] Scheduled scan failed: $e');
    }
  }

  /// تنبيه صحة حرجة
  Future<void> _notifyCriticalHealth(HealthReport report) async {
    debugPrint('🔔 [HealthTrigger] Sending critical notification');
  }

  /// تنبيه مشاكل مكتشفة
  Future<void> _notifyIssuesFound(HealthReport report) async {
    debugPrint(
        '🔔 [HealthTrigger] Sending issues notification: ${report.totalIssues} issues');
  }
}

class TimeOfDay {
  final int hour;
  final int minute;

  const TimeOfDay({required this.hour, required this.minute});
}
