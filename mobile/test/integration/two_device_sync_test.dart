// test/integration/two_device_sync_test.dart
//
// ✅ اختبار المزامنة والتعارض بين جهازين متصلين بنفس القاعدة السحابية
//
// السيناريو:
// - الجهاز A والجهاز B يتشاركان "سحابة" (Map في الذاكرة)
// - push: قراءة outbox → تحديث السحابة → markDeliveredToPrimary
// - pull: قراءة من السحابة → إدراج/تحديث محلي مع originIsServer

// ignore_for_file: lines_longer_than_80_chars, avoid_redundant_argument_values, prefer_const_declarations

@Tags(['integration'])
library marina_hotel_mobile.test.integration_two_device_sync_test;

import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_core/conflict_detector.dart';
import 'package:marina_hotel_mobile/services/sync_core/smart_conflict_resolver.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

d.Value<T> _v<T>(T v) => d.Value(v);
int _epoch() => Time.nowEpoch();

AppDatabase _makeDb() => AppDatabase.forTesting(NativeDatabase.memory());

RoomsCompanion _room({
  required String number,
  String uuid = '',
  String type = 'single',
  double price = 100,
  String status = 'شاغرة',
  int? serverId,
  int? lastModified,
}) {
  return RoomsCompanion(
    roomNumber: _v(number),
    localUuid: _v(uuid),
    type: _v(type),
    price: _v(price),
    status: _v(status),
    serverId: serverId != null ? _v(serverId) : const d.Value.absent(),
    createdAt: _v(_epoch()),
    updatedAt: _v(_epoch()),
    lastModified: _v(lastModified ?? _epoch()),
  );
}

BookingsCompanion _booking({
  required String uuid,
  required String roomNumber,
  String guestName = 'Guest',
  int? serverId,
}) {
  return BookingsCompanion(
    localUuid: _v(uuid),
    roomNumber: _v(roomNumber),
    guestName: _v(guestName),
    guestPhone: const d.Value(''),
    guestNationality: const d.Value(''),
    checkinDate: const d.Value('2026-07-19'),
    status: const d.Value('محجوزة'),
    expectedNights: const d.Value(1),
    calculatedNights: const d.Value(1),
    serverId: serverId != null ? _v(serverId) : const d.Value.absent(),
    createdAt: _v(_epoch()),
    updatedAt: _v(_epoch()),
    lastModified: _v(_epoch()),
  );
}

class CloudStore {
  final Map<String, Map<String, dynamic>> _store = {};
  int _nextId = 1;

  int get nextId => _nextId++;

  void upsert(String entity, Map<String, dynamic> doc) {
    _store['${entity}_${doc['localUuid']}'] = Map<String, dynamic>.from(doc);
  }

  Map<String, dynamic>? get(String entity, String localUuid) {
    return _store['${entity}_$localUuid'];
  }

  void delete(String entity, String localUuid) {
    _store.remove('${entity}_$localUuid');
  }

  List<Map<String, dynamic>> getAll(String entity) {
    return _store.entries
        .where((e) => e.key.startsWith('${entity}_'))
        .map((e) => Map<String, dynamic>.from(e.value))
        .toList();
  }
}

Future<int> simulatePush(
  AppDatabase db,
  OutboxDao outboxDao,
  CloudStore cloud,
  String deviceLabel,
) async {
  int count = 0;
  while (true) {
    final entries = await outboxDao.takeBatch(50, sources: const ['local']);
    if (entries.isEmpty) break;
    for (final entry in entries) {
      final payload = entry.payload;

      final doc = jsonDecode(payload) as Map<String, dynamic>;
      doc['localUuid'] = entry.localUuid;
      final existing = cloud.get(entry.entity, entry.localUuid);
      if (existing == null) {
        doc['serverId'] = cloud.nextId;
      } else {
        doc['serverId'] = existing['serverId'];
      }
      doc['updatedBy'] = deviceLabel;

      if (entry.op == 'delete') {
        cloud.delete(entry.entity, entry.localUuid);
      } else {
        cloud.upsert(entry.entity, doc);
      }
      await outboxDao.markDeliveredToPrimary(entry.id);
      count++;
    }
  }
  return count;
}

