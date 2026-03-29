import 'package:flutter/foundation.dart';

/// إعدادات Appwrite المُحسَّنة للسرعة
///
/// يحتفظ بجميع الثوابت القديمة كـ aliases للتوافق مع الكود الموجود (~160 مرجع عبر 17 ملف).
/// الثوابت الجديدة مُحسّنة للسرعة مع الحفاظ على التوافق الكامل.
class AppwriteConfig {
  AppwriteConfig._(); // منع الإنشاء

  // ═══════════════════════════════════════════════════════════════════
  // بيانات الاتصال
  // ═══════════════════════════════════════════════════════════════════

  /// Endpoint مع Keep-Alive وHTTP/2
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';

  /// Project ID
  static const String projectId = '690ff0da0025518570c1';

  /// Database ID
  static const String databaseId = 'hotel_db';

  // ═══════════════════════════════════════════════════════════════════
  // معرفات المجموعات — أسماء ثابتة (مُستخدمة عبر 17 ملف، ~160 مرجع)
  // ═══════════════════════════════════════════════════════════════════

  // --- المجموعات الحرجة (يتم تحميلها أولاً) ---
  static const String roomsCollectionId = 'rooms';
  static const String bookingsCollectionId = 'bookings';
  static const String paymentsCollectionId = 'payments';

  // --- المجموعات الثانوية ---
  static const String expensesCollectionId = 'expenses';
  static const String employeesCollectionId = 'employees';
  static const String debtsCollectionId = 'debts';
  static const String devicesCollectionId = 'devices';
  static const String syncLogsCollectionId = 'sync_logs';

  // --- المجموعات الإضافية ---
  static const String bookingNotesCollectionId = 'booking_notes';
  static const String cashTransactionsCollectionId = 'cash_transactions';
  static const String bookingNightsCollectionId = 'booking_nights';
  static const String salaryCyclesCollectionId = 'salary_cycles';
  static const String salaryPaymentsCollectionId = 'salary_payments';
  static const String salaryWithdrawalsCollectionId = 'salary_withdrawals';
  static const String shiftNotesCollectionId = 'shift_notes';

  // --- جداول التدقيق المالي والتعديلات ---
  static const String priceAdjustmentsCollectionId = 'price_adjustments';
  static const String bookingPriceAdjustmentsCollectionId =
      'booking_price_adjustments';
  static const String auditLogsCollectionId = 'audit_logs';
  static const String paymentVoidsCollectionId = 'payment_voids';

  // --- محلي فقط — لا يتم مزامنته مع Appwrite ---
  static const String localOnlyCollection = 'hotel_day_ledger';

  // ═══════════════════════════════════════════════════════════════════
  // قوائم المجموعات — للعمليات الجماعية (مزامنة، نسخ احتياطي)
  // ═══════════════════════════════════════════════════════════════════

  /// المجموعات الحرجة (يتم تحميلها أولاً)
  static const List<String> criticalCollections = [
    roomsCollectionId,
    bookingsCollectionId,
    paymentsCollectionId,
  ];

  /// المجموعات الثانوية (تحميل متأخر)
  static const List<String> secondaryCollections = [
    expensesCollectionId,
    employeesCollectionId,
    debtsCollectionId,
    devicesCollectionId,
    syncLogsCollectionId,
  ];

  /// المجموعات الإضافية (تحميل عند الطلب)
  static const List<String> onDemandCollections = [
    bookingNotesCollectionId,
    cashTransactionsCollectionId,
    bookingNightsCollectionId,
    salaryCyclesCollectionId,
    salaryPaymentsCollectionId,
    salaryWithdrawalsCollectionId,
    shiftNotesCollectionId,
    priceAdjustmentsCollectionId,
    bookingPriceAdjustmentsCollectionId,
    auditLogsCollectionId,
    paymentVoidsCollectionId,
  ];

  /// جميع المجموعات القابلة للمزامنة
  static const List<String> allSyncableCollections = [
    ...criticalCollections,
    ...secondaryCollections,
    ...onDemandCollections,
  ];

  // ═══════════════════════════════════════════════════════════════════
  // إعدادات المهلات المُحسَّنة للسرعة
  // ═══════════════════════════════════════════════════════════════════

  /// مهلة الاتصال — ⚡ 5 ثوانٍ (كانت 30)
  static const Duration connectionTimeout = Duration(seconds: 5);

  /// مهلة استقبال البيانات — ⚡ 10 ثوانٍ (كانت 30)
  static const Duration receiveTimeout = Duration(seconds: 10);

  /// مهلة إرسال البيانات — للعمليات الكتابة
  static const Duration sendTimeout = Duration(seconds: 8);

  /// مهلة خاصة لـ ping (اختبار سريع)
  static const Duration pingTimeout = Duration(seconds: 3);

  /// مهلة للعمليات الكبيرة — ⚡ 1 دقيقة (كانت 2)
  static const Duration longOperationTimeout = Duration(minutes: 1);

