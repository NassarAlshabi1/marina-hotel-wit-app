// ═══════════════════════════════════════════════════════════════
//  remote_change_notifier_test.dart
//  Tests for RemoteChangeNotifier — local notifications on
//  cross-device changes
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/local_notification_service.dart';
import 'package:marina_hotel_mobile/services/remote_change_notifier.dart';

class _CapturedNotification {
  _CapturedNotification({
    required this.title,
    required this.body,
    this.payload,
  });
  final String title;
  final String body;
  final String? payload;
}

// ignore: library_private_types_in_public_api
final List<_CapturedNotification> capturedNotifications =
    <_CapturedNotification>[];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    capturedNotifications.clear();

    LocalNotificationService.instance.setTestingCapture((title, body, payload) {
      capturedNotifications.add(
        _CapturedNotification(
          title: title,
          body: body,
          payload: payload,
        ),
      );
    });

    unawaited(RemoteChangeNotifier.instance.clearDedupForTesting());
  });

  tearDown(() {
    LocalNotificationService.instance.setTestingCapture(null);
  });

  group('Scenario 1: cross-device change triggers notification', () {
    test('cross-device change → 1 notification', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: {
          'local_uuid': 'booking-001',
          'updated_at': 1785549900,
          'device_id': 'device_B',
          'room_number': '101',
          'guest_name': 'أحمد',
        },
        op: 'create',
      );

      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(1));
      expect(capturedNotifications.first.title, contains('جهاز آخر'));
      expect(
        capturedNotifications.first.payload,
        startsWith('remote_change:bookings:'),
      );
    });
  });

  group('Scenario 2: same-device change → no notification', () {
    test('same-device change → 0 notifications', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: {
          'local_uuid': 'booking-002',
          'updated_at': 1785549900,
          'device_id': 'device_A',
          'room_number': '102',
        },
        op: 'create',
      );

      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(0));
    });

    test('empty device_id → 0 notifications', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: {
          'local_uuid': 'booking-003',
          'updated_at': 1785549900,
          'device_id': '',
        },
        op: 'create',
      );

      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(0));
    });
  });

  group('Scenario 3: duplicate delivery → one notification', () {
    test('duplicate delivery → 1 notification (dedup)', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      final record = {
        'local_uuid': 'booking-004',
        'updated_at': 1785549900,
        'device_id': 'device_B',
        'room_number': '103',
      };

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: record,
        op: 'create',
      );
      RemoteChangeNotifier.instance.flushForTesting();
      expect(capturedNotifications.length, equals(1));

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: record,
        op: 'create',
      );
      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(1));
    });
  });

  group('Scenario 4: aggregation prevents spam', () {
    test('5 changes aggregated → 1 notification', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      for (var i = 0; i < 5; i++) {
        await RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: 'bookings',
          record: {
            'local_uuid': 'booking-batch-$i',
            'updated_at': 1785549900 + i,
            'device_id': 'device_B',
            'room_number': '${200 + i}',
          },
          op: 'create',
        );
      }

      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(1));
      expect(capturedNotifications.first.title, contains('5'));
    });

    test('separated changes → 2 notifications', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: {
          'local_uuid': 'booking-005',
          'updated_at': 1785549900,
          'device_id': 'device_B',
          'room_number': '301',
        },
        op: 'create',
      );
      RemoteChangeNotifier.instance.flushForTesting();
      expect(capturedNotifications.length, equals(1));

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'payments',
        record: {
          'local_uuid': 'payment-005',
          'updated_at': 1785549901,
          'device_id': 'device_B',
          'amount': 500,
        },
        op: 'create',
      );
      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(2));
    });
  });

  group('Scenario 5: persistent dedup across restart', () {
    test('restart + re-process → no duplicate', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      final record = {
        'local_uuid': 'booking-006',
        'updated_at': 1785549900,
        'device_id': 'device_B',
        'room_number': '401',
      };

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: record,
        op: 'create',
      );
      RemoteChangeNotifier.instance.flushForTesting();
      expect(capturedNotifications.length, equals(1));

      final prefs = await SharedPreferences.getInstance();
      final savedKeys = prefs.getStringList('remote_change_dedup_keys');
      expect(savedKeys, isNotNull);
      expect(savedKeys!.length, equals(1));
      expect(
        savedKeys.first,
        equals('bookings:booking-006:1785549900:device_B'),
      );

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: record,
        op: 'create',
      );
      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(1));
    });
  });

  group('Scenario 6: tap handler payload', () {
    test('single payload format', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'payments',
        record: {
          'local_uuid': 'payment-007',
          'updated_at': 1785549900,
          'device_id': 'device_B',
          'amount': 750,
        },
        op: 'create',
      );
      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(1));
      final payload = capturedNotifications.first.payload!;
      expect(payload, equals('remote_change:payments:payment-007'));
    });

    test('aggregated payload format', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      for (var i = 0; i < 3; i++) {
        await RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: 'expenses',
          record: {
            'local_uuid': 'expense-batch-$i',
            'updated_at': 1785549900 + i,
            'device_id': 'device_B',
            'amount': 100 + i,
          },
          op: 'create',
        );
      }
      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(1));
      final payload = capturedNotifications.first.payload!;
      expect(payload, equals('remote_change:expenses:multiple'));
    });
  });

  group('Edge cases', () {
    test('LRU cap (600 keys → ≤500)', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      for (var i = 0; i < 600; i++) {
        await RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: 'bookings',
          record: {
            'local_uuid': 'uuid-$i',
            'updated_at': 1785549900 + i,
            'device_id': 'device_B',
          },
          op: 'create',
        );
      }
      RemoteChangeNotifier.instance.flushForTesting();

      expect(
        RemoteChangeNotifier.instance.dedupKeysCount,
        lessThanOrEqualTo(500),
      );
    });

    test('different devices same record → 2 notifications', () async {
      RemoteChangeNotifier.instance.setMyDeviceIdForTesting('device_A');

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: {
          'local_uuid': 'booking-shared',
          'updated_at': 1785549900,
          'device_id': 'device_B',
        },
        op: 'update',
      );
      RemoteChangeNotifier.instance.flushForTesting();
      expect(capturedNotifications.length, equals(1));

      await RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: 'bookings',
        record: {
          'local_uuid': 'booking-shared',
          'updated_at': 1785549901,
          'device_id': 'device_C',
        },
        op: 'update',
      );
      RemoteChangeNotifier.instance.flushForTesting();

      expect(capturedNotifications.length, equals(2));
    });
  });
}
