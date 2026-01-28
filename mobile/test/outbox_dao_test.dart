import 'package:drift/native.dart';
import 'package:test/test.dart';

import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  late AppDatabase db;
  late OutboxDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('merge preserves idempotencyKey across updates', () async {
    final localUuid = 'u1';

    await dao.merge(
      entity: 'rooms',
      op: 'create',
      localUuid: localUuid,
      serverId: null,
      payload: {'x': 1},
      clientTs: 1,
    );
    final first = await (db.select(db.outbox)..where((t) => t.localUuid.equals(localUuid))).getSingle();
    final key1 = first.idempotencyKey;

    await dao.merge(
      entity: 'rooms',
      op: 'create',
      localUuid: localUuid,
      serverId: null,
      payload: {'x': 2},
      clientTs: 2,
    );
    final second = await (db.select(db.outbox)..where((t) => t.localUuid.equals(localUuid))).getSingle();
    final key2 = second.idempotencyKey;

    expect(key1, isNotNull);
    expect(key1, key2);
  });

  test('setError resets processing and caps attempts', () async {
    final id = await db.into(db.outbox).insert(
          OutboxCompanion.insert(
            entity: 'rooms',
            op: 'create',
            localUuid: 'u2',
            payload: '{}',
            clientTs: 1,
            processingStatus: const Value('processing'),
            processingStartedAt: const Value(123),
            processingWorker: const Value('w1'),
          ),
        );

    await dao.setError(id, 'err', 2, maxAttempts: 3);
    final row = await (db.select(db.outbox)..where((t) => t.id.equals(id))).getSingle();
    expect(row.processingStatus, 'pending');
    expect(row.processingStartedAt, isNull);
    expect(row.processingWorker, isNull);
    expect(row.attempts, 2);

    await dao.setError(id, 'err2', 3, maxAttempts: 3);
    final row2 = await (db.select(db.outbox)..where((t) => t.id.equals(id))).getSingle();
    expect(row2.processingStatus, 'failed');
    expect(row2.attempts, 3);
  });

  test('takeBatch skips items exceeding maxAttempts', () async {
    await db.into(db.outbox).insert(
          OutboxCompanion.insert(
            entity: 'rooms',
            op: 'create',
            localUuid: 'u3',
            payload: '{}',
            clientTs: 1,
            attempts: const Value(5),
            processingStatus: const Value('pending'),
          ),
        );
    final batch = await dao.takeBatch(10, maxAttempts: 5);
    expect(batch, isEmpty);
  });
}