  // --- Aliases للتوافق مع الكود الموجود ---
  /// @deprecated استخدم connectionTimeout
  static const Duration defaultTimeout = connectionTimeout;

  /// @deprecated استخدم longOperationTimeout
  static const Duration longTimeout = longOperationTimeout;

  // ═══════════════════════════════════════════════════════════════════
  // إعدادات إعادة المحاولة المُحسَّنة
  // ═══════════════════════════════════════════════════════════════════

  /// عدد المحاولات — ⚡ 2 (كانت 3)
  static const int fastRetries = 2;
  static const Duration fastRetryDelay =
      Duration(milliseconds: 500); // ⚡ كان 2 ثانية
  static const double fastBackoffMultiplier = 1.5; // ⚡ كان 2.0

  /// إعادة محاولة للعمليات الحرجة
  static const int criticalRetries = 5;
  static const Duration criticalRetryDelay = Duration(seconds: 1);

  // --- Aliases للتوافق مع الكود الموجود ---
  /// @deprecated استخدم fastRetries
  static const int maxRetries = fastRetries;

  /// @deprecated استخدم fastRetryDelay
  static const Duration initialRetryDelay = fastRetryDelay;

  /// @deprecated استخدم fastBackoffMultiplier
  static const double retryBackoffMultiplier = fastBackoffMultiplier;

  // ═══════════════════════════════════════════════════════════════════
  // إعدادات المزامنة المُحسَّنة
  // ═══════════════════════════════════════════════════════════════════

  /// مزامنة فورية عند الاتصال
  static const bool syncOnConnect = true;

  /// فاصل المزامنة الحرجة — ⚡ 5 دقائق
  static const Duration criticalSyncInterval = Duration(minutes: 5);

  /// فاصل المزامنة العادية — 15 دقيقة
  static const Duration normalSyncInterval = Duration(minutes: 15);

  /// فاصل المزامنة الخلفية — ساعة
  static const Duration backgroundSyncInterval = Duration(hours: 1);

  // --- Aliases للتوافق ---
  /// @deprecated استخدم normalSyncInterval
  static const Duration syncInterval = normalSyncInterval;

  // ═══════════════════════════════════════════════════════════════════
  // إعدادات Pagination و Batch المُحسَّنة
  // ═══════════════════════════════════════════════════════════════════

  /// حجم الدفعة الأمثل — ⚡ 100 (كان 50)
  static const int optimalBatchSize = 100;
  static const int maxBatchSize = 200;

  /// حجم الصفحة السريع — ⚡ 50 (كان 25)
  static const int fastPageSize = 50;
  static const int maxFastPageSize = 100;

  // --- Aliases للتوافق ---
  /// @deprecated استخدم fastPageSize
  static const int defaultPageSize = fastPageSize;

  /// @deprecated استخدم maxFastPageSize
  static const int maxPageSize = maxFastPageSize;

  /// @deprecated استخدم optimalBatchSize
  static const int batchSize = optimalBatchSize;

  // ═══════════════════════════════════════════════════════════════════
  // إعدادات التخزين المؤقت المُحسَّنة
  // ═══════════════════════════════════════════════════════════════════

  /// تخزين مؤقت في الذاكرة — 5 دقائق
  static const Duration memoryCacheExpiry = Duration(minutes: 5);

  /// تخزين مؤقت على القرص — ⚡ ساعتان (كان 6 ساعات)
  static const Duration diskCacheExpiry = Duration(hours: 2);

  /// حجم الذاكرة — 50MB
  static const int memoryCacheSizeMB = 50;

  /// حجم القرص — 100MB
  static const int diskCacheSizeMB = 100;

  /// تخزين مؤقت فوري للبيانات الحرجة
  static const bool cacheCriticalData = true;
  static const bool prefetchRelatedData = true;

  // --- Aliases للتوافق ---
  /// @deprecated استخدم diskCacheExpiry
  static const Duration cacheExpiry = diskCacheExpiry;

  /// @deprecated استخدم memoryCacheSizeMB
  static const int maxCacheSizeMB = memoryCacheSizeMB;

  // ═══════════════════════════════════════════════════════════════════
  // إعدادات HTTP المُحسَّنة
  // ═══════════════════════════════════════════════════════════════════

  static const bool enableHttpKeepAlive = true;
  static const Duration keepAliveDuration = Duration(minutes: 5);
  static const bool enableHttp2 = true;
  static const bool enableCompression = true;
  static const int maxConnectionsPerHost = 10;
  static const int idleConnectionCount = 5;

  // ═══════════════════════════════════════════════════════════════════
  // إعدادات الـ Warm-up
  // ═══════════════════════════════════════════════════════════════════

  static const bool enableConnectionWarmup = true;
  static const Duration warmupTimeout = Duration(seconds: 3);
  static const bool enableCriticalDataPrefetch = true;
  static const bool enableDnsCache = true;
  static const Duration dnsCacheDuration = Duration(minutes: 10);

