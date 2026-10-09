import 'dart:async';

// ignore_for_file: depend_on_referenced_packages

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/auto_outbox_sync_watcher.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConnectivityPlatform originalPlatform;
  late FakeConnectivityPlatform fakePlatform;
  late AppDatabase database;
  final watcher = AutoOutboxSyncWatcher.instance;

  setUp(() async {
    originalPlatform = ConnectivityPlatform.instance;
    fakePlatform = FakeConnectivityPlatform()
      ..current = const [ConnectivityResult.wifi];
    ConnectivityPlatform.instance = fakePlatform;
    watcher.stop();
    if (SyncGuard.isActive) SyncGuard.markFinished();
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    watcher.stop();
    if (SyncGuard.isActive) SyncGuard.markFinished();
    await database.close();
    ConnectivityPlatform.instance = originalPlatform;
    await fakePlatform.dispose();
  });

  test('pushNow runs the push callback once and releases SyncGuard', () async {
    var pushCalls = 0;
    AutoOutboxSyncWatcher.pushFunction = () async {
      pushCalls++;
      return 1;
    };

    await watcher.start(database);
    await watcher.pushNow();

    expect(pushCalls, 1);
    expect(watcher.isPushing, isFalse);
    expect(SyncGuard.isActive, isFalse);
  });

  test(
    'pushNow releases SyncGuard after a failed push and can retry',
    () async {
      var failedCalls = 0;
      AutoOutboxSyncWatcher.pushFunction = () async {
        failedCalls++;
        throw StateError('simulated push failure');
      };

      await watcher.start(database);
      await watcher.pushNow();

      expect(failedCalls, 1);
      expect(watcher.isPushing, isFalse);
      expect(SyncGuard.isActive, isFalse);

      var retryCalls = 0;
      AutoOutboxSyncWatcher.pushFunction = () async {
        retryCalls++;
        return 1;
      };
      await watcher.pushNow();

      expect(retryCalls, 1);
      expect(SyncGuard.isActive, isFalse);
    },
  );
}

class FakeConnectivityPlatform extends ConnectivityPlatform {
  final StreamController<List<ConnectivityResult>> _events =
      StreamController<List<ConnectivityResult>>.broadcast();

  List<ConnectivityResult> current = const [ConnectivityResult.none];

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _events.stream;

  Future<void> dispose() => _events.close();
}
