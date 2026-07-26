import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/tasks/auto_sync_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AutoSyncTask consumes pending flag and triggers sync', () async {
    SharedPreferences.setMockInitialValues({
      'auto_sync_pending': true,
      'appwrite_sync_enabled': false,
      'google_drive_sync_enabled': false,
    });
    final prefs = await SharedPreferences.getInstance();

    AppDatabase.forTesting(NativeDatabase.memory());

    await AutoSyncTask.consumePendingAndSync();
    expect(prefs.getBool('auto_sync_pending'), isFalse);
  });
}
