/// ============================================================
/// Marina Hotel - Appwrite Collections Verifier
/// ============================================================
/// Verifies all collections exist in Appwrite
/// ============================================================

import 'package:dio/dio.dart';

class AppwriteCollectionsVerifier {
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';
  static const String projectId = '690ff0da0025518570c1';
  static const String databaseId = 'hotel_db';
  static const String apiKey = 'YOUR_API_KEY_HERE';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: endpoint,
    headers: {
      'X-Appwrite-Project': projectId,
      'X-Appwrite-Key': apiKey,
    },
  ));

  static const List<String> expectedCollections = [
    // Core
    'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
    // Extended
    'booking_notes', 'cash_transactions', 'booking_nights',
    'hotel_day_ledger', 'salary_cycles', 'salary_payments',
    'salary_withdrawals', 'shift_notes', 'price_adjustments',
    'booking_price_adjustments', 'audit_logs', 'payment_voids', 'guest_infos',
  ];

  static Future<void> verify() async {
    print('🔍 Verifying Appwrite Collections...');
    print('');

    try {
      final response = await _dio.get(
        '/databases/$databaseId/collections',
        queryParameters: {'limit': 100},
      );

      final collections = (response.data['collections'] as List)
          .map((c) => c['id'] as String)
          .toList();

      print('Found ${collections.length} collections:");
      for (final c in collections) {
        print('  ✓ $c');
      }
      print('');

      // Check for missing
      final missing = expectedCollections
          .where((c) => !collections.contains(c))
          .toList();

      if (missing.isEmpty) {
        print('✅ All expected collections are present!');
      } else {
        print('⚠️  Missing collections:');
        for (final m in missing) {
          print('  ❌ $m');
        }
      }
    } catch (e) {
      print('❌ Error: $e');
    }
  }
}

void main() async {
  await AppwriteCollectionsVerifier.verify();
}