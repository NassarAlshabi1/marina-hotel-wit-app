// test/unit/payload_normalizer_test.dart
//
// اختبارات مُطبِّع حمولة الدفع إلى Cloudflare D1 (عقد السلك).
//
// المرجع: FIELD_TYPE_MATCH_AUDIT (2026-09-05) — الـ worker لا يفهم إلا
// snake_case (يرشّح المفاتيح مقابل أعمدة D1 الفعلية) ويقرأ الهوية من
// data.local_uuid، وكانت حمولات outbox camelCase تُسقَط بصمت.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/payload_normalizer.dart';

void main() {
  group('PayloadNormalizer.toSnakeCase', () {
    test('يحوّل camelCase إلى snake_case', () {
      expect(PayloadNormalizer.toSnakeCase('localUuid'), 'local_uuid');
      expect(PayloadNormalizer.toSnakeCase('hotelDayKey'), 'hotel_day_key');
      expect(
        PayloadNormalizer.toSnakeCase('idempotencyKey'),
        'idempotency_key',
      );
      expect(
        PayloadNormalizer.toSnakeCase('receivedByUserId'),
        'received_by_user_id',
      );
    });

    test('idempotent — snake_case لا يتغير', () {
      expect(PayloadNormalizer.toSnakeCase('local_uuid'), 'local_uuid');
      expect(
        PayloadNormalizer.toSnakeCase('created_at_epoch'),
        'created_at_epoch',
      );
      expect(PayloadNormalizer.toSnakeCase('amount'), 'amount');
      expect(PayloadNormalizer.toSnakeCase('price'), 'price');
    });

    test('كلمة واحدة تبقى كما هي', () {
      for (final k in ['name', 'status', 'version', 'origin', 'reason']) {
        expect(PayloadNormalizer.toSnakeCase(k), k);
      }
    });
  });

  group('PayloadNormalizer.normalize', () {
    test('يحوّل المفاتيح ويحافظ على القيم', () {
      final out = PayloadNormalizer.normalize({
        'localUuid': 'u-1',
        'guestName': 'ضيف',
        'amount': 1500.75,
        'isActive': true,
        'isVoided': false,
        'serverId': null,
      });
      expect(out['local_uuid'], 'u-1');
      expect(out['guest_name'], 'ضيف');
      expect(out['amount'], 1500.75);
      // bool → INTEGER (0/1) — D1 يرفض ربط booleans
      expect(out['is_active'], 1);
      expect(out['is_voided'], 0);
      expect(out['server_id'], isNull);
    });

    test('لا يلمس مفاتيح snake_case الأصلية', () {
      final payload = {
        'local_uuid': 'u-2',
        'hotel_day_key': '2026-09-05',
        'vector_clock': '{"d1":3}',
      };
      final out = PayloadNormalizer.normalize(payload);
      expect(out.keys, containsAll(payload.keys));
      expect(out['vector_clock'], '{"d1":3}');
    });

    test('قيم JSON النصية (بيانات لا أعمدة) تمر حرفياً', () {
      // applied_adjustments_json قيمة بيانات — مفاتيحها الداخلية camelCase
      // ويجب ألا تُمس لأنها ليست أسماء أعمدة.
      final inner = jsonEncode([
        {'uuid': 'a-1', 'amountPerNight': 50},
      ]);
      final out = PayloadNormalizer.normalize({
        'appliedAdjustmentsJson': inner,
        'localUuid': 'n-1',
      });
      expect(out['applied_adjustments_json'], inner);
      expect(out['applied_adjustments_json'], contains('amountPerNight'));
      expect(out['local_uuid'], 'n-1');
    });

    test('المدخل غير مُعدَّل (يعيد خريطة جديدة)', () {
      final input = {'guestName': 'x'};
      PayloadNormalizer.normalize(input);
      expect(input.containsKey('guestName'), isTrue);
    });
  });

  group('buildPushOperation — عقد الدفع الكامل', () {
    test('يحقن local_uuid من صف outbox عندما تغيب الحمولة', () async {
      // الحمولات الرقيقة (soft-deletes القديمة {'id': 42}) بلا هوية —
      // requireEntityId (worker/src/sync.ts:60) كان يرميها validation_error.
      final op = await buildPushOperation(
        _outboxItem(payload: {'id': 42}, localUuid: 'row-uuid-1'),
        resolveRowVectorClock: (_, __) async => null,
      );
      final data = op['data'] as Map<String, dynamic>;
      expect(data['local_uuid'], 'row-uuid-1');
      expect(op['vectorClock'], '{}');
    });

    test('local_uuid الموجود في الحمولة يفوق قيمة الصف', () async {
      final op = await buildPushOperation(
        _outboxItem(
          payload: {'localUuid': 'payload-uuid'},
          localUuid: 'row-uuid',
        ),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect(
        (op['data'] as Map<String, dynamic>)['local_uuid'],
        'payload-uuid',
      );
    });

    test('يسحب ساعة المتجه من صف الكيان عبر المحلِّل', () async {
      final op = await buildPushOperation(
        _outboxItem(
          payload: {'roomNumber': '101'},
          localUuid: 'room-uuid',
        ),
        resolveRowVectorClock: (entity, uuid) async {
          expect(entity, 'rooms');
          expect(uuid, 'room-uuid');
          return '{"dev-a":4}';
        },
      );
      expect(op['vectorClock'], '{"dev-a":4}');
      expect(
        (op['data'] as Map<String, dynamic>)['vector_clock'],
        '{"dev-a":4}',
      );
    });

    test(
      'vector_clock داخل الحمولة (عقد app_users) يفوق محلِّل الصف',
      () async {
        final op = await buildPushOperation(
          _outboxItem(
            payload: {'vector_clock': '{"dev-x":9}', 'username': 'ahmed'},
            localUuid: 'user-1',
          ),
          resolveRowVectorClock: (_, __) async => '{"should-not-win":1}',
        );
        expect(op['vectorClock'], '{"dev-x":9}');
      },
    );

    test(
      'يبني حقول العملية كاملة (idempotencyKey/entity/operation/updatedAt)',
      () async {
        final item = _outboxItem(
          payload: {'guestName': 'علي'},
          localUuid: 'b-1',
          entity: 'bookings',
          op: 'update',
        );
        final op = await buildPushOperation(
          item,
          resolveRowVectorClock: (_, __) async => null,
        );
        expect(op['idempotencyKey'], item.idempotencyKey);
        expect(op['entity'], 'bookings');
        expect(op['operation'], 'update');
        expect(op['updatedAt'], item.clientTs);
        final data = op['data'] as Map<String, dynamic>;
        // camelCase حمولة adapter-based تُطبع snake قبل الإرسال
        expect(data['guest_name'], 'علي');
        expect(data.containsKey('guestName'), isFalse);
      },
    );
  });

  group('تكافؤ PushWireContract (أندرويد) — مطابقة حرفية', () {
    // كل توقع هنا مأخوذ حرفياً من
    // mobile/android/.../data/remote/PushWireContract.kt على فرع
    // agent/android-cloudflare — لا اجتهاد.

    test('mapOperation: insert/create/upsert ⇒ create', () {
      for (final op in ['insert', 'create', 'upsert', ' INSERT ']) {
        expect(mapOperation(op), 'create', reason: op);
      }
    });

    test('mapOperation: update/edit ⇒ update و soft_delete ⇒ delete', () {
      for (final op in ['update', 'edit', ' UPDATE ']) {
        expect(mapOperation(op), 'update', reason: op);
      }
      for (final op in ['delete', 'soft_delete', 'softdelete']) {
        expect(mapOperation(op), 'delete', reason: op);
      }
      // غير المعروف يمر مُطبَّعاً كما في Kotlin (`else -> lowercase()`)
      // — الـWorker يرفضه برسالة صريحة بدل تخمين الاسم.
      expect(mapOperation('BoGuS'), 'bogus');
    });

    test('canonicalEntity: blacklist_entries ⇒ blacklist', () {
      expect(canonicalEntity('blacklist_entries'), 'blacklist');
      expect(canonicalEntity(' rooms '), 'rooms');
      expect(canonicalEntity('invoices'), 'invoices');
    });

    test('buildPushOperation يطبّق canonicalEntity + mapOperation', () async {
      final op = await buildPushOperation(
        _outboxItem(
          payload: {'id': 7},
          localUuid: 'x-1',
          entity: 'blacklist_entries',
          op: 'insert',
        ),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect(op['entity'], 'blacklist');
      expect(op['operation'], 'create');
    });

    test(
      'فصل الموظف: employee_uuid فارغ ⇒ clear_employee_link=1 والرأس مرفوع',
      () async {
        final op = await buildPushOperation(
          _outboxItem(
            payload: {'amount': 10, 'employeeUuid': ''},
            localUuid: 'e-1',
            entity: 'expenses',
            op: 'update',
          ),
          resolveRowVectorClock: (_, __) async => null,
        );
        final data = op['data'] as Map<String, dynamic>;
        expect(data.containsKey('employee_uuid'), isFalse);
        expect(data['clear_employee_link'], 1);
      },
    );

    test('الفراغ الغائب أو غير update/expenses لا يمسح الربط أبداً', () async {
      // (1) بلا مفتاح أصلاً
      final a = await buildPushOperation(
        _outboxItem(
          payload: {'amount': 1},
          localUuid: 'a-1',
          entity: 'expenses',
          op: 'update',
        ),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect((a['data'] as Map).containsKey('clear_employee_link'), isFalse);

      // (2) قيمة حقيقية تبقى كما هي
      final b = await buildPushOperation(
        _outboxItem(
          payload: {'employeeUuid': 'emp-1'},
          localUuid: 'b-1',
          entity: 'expenses',
          op: 'update',
        ),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect((b['data'] as Map)['employee_uuid'], 'emp-1');
      expect((b['data'] as Map).containsKey('clear_employee_link'), isFalse);

      // (3) عملية إنشاء لا تفعّل العلامة
      final c = await buildPushOperation(
        _outboxItem(
          payload: {'employeeUuid': ''},
          localUuid: 'c-1',
          entity: 'expenses',
          op: 'create',
        ),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect((c['data'] as Map).containsKey('clear_employee_link'), isFalse);
    });

    test('تطبيع طوابع الصادر: ميلي ⇒ ثوانٍ في الأعمدة الستة فقط', () async {
      final op = await buildPushOperation(
        _outboxItem(
          payload: {
            'last_modified': 1760000000000,
            'created_at': '1760000000000',
            'updated_at': 1760000000,
            // ليسا عمودي طابع ⇒ يمرّان كما هما (withdraw_date ميلي بعمد)
            'withdraw_date': 1760000000000,
            'amount': 1760000000000,
            'localUuid': 'p-1',
          },
          localUuid: 'p-1',
          entity: 'salary_withdrawals',
          op: 'update',
        ),
        resolveRowVectorClock: (_, __) async => null,
      );
      final data = op['data'] as Map<String, dynamic>;
      expect(data['last_modified'], 1760000000);
      expect(data['created_at'], 1760000000);
      expect(data['updated_at'], 1760000000);
      expect(data['withdraw_date'], 1760000000000);
      expect(data['amount'], 1760000000000);
    });

    test('updatedAt يُوحَّد إلى ثوانٍ عند تجاوز عتبة 1e11', () async {
      final op = await buildPushOperation(
        _outboxItem(
          payload: {'roomNumber': '101'},
          localUuid: 'u-1',
          clientTs: 1760000000000,
        ),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect(op['updatedAt'], 1760000000);
    });

    test('updatedAt بالثواني (صندوق Dart) يبقى كما هو', () async {
      final op = await buildPushOperation(
        _outboxItem(payload: {'roomNumber': '101'}, localUuid: 'u-2'),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect(op['updatedAt'], 1720000000);
    });

    test('deviceId: مقدَّم يُرسَل، وغائب أو فارغ ⇒ unknown-origin', () async {
      final present = await buildPushOperation(
        _outboxItem(payload: {}, localUuid: 'd-1'),
        resolveRowVectorClock: (_, __) async => null,
        deviceId: 'dev-1',
      );
      expect(present['deviceId'], 'dev-1');

      final absent = await buildPushOperation(
        _outboxItem(payload: {}, localUuid: 'd-2'),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect(absent['deviceId'], 'unknown-origin');

      final blank = await buildPushOperation(
        _outboxItem(payload: {}, localUuid: 'd-3'),
        resolveRowVectorClock: (_, __) async => null,
        deviceId: '   ',
      );
      expect(blank['deviceId'], 'unknown-origin');
    });

    test('local_uuid نص فارغ ⇒ يُحقن من صف outbox (isNullOrBlank)', () async {
      final op = await buildPushOperation(
        _outboxItem(payload: {'local_uuid': ''}, localUuid: 'row-9'),
        resolveRowVectorClock: (_, __) async => null,
      );
      expect((op['data'] as Map)['local_uuid'], 'row-9');
    });

    test(
      'idempotencyKey غائبة أو فارغة ⇒ احتياط entity_op_localUuid',
      () async {
        final nullKey = _outboxItem(
          payload: {},
          localUuid: 'k-1',
          entity: 'bookings',
          op: 'update',
        ).copyWith(idempotencyKey: const Value<String?>(null));
        final opA = await buildPushOperation(
          nullKey,
          resolveRowVectorClock: (_, __) async => null,
        );
        expect(opA['idempotencyKey'], 'bookings_update_k-1');

        final blankKey = nullKey.copyWith(
          idempotencyKey: const Value<String?>('  '),
        );
        final opB = await buildPushOperation(
          blankKey,
          resolveRowVectorClock: (_, __) async => null,
        );
        expect(opB['idempotencyKey'], 'bookings_update_k-1');
      },
    );
  });
}

/// OutboxData حقيقية كما يولّدها Drift (نفس الصف المقروء من outbox).
OutboxData _outboxItem({
  required Map<String, dynamic> payload,
  required String localUuid,
  String entity = 'rooms',
  String op = 'create',
  int clientTs = 1720000000,
}) {
  return OutboxData(
    id: 1,
    entity: entity,
    op: op,
    localUuid: localUuid,
    payload: jsonEncode(payload),
    clientTs: clientTs,
    attempts: 0,
    processingStatus: 'pending',
    source: 'local',
    deliveredToPrimary: false,
    deliveredToSecondary: true,
    primaryProcessingStatus: 'pending',
    primaryAttempts: 0,
    secondaryProcessingStatus: 'pending',
    secondaryAttempts: 0,
    payloadVersion: 1,
    idempotencyKey: '$entity:$op:$localUuid:$clientTs',
  );
}
