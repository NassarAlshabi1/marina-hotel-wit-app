import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show Value;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../utils/id.dart';
import 'appwrite_sync_manager.dart';
import 'local_db.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// يتتبع جلسات التطبيق ويسجّلها في قاعدة البيانات،
/// ويقوم بجدولة النسخ الاحتياطي بعد 15 دقيقة من الاستخدام التراكمي.
class AppSessionManager {
  static const int _backupThresholdSeconds = 900;

  static AppDatabase? _database;
  static DateTime? _sessionStart;
  static String? _activeSessionUuid;
  static int _accumulatedSeconds = 0;
  static Future<String?> Function()? _deviceIdResolver;

  /// مرجع مشترك لمدير المزامنة — يُعيَّن عبر configure()
  static AppwriteSyncManager? _sharedSyncManager;

  /// تهيئة المدير بقاعدة البيانات والدوال المساعدة (مثل الحصول على معرف الجهاز).
  static void configure({
    required AppDatabase database,
    Future<String?> Function()? deviceIdResolver,
    AppwriteSyncManager? syncManager,
  }) {
    _database = database;
    _deviceIdResolver = deviceIdResolver;
    _sharedSyncManager = syncManager;
  }

  /// استدعاء عند تشغيل التطبيق أو عودته إلى الواجهة.
  static Future<void> onAppOpen() async {
    // تشغيل سحب البيانات من Appwrite تلقائياً
    unawaited(_triggerAppOpenAppwritePull());

    if (_sessionStart != null) {
      return;
    }

    _sessionStart = DateTime.now();
    _activeSessionUuid = IdGen.uuid();

    final db = _database;
    if (db != null && _activeSessionUuid != null) {
      final deviceId = await _resolveDeviceId();
      await db
          .into(db.appSessions)
          .insert(
            AppSessionsCompanion.insert(
              sessionUuid: _activeSessionUuid!,
              sessionStartIso: _sessionStart!.toIso8601String(),
              deviceId: deviceId != null
                  ? Value(deviceId)
                  : const Value.absent(),
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
      )..where((tbl) => tbl.sessionUuid.equals(sessionUuid))).write(
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

  /// تنفيذ سحب البيانات من Appwrite تلقائياً عند فتح التطبيق
  /// تم تحسينها لتكون "ذكية": يتم السحب مرة واحدة فقط كل ساعة كحد أقصى عند الفتح.
  static Future<void> _triggerAppOpenAppwritePull() async {
    try {
      dlog('🔄 [AppOpen] Checking for automatic Appwrite pull...');
      final prefs = await SharedPreferences.getInstance();
      final appwriteEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      final syncOnStartup = prefs.getBool('appwrite_sync_on_startup') ?? true;

      if (!appwriteEnabled || !syncOnStartup) {
        dlog(
          'ℹ️ [AppOpen] Appwrite sync on startup is disabled in settings. Skipping pull.',
        );
        return;
      }

      // --- بداية منطق الذكاء (مرة كل ساعة) ---
      // مفتاح التخزين الموحد لضمان القراءة الصحيحة
      const String lastPullKey = 'last_appwrite_pull_on_open_timestamp';

      // الحصول على الوقت الحالي
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;

      // قراءة آخر وقت سحب (0 إذا لم يوجد)
      final lastPullMs = prefs.getInt(lastPullKey) ?? 0;

      if (lastPullMs > 0) {
        final lastPullTime = DateTime.fromMillisecondsSinceEpoch(lastPullMs);
        final difference = now.difference(lastPullTime);

        // التحقق مما إذا كان الفارق أقل من 60 دقيقة
        if (difference.inMinutes < 60) {
          final remainingMinutes = 60 - difference.inMinutes;
          dlog(
            () =>
                'ℹ️ [AppOpen] Smart Sync: Skipping pull. Last pull was ${difference.inMinutes} mins ago. Next pull available in $remainingMinutes mins.',
          );
          return;
        }
      }
      // --- نهاية منطق الذكاء ---

      // الانتظار قليلاً للتأكد من استقرار الشبكة والأنظمة
      await Future<void>.delayed(const Duration(seconds: 3));

      dlog('📥 [AppOpen] Starting smart automatic Appwrite pull...');

      // استخدام SyncManager المشترك لتجنب مزامنة مزدوجة ومصادمات mutex
      final syncManager = _sharedSyncManager;
      if (syncManager == null) {
        dlog('ℹ️ [AppOpen] No shared SyncManager — skipping pull.');
        return;
      }

      // تنفيذ المزامنة (سحب فقط)
      final result = await syncManager.sync(push: false);

      // تحديث وقت آخر سحب ناجح
      await prefs.setInt(lastPullKey, nowMs);

      dlog(
        () =>
            '✅ [AppOpen] Smart pull completed: ${result.recordsPulled} records pulled.',
      );
    } catch (e) {
      dlog(() => '❌ [AppOpen] Error during automatic Appwrite pull: $e');
    }
  }
}
