// test/unit/payload_normalizer_test.dart
//
// اختبارات مُطبِّع حمولة الدفع إلى Cloudflare D1 (عقد السلك).
//
// المرجع: FIELD_TYPE_MATCH_AUDIT (2026-09-05) — الـ worker لا يفهم إلا
// snake_case (يرشّح المفاتيح مقابل أعمدة D1 الفعلية) ويقرأ الهوية من
// data.local_uuid، وكانت حمولات outbox camelCase تُسقَط بصمت.

import 'dart:convert';

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
          entity: 'rooms',
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
            payload: {
              'vector_clock': '{"dev-x":9}',
              'username': 'ahmed',
            },
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
}

/// OutboxData حقيقية كما يولّدها Drift (نفس الصف المقروء من outbox).
OutboxData _outboxItem({
  required Map<String, dynamic> payload,
  required String localUuid,
  String entity = 'rooms',
  String op = 'create',
}) {
  final clientTs = 1720000000;
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
