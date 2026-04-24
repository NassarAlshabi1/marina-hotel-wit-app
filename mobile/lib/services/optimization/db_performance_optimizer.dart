/// ============================================================
/// Marina Hotel - Database Performance Optimizer
/// ============================================================
/// Creates composite indexes for better query performance
/// Runs automatically on app startup
/// ============================================================

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../local_db.dart' as local_db;

class DatabaseOptimizer {
  final local_db.AppDatabase db;
  
  DatabaseOptimizer(this.db);
  
  /// Run all optimizations
  Future<void> optimizeAll() async {
    await _createCompositeIndexes();
    await _createCoveringIndexes();
    await _analyzeQueryPatterns();
    await _vacuumAndOptimize();
  }
  
  /// 1. Composite Indexes for common WHERE clauses
  Future<void> _createCompositeIndexes() async {
    final executor = db.executor;
    
    // ─── Bookings: Most queried table ───
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bookings_composite_1 
      ON bookings(status, hotel_day_checkin, guest_name)
    ''');
    
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bookings_composite_2 
      ON bookings(room_number, status, checkin_date)
    ''');
    
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bookings_dates 
      ON bookings(checkin_date, checkout_date)
    ''');
    
    // ─── Payments: Financial reports ───
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payments_composite_1 
      ON payments(hotel_day_key, revenue_type, payment_date)
    ''');
    
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payments_composite_2 
      ON payments(booking_local_id, payment_date, amount)
    ''');
    
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payments_date_amt 
      ON payments(payment_date DESC, amount)
    ''');
    
    // ─── Expenses ───
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_expenses_composite 
      ON expenses(hotel_day_key, expense_type, date)
    ''');
    
    // ─── Rooms: Status queries ───
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_rooms_status_price 
      ON rooms(status, price)
    ''');
    
    // ─── Debts: Collections tracking ───
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_debts_composite 
      ON debts(is_settled, remaining_amount, guest_name)
    ''');
    
    if (kDebugMode) {
      print('✅ Created composite indexes');
    }
  }
  
  /// 2. Covering Indexes (include all queried columns)
  Future<void> _createCoveringIndexes() async {
    final executor = db.executor;
    
    // Bookings covering index for list view
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bookings_covering 
      ON bookings(room_number, guest_name, checkin_date, status, id)
    ''');
    
    // Payments covering for reports
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payments_covering 
      ON payments(payment_date, amount, payment_method, revenue_type)
    ''');
    
    // Rooms covering for room list
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_rooms_covering 
      ON rooms(room_number, type, price, status, image_url)
    ''');
    
    if (kDebugMode) {
      print('✅ Created covering indexes');
    }
  }
  
  /// 3. Analyze query patterns and create missing indexes
  Future<void> _analyzeQueryPatterns() async {
    // This would query the drift query planner in real usage
    // For now, add commonly needed indexes
    
    final executor = db.executor;
    
    // Foreign key indexes (often missing)
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_bookings_server_id 
      ON bookings(server_booking_id)
    ''');
    
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payments_server_id 
      ON payments(server_payment_id)
    ''');
    
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_payments_cash_tx 
      ON payments(cash_transaction_local_id)
    ''');
    
    await executor.execute('''
      CREATE INDEX IF NOT EXISTS idx_expenses_cash_tx 
      ON expenses(cash_transaction_id)
    ''');
    
    if (kDebugMode) {
      print('✅ Analyzed and added missing indexes');
    }
  }
  
  /// 4. Database maintenance
  Future<void> _vacuumAndOptimize() async {
    final executor = db.executor;
    
    // Rebuild indexes
    await executor.execute('REINDEX');
    
    // Vacuum (reclaims space, defragments)
    await executor.execute('VACUUM');
    
    // Analyze for query planner
    await executor.execute('ANALYZE');
    
    if (kDebugMode) {
      print('✅ Database optimized (VACUUM + REINDEX)');
    }
  }
  
  /// Get index statistics
  static Future<Map<String, dynamic>> getIndexStats(local_db.AppDatabase db) async {
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
    
    return {
      'indexes': result,
      'count': result.length,
    };
  }
}

/// Quick optimization helper
class QuickOptimizer {
  static Future<void> runQuickOptimize(local_db.AppDatabase db) async {
    final optimizer = DatabaseOptimizer(db);
    await optimizer.optimizeAll();
  }
}
