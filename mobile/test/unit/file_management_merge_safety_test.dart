import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/file_management_service.dart';

void main() {
  late Directory tempDir;
  late FileManagementService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup-merge-safety-');
    service = FileManagementService();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> writeBackup(String name, Map<String, dynamic> data) async {
    final file = File('${tempDir.path}/$name.json');
    await file.writeAsString(jsonEncode(data));
    return file.path;
  }

  test(
    'aborts instead of merging two UUIDs with the same SQLite primary key',
    () async {
      final deviceA = await writeBackup('device-a', {
        'bookings': [
          {'id': 7, 'localUuid': 'booking-a'},
        ],
      });
      final deviceB = await writeBackup('device-b', {
        'bookings': [
          {'id': 7, 'localUuid': 'booking-b'},
        ],
      });

      await expectLater(
        service.mergeBackupFiles([
          deviceA,
          deviceB,
        ], 'must-not-be-created.json'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'aborts when the same UUID has conflicting local IDs or contents',
    () async {
      final deviceA = await writeBackup('device-a', {
        'bookings': [
          {'id': 7, 'localUuid': 'booking-shared', 'guestName': 'A'},
        ],
      });
      final deviceB = await writeBackup('device-b', {
        'bookings': [
          {'id': 19, 'localUuid': 'booking-shared', 'guestName': 'B'},
        ],
      });

      await expectLater(
        service.mergeBackupFiles([
          deviceA,
          deviceB,
        ], 'must-not-be-created.json'),
        throwsA(isA<StateError>()),
      );
    },
  );

  test(
    'aborts when a payment points to a booking absent from merged backups',
    () async {
      final source = await writeBackup('device-a', {
        'bookings': <Map<String, dynamic>>[],
        'payments': [
          {'id': 3, 'localUuid': 'payment-a', 'bookingLocalId': 7},
        ],
      });

      await expectLater(
        service.mergeBackupFiles([source], 'must-not-be-created.json'),
        throwsA(isA<StateError>()),
      );
    },
  );
}
