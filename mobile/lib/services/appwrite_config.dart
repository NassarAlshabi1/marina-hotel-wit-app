import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// إعدادات Appwrite المركزية
class AppwriteConfig {
  // Appwrite Endpoint
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';

  // Project ID - من لوحة تحكم Appwrite
  static const String projectId = '690ff0da0025518570c1';

  // Database ID - من لوحة تحكم Appwrite
  static const String databaseId = 'hotel_db';

  // Collections IDs
  static const String roomsCollectionId = 'rooms';
  static const String bookingsCollectionId = 'bookings';
  static const String paymentsCollectionId = 'payments';
  static const String expensesCollectionId = 'expenses';
  static const String employeesCollectionId = 'employees';
  static const String debtsCollectionId = 'debts';
  static const String devicesCollectionId = 'devices';
  static const String syncLogsCollectionId = 'sync_logs';

  // إضافات الجداول المتوفرة في local_db
  static const String bookingNotesCollectionId = 'booking_notes';
  static const String cashTransactionsCollectionId = 'cash_transactions';
  static const String bookingNightsCollectionId = 'booking_nights';
  // ❌ hotel_day_ledger — جدول محلي فقط، لا يتم مزامنته، غير موجود على Appwrite Cloud
  // تم إزالة hotelDayLedgerCollectionId لأنه لا وجود له على السحابة
  static const String salaryCyclesCollectionId = 'salary_cycles';
  static const String salaryPaymentsCollectionId = 'salary_payments';
  static const String shiftNotesCollectionId = 'shift_notes';
  static const String blacklistCollectionId = 'blacklist';
  
  // جداول التدقيق المالي والتعديلات
  static const String priceAdjustmentsCollectionId = 'price_adjustments';
  static const String bookingPriceAdjustmentsCollectionId = 'booking_price_adjustments';
  static const String auditLogsCollectionId = 'audit_logs';
  static const String paymentVoidsCollectionId = 'payment_voids';
  
  // جدول معلومات النزلاء
  static const String guestInfosCollectionId = 'guest_infos';
  
  // جدول سحوبات الرواتب
  static const String salaryWithdrawalsCollectionId = 'salary_withdrawals';

  // جدول إعدادات التطبيق (واتساب، وغيرها)
  static const String appSettingsCollectionId = 'app_settings';

  // إعدادات المزامنة
  static const Duration syncInterval = Duration(minutes: 15);
  static const Duration cacheExpiry = Duration(hours: 6);
  static const int maxCacheSizeMB = 20;
  static const int maxRetries = 3;
  static const Duration initialRetryDelay = Duration(seconds: 2);
  static const double retryBackoffMultiplier =
      2.0; // Exponential backoff multiplier

  // إعدادات Timeout
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration longTimeout = Duration(minutes: 2); // للعمليات الكبيرة

  // إعدادات Pagination
  static const int defaultPageSize = 25; // عدد السجلات في كل صفحة
  static const int maxPageSize = 100; // الحد الأقصى للسجلات
  static const int batchSize = 50; // عدد السجلات في كل دفعة

  /// طباعة الإعدادات (للتشخيص)
  static void printConfig() {
    if (kDebugMode) {
      AppLogger.info('═══════════════════════════════════════');
      AppLogger.info('🔧 Appwrite Configuration');
      AppLogger.info('═══════════════════════════════════════');
      AppLogger.info('Endpoint: $endpoint');
      AppLogger.info('Project ID: $projectId');
      AppLogger.info('Database ID: $databaseId');
      AppLogger.info('Sync Interval: ${syncInterval.inMinutes} minutes');
      AppLogger.info('Cache Expiry: ${cacheExpiry.inHours} hours');
      AppLogger.info('Max Cache Size: $maxCacheSizeMB MB');
      AppLogger.info('Default Page Size: $defaultPageSize');
      AppLogger.info('Max Page Size: $maxPageSize');
      AppLogger.info('Batch Size: $batchSize');
      AppLogger.info('Max Retries: $maxRetries');
      AppLogger.info('Default Timeout: ${defaultTimeout.inSeconds}s');
      AppLogger.info('Long Timeout: ${longTimeout.inSeconds}s');
      AppLogger.info('═══════════════════════════════════════');
    }
  }

  /// التحقق من صحة الإعدادات
  static bool validateConfig() {
    if (projectId == 'YOUR_PROJECT_ID_HERE') {
      AppLogger.error('❌ Error: Please set your Appwrite Project ID');
      return false;
    }
    return true;
  }
}
