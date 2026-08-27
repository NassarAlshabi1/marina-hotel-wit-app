import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// إعدادات Appwrite المركزية
class AppwriteConfig {
  // Appwrite Endpoint
  // غيّره عبر --dart-define=APPWRITE_ENDPOINT=... للـ CI أو mockoon
  static const String endpoint = String.fromEnvironment(
    'APPWRITE_ENDPOINT',
    defaultValue: 'https://fra.cloud.appwrite.io/v1',
  );

  // Project ID - من لوحة تحكم Appwrite
  // ✅ تم التغيير (2026-07-22): المشروع القديم (6a2b01d0) تجاوز حد Database Reads.
  // المشروع الجديد (6a4408f3) هو نفسه الذي كان secondary — يعمل بدون مشاكل.
  static const String projectId = '6a4408f300217885fd7b';

  // Database ID - من لوحة تحكم Appwrite
  static const String databaseId = '6a4409b50019dd39dde5';

  // ═══════════════════════════════════════════════════════════════
  //  API Key — مفتاح افتراضي مُدمج في التطبيق
  // ═══════════════════════════════════════════════════════════════
  // مفتاح API الافتراضي المُدمج. يُمكن للمستخدم تغييره في أي وقت من
  // شاشة إعدادات اتصال Appwrite. عند الاستبدال، يُحفظ المفتاح الجديد في
  // SharedPreferences ويُحمَّل عند بدء التطبيق بدلاً من هذا الافتراضي.
  // استخدم AppwriteConfigManager.apiKey للوصول للقيمة الفعّالة وقت التشغيل.
  // ✅ SECURITY: API key via --dart-define, NOT hardcoded.
  // Pass at build time: --dart-define=APPWRITE_API_KEY=standard_xxx
  static const String defaultApiKey = String.fromEnvironment(
    'APPWRITE_API_KEY',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Messaging — Appwrite Messaging Provider ID
  // ═══════════════════════════════════════════════════════════════
  // يُستخدم في AppwriteMessagingService.registerDevice() لتسجيل الـ Target.
  // احصل عليه من: Appwrite Console → Messaging → Providers → FCM → _id
  // القيم الافتراضية الشائعة: 'fcm' أو مخصّص مثل '6702abcdef1234567890'
  static const String messagingProviderId = String.fromEnvironment(
    'APPWRITE_MESSAGING_PROVIDER_ID',
    defaultValue: 'fcm',
  );

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
  static const String bookingPriceAdjustmentsCollectionId =
      'booking_price_adjustments';
  static const String auditLogsCollectionId = 'audit_logs';
  static const String paymentVoidsCollectionId = 'payment_voids';

  // جدول معلومات النزلاء
  static const String guestInfosCollectionId = 'guest_infos';

  // جدول سحوبات الرواتب
  static const String salaryWithdrawalsCollectionId = 'salary_withdrawals';

  // جدول سجلات ترحيل الرواتب
  static const String salaryCarryOverLogsCollectionId =
      'salary_carry_over_logs';

  // جدول إعدادات التطبيق (واتساب، وغيرها)
  static const String appSettingsCollectionId = 'app_settings';
  static const String inventoryItemsCollectionId = 'inventory_items';
  static const String inventoryTransactionsCollectionId =
      'inventory_transactions';

  /// خرائط أسماء الكيانات إلى collection IDs.
  /// تستخدم لتحويل اسم الكيان في outbox (مثل 'bookings') إلى collection ID
  /// في Appwrite (مثل 'bookings'). حالياً الاسم واحد، لكن هذه الخريطة
  /// تسمح بتغيير الأسماء مستقبلاً دون تعديل كل الاستدعاءات.
  static const Map<String, String> _entityToCollection = {
    'rooms': roomsCollectionId,
    'bookings': bookingsCollectionId,
    'payments': paymentsCollectionId,
    'expenses': expensesCollectionId,
    'employees': employeesCollectionId,
    'debts': debtsCollectionId,
    'booking_notes': bookingNotesCollectionId,
    'shift_notes': shiftNotesCollectionId,
    'cash_transactions': cashTransactionsCollectionId,
    'booking_nights': bookingNightsCollectionId,
    'salary_cycles': salaryCyclesCollectionId,
    'salary_payments': salaryPaymentsCollectionId,
    'salary_withdrawals': salaryWithdrawalsCollectionId,
    'salary_carry_over_logs': salaryCarryOverLogsCollectionId,
    'blacklist': blacklistCollectionId,
    'price_adjustments': priceAdjustmentsCollectionId,
    'booking_price_adjustments': bookingPriceAdjustmentsCollectionId,
    'audit_logs': auditLogsCollectionId,
    'payment_voids': paymentVoidsCollectionId,
    'guest_infos': guestInfosCollectionId,
    'app_settings': appSettingsCollectionId,
    'inventory_items': inventoryItemsCollectionId,
    'inventory_transactions': inventoryTransactionsCollectionId,
  };

  /// يحوّل اسم الكيان إلى collection ID في Appwrite.
  /// يُرجع null إذا لم يكن الكيان معروفاً (مثل 'hotel_day_ledger' المحلي فقط).
  static String? collectionIdFor(String entity) {
    return _entityToCollection[entity];
  }

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
      dlog('═══════════════════════════════════════');
      dlog('🔧 Appwrite Configuration');
      dlog('═══════════════════════════════════════');
      dlog(() => 'Endpoint: $endpoint');
      dlog(() => 'Project ID: $projectId');
      dlog(() => 'Database ID: $databaseId');
      dlog(() => 'Sync Interval: ${syncInterval.inMinutes} minutes');
      dlog(() => 'Cache Expiry: ${cacheExpiry.inHours} hours');
      dlog(() => 'Max Cache Size: $maxCacheSizeMB MB');
      dlog(() => 'Default Page Size: $defaultPageSize');
      dlog(() => 'Max Page Size: $maxPageSize');
      dlog(() => 'Batch Size: $batchSize');
      dlog(() => 'Max Retries: $maxRetries');
      dlog(() => 'Default Timeout: ${defaultTimeout.inSeconds}s');
      dlog(() => 'Long Timeout: ${longTimeout.inSeconds}s');
      dlog('═══════════════════════════════════════');
    }
  }

  /// التحقق من صحة الإعدادات
  static bool validateConfig() {
    if (projectId == 'YOUR_PROJECT_ID_HERE') {
      dlog('❌ Error: Please set your Appwrite Project ID');
      return false;
    }
    return true;
  }
}
