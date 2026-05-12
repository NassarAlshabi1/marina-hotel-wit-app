// ============================================================
// Marina Hotel - Optimized Queries
// ============================================================
// Pre-optimized queries for common operations
// Single-query alternatives to multiple queries
// ============================================================

import 'package:drift/drift.dart';
import '../local_db.dart' as local_db;

class OptimizedQueries {
  OptimizedQueries(this.db);

  final local_db.AppDatabase db;
  
  // ─── DASHBOARD: Single query instead of 4-5 queries ───
  
  /// Get all dashboard stats in ONE query
  Future<Map<String, dynamic>> getDashboardStats() async {
    final today = _todayKey();
    final result = await db.customSelect('''
      SELECT 
        -- Room stats
        COUNT(r.id) as total_rooms,
        COALESCE(SUM(CASE WHEN r.status = 'occupied' THEN 1 ELSE 0 END), 0) as occupied_rooms,
        COALESCE(SUM(CASE WHEN r.status = 'clean' THEN 1 ELSE 0 END), 0) as clean_rooms,
        
        -- Financial stats (today)
        COALESCE(SUM(p.amount), 0) as total_income,
        COALESCE(SUM(e.amount), 0) as total_expenses,
        
        -- Bookings
        COUNT(DISTINCT b.id) as total_bookings
      FROM rooms r
      LEFT JOIN payments p ON p.hotel_day_key = ?
      LEFT JOIN expenses e ON e.hotel_day_key = ?
      LEFT JOIN bookings b ON b.status NOT IN ('checked_out', 'cancelled')
        AND b.hotel_day_checkin = ?
    ''', variables: [
      Variable<String>(today),
      Variable<String>(today),
      Variable<String>(today),
    ],).getSingle();
    
    final data = result.data;
    final totalRooms = data['total_rooms'] as int;
    final occupiedRooms = data['occupied_rooms'] as int;
    final totalIncome = (data['total_income'] as num).toDouble();
    final totalExpenses = (data['total_expenses'] as num).toDouble();
    
    return {
      'totalRooms': totalRooms,
      'occupiedRooms': occupiedRooms,
      'cleanRooms': data['clean_rooms'] as int,
      'totalIncome': totalIncome,
      'totalExpenses': totalExpenses,
      'totalBookings': data['total_bookings'] as int,
      'occupancyRate': totalRooms > 0
          ? (occupiedRooms / totalRooms * 100)
          : 0.0,
      'netProfit': totalIncome - totalExpenses,
    };
  }
  
  // ─── REPORTS: Optimized queries ───
  
  /// Get monthly income vs expense in single query
  Future<List<Map<String, dynamic>>> getMonthlyIncomeExpense(
    int year,
    int month,
  ) async {
    final from = '$year-${month.toString().padLeft(2, '0')}-01';
    final to = '$year-${month.toString().padLeft(2, '0')}-31';
    
    final rows = await db.customSelect('''
      SELECT 
        date(payment_date) as day,
        SUM(amount) as income,
        0 as expense
      FROM payments
      WHERE payment_date BETWEEN ? AND ?
      GROUP BY date(payment_date)
      
      UNION ALL
      
      SELECT 
        date(date) as day,
        0 as income,
        SUM(amount) as expense
      FROM expenses
      WHERE date BETWEEN ? AND ?
      GROUP BY date(date)
      
      ORDER BY day
    ''', variables: [
      Variable<String>(from),
      Variable<String>(to),
      Variable<String>(from),
      Variable<String>(to),
    ],).get();
    
    return rows.map((row) => row.data).toList();
  }
  
