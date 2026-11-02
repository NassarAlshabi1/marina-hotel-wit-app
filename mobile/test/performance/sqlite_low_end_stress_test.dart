@Tags(['performance'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

Future<int> _pragmaInt(AppDatabase db, String name) async {
  final rows = await db.customSelect('PRAGMA $name').get();
  if (rows.isEmpty || rows.single.data.isEmpty) {
    return 0;
  }
  final value = rows.single.data.values.single;
  return value is int ? value : int.tryParse(value.toString()) ?? 0;
}

Future<String> _pragmaText(AppDatabase db, String name) async {
  final rows = await db.customSelect('PRAGMA $name').get();
  if (rows.isEmpty || rows.single.data.isEmpty) {
    return 'unavailable';
  }
  return rows.single.data.values.single.toString();
}

Future<void> _seed(AppDatabase db, {int rows = 5000}) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.transaction(() async {
    for (var i = 0; i < rows; i++) {
      final day = (i % 28) + 1;
      final date = '2026-08-${day.toString().padLeft(2, '0')}';
      final uuid = 'stress-$i';
      final sync = [
        "'$uuid'",
        'NULL',
        '$now',
        '$now',
        'NULL',
        '$now',
        'NULL',
        'NULL',
        'NULL',
        '$now',
        '$now',
        '1',
        "'local'",
        "'{}'",
        "''",
        '$now',
        'NULL',
      ].join(', ');

      await db.customStatement(
        '''
        INSERT INTO rooms (
          room_number, type, price, status, image_url, cleaning_status,
          last_cleaned_hotel_day, last_occupied_hotel_day, requires_maintenance,
          local_uuid, server_id, created_at, updated_at, deleted_at, last_modified,
          created_at_iso, updated_at_iso, deleted_at_iso, created_at_epoch,
          last_modified_epoch, version, origin, vector_clock, device_id,
          sync_timestamp, idempotency_key
        ) VALUES (
          'stress-room-$i', 'standard', 100.0, 'available', NULL, 'clean',
          NULL, NULL, 0, $sync
        )
      '''
            .replaceFirst('NULL, $sync', 'NULL, $sync'),
      );

      await db.customStatement('''
        INSERT INTO bookings (
          room_number, guest_name, guest_phone, guest_nationality,
          checkin_date, checkout_date, status,
          local_uuid, server_id, created_at, updated_at, deleted_at, last_modified,
          created_at_iso, updated_at_iso, deleted_at_iso, created_at_epoch,
          last_modified_epoch, version, origin, vector_clock, device_id,
          sync_timestamp, idempotency_key
        ) VALUES (
          'stress-room-$i', 'Guest $i', '000$i', 'N/A',
          '$date 10:00:00', '2026-09-01 10:00:00', 'active',
          'booking-$i', NULL, $now, $now, NULL, $now,
          NULL, NULL, NULL, $now, $now, 1, 'local', '{}', '', $now, NULL
        )
      ''');

      await db.customStatement('''
        INSERT INTO payments (
          booking_local_id, room_number, amount, payment_date,
          payment_method, revenue_type, is_pending_balance, is_voided,
          local_uuid, server_id, created_at, updated_at, deleted_at, last_modified,
          created_at_iso, updated_at_iso, deleted_at_iso, created_at_epoch,
          last_modified_epoch, version, origin, vector_clock, device_id,
          sync_timestamp, idempotency_key
        ) VALUES (
          NULL, 'stress-room-$i', 100.0, '$date 12:00:00',
          'cash', 'room', 0, 0,
          'payment-$i', NULL, $now, $now, NULL, $now,
          NULL, NULL, NULL, $now, $now, 1, 'local', '{}', '', $now, NULL
        )
      ''');

      await db.customStatement('''
        INSERT INTO expenses (
          expense_type, related_id, description, amount, date,
          hotel_day_key, is_auto_generated,
          local_uuid, server_id, created_at, updated_at, deleted_at, last_modified,
          created_at_iso, updated_at_iso, deleted_at_iso, created_at_epoch,
          last_modified_epoch, version, origin, vector_clock, device_id,
          sync_timestamp, idempotency_key
        ) VALUES (
          'test', NULL, 'Stress expense $i', 10.0, '$date',
          '$date', 0,
          'expense-$i', NULL, $now, $now, NULL, $now,
          NULL, NULL, NULL, $now, $now, 1, 'local', '{}', '', $now, NULL
        )
      ''');

      await db.customStatement('''
        INSERT INTO outbox (
          entity, op, local_uuid, server_id, payload, client_ts,
          idempotency_key, processing_status, delivered_to_primary, source
        ) VALUES (
          'bookings', 'update', 'outbox-$i', NULL, '{}', $i,
          'stress-outbox-$i', 'pending', 0, 'local'
        )
      ''');
    }
  });
}

Future<int> _run(AppDatabase db, String sql, int iterations) async {
  final samples = <int>[];
  for (var i = 0; i < iterations; i++) {
    final watch = Stopwatch()..start();
    await db.customSelect(sql).get();
    watch.stop();
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  final p50 = samples[samples.length ~/ 2];
  final p95 =
      samples[(samples.length * 95 ~/ 100).clamp(0, samples.length - 1)];
  return (p50 << 32) | p95;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQLite low-end stress: footprint and hot queries', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seed(db);

    final metrics = <String, String>{
      'journal_mode': await _pragmaText(db, 'journal_mode'),
      'page_size': '${await _pragmaInt(db, 'page_size')} bytes',
      'page_count': '${await _pragmaInt(db, 'page_count')}',
      'freelist_count': '${await _pragmaInt(db, 'freelist_count')}',
      'cache_size': '${await _pragmaInt(db, 'cache_size')}',
      'mmap_size': '${await _pragmaInt(db, 'mmap_size')} bytes',
      'rss_before_queries': '${ProcessInfo.currentRss} bytes',
    };

    const queries = <String, String>{
      'bookings': '''
        SELECT id, room_number, guest_name, checkin_date
        FROM bookings WHERE deleted_at IS NULL
        ORDER BY checkin_date DESC LIMIT 50
      ''',
      'payments': '''
        SELECT id, amount, payment_date FROM payments
        WHERE deleted_at IS NULL AND is_voided = 0
          AND is_pending_balance = 0
          AND payment_date >= '2026-08-01'
          AND payment_date < '2026-09-01'
        ORDER BY payment_date DESC LIMIT 50
      ''',
      'expenses': '''
        SELECT id, amount, date FROM expenses
        WHERE deleted_at IS NULL AND date >= '2026-08-01'
          AND date < '2026-09-01'
        ORDER BY date DESC LIMIT 50
      ''',
      'outbox': '''
        SELECT id, entity, local_uuid, client_ts FROM outbox
        WHERE processing_status = 'pending' AND delivered_to_primary = 0
          AND source IN ('local')
        ORDER BY client_ts ASC LIMIT 100
      ''',
    };

    for (final entry in queries.entries) {
      final packed = await _run(db, entry.value, 250);
      final p50 = packed >> 32;
      final p95 = packed & 0xffffffff;
      metrics['${entry.key}_p50_us'] = '$p50';
      metrics['${entry.key}_p95_us'] = '$p95';
    }

    metrics['rss_after_queries'] = '${ProcessInfo.currentRss} bytes';
    // ignore: avoid_print
    print(
      'SQLITE_LOW_END_STRESS ${metrics.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );

    expect(await _pragmaInt(db, 'page_count'), greaterThan(0));
    expect(await _pragmaInt(db, 'page_size'), greaterThan(0));
    expect(ProcessInfo.currentRss, greaterThan(0));
  });
}
