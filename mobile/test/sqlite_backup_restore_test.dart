import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sqlite_backup_restore.dart';

void main() {
  late AppDatabase db;
  late SqliteBackupRestore backupRestore;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backupRestore = SqliteBackupRestore(db);
    tempDir = await Directory.systemTemp.createTemp('sqlite_backup_test');
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('creates and restores sqlite backup file', () async {
    // insert minimal data
    final room = Room(
      localUuid: 'r1',
      serverId: null,
      createdAt: 1,
      updatedAt: 1,
      deletedAt: null,
      lastModified: 1,
      createdAtIso: null,
      updatedAtIso: null,
      deletedAtIso: null,
      createdAtEpoch: 1,
      lastModifiedEpoch: 1,
      version: 1,
      origin: 'app',
      id: 1,
      name: '101',
      type: 'std',
      price: 0,
      status: 'available',
      floor: 1,
      isActive: 1,
      currency: 'usd',
      description: null,
      facilities: null,
      capacity: 1,
      lastCleanedAt: null,
      bookingStatus: null,
      colorTag: null,
      createdBy: 'u',
      updatedBy: 'u',
      housekeepingStatus: null,
      housekeepingNote: null,
      deviceId: null,
      cancellationReason: null,
    );
    await db.into(db.rooms).insert(room);

    final backupPath = await backupRestore.createBackup(tempDir.path);
    expect(File(backupPath).existsSync(), isTrue);

    // mutate db then restore
    await db.delete(db.rooms).go();
    expect((await db.select(db.rooms).get()).isEmpty, isTrue);

    final restored = await backupRestore.restoreBackup(backupPath);
    expect(restored, isTrue);
    expect((await db.select(db.rooms).get()).length, 1);
  });
}