  // ═══════════════════════════════════════════════════════════════════
  // دوال مساعدة للسرعة
  // ═══════════════════════════════════════════════════════════════════

  /// الحصول على المهلة حسب نوع العملية
  static Duration timeoutFor(String operation) => switch (operation) {
        'ping' || 'health' => pingTimeout,
        'read' || 'query' => receiveTimeout,
        'write' || 'create' || 'update' || 'delete' => sendTimeout,
        'batch' || 'bulk' => longOperationTimeout,
        'connect' => connectionTimeout,
        _ => receiveTimeout,
      };

  /// الحصول على فاصل المزامنة حسب الأولوية
  static Duration syncIntervalFor(String priority) => switch (priority) {
        'critical' => criticalSyncInterval,
        'normal' => normalSyncInterval,
        'background' => backgroundSyncInterval,
        _ => normalSyncInterval,
      };

  /// الحصول على حجم الدفعة الأمثل
  static int batchSizeFor(int totalCount) {
    if (totalCount <= 10) return totalCount;
    if (totalCount <= optimalBatchSize) return totalCount;
    if (totalCount <= maxBatchSize * 2) return optimalBatchSize;
    return maxBatchSize;
  }

  /// Headers مُحسَّنة للسرعة
  static Map<String, String> get fastHeaders => {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': projectId,
        'Accept-Encoding': 'gzip',
        'Connection': 'keep-alive',
        'X-Appwrite-Response-Format': '1.0',
      };

  /// URL للمجموعة مع معاملات السرعة
  static String fastCollectionUrl(
    String collectionId, {
    List<String>? queries,
    int? limit,
    int? offset,
  }) {
    final base =
        '$endpoint/databases/$databaseId/collections/$collectionId/documents';
    final params = <String>[];

    if (queries != null && queries.isNotEmpty) {
      params.addAll(queries.map((q) => 'queries[]=$q'));
    }
    if (limit != null) params.add('limit=$limit');
    if (offset != null) params.add('offset=$offset');

    if (params.isEmpty) return base;
    return '$base?${params.join('&')}';
  }

  // ═══════════════════════════════════════════════════════════════════
  // التسجيل والتشخيص
  // ═══════════════════════════════════════════════════════════════════

  /// طباعة الإعدادات المُحسَّنة (للتشخيص في Debug mode)
  static void printFastConfig() {
    if (!kDebugMode) return;

    debugPrint(
        '╔════════════════════════════════════════════════════════════╗');
    debugPrint(
        '║           ⚡ Appwrite Fast Configuration                   ║');
    debugPrint(
        '╠════════════════════════════════════════════════════════════╣');
    debugPrint('║ Endpoint: $endpoint');
    debugPrint('║ Project: ${projectId.substring(0, 8)}...');
    debugPrint(
        '║ ════════════════════════════════════════════════════════════');
    debugPrint('║ ⚡ السرعة:');
    debugPrint('║   • Connection: ${connectionTimeout.inSeconds}s');
    debugPrint('║   • Receive: ${receiveTimeout.inSeconds}s');
    debugPrint('║   • Ping: ${pingTimeout.inSeconds}s');
    debugPrint('║   • HTTP/2: ${enableHttp2 ? "✅" : "❌"}');
    debugPrint('║   • Keep-Alive: ${enableHttpKeepAlive ? "✅" : "❌"}');
    debugPrint(
        '║ ════════════════════════════════════════════════════════════');
    debugPrint('║ 🔄 المزامنة:');
    debugPrint(
        '║   • Critical: ${criticalSyncInterval.inMinutes}min');
    debugPrint(
        '║   • Normal: ${normalSyncInterval.inMinutes}min');
    debugPrint('║   • Batch Size: $optimalBatchSize');
    debugPrint(
        '║ ════════════════════════════════════════════════════════════');
    debugPrint('║ 💾 التخزين المؤقت:');
    debugPrint(
        '║   • Memory: ${memoryCacheSizeMB}MB (${memoryCacheExpiry.inMinutes}min)');
    debugPrint(
        '║   • Disk: ${diskCacheSizeMB}MB (${diskCacheExpiry.inHours}h)');
    debugPrint(
        '╚════════════════════════════════════════════════════════════╝');
  }

  /// طباعة الإعدادات (للتشخيص) — alias للتوافق
  static void printConfig() => printFastConfig();

  /// التحقق من صحة الإعدادات
  static bool validateConfig() {
    var isValid = true;

    if (projectId == 'YOUR_PROJECT_ID_HERE') {
      debugPrint('❌ Error: Please set your Appwrite Project ID');
      isValid = false;
    }

    if (!endpoint.startsWith('https://')) {
      debugPrint('❌ Error: HTTPS required');
      isValid = false;
    }

    if (kDebugMode && connectionTimeout > Duration(seconds: 10)) {
      debugPrint('⚠️ Warning: Connection timeout too slow');
    }

    return isValid;
  }

  /// التحقق من صحة الإعدادات المُحسَّنة
  static bool validateFastConfig() => validateConfig();
}
