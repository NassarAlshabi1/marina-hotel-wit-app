import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:workmanager/workmanager.dart';

import '../utils/id.dart';
import 'local_db.dart';

/// يتتبع جلسات التطبيق ويسجّلها في قاعدة البيانات،
/// ويقوم بجدولة النسخ الاحتياطي بعد 15 دقيقة من الاستخدام التراكمي.
class AppSessionManager {
  static const int _backupThresholdSeconds = 900;

  static AppDatabase? _database;
  static DateTime? _sessionStart;
  static String? _activeSessionUuid;
  static int _accumulatedSeconds = 0;
  static Future<String?> Function()? _deviceIdResolver;

  /// تهيئة المدير بقاعدة البيانات والدوال المساعدة (مثل الحصول على معرف الجهاز).
  static void configure({
    required AppDatabase database,
    Future<String?> Function()? deviceIdResolver,
  }) {
    _database = database;
    _deviceIdResolver = deviceIdResolver;
  }

  /// استدعاء عند تشغيل التطبيق أو عودته إلى الواجهة.
  static Future<void> onAppOpen() async {
    if (_sessionStart != null) {
      return;
    }

    _sessionStart = DateTime.now();
    _activeSessionUuid = IdGen.uuid();

    final db = _database;
    if (db != null && _activeSessionUuid != null) {
      final deviceId = await _resolveDeviceId();
      await db.into(db.appSessions).insert(
            AppSessionsCompanion.insert(
              sessionUuid: _activeSessionUuid!,
              sessionStartIso: _sessionStart!.toIso8601String(),
              deviceId:
                  deviceId != null ? Value(deviceId) : const Value.absent(),
              durationSeconds: const Value(0),
            ),
          );
    }
  }

  /// استدعاء عند انتقال التطبيق إلى الخلفية أو إغلاقه.
  static Future<void> onAppCloseOrBackground() async {
    final start = _sessionStart;
    if (start == null) {
      return;
    }

    final end = DateTime.now();
    final durationSeconds = max(0, end.difference(start).inSeconds);
    _accumulatedSeconds += durationSeconds;

    final db = _database;
    final sessionUuid = _activeSessionUuid;
    if (db != null && sessionUuid != null) {
      final deviceId = await _resolveDeviceId();
      await (db.update(
        db.appSessions,
      )..where((tbl) => tbl.sessionUuid.equals(sessionUuid)))
          .write(
        AppSessionsCompanion(
          sessionEndIso: Value(end.toIso8601String()),
          durationSeconds: Value(durationSeconds),
          deviceId: deviceId != null ? Value(deviceId) : const Value.absent(),
        ),
      );
    }

    _sessionStart = null;
    _activeSessionUuid = null;

    await _scheduleBackupIfNeeded();
  }

  /// تهيئة النسخ الاحتياطي عند تجاوز الحد التراكمي (15 دقيقة).
  static Future<void> _scheduleBackupIfNeeded() async {
    if (_accumulatedSeconds >= _backupThresholdSeconds) {
      await Workmanager().registerOneOffTask(
        'backupAfterInactivity',
        'backupAfterInactivity',
        initialDelay: const Duration(minutes: 1),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        inputData: const <String, dynamic>{'trigger': 'session_threshold'},
      );
      _accumulatedSeconds = 0;
    }
  }

  static Future<String?> _resolveDeviceId() async {
    if (_deviceIdResolver != null) {
      try {
        return await _deviceIdResolver!();
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
