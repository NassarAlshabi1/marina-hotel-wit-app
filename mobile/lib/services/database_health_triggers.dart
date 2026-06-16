import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

import 'database_fixer.dart';
import 'database_health_monitor.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// نظام التشغيل التلقائي لفحص صحة قاعدة البيانات
class DatabaseHealthTriggers {

  DatabaseHealthTriggers(this.monitor, this.fixer);
  final DatabaseHealthMonitor monitor;
  final DatabaseFixer fixer;

  /// فحص عند إقلاع التطبيق
  Future<HealthReport?> onAppLaunch({bool quickScan = true}) async {
    AppLogger.info('🏥 [HealthTrigger] Running app launch scan...', tag: 'APP');

    try {
      final prefs = getSharedPrefs();
      final lastScan = prefs.getInt('health_last_scan') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final hoursSinceLastScan = (now - lastScan) / 3600;

      if (hoursSinceLastScan < 6) {
        AppLogger.info(
  '🏥 [HealthTrigger] Skipped (scanned ${hoursSinceLastScan.toStringAsFixed(1)}h ago)',
  tag: 'APP',
);
        return null;
      }

      final report = quickScan
          ? await monitor.quickScan()
          : await monitor.deepScan();

      await prefs.setInt('health_last_scan', now);

      if (report.isCritical) {
        AppLogger.error('❌ [HealthTrigger] CRITICAL health detected!', tag: 'APP');
        await _notifyCriticalHealth(report);
      } else if (!report.isHealthy) {
        AppLogger.warning('⚠️ [HealthTrigger] Health issues detected', tag: 'APP');
      } else {
        AppLogger.info('✅ [HealthTrigger] Database is healthy', tag: 'APP');
      }

      return report;
    } catch (e) {
      AppLogger.error('❌ [HealthTrigger] Error: $e', tag: 'APP');
      return null;
    }
  }

  /// فحص قبل المزامنة
  Future<bool> preSyncValidation() async {
    AppLogger.info('🔄 [HealthTrigger] Pre-sync validation...', tag: 'APP');

    try {
      final report = await monitor.quickScan();

      if (report.isCritical) {
        AppLogger.error('❌ [HealthTrigger] CRITICAL - sync blocked', tag: 'APP');
        return false;
      }

      if (report.totalIssues > 0) {
        AppLogger.warning('⚠️ [HealthTrigger] ${report.totalIssues} issues found', tag: 'APP');

        final prefs = getSharedPrefs();
        final autoFix = prefs.getBool('health_auto_fix_before_sync') ?? false;

        if (autoFix) {
          AppLogger.info('🔧 [HealthTrigger] Auto-fixing...', tag: 'APP');
          final fixResult = await fixer.fixAllIssues();
          AppLogger.info('✅ [HealthTrigger] Fixed ${fixResult.totalFixed} issues', tag: 'APP');
        }
      }

      return true;
    } catch (e) {
      AppLogger.error('❌ [HealthTrigger] Validation failed: $e', tag: 'APP');
      return false;
    }
  }

  /// فحص بعد استعادة النسخة الاحتياطية
  Future<HealthReport> postRestoreScan() async {
    AppLogger.info('📥 [HealthTrigger] Post-restore scan...', tag: 'APP');

    try {
      final report = await monitor.deepScan();

      if (report.hasIssues) {
        AppLogger.warning(
  '⚠️ [HealthTrigger] ${report.totalIssues} issues after restore',
  tag: 'APP',
);

        final prefs = getSharedPrefs();
        final autoFix = prefs.getBool('health_auto_fix_after_restore') ?? true;

        if (autoFix) {
          AppLogger.info('🔧 [HealthTrigger] Auto-fixing after restore...', tag: 'APP');
          final fixResult = await fixer.fixAllIssues();
          AppLogger.info('✅ [HealthTrigger] Fixed ${fixResult.totalFixed} issues', tag: 'APP');

          return await monitor.quickScan();
        }
      }

      return report;
    } catch (e) {
      AppLogger.error('❌ [HealthTrigger] Post-restore scan failed: $e', tag: 'APP');
      return HealthReport.error(e.toString());
    }
  }

  /// فحص مجدول (يومي)
  Future<void> scheduledDailyScan({required TimeOfDay time}) async {
    AppLogger.info(
  '⏰ [HealthTrigger] Scheduled scan at ${time.hour}:${time.minute}',
  tag: 'APP',
);

    try {
      final report = await monitor.deepScan();

      final prefs = getSharedPrefs();
      await prefs.setString(
        'health_last_scheduled_scan',
        DateTime.now().toIso8601String(),
      );

      if (report.hasIssues) {
        final autoFix = prefs.getBool('health_auto_fix_scheduled') ?? false;

        if (autoFix && report.totalIssues <= 20) {
          AppLogger.info('🔧 [HealthTrigger] Auto-fixing scheduled issues...', tag: 'APP');
          await fixer.fixAllIssues();
        } else {
          await _notifyIssuesFound(report);
        }
      }
    } catch (e) {
      AppLogger.error('❌ [HealthTrigger] Scheduled scan failed: $e', tag: 'APP');
    }
  }

  /// تنبيه صحة حرجة
  Future<void> _notifyCriticalHealth(HealthReport report) async {
    AppLogger.info('🔔 [HealthTrigger] Sending critical notification', tag: 'APP');
  }

  /// تنبيه مشاكل مكتشفة
  Future<void> _notifyIssuesFound(HealthReport report) async {
    AppLogger.info(
  '🔔 [HealthTrigger] Sending issues notification: ${report.totalIssues} issues',
  tag: 'APP',
);
  }
}

class TimeOfDay {

  const TimeOfDay({required this.hour, required this.minute});
  final int hour;
  final int minute;
}