  /// Get top rooms by revenue (covering index query)
  Future<List<Map<String, dynamic>>> getTopRoomsByRevenue({
    int limit = 10,
    String? fromDate,
    String? toDate,
  }) async {
    final where = fromDate != null ? 'WHERE p.payment_date >= ?' : '';
    final params = fromDate != null
        ? <Variable<Object>>[Variable<String>(fromDate)]
        : <Variable<Object>>[];
    if (toDate != null) {
      params.add(Variable<String>(toDate));
    }
    
    final rows = await db.customSelect('''
      SELECT 
        r.room_number,
        COUNT(p.id) as payment_count,
        SUM(p.amount) as total_revenue,
        AVG(p.amount) as avg_revenue
      FROM rooms r
      INNER JOIN payments p ON p.room_number = r.room_number
      $where
      GROUP BY r.room_number, r.id
      ORDER BY total_revenue DESC
      LIMIT ?
    ''', variables: [...params, Variable<int>(limit)],).get();
    
    return rows.map((row) => row.data).toList();
  }
  
  /// Get occupancy trend (last 7 days) - optimized
  Future<List<Map<String, dynamic>>> getOccupancyTrend({int days = 7}) async {
    final rows = await db.customSelect('''
      SELECT 
        date(hotel_day_checkin) as day,
        COUNT(DISTINCT room_number) as occupied,
        (SELECT COUNT(*) FROM rooms) as total_rooms,
        ROUND(
          COUNT(DISTINCT room_number) * 100.0 / 
          (SELECT COUNT(*) FROM rooms), 2
        ) as occupancy_rate
      FROM bookings
      WHERE hotel_day_checkin >= date('now', '-' || ? || ' days')
        AND status NOT IN ('checked_out', 'cancelled')
      GROUP BY date(hotel_day_checkin)
      ORDER BY day
    ''', variables: [Variable<int>(days - 1)]).get();
    
    return rows.map((row) => row.data).toList();
  }
  
  /// Get guest debts - optimized with index hint
  Future<List<local_db.Debt>> getOverdueDebts() async {
    final query = db.select(db.debts)
      ..where((d) => d.isSettled.equals(0) &
                    d.remainingAmount.isBiggerThanValue(0),)
      ..orderBy([(d) => OrderingTerm.desc(d.id)])
      ..limit(100);
    return query.get();
  }
  
  /// Get employee salary summary
  Future<Map<String, dynamic>> getEmployeeSalarySummary(int employeeId) async {
    final result = await db.customSelect('''
      SELECT 
        e.name,
        e.basic_salary,
        COALESCE(SUM(sc.actual_paid), 0) as total_paid,
        COALESCE(SUM(sc.remaining_amount), 0) as total_remaining
      FROM employees e
      LEFT JOIN salary_cycles sc ON sc.employee_id = e.id
      WHERE e.id = ?
      GROUP BY e.id
    ''', variables: [Variable<int>(employeeId)],).getSingle();
    
    final r = result.data;
    return {
      'name': r['name'],
      'basicSalary': r['basic_salary'],
      'totalPaid': r['total_paid'],
      'totalRemaining': r['total_remaining'],
    };
  }
  
  // ─── ROOMS: Fast room status lookup ───
  
  /// Get room with booking details (single join query)
  Future<Map<String, dynamic>?> getRoomWithBooking(String roomNumber) async {
    final result = await db.customSelect('''
      SELECT 
        r.*,
        b.guest_name,
        b.checkin_date,
        b.checkout_date,
        b.status as booking_status
      FROM rooms r
      LEFT JOIN bookings b ON b.room_number = r.room_number
        AND b.status NOT IN ('checked_out', 'cancelled')
        AND b.room_number = ?
      WHERE r.room_number = ?
      LIMIT 1
    ''', variables: [
      Variable<String>(roomNumber),
      Variable<String>(roomNumber),
    ],).getSingleOrNull();
    
    return result?.data;
  }
  
  /// Get room occupancy rate quickly
  Future<double> getOccupancyRate(String? hotelDay) async {
    // hotelDay parameter reserved for future date-specific queries
    
    final result = await db.customSelect('''
      SELECT 
        ROUND(
          COUNT(DISTINCT CASE WHEN status = 'occupied' THEN room_number END) * 100.0 /
          NULLIF(COUNT(DISTINCT room_number), 0),
        2
      ) as rate
      FROM rooms
    ''').getSingle();
    
    return (result.data['rate'] as num?)?.toDouble() ?? 0.0;
  }
  
