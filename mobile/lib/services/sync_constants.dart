class SyncConstants {
  SyncConstants._();

  /// ✅ إصلاح حرج (audit agent-10): ترتيب الجداول المتزامنة الكاملة
  /// محترماً قيود المفاتيح الأجنبية (Foreign Keys).
  ///
  /// المشكلة السابقة:
  ///   - payments كان قبل cash_transactions رغم أن payments.cash_transaction_local_id
  ///     FK→cash_transactions.id → انتهاك FK عند الاستعادة
  ///   - 6 جداول متزامنة كانت مفقودة تماماً (salary_withdrawals, price_adjustments,
  ///     booking_price_adjustments, audit_logs, payment_voids, guest_infos)
  ///     → فقدان صامت لهذه البيانات عند sync rollback
  ///
  /// الترتيب الجديد يتبع الترتيب الطوبولوجي (Topological Sort):
  ///   Level 0: جداول بدون FK صادر
  ///   Level 1: جداول FK→ Level 0
  ///   Level 2: جداول FK→ Level 0/1
  static const tableOrder = [
    // Level 0 — جداول مستقلة بدون FK صادر
    'rooms',
    'employees',
    'cash_transactions',
    'shift_notes',
    'hotel_day_ledger',
    'price_adjustments',
    'audit_logs',
    'payment_voids',
    'guest_infos',
    'ancestor_cache', // ✅ Audit Fix (2026-08-06): كان مفقوداً — لا يُحذف في sync rollback
    'auto_fix_runs',
    'app_sessions',
    'outbox',
    'sync_state',
    'restore_fix_log',
    'sync_queue',
    'sync_log',
    // Level 1 — FK → Level 0
    'bookings', // FK→ rooms.roomNumber
    'expenses', // (لا FK فعلي لكن نضعه هنا للأمان)
    'salary_cycles', // FK→ employees.id
    'sync_conflicts', // FK→ sync_log.id
    // Level 2 — FK → Level 0/1
    'booking_notes', // FK→ bookings.id
    'payments', // FK→ bookings.id, cash_transactions.id
    'debts', // FK→ bookings.id
    'booking_nights', // FK→ bookings.id
    'booking_price_adjustments', // FK→ bookings.localUuid, bookings.id
    'salary_payments', // FK→ salary_cycles.id
    'salary_withdrawals', // FK→ employees.id
    'salary_carry_over_logs', // FK→ employees.id
    'integrity_violations', // FK→ auto_fix_runs.id
  ];

  /// للتوافق مع الكود القديم الذي يستخدم extraTables
  /// الآن كل الجداول في tableOrder، فextraTables فارغ
  static const extraTables = <String>[];

  static List<String> get allTablesInOrder => tableOrder;

  static List<String> get allTablesInReverseOrder =>
      allTablesInOrder.reversed.toList();

  static const int maxErrorMessageLength = 500;
  static const int maxMetricsPayloadLength = 4000;

  static const Duration defaultAutoSyncInterval = Duration(minutes: 15);

  /// مفتاح SharedPreferences لفاصل المزامنة التلقائية (بالدقائق).
  /// يُسمح للمستخدم بتغييره من شاشة الإعدادات دون إعادة بناء التطبيق.
  /// القيم المقترحة:
  ///   5  — للموظفين النشطين (300 reads/hour/device)
  ///   15 — افتراضي (240 reads/hour/device × 3 = 720/hour)
  ///   30 — للأجهزة الثابتة (120 reads/hour/device)
  ///   60 — للأجهزة منخفضة الأولوية (60 reads/hour/device)
  static const String autoSyncIntervalPrefKey = 'auto_sync_interval_minutes';
  static const int autoSyncIntervalDefaultMinutes = 15;
  static const int autoSyncIntervalMinMinutes = 1;
  static const int autoSyncIntervalMaxMinutes = 120;

  /// مهلة تجميع الكتابات المحلية قبل دفعها إلى Appwrite.
  ///
  /// يُعاد تشغيل هذه المهلة عند كل إنشاء أو تعديل أو حذف مسجّل في Outbox؛
  /// لذلك تُرفع الدفعة بعد 3 ثوانٍ من **آخر** تغيير، لا بعد كل نقرة. هذا
  /// يحقق مزامنة شبه فورية من دون طلبات شبكة متتابعة على الأجهزة الضعيفة.
  static const Duration outboxDebounceWindow = Duration(seconds: 3);
  static const Duration guardianOutboxDebounce = Duration(seconds: 30);
  static const Duration guardianLocalChangeDebounce = Duration(seconds: 5);
  static const Duration shortPollingDelay = Duration(milliseconds: 500);
  static const Duration appForegroundDelay = Duration(milliseconds: 500);
  static const Duration appForegroundAppwriteDelay = Duration(
    milliseconds: 1000,
  );

  /// الفترة الزمنية الدنيا بين سحبين تلقائيين عند فتح التطبيق
  /// إذا مرت أقل من هذه المدة منذ آخر سحب تلقائي، يتم تخطي السحب
  static const Duration appOpenSyncInterval = Duration(hours: 1);

  /// مفتاح SharedPreferences لحفظ وقت آخر سحب تلقائي عند فتح التطبيق
  static const String lastAppOpenPullKey = 'last_app_open_pull_epoch_ms';

  static const int googleDriveDefaultShardBytes = 4 * 1024 * 1024;
  static const int estimatedBytesPerDeltaChange = 500;
}
