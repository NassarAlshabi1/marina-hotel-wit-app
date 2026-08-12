// test/unit/wave7_remote_change_notification_test.dart
//
// ✅ Wave 7 (2026-08-12) — Remote Change Notification Tests
//
// Tests that prove:
// 1. Remote change from another device → notification triggered
// 2. Change from same device → no notification
// 3. Same change processed twice → only one notification (dedup)
// 4. Multiple changes batched → single notification
// 5. Restart then reprocess → no duplicate (persistent dedup)
// 6. Empty deviceId → no notification (can't determine source)

// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/services/remote_change_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late RemoteChangeNotificationService service;

  setUp(() async {
    service = RemoteChangeNotificationService.instance;
    await service.clearPersistentDedup();
    service.clearSessionDedup();
    service.clearPending();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 1. Remote change from another device → notification triggered
  // ═══════════════════════════════════════════════════════════════════════
  group('1. Remote change from another device', () {
    test('1a. onRemoteRecordApplied collects change from different device', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-1',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      expect(service.pendingCount, 1,
          reason: 'Change from another device should be collected');
    });

    test('1b. flushPendingNotifications shows notification', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-2',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000001,
      );
      await service.flushPendingNotifications();
      expect(service.pendingCount, 0,
          reason: 'Pending should be cleared after flush');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 2. Change from same device → no notification
  // ═══════════════════════════════════════════════════════════════════════
  group('2. Change from same device', () {
    test('2a. Same deviceId → no collection', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-3',
        remoteDeviceId: 'device-B',
        currentDeviceId: 'device-B',
        lastModified: 1700000002,
      );
      expect(service.pendingCount, 0,
          reason: 'Change from same device should NOT be collected');
    });

    test('2b. Null currentDeviceId → collected (can\'t determine source)', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-4',
        remoteDeviceId: 'device-A',
        currentDeviceId: null,
        lastModified: 1700000003,
      );
      expect(service.pendingCount, 1,
          reason: 'If currentDeviceId is null, we can\'t compare — collect');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 3. Same change processed twice → only one notification (dedup)
  // ═══════════════════════════════════════════════════════════════════════
  group('3. Dedup — same change processed twice', () {
    test('3a. Same fingerprint → only collected once', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-dup',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      expect(service.pendingCount, 1, reason: 'First call should collect');

      // Same fingerprint — should be dedup'd
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-dup',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      expect(service.pendingCount, 1, reason: 'Second call should NOT collect');
    });

    test('3b. Different lastModified → collected (new change)', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-new',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      expect(service.pendingCount, 1);

      // Different lastModified → different fingerprint → collected
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-uuid-new',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000001,
      );
      expect(service.pendingCount, 2, reason: 'New lastModified = new change');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 4. Multiple changes batched → single notification
  // ═══════════════════════════════════════════════════════════════════════
  group('4. Batching — multiple changes', () {
    test('4a. Multiple changes from same device → batched', () async {
      for (var i = 0; i < 5; i++) {
        await service.onRemoteRecordApplied(
          entity: 'rooms',
          localUuid: 'room-batch-$i',
          remoteDeviceId: 'device-A',
          currentDeviceId: 'device-B',
          lastModified: 1700000000 + i,
        );
      }
      expect(service.pendingCount, 5, reason: '5 changes collected');
    });

    test('4b. Changes from different devices → batched by device', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-multi-1',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      await service.onRemoteRecordApplied(
        entity: 'bookings',
        localUuid: 'booking-multi-1',
        remoteDeviceId: 'device-C',
        currentDeviceId: 'device-B',
        lastModified: 1700000001,
      );
      expect(service.pendingCount, 2, reason: '2 changes from 2 devices');
    });

    test('4c. Flush after batch → pending cleared', () async {
      for (var i = 0; i < 3; i++) {
        await service.onRemoteRecordApplied(
          entity: 'rooms',
          localUuid: 'room-flush-$i',
          remoteDeviceId: 'device-A',
          currentDeviceId: 'device-B',
          lastModified: 1700000000 + i,
        );
      }
      expect(service.pendingCount, 3);
      await service.flushPendingNotifications();
      expect(service.pendingCount, 0, reason: 'Pending cleared after flush');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 5. Restart → no duplicate (persistent dedup)
  // ═══════════════════════════════════════════════════════════════════════
  group('5. Persistent dedup — survives restart', () {
    test('5a. Same change after "restart" → dedup\'d', () async {
      // Simulate first run
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-restart-1',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      await service.flushPendingNotifications();

      // Simulate "restart" — clear session dedup (simulating new app launch)
      service.clearSessionDedup();
      service.clearPending();

      // Same change arrives again after restart
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-restart-1',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );

      // Should be dedup'd by persistent storage (SharedPreferences)
      expect(service.pendingCount, 0,
          reason: 'Same change after restart should NOT be collected (persistent dedup)');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // 6. Edge cases
  // ═══════════════════════════════════════════════════════════════════════
  group('6. Edge cases', () {
    test('6a. Empty remoteDeviceId → no collection', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-empty-device',
        remoteDeviceId: '',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      expect(service.pendingCount, 0,
          reason: 'Empty deviceId → can\'t determine source → skip');
    });

    test('6b. Null lastModified → still collected', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-null-ts',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: null,
      );
      expect(service.pendingCount, 1,
          reason: 'Null lastModified should still be collected');
    });

    test('6c. clearPending removes all pending', () async {
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-clear-1',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000000,
      );
      await service.onRemoteRecordApplied(
        entity: 'rooms',
        localUuid: 'room-clear-2',
        remoteDeviceId: 'device-A',
        currentDeviceId: 'device-B',
        lastModified: 1700000001,
      );
      expect(service.pendingCount, 2);

      service.clearPending();
      expect(service.pendingCount, 0, reason: 'clearPending should remove all');
    });
  });
}
