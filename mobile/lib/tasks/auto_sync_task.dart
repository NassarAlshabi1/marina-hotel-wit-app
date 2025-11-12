import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../services/google_drive_sync_service.dart';

/// اسم المهمة الخلفية في Workmanager
const String kGoogleDriveAutoSyncTask = 'google_drive_auto_sync_task';

/// الفاصل الافتراضي للمزامنة الآلية (15 دقيقة)
const Duration kDefaultAutoSyncInterval = Duration(minutes: 15);

/// مدير المهام الخلفية لمزامنة Google Drive
class GoogleDriveAutoSyncTask {
  GoogleDriveAutoSyncTask._();

  static final GoogleDriveAutoSyncTask instance = GoogleDriveAutoSyncTask._();

  bool _initialized = false;

  /// تهيئة Workmanager والسماح بتسجيل المهام.
  Future<void> initialize() async {
    if (_initialized) return;

    WidgetsFlutterBinding.ensureInitialized();

    await Workmanager().initialize(
      googleDriveAutoSyncCallbackDispatcher,
      isInDebugMode: false,
    );

    _initialized = true;
  }

  /// جدولة مهمة المزامنة التلقائية كل [interval]
  Future<void> schedule({Duration interval = kDefaultAutoSyncInterval}) async {
    await initialize();

    await Workmanager().cancelByUniqueName(kGoogleDriveAutoSyncTask);

    await Workmanager().registerPeriodicTask(
      kGoogleDriveAutoSyncTask,
      kGoogleDriveAutoSyncTask,
      frequency: interval < const Duration(minutes: 15)
          ? const Duration(minutes: 15)
          : interval,
      initialDelay: const Duration(minutes: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// إلغاء المهمة المجدولة
  Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kGoogleDriveAutoSyncTask);
    _initialized = false;
  }

  /// تشغيل المزامنة فوراً (خارج Workmanager)
  Future<void> runNow() async {
    await GoogleDriveSyncService().syncAllTables();
  }
}

@pragma('vm:entry-point')
void googleDriveAutoSyncCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await GoogleDriveSyncService().syncAllTables();
      return true;
    } catch (error) {
      // ignore: avoid_print
      print('⚠️ فشل تنفيذ مهمة المزامنة الخلفية: $error');
      return false;
    }
  });
}
