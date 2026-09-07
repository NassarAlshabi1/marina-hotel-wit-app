@Tags(['performance'])
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

Future<List<String>> _plan(AppDatabase db, String sql) async {
  final rows = await db.customSelect('EXPLAIN QUERY PLAN $sql').get();
  return rows.map((row) => row.data.values.join(' ')).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('يوثق خطط الاستعلام ويقارن الفهارس الجزئية المرشحة', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    const bookingsSql = '''
      SELECT id FROM bookings
      WHERE deleted_at IS NULL
      ORDER BY checkin_date DESC
      LIMIT 50
    ''';
    const paymentsSql = '''
      SELECT id FROM payments
      WHERE deleted_at IS NULL
        AND is_voided = 0
        AND is_pending_balance = 0
        AND payment_date >= '2026-01-01'
        AND payment_date < '2026-02-01'
      ORDER BY payment_date DESC
      LIMIT 50
    ''';
    const expensesSql = '''
      SELECT id FROM expenses
      WHERE deleted_at IS NULL
        AND date >= '2026-01-01'
        AND date < '2026-02-01'
      ORDER BY date DESC
      LIMIT 50
    ''';
    const outboxSql = '''
      SELECT id FROM outbox
      WHERE processing_status = 'pending'
        AND delivered_to_primary = 0
        AND source IN ('local')
      ORDER BY client_ts ASC
      LIMIT 50
    ''';

    // AppDatabase may already create production indexes from the table
    // definitions. Drop only the four candidate indexes so BEFORE is a real
    // baseline and AFTER proves the measured index is selected.
    for (final indexName in <String>[
      'idx_bookings_active_checkin',
      'idx_payments_active_report_date',
      'idx_expenses_active_date',
      'idx_outbox_pending_primary_source_ts',
    ]) {
      await db.customStatement('DROP INDEX IF EXISTS $indexName');
    }

    final before = <String, List<String>>{
      'bookings': await _plan(db, bookingsSql),
      'payments': await _plan(db, paymentsSql),
      'expenses': await _plan(db, expensesSql),
      'outbox': await _plan(db, outboxSql),
    };

    await db.customStatement(
      'CREATE INDEX idx_test_bookings_active_checkin '
      'ON bookings (checkin_date DESC) WHERE deleted_at IS NULL',
    );
    await db.customStatement(
      'CREATE INDEX idx_test_payments_active_report_date '
      'ON payments (payment_date DESC) '
      'WHERE deleted_at IS NULL AND is_voided = 0 AND is_pending_balance = 0',
    );
    await db.customStatement(
      'CREATE INDEX idx_test_expenses_active_date '
      'ON expenses (date DESC) WHERE deleted_at IS NULL',
    );
    await db.customStatement(
      'CREATE INDEX idx_test_outbox_pending_primary_source_ts '
      'ON outbox (source, client_ts) '
      "WHERE processing_status = 'pending' AND delivered_to_primary = 0",
    );

    final after = <String, List<String>>{
      'bookings': await _plan(db, bookingsSql),
      'payments': await _plan(db, paymentsSql),
      'expenses': await _plan(db, expensesSql),
      'outbox': await _plan(db, outboxSql),
    };

    for (final entry in before.entries) {
      // ignore: avoid_print
      print('PLAN_BEFORE ${entry.key}: ${entry.value.join(' | ')}');
      // ignore: avoid_print
      print('PLAN_AFTER ${entry.key}: ${after[entry.key]!.join(' | ')}');
    }

    expect(after['bookings']!.join(' '), contains('idx_test_bookings'));
    expect(after['payments']!.join(' '), contains('idx_test_payments'));
    expect(after['expenses']!.join(' '), contains('idx_test_expenses'));
    expect(after['outbox']!.join(' '), contains('idx_test_outbox'));
  });
}
