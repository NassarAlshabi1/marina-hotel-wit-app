import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_safety_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_safety_test');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SyncSafetyLayer.instance.setTestingDirectory(tempDir);
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('snapshot rollback restores data after simulated failure', () async {
    await db.into(db.shiftNotes).insert(ShiftNotesCompanion.insert(
      title: 'ملاحظة اختبار',
      content: 'قبل المزامنة',
      createdAt: DateTime.now().toIso8601String(),
    ));

    final snapshot = await SyncSafetyLayer.instance.captureSnapshot(
      db: db,
      syncId: 'sync_test',
      phase: 'push',
    );

    await db.delete(db.shiftNotes).go();
    expect((await db.select(db.shiftNotes).get()).isEmpty, isTrue);

    await SyncSafetyLayer.instance.rollbackSnapshot(
      db: db,
      snapshot: snapshot,
      error: 'simulated failure',
    );

    final restoredNotes = await db.select(db.shiftNotes).get();
    expect(restoredNotes.length, 1);
    expect(restoredNotes.first.title, 'ملاحظة اختبار');
  });

  test('committing snapshot stores audit metadata', () async {
    final snapshot = await SyncSafetyLayer.instance.captureSnapshot(
      db: db,
      syncId: 'sync_commit',
      phase: 'pull',
    );

    await SyncSafetyLayer.instance.commitSnapshot(
      db: db,
      snapshot: snapshot,
      direction: 'pull',
      checksum: 'abc123',
      deviceId: 'device-test',
      metadata: {'conflicts': 0},
    );

    final result = await db.customSelect('SELECT COUNT(*) as count FROM sync_audit').getSingle();
    final count = (result.data['count'] as int?) ?? (result.data['count'] as num).toInt();
    expect(count, 1);
  });
}
