import 'package:flutter/foundation.dart';

/// إعدادات Appwrite المُحسَّنة للسرعة
///
/// يحتفظ بجميع الثوابت القديمة كـ aliases للتوافق العكسي مع الكود الموجود.
/// الثوابت الجديدة تُسبق بتعليق ⚡ .
class AppwriteConfig {
  AppwriteConfig._(); // منع الإنشاء

  // ═══════════════════════════════════════════════════════════════════
  // بيانات الاتصال
  // ═══════════════════════════════════════════════════════════════════

  /// Endpoint مع Keep-Alive و HTTP/2
  static const String endpoint = 'https://fra.cloud.appwrite.io/v1';

  /// Project ID
  static const String projectId = '690ff0da0025518570c1';

  /// Database ID
  static const String databaseId = 'hotel_db';

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ معرفات المجموعات — ترتيب حسب الأولوية
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ المجموعات الحرجة (يتم تحميلها أولاً)
  static const List<String> criticalCollections = [
    'rooms',
    'bookings',
    'payments',
  ];

  /// ⚡ المجموعات الثانوية (تحميل متأخر)
  static const List<String> secondaryCollections = [
    'expenses',
    'employees',
    'debts',
    'devices',
    'sync_logs',
  ];

  /// ⚡ المجموعات الإضافية (تحميل عند الطلب)
  static const List<String> onDemandCollections = [
    'booking_notes',
    'cash_transactions',
    'booking_nights',
    'salary_cycles',
    'salary_payments',
    'salary_withdrawals',
    'shift_notes',
    'price_adjustments',
    'booking_price_adjustments',
    'audit_logs',
    'payment_voids',
  ];

  /// ⚡ جميع المجموعات القابلة للمزامنة
  static const List<String> allSyncableCollections = [
    ...criticalCollections,
    ...secondaryCollections,
    ...onDemandCollections,
  ];

  // ═══════════════════════════════════════════════════════════════════
  // معرفات المجموعات الفردية — محفوظة للتوافق العكسي (150+ استدعاء)
  // ═══════════════════════════════════════════════════════════════════

  // المجموعات الحرجة
  static const String roomsCollectionId = 'rooms';
  static const String bookingsCollectionId = 'bookings';
  static const String paymentsCollectionId = 'payments';

  // المجموعات الثانوية
  static const String expensesCollectionId = 'expenses';
  static const String employeesCollectionId = 'employees';
  static const String debtsCollectionId = 'debts';
  static const String devicesCollectionId = 'devices';
  static const String syncLogsCollectionId = 'sync_logs';

  // المجموعات الإضافية
  static const String bookingNotesCollectionId = 'booking_notes';
  static const String cashTransactionsCollectionId = 'cash_transactions';
  static const String bookingNightsCollectionId = 'booking_nights';
  static const String salaryCyclesCollectionId = 'salary_cycles';
  static const String salaryPaymentsCollectionId = 'salary_payments';
  static const String salaryWithdrawalsCollectionId = 'salary_withdrawals';
  static const String shiftNotesCollectionId = 'shift_notes';
  static const String priceAdjustmentsCollectionId = 'price_adjustments';
  static const String bookingPriceAdjustmentsCollectionId =
      'booking_price_adjustments';
  static const String auditLogsCollectionId = 'audit_logs';
  static const String paymentVoidsCollectionId = 'payment_voids';

  // ❌ محلي فقط — لا يتم مزامنته مع Appwrite
  static const String localOnlyCollection = 'hotel_day_ledger';

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ إعدادات المهلات السريعة
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ مهلة الاتصال (5 ثوانٍ بدلاً من 30)
  static const Duration connectionTimeout = Duration(seconds: 5);

  /// ⚡ مهلة الاستلام (10 ثوانٍ بدلاً من 30)
  static const Duration receiveTimeout = Duration(seconds: 10);

  /// ⚡ مهلة الإرسال (8 ثوانٍ للكتابة)
  static const Duration sendTimeout = Duration(seconds: 8);

  /// ⚡ مهلة خاصة للـ ping (3 ثوانٍ)
  static const Duration pingTimeout = Duration(seconds: 3);

