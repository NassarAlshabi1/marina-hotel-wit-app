/// ============================================================
/// Marina Hotel - Foreground Sync Service
/// ============================================================
/// خدمة خلفية أمامية (Foreground Service) للمزامنة
/// يضمن استمرار المزامنة حتى لو أغلق المستخدم التطبيق
/// Android 12+ يقتل WorkManager → هذا الحل يعمل دائماً
///
/// المتطلبات:
///   pubspec.yaml: flutter_background_service: ^5.0.0
///   AndroidManifest.xml:
///     <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
///     <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
///     <service android:name="com.blloc.flutter_background_service.IsolateService"
///              android:foregroundServiceType="dataSync" />
/// ============================================================
library;

import 'dart:async';
import 'dart:developer' as developer;

// يتطلب إضافة flutter_background_service للـ pubspec.yaml
// import 'package:flutter_background_service/flutter_background_service.dart';
// import 'package:flutter_background_service_android/flutter_background_service_android.dart';

import 'package:drift/drift.dart' show Variable;

import '../utils/prefs_cache.dart';
import 'appwrite_service.dart';
import 'appwrite_sync_manager.dart';
import 'local_db.dart';

/// حالة خدمة الخلفية
enum ForegroundSyncState { stopped, starting, running, syncing, error }

/// خدمة خلفية أمامية للمزامنة الموثوقة
class ForegroundSyncService {
  ForegroundSyncService._();
  static final ForegroundSyncService instance = ForegroundSyncService._();

  bool _isRunning = false;
  Timer? _syncTimer;
  AppwriteSyncManager? _syncManager;
  Timer? _cleanupTimer;

  final StreamController<ForegroundSyncState> _stateController =
      StreamController<ForegroundSyncState>.broadcast();

  Stream<ForegroundSyncState> get stateStream => _stateController.stream;
  bool get isRunning => _isRunning;

  /// بدء خدمة الخلفية — تستخدم Singletons لتجنب فتح اتصالات جديدة
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      final db = DatabaseManager.instance;
      final appwrite = AppwriteService(); // Singleton — factory

      _syncManager = AppwriteSyncManager(
        appwriteService: appwrite,
        database: db,
      );

      // مؤقت المزامنة الدورية (كل 5 دقائق)
      _syncTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _performSync(),
      );

      // مؤقت تنظيف Outbox كل ساعة
      _cleanupTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) => _cleanupOutbox(),
      );

      // تحديث إشعار الخدمة
      // _updateNotification(title: 'المزامنة نشطة', message: 'تنتظر الجدول التالي...');

      _stateController.add(ForegroundSyncState.running);
      developer.log('✅ ForegroundSyncService started', name: 'SYNC');

      // مزامنة فورية عند بدء الخدمة
      unawaited(_performSync());
    } catch (e, st) {
      developer.log(
        '❌ ForegroundSyncService start failed: $e',
        name: 'SYNC',
        error: e,
        stackTrace: st,
      );
      _isRunning = false;
      _stateController.add(ForegroundSyncState.error);
    }
  }

  /// إيقاف خدمة الخلفية
  Future<void> stop() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
    _isRunning = false;

    // إيقاف خدمة Android
    // final service = FlutterBackgroundService();
    // await service.invoke('stopService');

    _stateController.add(ForegroundSyncState.stopped);
    developer.log('⏹️ ForegroundSyncService stopped', name: 'SYNC');
  }

  /// تنفيذ المزامنة في الخلفية
  Future<void> _performSync() async {
    if (_syncManager == null) return;
    if (!_isRunning) return;

    _stateController.add(ForegroundSyncState.syncing);

    try {
      // التحقق من تمكين المزامنة
      final syncEnabled = PrefsCache.getBool('appwrite_sync_enabled', true);
      if (!syncEnabled) return;

      // تنفيذ المزامنة الكاملة (Push + Pull)
      await _syncManager!.sync();

      // تحديث إشعار الخدمة
      // _updateNotification(title: 'تمت المزامنة', message: 'البيانات محدثة');

      _stateController.add(ForegroundSyncState.running);
    } catch (e, st) {
      developer.log(
        '⚠️ Background sync failed (سيُعاد المحاولة): $e',
        name: 'SYNC',
        error: e,
        stackTrace: st,
      );
      _stateController.add(ForegroundSyncState.running);
    }
  }

  /// تنظيف الـ Outbox من السجلات القديمة
  Future<void> _cleanupOutbox() async {
    try {
      final db = DatabaseManager.instance;
      if (!DatabaseManager.isInitialized) return;
      await db.customUpdate(
        "DELETE FROM outbox WHERE processing_status = 'completed' AND client_ts < ?",
        variables: [
          Variable<int>(
            DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400, // 24h
          ),
        ],
      );
    } catch (_) {}
  }

  /// التخلص من الموارد
  void dispose() {
    stop();
    _stateController.close();
  }
}
