/// ============================================================
/// Marina Hotel - Optimized Queries
/// ============================================================
/// Pre-optimized queries for common operations
/// Single-query alternatives to multiple queries
/// ============================================================

import 'package:drift/drift.dart';
import '../local_db.dart' as local_db;

class OptimizedQueries {
  final local_db.AppDatabase db;
  
  OptimizedQueries(this.db);
  
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
    ''', variables: [today, today, today]).getSingle();
    
    return {
      'totalRooms': result.total_rooms,
      'occupiedRooms': result.occupied_rooms,
      'cleanRooms': result.clean_rooms,
      'totalIncome': result.total_income,
      'totalExpenses': result.total_expenses,
      'totalBookings': result.total_bookings,
      'occupancyRate': result.total_rooms > 0
          ? (result.occupied_rooms / result.total_rooms * 100)
          : 0.0,
      'netProfit': result.total_income - result.total_expenses,
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
    
    return await db.customSelect('''
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
    ''', variables: [from, to, from, to]).get();
  }
  
  /// Get top rooms by revenue (covering index query)
  Future<List<Map<String, dynamic>>> getTopRoomsByRevenue({
    int limit = 10,
    String? fromDate,
    String? toDate,
  }) async {
    final where = fromDate != null ? 'WHERE p.payment_date >= ?' : '';
    final params = fromDate != null ? [fromDate] : [];
    if (toDate != null) {
      params.add(toDate);
    }
    
    return await db.customSelect('''
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
    ''', variables: [...params, limit]).get();
  }
  
  /// Get occupancy trend (last 7 days) - optimized
  Future<List<Map<String, dynamic>>> getOccupancyTrend({int days = 7}) async {
    return await db.customSelect('''
      SELECT 
        date(hotel_day_checkin) as day,
        COUNT(DISTINCT room_number) as occupied,
        (SELECT COUNT(*) FROM rooms) as total_rooms,
        ROUND(
          COUNT(DISTINCT room_number) * 100.0 / 
          (SELECT COUNT(*) FROM rooms), 2
        ) as occupancy_rate
      FROM bookings
      WHERE hotel_day_checkin >= date('now', '-${days - 1} days')
        AND status NOT IN ('checked_out', 'cancelled')
      GROUP BY date(hotel_day_checkin)
      ORDER BY day
    ''').get();
  }
  
  /// Get guest debts - optimized with index hint
  Future<List<local_db.Debt>> getOverdueDebts() async {
    return await db.select(db.debts)
      .where((d) => d.isSettled.equals(0) &
                    d.remainingAmount.biggerThan(0))
      .orderBy([(d) => OrderingTerm.desc(d.id)])
      .limit(100) // Prevent loading too many
      .get();
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
    ''', variables: [employeeId]).getSingle();
    
    return {
      'name': result.name,
      'basicSalary': result.basic_salary,
      'totalPaid': result.total_paid,
      'totalRemaining': result.total_remaining,
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
    ''', variables: [roomNumber, roomNumber]).getSingleOrNull();
    
    return result;
  }
  
  /// Get room occupancy rate quickly
  Future<double> getOccupancyRate(String? hotelDay) async {
    final day = hotelDay ?? _todayKey();
    
    final result = await db.customSelect('''
      SELECT 
        ROUND(
          COUNT(DISTINCT CASE WHEN status = 'occupied' THEN room_number END) * 100.0 /
          NULLIF(COUNT(DISTINCT room_number), 0),
        2
      ) as rate
      FROM rooms
    ''').getSingle();
    
    return result.rate ?? 0.0;
  }
  
  // ─── PAYMENTS: Aggregations ───
  
  /// Get today's total payments (uses index on payment_date)
  Future<double> getTodayPayments() async {
    final today = _todayKey();
    final result = await db.select(db.payments)
      .where((p) => p.paymentDate.equals(today) &
                    p.isVoided.equals(false))
      .watch()
      .get();
    
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
    ''', variables: [from, to]).get();
    
    return {
      for (final r in results)
        r.revenue_type as String: r.total as double,
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
    ''', variables: [from, to]).get();
    
    return {
      for (final r in results)
        r.expense_type as String: r.total as double,
    };
  }
  
  // ─── UTILITIES ───
  
  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
  
  /// Generic method for paginated queries with optimized limit
  Future<List<T>> getPaginated<T extends Table>(
    TableInfo<dynamic, T> table, {
    required int page,
    required int limit,
    Expression? where,
    OrderingTerm? orderBy,
  }) async {
    final offset = (page - 1) * limit;
    var query = db.select(table);
    
    if (where != null) {
      query = query.where((t) => where);
    }
    
    if (orderBy != null) {
      query = query.orderBy([orderBy]);
    }
    
    return await query.limit(limit, offset: offset).get();
  }
}
