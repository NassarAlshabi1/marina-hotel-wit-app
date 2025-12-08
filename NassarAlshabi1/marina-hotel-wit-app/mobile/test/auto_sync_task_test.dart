import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_manager.dart';
import 'package:marina_hotel_mobile/services/google_drive_sync_service.dart';
import 'package:marina_hotel_mobile/tasks/auto_sync_task.dart';

class _DummyDriveSyncService extends GoogleDriveSyncService {
  _DummyDriveSyncService() : super();

  @override
  Future<void> init({bool enableEncryption = false, String? encryptionKey}) async {}
}

class _TestSyncManager extends SyncManager {
  _TestSyncManager(AppDatabase db)
      : super(db: db, driveService: _DummyDriveSyncService());

  int invocations = 0;

  @override
  Future<void> syncAllTables({bool force = false}) async {
    invocations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AutoSyncTask consumes pending flag and triggers sync', () async {
    SharedPreferences.setMockInitialValues({'auto_sync_pending': true});
    final prefs = await SharedPreferences.getInstance();

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = _TestSyncManager(db);

    await AutoSyncTask.consumePendingAndSync(manager);

    expect(manager.invocations, 1);
    expect(prefs.getBool('auto_sync_pending'), isFalse);
  });
}
