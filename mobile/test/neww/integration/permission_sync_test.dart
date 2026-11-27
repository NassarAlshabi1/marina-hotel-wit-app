import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_config.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  late AppDatabase db;
  late OutboxDao outbox;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxDao(db, AdapterRegistry.testing(db));
  });

  tearDown(() async => db.close());

  test('app_users permission updates are queued and coalesced', () async {
    const docId = 'user_ali';
    final firstTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await outbox.merge(
      entity: 'app_users',
      op: 'update',
      localUuid: docId,
      payload: {
        'username': 'ali',
        'permissions': jsonEncode(['inventory.view', 'inventory.create']),
        'version': 2,
      },
      clientTs: firstTs,
    );
    await outbox.merge(
      entity: 'app_users',
      op: 'update',
      localUuid: docId,
      payload: {
        'username': 'ali',
        'permissions': jsonEncode(['inventory.view']),
        'version': 3,
      },
      clientTs: firstTs + 1,
    );

    final rows = await (db.select(
      db.outbox,
    )..where((row) => row.entity.equals('app_users'))).get();
    expect(rows, hasLength(1));
    expect(rows.single.localUuid, docId);
    expect(
      jsonDecode(rows.single.payload)['permissions'],
      jsonEncode(['inventory.view']),
    );
    expect(await outbox.countPendingPushable(), 1);
  });

  test('app_users has a canonical Appwrite collection mapping', () {
    expect(AppwriteConfig.appUsersCollectionId, 'app_users');
    expect(AppwriteConfig.collectionIdFor('app_users'), 'app_users');
  });
}
