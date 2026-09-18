/// ============================================================
/// Marina Hotel - Database Performance Optimizer
/// ============================================================
/// Creates composite indexes for better query performance
/// Runs automatically on app startup
/// ============================================================
library;

import 'package:flutter/foundation.dart';

import '../local_db.dart' as local_db;
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class DatabaseOptimizer {
  DatabaseOptimizer(this.db);
  final local_db.AppDatabase db;

  /// Run all optimizations
  Future<void> optimizeAll() async {
    await _createCompositeIndexes();
    await _createCoveringIndexes();
    await _analyzeQueryPatterns();
    await _vacuumAndOptimize();
  }

  /// 1. Composite Indexes for common WHERE clauses
  Future<void> _createCompositeIndexes() async {
    // ─── Bookings: Most queried table ───
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_bookings_composite_1 
      ON bookings(status, hotel_day_checkin, guest_name)
    ''');

    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_bookings_composite_2 
      ON bookings(room_number, status, checkin_date)
    ''');

    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_bookings_dates 
      ON bookings(checkin_date, checkout_date)
    ''');

    // ─── Payments: Financial reports ───
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_payments_composite_1 
      ON payments(hotel_day_key, revenue_type, payment_date)
    ''');

    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_payments_composite_2 
      ON payments(booking_local_id, payment_date, amount)
    ''');

    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_payments_date_amt 
      ON payments(payment_date DESC, amount)
    ''');

    // ─── Expenses ───
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_expenses_composite 
      ON expenses(hotel_day_key, expense_type, date)
    ''');

    // ─── Rooms: Status queries ───
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_rooms_status_price 
      ON rooms(status, price)
    ''');

    // ─── Debts: Collections tracking ───
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_debts_composite 
      ON debts(is_settled, remaining_amount, guest_name)
    ''');

    if (kDebugMode) {
      dlog('✅ Created composite indexes');
    }
  }

  /// 2. Covering Indexes (include all queried columns)
  Future<void> _createCoveringIndexes() async {
    // Bookings covering index for list view
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_bookings_covering 
      ON bookings(room_number, guest_name, checkin_date, status, id)
    ''');

    // Payments covering for reports
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_payments_covering 
      ON payments(payment_date, amount, payment_method, revenue_type)
    ''');

    // Rooms covering for room list
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_rooms_covering 
      ON rooms(room_number, type, price, status, image_url)
    ''');

    if (kDebugMode) {
      dlog('✅ Created covering indexes');
    }
  }

  /// 3. Analyze query patterns and create missing indexes
  Future<void> _analyzeQueryPatterns() async {
    // This would query the drift query planner in real usage
    // For now, add commonly needed indexes

    // Foreign key indexes (often missing)
    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_bookings_server_id 
      ON bookings(server_booking_id)
    ''');

    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_payments_server_id 
      ON payments(server_payment_id)
    ''');

    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_payments_cash_tx 
      ON payments(cash_transaction_local_id)
    ''');

    await db.customStatement('''
      CREATE INDEX IF NOT EXISTS idx_expenses_cash_tx 
      ON expenses(cash_transaction_id)
    ''');

    if (kDebugMode) {
      dlog('✅ Analyzed and added missing indexes');
    }
  }

  /// 4. Database maintenance
  Future<void> _vacuumAndOptimize() async {
    // Rebuild indexes
    await db.customStatement('REINDEX');

    // Vacuum (reclaims space, defragments)
    await db.customStatement('VACUUM');

    // Analyze for query planner
    await db.customStatement('ANALYZE');

    if (kDebugMode) {
      dlog('✅ Database optimized (VACUUM + REINDEX)');
    }
  }

  /// Get index statistics
  static Future<Map<String, dynamic>> getIndexStats(
    local_db.AppDatabase db,
  ) async {
    final result = await db.customSelect('''
      SELECT 
        tbl.name as table_name,
        idx.name as index_name,
        idx.sql as index_def
      FROM sqlite_master idx
      JOIN sqlite_master tbl ON idx.tbl_name = tbl.name
      WHERE idx.type = 'index'
      ORDER BY tbl.name, idx.name
    ''').get();

    return {'indexes': result, 'count': result.length};
  }
}

/// Quick optimization helper
class QuickOptimizer {
  static Future<void> runQuickOptimize(local_db.AppDatabase db) async {
    final optimizer = DatabaseOptimizer(db);
    await optimizer.optimizeAll();
  }
}