  /// ⚡ مهلة العمليات الكبيرة (دقيقة واحدة بدلاً من 2)
  static const Duration longOperationTimeout = Duration(minutes: 1);

  // ── Aliases للتوافق العكسي ──

  /// @Deprecated استخدم connectionTimeout. محفوظ للتوافق العكسي.
  static const Duration defaultTimeout = connectionTimeout;

  /// @Deprecated استخدم longOperationTimeout. محفوظ للتوافق العكسي.
  static const Duration longTimeout = longOperationTimeout;

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ إعدادات المزامنة السريعة
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ مزامنة فورية عند الاتصال
  static const bool syncOnConnect = true;

  /// ⚡ فاصل المزامنة الحرجة (5 دقائق بدلاً من 15)
  static const Duration criticalSyncInterval = Duration(minutes: 5);

  /// ⚡ فاصل المزامنة العادية (15 دقيقة)
  static const Duration normalSyncInterval = Duration(minutes: 15);

  /// ⚡ فاصل المزامنة في الخلفية (ساعة واحدة)
  static const Duration backgroundSyncInterval = Duration(hours: 1);

  // ── Aliases للتوافق العكسي ──

  /// @Deprecated استخدم normalSyncInterval. محفوظ للتوافق العكسي.
  static const Duration syncInterval = normalSyncInterval;

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ إعدادات Pagination و Batch السريعة
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ حجم الدفعة الأمثل (100 بدلاً من 50)
  static const int optimalBatchSize = 100;

  /// ⚡ حجم الدفعة الأقصى
  static const int maxBatchSize = 200;

  /// ⚡ حجم الصفحة للقراءة السريعة (50 بدلاً من 25)
  static const int fastPageSize = 50;

  /// ⚡ الحد الأقصى لحجم الصفحة
  static const int maxFastPageSize = 100;

  // ── Aliases للتوافق العكسي ──

  /// @Deprecated استخدم optimalBatchSize. محفوظ للتوافق العكسي.
  static const int batchSize = optimalBatchSize;

  /// @Deprecated استخدم fastPageSize. محفوظ للتوافق العكسي.
  static const int defaultPageSize = fastPageSize;

  /// @Deprecated استخدم maxFastPageSize. محفوظ للتوافق العكسي.
  static const int maxPageSize = maxFastPageSize;

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ إعدادات التخزين المؤقت
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ مدة التخزين المؤقت في الذاكرة (5 دقائق بدلاً من 6 ساعات)
  static const Duration memoryCacheExpiry = Duration(minutes: 5);

  /// ⚡ مدة التخزين المؤقت على القرص (ساعتان بدلاً من 6)
  static const Duration diskCacheExpiry = Duration(hours: 2);

  /// ⚡ حجم التخزين المؤقت في الذاكرة (50 ميجابايت بدلاً من 20)
  static const int memoryCacheSizeMB = 50;

  /// ⚡ حجم التخزين المؤقت على القرص (100 ميجابايت)
  static const int diskCacheSizeMB = 100;

  /// ⚡ تخزين مؤقت فوري للبيانات الحرجة
  static const bool cacheCriticalData = true;

  /// ⚡ تحميل مسبق للبيانات ذات الصلة
  static const bool prefetchRelatedData = true;

  // ── Aliases للتوافق العكسي ──

  /// @Deprecated استخدم memoryCacheExpiry. محفوظ للتوافق العكسي.
  static const Duration cacheExpiry = memoryCacheExpiry;

  /// @Deprecated استخدم memoryCacheSizeMB. محفوظ للتوافق العكسي.
  static const int maxCacheSizeMB = memoryCacheSizeMB;

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ إعدادات إعادة المحاولة السريعة
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ عدد المحاولات السريعة (2 بدلاً من 3)
  static const int fastRetries = 2;

  /// ⚡ تأخير المحاولة الأولى (500ms بدلاً من 2s)
  static const Duration fastRetryDelay = Duration(milliseconds: 500);

  /// ⚡ معامل التصاعد (1.5 بدلاً من 2.0)
  static const double fastBackoffMultiplier = 1.5;

