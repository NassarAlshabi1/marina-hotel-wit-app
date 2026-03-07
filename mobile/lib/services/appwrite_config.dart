import 'package:flutter/foundation.dart';

/// إعدادات Appwrite المركزية
class AppwriteConfig {
  // Appwrite Endpoint
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';

  // Project ID - من لوحة تحكم Appwrite
  static const String projectId = '690ff0da0025518570c1';

  // Database ID - من لوحة تحكم Appwrite
  static const String databaseId = 'hotel_db';

  // ==================== Collections IDs ====================
  
  // الجداول الأساسية
  static const String roomsCollectionId = 'rooms';
  static const String bookingsCollectionId = 'bookings';
  static const String paymentsCollectionId = 'payments';
  static const String expensesCollectionId = 'expenses';
  static const String employeesCollectionId = 'employees';
  static const String debtsCollectionId = 'debts';
  static const String devicesCollectionId = 'devices';
  static const String syncLogsCollectionId = 'sync_logs';

  // جداول الحجوزات
  static const String bookingNotesCollectionId = 'booking_notes';
  static const String bookingNightsCollectionId = 'booking_nights';

  // جداول المالية
  static const String cashTransactionsCollectionId = 'cash_transactions';
  static const String hotelDayLedgerCollectionId = 'hotel_day_ledger';
  static const String priceAdjustmentsCollectionId = 'price_adjustments';
  static const String bookingPriceAdjustmentsCollectionId = 'booking_price_adjustments';

  // جداول الرواتب
  static const String salaryCyclesCollectionId = 'salary_cycles';
  static const String salaryPaymentsCollectionId = 'salary_payments';
  static const String salaryWithdrawalsCollectionId = 'salary_withdrawals';

  // جداول الملاحظات والورديات
  static const String shiftNotesCollectionId = 'shift_notes';

  // جداول التدقيق والتتبع
  static const String auditLogsCollectionId = 'audit_logs';
  static const String paymentVoidsCollectionId = 'payment_voids';

  // ==================== Sync Settings ====================
  
  static const Duration syncInterval = Duration(minutes: 15);
  static const Duration cacheExpiry = Duration(hours: 6);
  static const int maxCacheSizeMB = 20;
  static const int maxRetries = 3;
  static const Duration initialRetryDelay = Duration(seconds: 2);
  static const double retryBackoffMultiplier = 2.0;

  // Timeout Settings
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration longTimeout = Duration(minutes: 2);

  // Pagination Settings
  static const int defaultPageSize = 25;
  static const int maxPageSize = 100;
  static const int batchSize = 50;

  /// طباعة الإعدادات (للتشخيص)
  static void printConfig() {
    if (kDebugMode) {
      debugPrint('═══════════════════════════════════════');
      debugPrint('🔧 Appwrite Configuration');
      debugPrint('═══════════════════════════════════════');
      debugPrint('Endpoint: $endpoint');
      debugPrint('Project ID: $projectId');
      debugPrint('Database ID: $databaseId');
      debugPrint('Sync Interval: ${syncInterval.inMinutes} minutes');
      debugPrint('Cache Expiry: ${cacheExpiry.inHours} hours');
      debugPrint('Max Cache Size: $maxCacheSizeMB MB');
      debugPrint('Default Page Size: $defaultPageSize');
      debugPrint('Max Page Size: $maxPageSize');
      debugPrint('Batch Size: $batchSize');
      debugPrint('Max Retries: $maxRetries');
      debugPrint('Default Timeout: ${defaultTimeout.inSeconds}s');
      debugPrint('Long Timeout: ${longTimeout.inSeconds}s');
      debugPrint('═══════════════════════════════════════');
    }
  }

  /// التحقق من صحة الإعدادات
  static bool validateConfig() {
    if (projectId == 'YOUR_PROJECT_ID_HERE') {
      debugPrint('❌ Error: Please set your Appwrite Project ID');
      return false;
    }
    return true;
  }
}
