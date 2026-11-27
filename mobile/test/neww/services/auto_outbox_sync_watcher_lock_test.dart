import 'dart:async';
import 'dart:io';

// ignore_for_file: depend_on_referenced_packages

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/auto_outbox_sync_watcher.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';
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

  test(
    'keeps offline entries pending and pushes after connectivity returns',
    () async {
      fakePlatform.current = const [ConnectivityResult.none];
      final outboxDao = OutboxDao(database);
      await outboxDao.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: 'offline-room',
        payload: const {'roomNumber': '101'},
        clientTs: 1000,
      );

      var pushCalls = 0;
      final pushed = Completer<void>();
      AutoOutboxSyncWatcher.pushFunction = () async {
        pushCalls++;
        if (!pushed.isCompleted) pushed.complete();
        return 1;
      };

      await watcher.start(database);
      await Future<void>.delayed(
        SyncConstants.outboxDebounceWindow + const Duration(milliseconds: 100),
      );

      expect(watcher.isOnline, isFalse);
      expect(pushCalls, 0);
      expect(await outboxDao.countPendingPushable(sources: const ['local']), 1);

      fakePlatform.emit(const [ConnectivityResult.wifi]);
      await pushed.future.timeout(const Duration(seconds: 5));

      expect(watcher.isOnline, isTrue);
      expect(pushCalls, 1);
      expect(
        await outboxDao.countPendingPushable(sources: const ['local']),
        1,
        reason: 'callback is a sender stub; only a real ACK may remove the row',
      );
    },
  );

  test('retries a queued push after another sync releases SyncGuard', () async {
    final outboxDao = OutboxDao(database);
    await outboxDao.merge(
      entity: 'rooms',
      op: 'update',
      localUuid: 'guarded-room',
      payload: const {'roomNumber': '102'},
      clientTs: 1001,
    );
    final otherSync = SyncGuard.tryAcquire(label: 'test_external_sync');
    expect(otherSync, isNotNull);

    var pushCalls = 0;
    final pushed = Completer<void>();
    AutoOutboxSyncWatcher.pushFunction = () async {
      pushCalls++;
      if (!pushed.isCompleted) pushed.complete();
      return 1;
    };

    await watcher.start(database);
    await Future<void>.delayed(
      SyncConstants.outboxDebounceWindow + const Duration(milliseconds: 100),
    );
    expect(pushCalls, 0);

    SyncGuard.release(otherSync!);
    await pushed.future.timeout(const Duration(seconds: 8));
    expect(pushCalls, 1);
  });

  test(
    'pending outbox row survives closing and reopening its SQLite file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'outbox_restart_persistence_',
      );
      final file = File('${directory.path}/outbox.db');
      final firstDatabase = AppDatabase.forTesting(NativeDatabase(file));
      AppDatabase? reopenedDatabase;
      var firstDatabaseClosed = false;

      try {
        await OutboxDao(firstDatabase).merge(
          entity: 'rooms',
          op: 'create',
          localUuid: 'persisted-room',
          payload: const {'roomNumber': '103'},
          clientTs: 1002,
        );
        await firstDatabase.close();
        firstDatabaseClosed = true;

        reopenedDatabase = AppDatabase.forTesting(NativeDatabase(file));
        final rows = await reopenedDatabase
            .select(reopenedDatabase.outbox)
            .get();
        expect(rows, hasLength(1));
        expect(rows.single.localUuid, 'persisted-room');
        expect(rows.single.processingStatus, 'pending');
        expect(rows.single.source, 'local');
      } finally {
        if (!firstDatabaseClosed) await firstDatabase.close();
        await reopenedDatabase?.close();
        await directory.delete(recursive: true);
      }
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

  void emit(List<ConnectivityResult> results) {
    current = results;
    _events.add(results);
  }

  Future<void> dispose() => _events.close();
}