  /// ⚡ عدد محاولات العمليات الحرجة (5)
  static const int criticalRetries = 5;

  /// ⚡ تأخير المحاولات الحرجة (ثانية واحدة)
  static const Duration criticalRetryDelay = Duration(seconds: 1);

  // ── Aliases للتوافق العكسي ──

  /// @Deprecated استخدم fastRetries. محفوظ للتوافق العكسي.
  static const int maxRetries = fastRetries;

  /// @Deprecated استخدم fastRetryDelay. محفوظ للتوافق العكسي.
  static const Duration initialRetryDelay = fastRetryDelay;

  /// @Deprecated استخدم fastBackoffMultiplier. محفوظ للتوافق العكسي.
  static const double retryBackoffMultiplier = fastBackoffMultiplier;

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ إعدادات HTTP
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ Keep-Alive للاتصالات المستمرة
  static const bool enableHttpKeepAlive = true;

  /// ⚡ مدة Keep-Alive
  static const Duration keepAliveDuration = Duration(minutes: 5);

  /// ⚡ HTTP/2 للسرعة
  static const bool enableHttp2 = true;

  /// ⚡ ضغط الاستجابة
  static const bool enableCompression = true;

  /// ⚡ عدد الاتصالات الأقصى لكل host
  static const int maxConnectionsPerHost = 10;

  /// ⚡ عدد الاتصالات الخاملة
  static const int idleConnectionCount = 5;

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ إعدادات Warm-up
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ تهيئة مسبقة للاتصال
  static const bool enableConnectionWarmup = true;

  /// ⚡ مهلة الـ warm-up
  static const Duration warmupTimeout = Duration(seconds: 3);

  /// ⚡ تحميل مسبق للبيانات الحرجة
  static const bool enableCriticalDataPrefetch = true;

  /// ⚡ DNS Cache
  static const bool enableDnsCache = true;

  /// ⚡ مدة DNS Cache
  static const Duration dnsCacheDuration = Duration(minutes: 10);

  // ═══════════════════════════════════════════════════════════════════
  // ⚡ دوال مساعدة للسرعة
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

  /// الحصول على حجم الدفعة الأمثل بناءً على العدد الإجمالي
  static int batchSizeFor(int totalCount) {
    if (totalCount <= 10) return totalCount;
    if (totalCount <= optimalBatchSize) return totalCount;
    if (totalCount <= maxBatchSize * 2) return optimalBatchSize;
    return maxBatchSize;
  }

  /// ⚡ Headers مُحسَّنة للسرعة
  static Map<String, String> get fastHeaders => {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': projectId,
        'Accept-Encoding': 'gzip',
        'Connection': 'keep-alive',
        'X-Appwrite-Response-Format': '1.0',
      };

  /// ⚡ URL للمجموعة مع معاملات السرعة
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
    if (limit != null) {
      params.add('limit=$limit');
    }
    if (offset != null) {
      params.add('offset=$offset');
    }

    if (params.isEmpty) return base;
    return '$base?${params.join('&')}';
  }

  // ═══════════════════════════════════════════════════════════════════
  // التسجيل والتشخيص
  // ═══════════════════════════════════════════════════════════════════

  /// ⚡ طباعة الإعدادات المُحسَّنة
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
    debugPrint('║   • Critical: ${criticalSyncInterval.inMinutes}min');
    debugPrint('║   • Normal: ${normalSyncInterval.inMinutes}min');
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

  /// ⚡ التحقق من صحة الإعدادات
  static bool validateFastConfig() {
    var isValid = true;

    if (!endpoint.startsWith('https://')) {
      debugPrint('❌ Error: HTTPS required');
      isValid = false;
    }

    if (connectionTimeout > Duration(seconds: 10)) {
      debugPrint('⚠️ Warning: Connection timeout too slow');
    }

    return isValid;
  }

  /// طباعة الإعدادات (محفوظ للتوافق العكسي — يستدعي printFastConfig)
  static void printConfig() => printFastConfig();

  /// التحقق من صحة الإعدادات (محفوظ للتوافق العكسي — يستدعي validateFastConfig)
  static bool validateConfig() => validateFastConfig();
}
