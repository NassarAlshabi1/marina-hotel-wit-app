/// ============================================================
/// Marina Hotel - Appwrite Collections Creator
/// ============================================================
/// Creates all collections in Appwrite database
/// Run with: dart run lib/scripts/create_appwrite_collections.dart
/// ============================================================

import 'package:dio/dio.dart';

class AppwriteCollectionsCreator {
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';
  static const String projectId = '690ff0da0025518570c1';
  static const String databaseId = 'hotel_db';
  static const String apiKey = 'YOUR_API_KEY_HERE'; // Replace with your API key

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: endpoint,
    headers: {
      'Content-Type': 'application/json',
      'X-Appwrite-Project': projectId,
      'X-Appwrite-Key': apiKey,
    },
  ));

  /// All collections to create
  static final List<Map<String, dynamic>> collections = [
    // Core Collections
    {
      'name': 'rooms',
      'description': 'Hotel rooms',
      'id': 'rooms',
    },
    {
      'name': 'bookings', 
      'description': 'Hotel bookings',
      'id': 'bookings',
    },
    {
      'name': 'payments',
      'description': 'Payment records',
      'id': 'payments',
    },
    {
      'name': 'expenses',
      'description': 'Expense records',
      'id': 'expenses',
    },
    {
      'name': 'employees',
      'description': 'Hotel employees',
      'id': 'employees',
    },
    {
      'name': 'debts',
      'description': 'Guest debts',
      'id': 'debts',
    },
    // Extended Collections
    {
      'name': 'booking_notes',
      'description': 'Booking notes and alerts',
      'id': 'booking_notes',
    },
    {
      'name': 'cash_transactions',
      'description': 'Cash transaction records',
      'id': 'cash_transactions',
    },
    {
      'name': 'booking_nights',
      'description': 'Booking nights tracking',
      'id': 'booking_nights',
    },
    {
      'name': 'hotel_day_ledger',
      'description': 'Daily hotel ledger',
      'id': 'hotel_day_ledger',
    },
    {
      'name': 'salary_cycles',
      'description': 'Employee salary cycles',
      'id': 'salary_cycles',
    },
    {
      'name': 'salary_payments',
      'description': 'Salary payment records',
      'id': 'salary_payments',
    },
    {
      'name': 'salary_withdrawals',
      'description': 'Salary withdrawals',
      'id': 'salary_withdrawals',
    },
    {
      'name': 'shift_notes',
      'description': 'Shift notes',
      'id': 'shift_notes',
    },
    {
      'name': 'price_adjustments',
      'description': 'Price adjustments',
      'id': 'price_adjustments',
    },
    {
      'name': 'booking_price_adjustments',
      'description': 'Booking price adjustments',
      'id': 'booking_price_adjustments',
    },
    {
      'name': 'audit_logs',
      'description': 'System audit logs',
      'id': 'audit_logs',
    },
    {
      'name': 'payment_voids',
      'description': 'Payment void records',
      'id': 'payment_voids',
    },
    {
      'name': 'guest_infos',
      'description': 'Guest information',
      'id': 'guest_infos',
    },
  ];

  /// Create a single collection
  static Future<bool> createCollection(String id, String name, String description) async {
    try {
      final response = await _dio.post(
        '/databases/$databaseId/collections',
        data: {
          'collectionId': id,
          'name': name,
          'documentSecurity': false,
        },
      );
      print('✅ Created: $name ($id)');
      return true;
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        print('⏭️  Already exists: $name ($id)');
        return true;
      }
      print('❌ Failed: $name - ${e.message}');
      return false;
    }
  }

  /// Create all collections
  static Future<void> createAllCollections() async {
    print('═' * 50);
    print('🏨 Creating Appwrite Collections');
    print('═' * 50);
    print('Database: $databaseId');
    print('');

    int success = 0;
    int failed = 0;

    for (final col in collections) {
      final result = await createCollection(
        col['id'],
        col['name'],
        col['description'],
      );
      if (result) success++;
      else failed++;
    }

    print('');
    print('═' * 50);
    print('📊 Summary: $success created, $failed failed');
    print('═' * 50);
  }
}

void main() async {
  await AppwriteCollectionsCreator.createAllCollections();
}
