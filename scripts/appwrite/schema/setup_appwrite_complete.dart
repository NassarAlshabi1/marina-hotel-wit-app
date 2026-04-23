/// ============================================================
/// Marina Hotel - Complete Appwrite Setup
/// ============================================================
/// One script to set up everything
/// Run: dart run lib/scripts/setup_appwrite_complete.dart
/// ============================================================

import 'package:dio/dio.dart';

class CompleteSetup {
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';
  static const String projectId = '690ff0da0025518570c1';
  static const String databaseId = 'hotel_db';
  static const String apiKey = 'YOUR_API_KEY_HERE'; // ⚠️ Replace with your API key

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: endpoint,
    headers: {
      'Content-Type': 'application/json',
      'X-Appwrite-Project': projectId,
      'X-Appwrite-Key': apiKey,
    },
  ));

  static final List<Map<String, dynamic>> collections = [
    {'id': 'rooms', 'name': 'Rooms', 'desc': 'Hotel rooms'},
    {'id': 'bookings', 'name': 'Bookings', 'desc': 'Reservations'},
    {'id': 'payments', 'name': 'Payments', 'desc': 'Payments'},
    {'id': 'expenses', 'name': 'Expenses', 'desc': 'Expenses'},
    {'id': 'employees', 'name': 'Employees', 'desc': 'Staff'},
    {'id': 'debts', 'name': 'Debts', 'desc': 'Debts'},
    {'id': 'booking_notes', 'name': 'Booking Notes', 'desc': 'Notes'},
    {'id': 'cash_transactions', 'name': 'Cash', 'desc': 'Transactions'},
    {'id': 'booking_nights', 'name': 'Nights', 'desc': 'Booking nights'},
    {'id': 'hotel_day_ledger', 'name': 'Ledger', 'desc': 'Daily ledger'},
    {'id': 'salary_cycles', 'name': 'Salary Cycles', 'desc': 'Cycles'},
    {'id': 'salary_payments', 'name': 'Salary Payments', 'desc': 'Payments'},
    {'id': 'salary_withdrawals', 'name': 'Withdrawals', 'desc': 'Withdrawals'},
    {'id': 'shift_notes', 'name': 'Shift Notes', 'desc': 'Notes'},
    {'id': 'price_adjustments', 'name': 'Price Adj', 'desc': 'Adjustments'},
    {'id': 'booking_price_adjustments', 'name': 'Booking Price', 'desc': 'Price'},
    {'id': 'audit_logs', 'name': 'Audit', 'desc': 'Logs'},
    {'id': 'payment_voids', 'name': 'Voids', 'desc': 'Voids'},
    {'id': 'guest_infos', 'name': 'Guests', 'desc': 'Info'},
  ];

  static Future<bool> createCollection(col) async {
    try {
      await _dio.post('/databases/$databaseId/collections', data: {
        'collectionId': col['id'],
        'name': col['name'],
        'documentSecurity': false,
      });
      print('✅ ${col['name']}');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        print('⏭️  ${col['name']} (exists)');
        return true;
      }
      print('❌ ${col['name']}: ${e.message}');
      return false;
    }
  }

  static Future<void> run() async {
    print('═' * 55);
    print('🏨 Marina Hotel - Complete Appwrite Setup');
    print('═' * 55);
    print('Project: $projectId');
    print('Database: $databaseId');
    print('Collections: ${collections.length}');
    print('');

    // 1. Create database
    try {
      await _dio.post('/databases', data: {
        'databaseId': databaseId,
        'name': 'Hotel Database',
      });
      print('✅ Database created');
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        print('⏭️  Database exists');
      } else {
        print('❌ Database: ${e.message}');
      }
    }
    print('');

    // 2. Create collections
    print('📦 Creating Collections...');
    int ok = 0, fail = 0;
    for (final col in collections) {
      if (await createCollection(col)) ok++; else fail++;
    }

    print('');
    print('═' * 55);
    print('📊 Result: $ok ✅ | $fail ❌');
    print('═' * 55);
  }
}

void main() async => CompleteSetup.run();