  // ─── PAYMENTS: Aggregations ───
  
  /// Get today's total payments (uses index on payment_date)
  Future<double> getTodayPayments() async {
    final today = _todayKey();
    final query = db.select(db.payments)
      ..where((p) => p.paymentDate.equals(today) &
                    p.isVoided.equals(false),);
    final result = await query.get();
    
    return result.fold<double>(0, (sum, p) => sum + p.amount);
  }
  
  /// Get payments grouped by revenue type (uses composite index)
  Future<Map<String, double>> getPaymentsByRevenueType({
    required String from,
    required String to,
  }) async {
    final results = await db.customSelect('''
      SELECT 
        revenue_type,
        SUM(amount) as total
      FROM payments
      WHERE payment_date BETWEEN ? AND ?
        AND is_voided = 0
      GROUP BY revenue_type
    ''', variables: [
      Variable<String>(from),
      Variable<String>(to),
    ],).get();
    
    return {
      for (final r in results)
        r.read<String>('revenue_type'): r.read<double>('total'),
    };
  }
  
  // ─── EXPENSES: Optimized queries ───
  
  /// Get monthly expense summary
  Future<Map<String, double>> getMonthlyExpenseSummary(
    int year,
    int month,
  ) async {
    final from = '$year-${month.toString().padLeft(2, '0')}-01';
    final to = '$year-${month.toString().padLeft(2, '0')}-31';
    
    final results = await db.customSelect('''
      SELECT 
        expense_type,
        SUM(amount) as total
      FROM expenses
      WHERE date BETWEEN ? AND ?
      GROUP BY expense_type
    ''', variables: [
      Variable<String>(from),
      Variable<String>(to),
    ],).get();
    
    return {
      for (final r in results)
        r.read<String>('expense_type'): r.read<double>('total'),
    };
  }
  
  // ─── UTILITIES ───
  
  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  
  /// Generic method for paginated queries with optimized limit.
  /// Uses raw SQL since Drift's typed select API requires compile-time
  /// table types, which is incompatible with a generic parameter.
  ///
  /// ⚠️ SECURITY: tableName must be from a whitelist; whereSql/orderBySql
  /// must NOT contain user-controlled input.
  static const _allowedTables = {
    'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
    'booking_notes', 'cash_transactions', 'booking_nights', 'hotel_day_ledger',
    'salary_cycles', 'salary_payments', 'salary_withdrawals', 'shift_notes',
    'blacklist', 'price_adjustments', 'booking_price_adjustments',
    'audit_logs', 'payment_voids', 'guest_infos',
  };

  Future<List<Map<String, dynamic>>> getPaginated(
    String tableName, {
    required int page,
    required int limit,
    String? whereSql,
    List<Variable<Object>>? variables,
    String? orderBySql,
  }) async {
    // ✅ التحقق من اسم الجدول لمنع SQL Injection
    if (!_allowedTables.contains(tableName)) {
      throw ArgumentError('اسم الجدول غير مسموح به: $tableName');
    }
    // ✅ التحقق من أن whereSql و orderBySql لا يحتويان على أحرف خطرة
    if (whereSql != null && whereSql.contains(RegExp(';|--'))) {
      throw ArgumentError('whereSql يحتوي على أحرف غير مسموح بها');
    }
    if (orderBySql != null && orderBySql.contains(RegExp(';|--'))) {
      throw ArgumentError('orderBySql يحتوي على أحرف غير مسموح بها');
    }

    final offset = (page - 1) * limit;
    final params = <Variable<Object>>[...?variables];

    var sql = 'SELECT * FROM "$tableName"';

    if (whereSql != null) {
      sql += ' WHERE $whereSql';
    }

    if (orderBySql != null) {
      sql += ' ORDER BY $orderBySql';
    }

    sql += ' LIMIT ? OFFSET ?';
    params
      ..add(Variable<int>(limit))
      ..add(Variable<int>(offset));

    final rows = await db.customSelect(sql, variables: params).get();
    return rows.map((row) => row.data).toList();
  }
}