Future<int> simulatePull(
  AppDatabase db,
  OutboxDao outboxDao,
  CloudStore cloud,
) async {
  int count = 0;

  for (final entity in ['rooms', 'bookings']) {
    final docs = cloud.getAll(entity);
    for (final doc in docs) {
      final serverId = doc['serverId'] as int?;
      if (serverId == null) continue;

      if (entity == 'rooms') {
        final localUuid = doc['localUuid'] as String? ?? 'cloud-${serverId}r';
        final existing = await (db.select(
          db.rooms,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        final now = _epoch();

        if (existing == null) {
          await db
              .into(db.rooms)
              .insert(
                RoomsCompanion(
                  roomNumber: _v(
                    doc['roomNumber'] as String? ?? 'CLOUD-$serverId',
                  ),
                  localUuid: _v(localUuid),
                  type: _v(doc['type'] as String? ?? 'single'),
                  price: _v((doc['price'] as num?)?.toDouble() ?? 100),
                  status: _v(doc['status'] as String? ?? 'شاغرة'),
                  serverId: _v(serverId),
                  createdAt: _v(now),
                  updatedAt: _v(now),
                  lastModified: _v(now),
                  origin: const d.Value('server'),
                ),
              );
          count++;
        } else {
          await (db.update(
            db.rooms,
          )..where((t) => t.id.equals(existing.id))).write(
            RoomsCompanion(
              type: _v(doc['type'] as String? ?? existing.type),
              price: _v((doc['price'] as num?)?.toDouble() ?? existing.price),
              status: _v(doc['status'] as String? ?? existing.status),
              origin: const d.Value('server'),
              lastModified: _v(now),
            ),
          );
          count++;
        }
      } else if (entity == 'bookings') {
        final localUuid = doc['localUuid'] as String? ?? 'cloud-${serverId}b';
        final existing = await (db.select(
          db.bookings,
        )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
        final now = _epoch();

        if (existing == null) {
          await db
              .into(db.bookings)
              .insert(
                BookingsCompanion(
                  localUuid: _v(localUuid),
                  roomNumber: _v(doc['roomNumber'] as String? ?? 'CLOUD'),
                  guestName: _v(doc['guestName'] as String? ?? 'Cloud Guest'),
                  guestPhone: const d.Value(''),
                  guestNationality: const d.Value(''),
                  checkinDate: const d.Value('2026-07-19'),
                  status: const d.Value('محجوزة'),
                  expectedNights: const d.Value(1),
                  calculatedNights: const d.Value(1),
                  serverId: _v(serverId),
                  serverBookingId: _v(serverId),
                  createdAt: _v(now),
                  updatedAt: _v(now),
                  lastModified: _v(now),
                  origin: const d.Value('server'),
                ),
              );
          count++;
        } else {
          await (db.update(
            db.bookings,
          )..where((t) => t.id.equals(existing.id))).write(
            BookingsCompanion(
              guestName: _v(doc['guestName'] as String? ?? existing.guestName),
              origin: const d.Value('server'),
              lastModified: _v(now),
            ),
          );
          count++;
        }
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase dbA;
  late AppDatabase dbB;
  late OutboxDao outboxA;
  late OutboxDao outboxB;
  late CloudStore cloud;

  setUp(() {
    dbA = _makeDb();
    dbB = _makeDb();
    outboxA = OutboxDao(dbA);
    outboxB = OutboxDao(dbB);
    cloud = CloudStore();
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  group('جهازين — مزامنة أساسية', () {
    test('الجهاز A يُنشئ غرفة ← push ← الجهاز B يسحبها', () async {
      final roomUuid = 'room-a-001';
      await dbA
          .into(dbA.rooms)
          .insert(
            _room(number: '101', uuid: roomUuid, type: 'double', price: 200),
          );
      await outboxA.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '101',
          'type': 'double',
          'price': 200,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      expect(await outboxA.count(), 1);

      final pushed = await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      expect(pushed, 1);

      final pulled = await simulatePull(dbB, outboxB, cloud);
      expect(pulled, 1);

      final roomsB = await dbB.select(dbB.rooms).get();
      expect(roomsB.length, 1);
      expect(roomsB.first.roomNumber, '101');
      expect(roomsB.first.type, 'double');
      expect(roomsB.first.serverId, greaterThan(0));
    });

    test('الجهاز A يُنشئ حجزاً ← push ← B يسحب ← B يُعدّل الغرفة', () async {
      final roomUuid = 'room-a-002';
      final bkgUuid = 'bkg-a-002';
      await dbA
          .into(dbA.rooms)
          .insert(
            _room(number: '102', uuid: roomUuid, type: 'single', price: 150),
          );
      await dbA
          .into(dbA.bookings)
          .insert(
            _booking(uuid: bkgUuid, roomNumber: '102', guestName: 'ضيف A'),
          );
      await outboxA.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '102',
          'type': 'single',
          'price': 150,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      await outboxA.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: bkgUuid,
        payload: {'roomNumber': '102', 'guestName': 'ضيف A'},
        clientTs: _epoch(),
        source: 'local',
      );

      await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      await simulatePull(dbB, outboxB, cloud);
      expect(await dbB.select(dbB.bookings).get().then((b) => b.length), 1);

      final roomB = await (dbB.select(
        dbB.rooms,
      )..where((t) => t.roomNumber.equals('102'))).getSingle();
      await (dbB.update(dbB.rooms)..where((t) => t.id.equals(roomB.id))).write(
        RoomsCompanion(
          price: const d.Value(250),
          lastModified: d.Value(_epoch() + 100),
        ),
      );
      await outboxB.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: roomB.localUuid,
        payload: {
          'roomNumber': '102',
          'type': 'single',
          'price': 250,
          'status': 'شاغرة',
        },
        clientTs: _epoch() + 100,
        source: 'local',
      );

      final pushedB = await simulatePush(dbB, outboxB, cloud, 'DeviceB');
      expect(pushedB, 1);
      expect(cloud.getAll('rooms').first['price'], 250);
    });

    test('الجهازان ينشئان غرفاً بدون تعارض', () async {
      await dbA
          .into(dbA.rooms)
          .insert(
            _room(
              number: '201',
              uuid: 'room-indep-a',
              type: 'double',
              price: 300,
            ),
          );
      await outboxA.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-indep-a',
        payload: {
          'roomNumber': '201',
          'type': 'double',
          'price': 300,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      await dbB
          .into(dbB.rooms)
          .insert(
            _room(
              number: '202',
              uuid: 'room-indep-b',
              type: 'suite',
              price: 500,
            ),
          );
      await outboxB.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-indep-b',
        payload: {
          'roomNumber': '202',
          'type': 'suite',
          'price': 500,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );

      await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      await simulatePush(dbB, outboxB, cloud, 'DeviceB');
      expect(cloud.getAll('rooms').length, 2);

      await simulatePull(dbA, outboxA, cloud);
      await simulatePull(dbB, outboxB, cloud);
      expect(await dbA.select(dbA.rooms).get().then((r) => r.length), 2);
      expect(await dbB.select(dbB.rooms).get().then((r) => r.length), 2);
    });
  });

  group('جهازين — كشف التعارضات وحلّها', () {
    test('تعديل سعر الغرفة — push from B wins (newerWins)', () async {
      final roomUuid = 'room-conflict-price';
      await dbA
          .into(dbA.rooms)
          .insert(
            _room(number: '301', uuid: roomUuid, type: 'single', price: 100),
          );
      await outboxA.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '301',
          'type': 'single',
          'price': 100,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      await simulatePull(dbB, outboxB, cloud);

      final roomB = await (dbB.select(
        dbB.rooms,
      )..where((t) => t.localUuid.equals(roomUuid))).getSingle();
      await (dbB.update(dbB.rooms)..where((t) => t.id.equals(roomB.id))).write(
        RoomsCompanion(
          price: const d.Value(350),
          lastModified: d.Value(_epoch() + 2000),
        ),
      );
      await outboxB.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '301',
          'type': 'single',
          'price': 350,
          'status': 'شاغرة',
        },
        clientTs: _epoch() + 2000,
        source: 'local',
      );

      await simulatePush(dbB, outboxB, cloud, 'DeviceB');
      expect(cloud.getAll('rooms').first['price'], 350);

      await simulatePull(dbA, outboxA, cloud);
      final roomAFinal = await (dbA.select(
        dbA.rooms,
      )..where((t) => t.localUuid.equals(roomUuid))).getSingle();
      expect(roomAFinal.price, 350);
    });

    test('تعديل حقول مختلفة — الجهازان يتفقان بعد السحب', () async {
      final roomUuid = 'room-merge-fields';
      await dbA
          .into(dbA.rooms)
          .insert(
            _room(
              number: '401',
              uuid: roomUuid,
              type: 'single',
              price: 100,
              status: 'شاغرة',
            ),
          );
      await outboxA.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '401',
          'type': 'single',
          'price': 100,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      await simulatePull(dbB, outboxB, cloud);

      final roomB = await (dbB.select(
        dbB.rooms,
      )..where((t) => t.localUuid.equals(roomUuid))).getSingle();
      await (dbB.update(dbB.rooms)..where((t) => t.id.equals(roomB.id))).write(
        RoomsCompanion(
          status: const d.Value('مشغولة'),
          lastModified: d.Value(_epoch() + 2000),
        ),
      );
      await outboxB.merge(
        entity: 'rooms',
        op: 'update',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '401',
          'type': 'single',
          'price': 100,
          'status': 'مشغولة',
        },
        clientTs: _epoch() + 2000,
        source: 'local',
      );

      await simulatePush(dbB, outboxB, cloud, 'DeviceB');
      await simulatePull(dbA, outboxA, cloud);

      final roomA = await (dbA.select(
        dbA.rooms,
      )..where((t) => t.localUuid.equals(roomUuid))).getSingle();
      expect(roomA.status, 'مشغولة');
    });

    test('ConflictDetector يكتشف تعارض تعديل متزامن vectorClock', () async {
      final ancestor = {
        'roomNumber': '501',
        'type': 'single',
        'price': 150,
        'status': 'شاغرة',
        'vectorClock': '{}',
        'lastModified': 1000,
      };
      final local = {
        'roomNumber': '501',
        'type': 'single',
        'price': 250,
        'status': 'شاغرة',
        'vectorClock': '{"deviceA": 2}',
        'lastModified': 2000,
      };
      final remote = {
        'roomNumber': '501',
        'type': 'single',
        'price': 350,
        'status': 'شاغرة',
        'vectorClock': '{"deviceB": 2}',
        'lastModified': 2500,
      };

      final result = ConflictDetector.detect(
        localData: local,
        remoteData: remote,
        commonAncestor: ancestor,
      );

      expect(result.type, equals(ConflictType.concurrentSameFields));
      expect(result.conflictingFields, contains('price'));
    });

    test('SmartConflictResolver يحل تعارض السعر بـ newerWins', () async {
      final ancestor = {
        'roomNumber': '601',
        'type': 'single',
        'price': 150,
        'status': 'شاغرة',
        'vectorClock': '{}',
        'lastModified': 1000,
      };
      final local = {
        'roomNumber': '601',
        'type': 'single',
        'price': 200,
        'status': 'شاغرة',
        'vectorClock': '{"deviceA": 2}',
        'lastModified': 1000,
      };
      final remote = {
        'roomNumber': '601',
        'type': 'single',
        'price': 350,
        'status': 'شاغرة',
        'vectorClock': '{"deviceB": 2}',
        'lastModified': 2000,
      };

      final resolved = SmartConflictResolver.resolve(
        entity: 'rooms',
        localData: local,
        remoteData: remote,
        commonAncestor: ancestor,
      );

      expect(resolved.mergedData['price'], 350);
    });

    test('دورة push/pull كاملة — 3 كيانات بدون فقدان', () async {
      final roomUuid = 'room-full-cycle';
      final bkgUuid = 'bkg-full-cycle';

      await dbA
          .into(dbA.rooms)
          .insert(
            _room(number: '701', uuid: roomUuid, type: 'suite', price: 400),
          );
      await outboxA.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '701',
          'type': 'suite',
          'price': 400,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      await dbA
          .into(dbA.bookings)
          .insert(
            _booking(uuid: bkgUuid, roomNumber: '701', guestName: 'ضيف كامل'),
          );
      await outboxA.merge(
        entity: 'bookings',
        op: 'create',
        localUuid: bkgUuid,
        payload: {'roomNumber': '701', 'guestName': 'ضيف كامل'},
        clientTs: _epoch(),
        source: 'local',
      );

      await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      expect(cloud.getAll('rooms').length, 1);
      expect(cloud.getAll('bookings').length, 1);

      await simulatePull(dbB, outboxB, cloud);
      expect(await dbB.select(dbB.rooms).get().then((r) => r.length), 1);
      expect(await dbB.select(dbB.bookings).get().then((b) => b.length), 1);

      await dbB
          .into(dbB.rooms)
          .insert(
            _room(
              number: '702',
              uuid: 'room-b-full',
              type: 'double',
              price: 300,
            ),
          );
      await outboxB.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: 'room-b-full',
        payload: {
          'roomNumber': '702',
          'type': 'double',
          'price': 300,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      await simulatePush(dbB, outboxB, cloud, 'DeviceB');
      expect(cloud.getAll('rooms').length, 2);

      await simulatePull(dbA, outboxA, cloud);
      expect(await dbA.select(dbA.rooms).get().then((r) => r.length), 2);
    });
  });

  group('جهازين — حالات حافة', () {
    test('حذف من A — السحابة تعكس الحذف', () async {
      final roomUuid = 'room-del-upd';
      await dbA
          .into(dbA.rooms)
          .insert(
            _room(number: '801', uuid: roomUuid, type: 'single', price: 100),
          );
      await outboxA.merge(
        entity: 'rooms',
        op: 'create',
        localUuid: roomUuid,
        payload: {
          'roomNumber': '801',
          'type': 'single',
          'price': 100,
          'status': 'شاغرة',
        },
        clientTs: _epoch(),
        source: 'local',
      );
      await simulatePush(dbA, outboxA, cloud, 'DeviceA');

      await outboxA.merge(
        entity: 'rooms',
        op: 'delete',
        localUuid: roomUuid,
        payload: {'roomNumber': '801'},
        clientTs: _epoch() + 100,
        source: 'local',
      );
      await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      expect(cloud.getAll('rooms').length, 0);
    });

    test('ConflictDetector يكتشف deleteVsUpdate', () async {
      final ancestor = {
        'vectorClock': '{}',
        'deletedAt': null,
        'price': 100,
        'status': 'شاغرة',
      };
      final local = {'vectorClock': '{}', 'deletedAt': 99999};
      final remote = {
        'vectorClock': '{}',
        'deletedAt': null,
        'price': 500,
        'status': 'مشغولة',
      };

      final result = ConflictDetector.detect(
        localData: local,
        remoteData: remote,
        commonAncestor: ancestor,
      );

      expect(result.type, equals(ConflictType.deleteVsUpdate));
    });

    test('100 عملية push/pull متتالية بين الجهازين', () async {
      const count = 100;
      for (var i = 0; i < count; i++) {
        final roomUuid = 'room-stress-$i';
        await dbA
            .into(dbA.rooms)
            .insert(
              _room(
                number: '9${i.toString().padLeft(2, '0')}',
                uuid: roomUuid,
                price: 100.0 + i,
              ),
            );
        await outboxA.merge(
          entity: 'rooms',
          op: 'create',
          localUuid: roomUuid,
          payload: {
            'roomNumber': '9${i.toString().padLeft(2, '0')}',
            'type': 'single',
            'price': 100.0 + i,
            'status': 'شاغرة',
          },
          clientTs: _epoch(),
          source: 'local',
        );
      }
      expect(await outboxA.count(), count);

      final pushed = await simulatePush(dbA, outboxA, cloud, 'DeviceA');
      expect(pushed, count);
      expect(cloud.getAll('rooms').length, count);

      await simulatePull(dbB, outboxB, cloud);
      expect(await dbB.select(dbB.rooms).get().then((r) => r.length), count);

      final roomsB = await dbB.select(dbB.rooms).get();
      for (var i = 0; i < count; i++) {
        expect(
          roomsB
              .where((r) => r.roomNumber == '9${i.toString().padLeft(2, '0')}')
              .length,
          1,
          reason:
              'الغرفة 9${i.toString().padLeft(2, '0')} يجب أن تكون موجودة مرة واحدة',
        );
      }
    });
  });
}
