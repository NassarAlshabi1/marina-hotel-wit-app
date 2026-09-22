// ═══════════════════════════════════════════════════════════════
//  cloudflare_sync_manager.dart — Cloudflare Sync Manager
//  Drop-in replacement for AppwriteSyncManager
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/settings/error_tracker_screen.dart'
    show logHttpError, logError, ErrorCategory;
import '../utils/env.dart';
import 'appwrite_models.dart' show AppwriteDevice;
import 'booking_derived_fields_service.dart';
import 'cloudflare_config.dart';
import 'cloudflare_d1_service.dart';
import 'cloudflare_dual_run_service.dart';
import 'cloudflare_realtime_sync.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'logging/log_models.dart' show LogLevel;
import 'remote_change_notifier.dart';
import 'resilient_http_client.dart';
import 'sync/payload_normalizer.dart';
import 'sync_core/smart_conflict_resolver.dart';
import 'sync_enums.dart';
import 'vector_clock_service.dart';

// ✅ المرحلة 3: التنفيذ الكامل للـ Realtime في cloudflare_realtime_sync.dart
// (WebSocket على SyncLockDO) — الاستيراد أعلاه + هذا الـ export يحفظان
// كل imports القائمة دون تغيير في بقية الملفات.
export 'cloudflare_realtime_sync.dart';

// ─── قواعد ترجمة علاقات FK بين هوية الخادم والهوية المحلية ─────

/// نوع قاعدة FK:
/// - [numericPointer]: العمود الرقمي على الابن يحمل id الأب في فضاء
///   الخادم (D1) — تُترجم القيمة إلى id الصف المحلي عند التطبيق.
/// - [naturalKey]: العمود نصّي يحمل مفتاحاً عالمياً ثابتاً بين الأجهزة
///   (room_number أو local_uuid للأب) — القيمة تمر كما هي، والمطلوب
///   فقط التأكد من وجود الأب (وإلا يؤجَّل الصف).
enum _FkKind { numericPointer, naturalKey }

class _FkRule {
  const _FkRule({
    required this.entity,
    required this.column,
    required this.kind,
    required this.parentTable,
    required this.parentKeyColumn,
    this.nullable = false,
    this.uuidCacheColumn,
    this.legacyServerBookingId = false,
    this.nullWhenUnresolvable = false,
  });

  /// كيان الابن (اسم جدول D1).
  final String entity;

  /// عمود FK على الابن.
  final String column;

  final _FkKind kind;

  /// جدول الأب المحلي.
  final String parentTable;

  /// عمود المفتاح على الأب: 'id' للمؤشرات الرقمية، أو المفتاح الطبيعي
  /// (room_number / local_uuid) لقواعد naturalKey.
  final String parentKeyColumn;

  /// هل يقبل العمود NULL محلياً؟ (غير القابل للـ null بلا حل = تأجيل).
  final bool nullable;

  /// عمود uuid-cache على الابن يحمل local_uuid الأب — المفتاح العالمي
  /// الأول (مثل booking_uuid_cache / item_local_uuid).
  final String? uuidCacheColumn;

  /// جرّب أيضاً فضاء Appwrite القديم: server_booking_id على الابن ضد
  /// server_booking_id على الأب (الصفوف المهاجرة من Appwrite تشترك
  /// في فضاء المعرفات هذا).
  final bool legacyServerBookingId;

  /// مؤشر ثانوي غير جوهري (cash_transaction_local_id): تعذّرت الترجمة
  /// → NULL بدل تعطيل دورة السحب كلها. لا يُستخدم إلا مع nullable.
  final bool nullWhenUnresolvable;
}

/// خريطة علاقات FK المحلية التي تحمل هوية خادمية — مستخرجة آلياً من
/// local_db.dart (كل .references) وschema.sql الخادمي.
///
/// ملاحظات:
///  * payment_voids وprice_adjustments أعمدتها كلها uuid عالمية بلا
///    قيود FK محلية — تمر بلا ترجمة، فلا قاعدة لها هنا.
///  * bookings.room_number → rooms.room_number مفتاح طبيعي ثابت بين
///    الأجهزة (نفس النص)، المطلوب وجود الغرفة فقط.
const List<_FkRule> _fkRules = [
  // الحجوزات: room_number مفتاح طبيعي على الغرف.
  _FkRule(
    entity: 'bookings',
    column: 'room_number',
    kind: _FkKind.naturalKey,
    parentTable: 'rooms',
    parentKeyColumn: 'room_number',
  ),
  // ليالي الحجز → الحجز.
  _FkRule(
    entity: 'booking_nights',
    column: 'booking_local_id',
    kind: _FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'booking_uuid_cache',
    legacyServerBookingId: true,
  ),
  // ملاحظات الحجز → الحجز (لا uuid-cache على السلك — الاعتماد على
  // ظلّ server_id للأب أو فضاء Appwrite).
  _FkRule(
    entity: 'booking_notes',
    column: 'booking_id',
    kind: _FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    legacyServerBookingId: true,
  ),
  // المدفوعات → الحجز (قابل للـ null — دفعة بلا حجز تمر بـ NULL).
  _FkRule(
    entity: 'payments',
    column: 'booking_local_id',
    kind: _FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    nullable: true,
    uuidCacheColumn: 'booking_uuid_cache',
    legacyServerBookingId: true,
  ),
  // المدفوعات → معاملة الصندوق: مؤشر ثانوي بلا مفتاح عالمي على السلك
  // (local_id المحلي للجهاز الدافع لا معنى له بين الأجهزة) — تعذّرت
  // الترجمة → NULL ولا يُعطَّل السحب لمجرد مؤشر صندوق.
  _FkRule(
    entity: 'payments',
    column: 'cash_transaction_local_id',
    kind: _FkKind.numericPointer,
    parentTable: 'cash_transactions',
    parentKeyColumn: 'id',
    nullable: true,
    nullWhenUnresolvable: true,
  ),
  // تسويات السعر → الحجز (بالمعرّفين معاً).
  _FkRule(
    entity: 'booking_price_adjustments',
    column: 'booking_local_id',
    kind: _FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    nullable: true,
    uuidCacheColumn: 'booking_uuid',
    legacyServerBookingId: true,
  ),
  _FkRule(
    entity: 'booking_price_adjustments',
    column: 'booking_local_uuid',
    kind: _FkKind.naturalKey,
    parentTable: 'bookings',
    parentKeyColumn: 'local_uuid',
  ),
  // دورات الرواتب → الموظف.
  _FkRule(
    entity: 'salary_cycles',
    column: 'employee_id',
    kind: _FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
  ),
  // دفعات الدورة → الدورة (سلّتان: موظف ثم دورة — ترتيب الأولويات
  // في إعادة المحاولة يضمن اكتمال السلسلة).
  _FkRule(
    entity: 'salary_payments',
    column: 'cycle_id',
    kind: _FkKind.numericPointer,
    parentTable: 'salary_cycles',
    parentKeyColumn: 'id',
  ),
  // السحب من الراتب → الموظف.
  _FkRule(
    entity: 'salary_withdrawals',
    column: 'employee_id',
    kind: _FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
  ),
  // سجلات ترحيل الراتب → الموظف.
  _FkRule(
    entity: 'salary_carry_over_logs',
    column: 'employee_id',
    kind: _FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
  ),
  // حركات المخزون → صنف المخزون (item_local_uuid مفتاح عالمي).
  _FkRule(
    entity: 'inventory_transactions',
    column: 'item_id',
    kind: _FkKind.numericPointer,
    parentTable: 'inventory_items',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'item_local_uuid',
  ),
];

final Map<String, List<_FkRule>> _fkRulesByEntity = (() {
  final map = <String, List<_FkRule>>{};
  for (final rule in _fkRules) {
    map.putIfAbsent(rule.entity, () => <_FkRule>[]).add(rule);
  }
  return map;
})();

/// أولوية الآباء عند إعادة محاولة الصفوف المؤجلة — الأب قبل الابن.
const Map<String, int> _pullApplyPriority = {
  'rooms': 0,
  'employees': 1,
  'inventory_items': 1,
  'cash_transactions': 1,
  'bookings': 2,
  'salary_cycles': 3,
  'booking_nights': 4,
  'payments': 4,
  'booking_notes': 4,
  'guest_infos': 4,
  'booking_price_adjustments': 4,
  'inventory_transactions': 4,
  'salary_withdrawals': 4,
  'salary_carry_over_logs': 4,
  'salary_payments': 5,
};

/// ✅ (2026-09-09) إصلاح تجميد السحب (398 ليلة): المفاتيح الطبيعية
/// الفريدة محلياً لكل كيان (uniqueKeys في local_db.dart). صف خادمي
/// يصل بـ local_uuid جديد لكن بمفتاح طبيعي موجود محلياً = نسخة
/// مكررة منطقياً (أصل: سطر restore نسخة احتياطية بـ idempotency_key
/// «backup_*»، أو إعادة بناء مشتقات محلية origin='auto_fix' مقابل
/// نسخ خادمية لنفس الليلة). INSERT عليها كان يرمي SqliteException(2067)
/// فيُفشل كل دورة سحب إلى الأبد.
///
/// العقد: قبل INSERT نبحث بالمفتاح الطبيعي — إن وُجد صف محلي فالوارد
/// نسخة مكررة تُدمج بـ LWW (الأحدث بيانات يفوز، هوية الصف المحلي
/// تبقى) ولا يُدرج صف ثانٍ. UNIQUE المحلي يبقى ضامناً لصف واحد لكل
/// ليلة، والدورة تكمل بدل أن تتجمد.
const Map<String, List<String>> _naturalUniqueKeys = {
  'booking_nights': ['booking_local_id', 'hotel_day_key'],
};

// ─── SyncPullProgress (2026-09-10 مؤشر تقدم السحب) ─────────────

/// لقطة تقدم السحب الحيّ — يبثّها المدير بعد كل صفحة تُطبَّق.
///
/// طلب المستخدم: «مؤشر السحب الكامل يجب أن أعرف مسار حجم السحب
/// والمتبقي ويجب أن لا يعيق الانتقال إلى الشاشات الأخرى»:
/// - [pulledRows]: ما طُبِّق فعلياً على قاعدة الجهاز (عدّاد تراكمي).
/// - [remainingRows]: ما بقي على الخادم (من COUNT خادمي في السحب
///   الكامل؛ null = غير متاح — worker قديم أو دلتا) فيظهر المؤشر
///   غير-محدد مع العدّاد.
/// - [isFullSync]: دلالة «سحب كامل» لتمييزه عن دلتا روتينية.
/// البثّ من broadcast stream — لا يحجب ولا ينتظر أي UI.
class SyncPullProgress {
  SyncPullProgress({
    required this.pulledRows,
    this.remainingRows,
    this.pages = 0,
    this.isFullSync = false,
    this.isDone = false,
    this.errorMessage,
  });

  final int pulledRows;
  final int? remainingRows;
  final int pages;
  final bool isFullSync;
  final bool isDone;
  final String? errorMessage;

  /// نسبة التقدم 0..1 — null عند غياب remaining (لا يُعرف الإجمالي).
  double? get fraction {
    final remaining = remainingRows;
    if (remaining == null) return null;
    final total = pulledRows + remaining;
    if (total <= 0) return isDone ? 1.0 : null;
    return (pulledRows / total).clamp(0.0, 1.0);
  }

  SyncPullProgress copyWith({
    int? pulledRows,
    int? Function()? remainingRows,
    int? pages,
    bool? isFullSync,
    bool? isDone,
    String? errorMessage,
  }) => SyncPullProgress(
    pulledRows: pulledRows ?? this.pulledRows,
    remainingRows: remainingRows != null ? remainingRows() : this.remainingRows,
    pages: pages ?? this.pages,
    isFullSync: isFullSync ?? this.isFullSync,
    isDone: isDone ?? this.isDone,
    errorMessage: errorMessage ?? this.errorMessage,
  );
}

// ─── SyncResult (same interface as AppwriteSyncManager) ────────

class SyncResult {
  SyncResult({
    required this.status,
    required this.timestamp,
    required this.duration,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
  });

  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
}

/// نتيجة تطبيق دفعة صفوف مسحوبة — عقد مسار السحب على طرف العميل.
///
/// ✅ (2026-09-09) الجذر (ب) — كان تطبيق الصف الفاشل يُكتَم استثناؤه
/// (try-catch لكل صف + تقدم المؤشر) فتضيع الصفوف بينما «ينجح» السحب:
/// الآن كل فشل تطبيق حقيقي أو علاقة غير قابلة للحل يظهر في التقرير
/// ويُفسد الدورة (لا checkpoint ولا علامة full sync).
@visibleForTesting
class PullApplyReport {
  PullApplyReport({
    required this.appliedCount,
    required this.deferredCount,
    required this.touchedEntities,
    required this.unresolvable,
    required this.errors,
  });

  /// الصفوف التي طُبّقت فعلاً (إدراج/تحديث/تخطي بعذر).
  final int appliedCount;

  /// الصفوف المؤجلة التي لم تُحلّ علاقاتها بعد إعادة المحاولة.
  final int deferredCount;

  /// الكيانات التي وصلت منها صفوف مُطبّقة (لبناء المشتقات).
  final Set<String> touchedEntities;

  /// 'entity/local_uuid' لكل صف بقي بلا أب (يُجمّد المؤشر عنده).
  final List<String> unresolvable;

  /// 'entity/uuid: message' لكل فشل تطبيق حقيقي (خطأ قاعدة بيانات).
  final List<String> errors;

  bool get isClean => unresolvable.isEmpty && errors.isEmpty;
}

// ─── Realtime sync state ───────────────────────────────────────
// ✅ المرحلة 3: كانت هنا stub فارغة — التنفيذ الكامل أصبح في
// cloudflare_realtime_sync.dart (مُستورد ومُعاد تصديره أعلاه).

// ─── CloudflareSyncManager ─────────────────────────────────────

class CloudflareSyncManager {
  factory CloudflareSyncManager({
    // ✅ توافق Drop-in مع مواقع استدعاء AppwriteSyncManager القديمة
    // (perf providers/backup services تمرّرها) — تُتجاهل: خدمة Appwrite
    // ليست جزءاً من مسار Cloudflare، والقاعدة تُحَدَّد في initialize().
    // (تعطيل القاعدة هنا متعمّد: المعاملات وهمية للحفاظ على توافق الاستدعاء)
    // ignore: avoid_unused_constructor_parameters
    dynamic appwriteService,
    // ignore: avoid_unused_constructor_parameters
    dynamic database,
  }) => _instance;
  CloudflareSyncManager._internal();

  /// ✅ توافق: كود perf يستدعي `AppwriteSyncManager.instance`.
  static CloudflareSyncManager get instance => _instance;
  static final CloudflareSyncManager _instance =
      CloudflareSyncManager._internal();

  // ─── Static device ID (same interface as AppwriteSyncManager) ──
  static String? _staticDeviceId;
  static String? get currentDeviceIdStatic => _staticDeviceId;
  static void setStaticDeviceId(String id) => _staticDeviceId = id;

  // ─── State ──────────────────────────────────────────────────
  AppDatabase? _db;
  String? _token;
  String? _deviceId;
  String? _initError;
  String? _lastError;
  SyncStatus _currentStatus = SyncStatus.idle;
  Timer? _autoSyncTimer;
  int _lastPullCursor = 0;

  /// ✅ P0-B (full sync bootstrap): علامة "اكتملت المزامنة الكاملة بنجاح".
  /// تُضبط على true فقط بعد اكتمال pagination حتى exhaustion لكل collections.
  /// قبل ذلك، أي مزامنة تُعتبر "full sync غير مكتملة" ولا يُسمح بالانتقال
  /// لـ delta-only sync.
  /// تُخزَّن في SharedPreferences لتعيش بين جلسات التطبيق.
  bool _fullSyncCompleted = false;
  static const String _kFullSyncCompletedKey = 'cf_full_sync_completed';
  bool? _timestampNormalizationDone;
  static const String _kTimestampNormalizationDoneKey =
      'cf_timestamp_normalization_v1_done';

  /// ✅ (2026-09-08) السقف المعقول لمؤشر السحب: عتبة فصل وحدات الطوابع
  /// الزمنية (ثوانٍ مقابل ميلي ثانية). ثواني الـ epoch تبقى تحت 1e11 حتى
  /// سنة ~5138 — أي مؤشر أعلى من ذلك خُلِّف من طوابع ميلي قديمة (migration
  /// قديمة أو worker قديم يرجّع global-max) ويجب ألا يُخزَّن أبداً.
  static const int maxSanePullCursor = 100000000000; // 1e11

  /// ✅ (2026-09-17) عتبة صنف التسمم الثاني (المستقبلي/‎sentinel): حارس
  /// الميلي أعلاه (‎1e11) لا يلتقط الـ sentinel 9999999999 (‎1e10 — أثر
  /// سكربت appwrite_cloud_restore.py) لأنه تحتها! ثواني الـ epoch الحالية
  /// (~1.79e9) تبقى تحت 2e9 حتى سنة 2033، فأي مؤشر فوق ذلك مسموم بأحد
  /// الصنفين معاً (sentinel أو ميلي) ويُعمي الجهاز للأبد (كل كتابة لاحقة
  /// ~1.79e9 دونه في WHERE updated_at > cursor). مرآة عتبة الخادم
  /// FUTURE_TIMESTAMP_THRESHOLD (worker/src/database.ts) — تقرأها حركات
  /// التهيئة والتشغيل والتثبيت أدناه.
  static const int maxSanePullCursorFuture = 2000000000; // 2e9 — سنة 2033

  /// ✅ (2026-09-17) هامش تقديم المؤشر المقبول على وقت الخادم المُعلن في
  /// ردود السحب (server_time): سنة كاملة تسع انحرافات ساعة الأجهزة
  /// والتقديم المشروع للقيم السليمة — ومؤشر يتجاوز ذلك (sentinel/ميلي
  /// من worker غير مُصلح) يُرفض فوراً في مسار التشغيل قبل تثبيته.
  static const int maxCursorAheadOfServerSec = 31536000; // سنة

  /// ✅ P0-B: عدد صفحات full sync المتبقية (للتشخيص فقط).
  /// تُستخدم لعرض "full sync in progress (page 3/?)"
  int get fullSyncRemainingPages => _fullSyncRemainingPages;
  int _fullSyncRemainingPages = 0;

  /// ✅ P0-B: هل full sync قيد التنفيذ حالياً؟
  bool get isFullSyncInProgress => _isFullSyncInProgress;
  bool _isFullSyncInProgress = false;

  /// ✅ P0-C: Collections التي فشلت في آخر مزامنة (لمنع advance checkpoint).
  /// لا يُحرّك checkpoint لأي collection فشلت حتى تنجح في محاولة لاحقة.
  final Set<String> _failedCollectionsInLastSync = <String>{};

  // ─── الحجر الصحي وسجل الانتظار للصفوف اليتيمة (2026-09-09 → 2026-09-15) ──
  //
  // المشكلة: صف واحد بأبٍ مفقود خادمياً (يتيم بنيوي — أبُه حُذف يدوياً
  // من D1 أو لم يُنشأ أصلاً) كان يُفشل دورة السحب كلها عند كل محاولة
  // → المؤشر لا يتحرك → full sync لا يكتمل → bootstrap يعيد المحاولة
  // عند كل إقلاع إلى الأبد (خطأ بيانات واحد = جهاز مجمّد نهائياً).
  //
  // السياسة القديمة (2026-09-09): تدرّج 3 دورات لكن عبر «تراجع المؤشر» —
  // كل دورة بهوية محجوبة تعيد سحب كل الصفحات وتطبيقها من أول الدورة
  // (7,300+ صف) حتى تكتمل العتبة. مكلف زمنياً جداً على شبكة يمن، ويولّد
  // تكراراً مزعجاً في مركز الأخطاء (تقرير 2026-09-14: 55 سجلاً محجوباً).
  //
  // السياسة المصححة (2026-09-15 — طلب المستخدم: تسريع السحب وإصلاح
  // تجميد المؤشر): «سجل انتظار» بالحمولات الكاملة —
  //   1. المؤشر يتقدم في نفس الدورة طالما الصفحات نفسها سليمة (لا شبكة/
  //      HTTP/JSON/جداول متخطاة) — الصفحات طبّقت كلها فعلاً.
  //   2. كل سجل محجوب (أب غير محلول أو تعارض مفتاح فريد) تُحفظ حمولته
  //      كاملة في [_blockedPending] (persistent) ويُعاد حلّه من الحمولة
  //      في كل دورة — بلا إعادة سحب أي صفحة إطلاقاً.
  //   3. بعد [_quarantineBlockThreshold] دورات بنفس الهوية: يُنقل لسجل
  //      الحجر [_quarantinedRecords] (مع حمولته أيضاً) ويتوقف عن إثقال
  //      الدورة نهائياً.
  //   4. الشفاء تلقائي من الحمولة: وصول الأب أو تفريغ المفتاح أو وصول
  //      tombstone → التطبيق ينجح في إعادة المحاولة الدورية → يُمسح من
  //      السجلين معاً. (وعد السابق كان معلقاً على إعادة بث الصف من
  //      الخادم — الآن محقق دائماً لأن الحمولة محلية.)
  static const String _kQuarantineCountsKey = 'cf_pull_orphan_block_counts';
  static const String _kQuarantinedKey = 'cf_pull_quarantined_records';
  static const String _kBlockedPendingKey = 'cf_pull_blocked_pending';
  static const int _quarantineBlockThreshold = 3;

  /// عدد الدورات التي حُجب فيها كل سجل معتّق (identity = 'entity/uuid').
  final Map<String, int> _orphanBlockCounts = <String, int>{};

  /// سجل الحجر الصحي: identity -> بيانات التشخيص + حمولة السجل (record)
  /// لإعادة المحاولة الدورية (الشفاء من الحمولة المحلية).
  final Map<String, Map<String, dynamic>> _quarantinedRecords =
      <String, Map<String, dynamic>>{};

  /// ✅ (2026-09-15) سجل الانتظار: المحجوبون تحت العتبة مع حمولاتهم —
  /// يُعاد حلّهم من الحمولة كل دورة بدل إعادة سحب الصفحات عبر تراجع
  /// المؤشر. السقف يمنع انفجار التخزين في حالات مرضية قصوى.
  final Map<String, ({String entity, Map<String, dynamic> record})>
  _blockedPending = <String, ({String entity, Map<String, dynamic> record})>{};

  /// سقف سجل الانتظار (عدد السجلات). تجاوزه = عزل فوري للفائض الأقرب
  /// للعتبة (صمام أمان — الحالة الواقعية عشرات).
  static const int _blockedPendingCap = 300;

  /// ✅ (M2) سقف سجل الحجر الصحي — كان بلا حد والحمولات الكاملة تُخزَّن
  /// في SharedPreferences (بطء كل initialize + خطر TransactionTooLarge
  /// على أندرويد). الإخلاء بالأقدم first_seen مع عدّاده (بداية نظيفة
  /// إن عاد الصف ببث خادمي لاحق).
  static const int _quarantineCap = 300;

  /// سقف محاولات الشفاء الدورية للمعزولين في كل دورة (تكلفة محلية صفرية
  /// تقريباً لكن بلا سقف قد تنمو مع تاريخ الحجب الطويل).
  static const int _quarantineHealRetryLimit = 100;

  /// ✅ سقف صفحات السحب في الدورة الواحدة — حلقة `while (hasMore)` بلا سقف
  /// كانت قد تعلق إلى الأبد أمام كاتب ساخن ينتج صفوفاً بلا توقف، حاجبةً
  /// كل مزامنة لاحقة عبر قفل re-entrancy ومستنزفةً البطارية. 100 صفحة ×
  /// 500 صف = 50k صف — فوق أي حمل واقعي (~7,300 صف للكامل) بفارق مريح.
  /// عند بلوغه تتوقف الدورة بنجاح جزئي (المؤشر تقدم عبر صفحات سليمة
  /// فقط) وتُستأنف البقية الدورة القادمة — بلا تجميد وبلا فقد
  /// (التطبيق idempotent عبر local_uuid).
  static const int _maxPullPagesPerCycle = 100;

  /// ✅ (مراجعة #1) مسح تقارب الحذفيات لمرة واحدة — جهاز سحب أثناء
  /// نافذة العقد القديم (worker كان يفلتر tombstones من السحب) تكون
  /// مؤشره تجاوز حذفيات لم تُبَث أبداً. النافذة tombstones_only رخيصة
  /// (الحذفيات قليلة بنيوياً: تدقيق 2026-09-09 = 1 صف) ولا تمس
  /// المؤشر الرئيسي ولا تعيد سحب الصفوف الحية.
  static const String _kTombstoneSweepDoneKey = 'cf_tombstone_sweep_v1_done';

  /// ✅ إصلاح بطء السحب (تقرير مستخدم: «يتأخر كثيراً أثناء سحب التغييرات»):
  /// مؤشر تقدّم مسح الحذفيات التاريخي — يُحفظ بعد كل صفحة مطبَّقة بنجاح.
  /// قبل هذا الإصلاح كان `_sweepHistoricalTombstones` يبدأ دائماً من
  /// cursor=0 عند أي استئناف (أي فشل شبكي جزئي لا يُثبِّت العلم `_done`)،
  /// فيُعيد جلب وتطبيق كل الصفحات التي أُنجزت فعلاً من جديد في كل محاولة
  /// سحب لاحقة — على شبكات ضعيفة (النفق الاحتياطي قد يستغرق حتى 36 ثانية
  /// للطلب الواحد، انظر `_fetchPullPage`) هذا يعني أن كل ضغطة على زر
  /// «سحب التغييرات» قد تُعيد نفس العمل غير المكتمل من الصفر إلى الأبد.
  static const String _kTombstoneSweepCursorKey =
      'cf_tombstone_sweep_v1_cursor';

  // ✅ (مراجعة 2026-09-09 #14) سقفا المحاولات على مسار الرفع:
  // - سقف اختيار الحلقة (يطابق reclaimForPush.maxFailedAttempts) —
  //   failed فوقه يُترك للمؤقت الدوري retryFailedWithBackoff.
  // - سقف الـ dead-letter: فشل مؤقت/تعارض يتجاوز هذا العدد يوضع في
  //   الحالة النهائية dead لمراجعة يدوية بدل إعادة محاولة صامتة للأبد
  //   (validation يصل dead من أول رفض كما كان).
  static const int _maxFailedAttemptsPerPushCycle = 5;
  static const int _pushDeadLetterThreshold = 10;

  /// ✅ (fix M4) رسائل رفض خادمية دائمة قد تصل بلا حقل status (عقد قديم
  /// أو مسار غير موسوم) — نمط تصنيف فوري كخطأ دائم بدل إعادة الدفع
  /// حتى عتبة dead-letter بلا فائدة (الخادم سيرفضها في كل مرة).
  static final RegExp _permanentPushErrorPattern = RegExp(
    'is required|Invalid operation|must be|Unknown entity|not in whitelist|invalid entity',
    caseSensitive: false,
  );

  /// ✅ (fix R1) تهدئة 429: عند ردّ الخادم 429 مع Retry-After نوقف محاولات
  /// الدفع حتى انتهاء المدة بدل اختراق الحد في كل دورة.
  DateTime _pushCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// ✅ P0-I: قفل متزامن لمنع ت重叠 عمليات sync المتزامنة.
  /// قبل هذا القفل، كان ممكناً أن يبدأ autoSync + manualSync + onResumeSync
  /// في نفس الوقت وكلها تعدّل على نفس outbox.
  bool _syncInProgress = false;

  // ─── إصلاح الجذري الثالث (2026-09-09): هوية الخادم وعلاقات FK ──
  //
  // الجذران المؤكدان من تقرير جهاز حقيقي («لم يتم سحب كل البيانات»):
  //  (أ) الصفوف الخادمية تحمل أعمدة لا يعرفها مخطط Drift المحلي
  //      (sync_timestamp وغيرها من بقايا مخطط D1 القديم) — كان INSERT
  //      يفشل بـ «no such column» صمتاً (يلتقطه try-catch لكل صف) ويتقدم
  //      المؤشر: «نجاح» بلا بيانات.
  //  (ب) أعمدة FK الرقمية على الابن (booking_nights.booking_local_id …)
  //      تحمل id خادم D1 (autoincrement) — كتابتها كما هي داخل الصف
  //      المحلي تعني 31 انتهاك FK حقيقي (وكانت تفشل صمتاً قبل إطفاء
  //      FK): العلاقات بين الحجوزات ولياليها ومدفوعاتها كلها معطوبة.
  //
  // الحل الثلاثي هنا:
  //  1. فلترة أعمدة الصف الوارد ضد PRAGMA table_info للجدول المحلي —
  //     أي عمود غريب يُسقَط (بسجل) بدل أن يفشل الصف كله.
  //  2. ظلّ هوية الخادم: كل جدول SyncFields محلي فيه عمود server_id —
  //     عند تطبيق صف أب نخزن فيه id الخادم، فيصير سجلَّ ترجمة دائم
  //     «D1 id → صف محلي» داخل البيانات نفسها (بلا جدول جانبي).
  //  3. ترجمة FK عند التطبيق: uuid-cache أولًا (المفتاح العالمي بين
  //     الأجهزة)، ثم ظلّ server_id للأب، ثم فضاء Appwrite القديم
  //     (server_booking_id)، ثم الصف الموجود محلياً؛ ما لم يُحلّ يُؤجَّل
  //     لإعادة محاولة بعد اكتمال السحب (الآب قد يصل في صفحة لاحقة)،
  //     وما بقي غير محلول = دورة فاشلة: المؤشر يتراجع ولا full sync.

  /// كاش أعمدة الجداول المحلية (PRAGMA table_info) — يُمسح عند إعادة
  /// التهيئة لأن ترحيل المخطط قد يضيف أعمدة أثناء عمر العملية.
  final Map<String, Set<String>> _localColumnsCache = <String, Set<String>>{};

  /// مفاتيح FK التي سُقِطت/عُدِّلت في هذه العملية (لمنع إغراق السجل).
  final Set<String> _fkLogSeen = <String>{};

  /// ✅ (2026-09-22 تسريع full sync) كاش نتائج [_lookupLocalParentId]
  /// الموجبة فقط ضمن دورة سحب واحدة — مفتاحه `parentTable|keyColumn|
  /// keyValue`. صفوف كثيرة (booking_nights أهمها: ~11.5k صف يشترك
  /// معظمها في عدد صغير من آباء bookings) كانت تُعيد نفس استعلام
  /// SELECT لنفس الأب مئات المرات. تخزين "غير موجود" مرفوض عمداً:
  /// الأب قد يصل لاحقاً في نفس الدورة (صفحة تالية) وتُعاد محاولة
  /// الصفوف المؤجَّلة بعد اكتمال الصفحات (_retryDeferredRecords) —
  /// كاش سلبي كان سيُفشل تلك المحاولة الثانية زوراً. يُمسح في بداية
  /// كل [_pullChanges] (نفس دورة حياة [_localColumnsCache] تقريباً).
  final Map<String, Object> _fkParentIdCache = <String, Object>{};

  // ─── إحصائيات حقيقية لدورات المزامنة (2026-09-05) ──────────
  // ✅ كانت getSyncStatistics() تُرجع {} فارغة فتعرض شاشات الإحصائيات
  // أصفاراً دائمة (مضللة للإنتاج). الآن تُراكم المدير عدادات دورة
  // sync الفعلية وتُخزن في SharedPreferences لتبقى بين الجلسات.
  int _statTotalSyncs = 0;
  int _statSuccessfulSyncs = 0;
  int _statFailedSyncs = 0;
  int _statTotalPushed = 0;
  int _statTotalPulled = 0;
  DateTime? _statLastSyncTime;
  static const String _kSyncStatsKey = 'cf_sync_stats_v1';

  bool get isAvailable => _token != null;
  String? get token => _token;
  String? get initError => _initError;
  String? get lastError => _lastError;
  SyncStatus get currentStatus => _currentStatus;
  String? get currentDeviceId => _deviceId;

  /// ✅ P0-B: هل اكتملت المزامنة الكاملة؟ (للـ UI ولفظ السلوك)
  bool get isFullSyncCompleted => _fullSyncCompleted;

  // ─── Realtime status stream (used by UnifiedSyncOrchestrator) ──
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _statusController.stream;

  // ─── Pull progress stream (2026-09-10 مؤشر تقدم السحب) ────────
  /// يبثّ [SyncPullProgress] بعد كل صفحة تُطبَّق — مستمعو UI فقط،
  /// لا أحد ينتظر البثّ (لاحجاب صفر للتنقل بين الشاشات).
  final _pullProgressController =
      StreamController<SyncPullProgress>.broadcast();
  Stream<SyncPullProgress> get syncPullProgressStream =>
      _pullProgressController.stream;

  /// آخر لقطة تقدم (للواجهات التي تفتح متأخراً — لا تنتظر البثّ القادم).
  SyncPullProgress _lastPullProgress = SyncPullProgress(pulledRows: 0);
  SyncPullProgress get lastPullProgress => _lastPullProgress;

  void _emitPullProgress(SyncPullProgress progress) {
    _lastPullProgress = progress;
    if (!_pullProgressController.isClosed) {
      _pullProgressController.add(progress);
    }
  }

  // ─── HTTP client with DoH + tunnel fallback (bypasses broken ISP DNS/connect) ──
  // ✅ (2026-09-09) إعادة تصميم: أي فشل في المسار السريع (DNS، حجب، تعليق،
  // socket ميت) — وليس أخطاء DNS فقط — يُفعّل المسار البديل خلال 6 ثوانٍ:
  // DoH متوازي (Cloudflare+Google) + نفق CONNECT محلي يربط بالـIP مباشرة
  // مع SNI صحيح (نهج IP-in-URL القديم كان مكسوراً: Cloudflare يرفض الـTLS).
  //breaker لكل دومين 10 دقائق حتى لا يتكرر التعليق عند كل طلب.
  http.Client _httpClient = createResilientHttpClient(
    timeout: const Duration(seconds: 30),
  );

  /// ✅ (2026-09-10) طابع آخر محاولة إعادة تهيئة كسولة — تبريد 60
  /// ثانية يمنع طرق شبكة محجوبة عند كل سحب، مع السماح بالشفاء
  /// التلقائي خلال دقيقة دون إعادة فتح التطبيق.
  DateTime? _lastLazyInitAttempt;

  /// سقف التبريد بين محاولات إعادة تسجيل الدخول الكسولة
  /// (visibleForTesting ليضبطه الاختبار على صفر).
  @visibleForTesting
  Duration lazyInitCooldown = const Duration(seconds: 60);

  /// عملية تهيئة واحدة مشتركة؛ تمنع عدة شاشات من إرسال login متزامن.
  Future<void>? _initializeInFlight;

  /// ✅ (2026-09-08) حقن اختباري مباشر: قاعدة بيانات + عميل HTTP وهمي
  /// + توكن — بلا login شبكي. يُتيح اختبارات عقدية لحلقة السحب كاملة
  /// (ترحيل المؤشر، أعطال الجداول الخادمية، فصل الدفع عن السحب).
  /// يعيد ضبط كل الحالة الداخلية أيضاً — المدير singleton وبدون هذا
  /// كانت حالة اختبار سابق (_fullSyncCompleted/_lastPullCursor) تتسرب
  /// للاختبار التالي وتفصل الاختبارات عن بعضها زوراً.
  @visibleForTesting
  void configureForTesting({
    required AppDatabase database,
    required http.Client httpClient,
    String? token,
    String? deviceId,
    bool fullSyncCompleted = false,
    int lastPullCursor = 0,
  }) {
    _db = database;
    _httpClient = httpClient;
    _token = token;
    _deviceId = deviceId ?? 'test-device';
    setStaticDeviceId(_deviceId!);
    _fullSyncCompleted = fullSyncCompleted;
    _timestampNormalizationDone = false;
    _lastPullCursor = lastPullCursor;
    _isFullSyncInProgress = false;
    _fullSyncRemainingPages = 0;
    _failedCollectionsInLastSync.clear();
    _lastError = null;
    _currentStatus = SyncStatus.idle;
    _localColumnsCache.clear();
    _fkLogSeen.clear();
    // ✅ (مراجعة #2+#16) عزل حالة الحجر بين الاختبارات (singleton).
    _orphanBlockCounts.clear();
    _quarantinedRecords.clear();
    // ✅ (2026-09-15) عزل سجل الانتظار بين الاختبارات (singleton).
    _blockedPending.clear();
    // ✅ (2026-09-10) عزل حالة إعادة التهيئة الكسولة بين الاختبارات.
    _lastLazyInitAttempt = null;
    lazyInitCooldown = const Duration(seconds: 60);
    // ✅ (2026-09-10) عزل لقطة تقدم السحب بين الاختبارات (singleton).
    _lastPullProgress = SyncPullProgress(pulledRows: 0);
  }

  /// ✅ (2026-09-08) عقد القراءة: الجداول التي تخطاها الخادم في آخر
  /// دورة مزامنة. فارغة = الدورة سليمة؛ غير فارغة = فشل جزئي ويجب
  /// ألا يُعتبر full sync مكتملاً ولا المؤشر متقدماً بأمان.
  @visibleForTesting
  Set<String> get failedCollectionsInLastSync =>
      Set<String>.unmodifiable(_failedCollectionsInLastSync);

  // ─── Initialize ─────────────────────────────────────────────
  Future<void> initialize({
    AppDatabase? database,
    bool forceRetry = false,
    int loginAttempts = 3,
  }) {
    final inFlight = _initializeInFlight;
    if (inFlight != null) return inFlight;
    if (_token != null && !forceRetry && !_isTokenExpired(_token!)) {
      return Future<void>.value();
    }
    final operation = _initializeInternal(
      database: database,
      forceRetry: forceRetry,
      loginAttempts: loginAttempts,
    );
    _initializeInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_initializeInFlight, operation)) {
        _initializeInFlight = null;
      }
    });
  }

  Future<void> _initializeInternal({
    AppDatabase? database,
    bool forceRetry = false,
    int loginAttempts = 3,
  }) async {
    if (forceRetry) {
      // ✅ كاش أعمدة الجداول (PRAGMA) قد يَعْتَق بعد ترحيل مخطط أثناء عمر
      // العملية — إعادة التهيئة الصريحة تُبطلُه فيُعاد قراءته طازجاً
      // (يطابق العقد الموثق على [_localColumnsCache]).
      _localColumnsCache.clear();
    }
    if (_token != null && !forceRetry && !_isTokenExpired(_token!)) return;
    if (_token != null && _isTokenExpired(_token!)) {
      debugPrint('🔄 Cloudflare token expired/near expiry — refreshing');
      _token = null;
      Env.cloudflareAuthToken = null;
    }

    _db = database ?? _db ?? DatabaseManager.instance;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('cf_device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _generateDeviceId();
      await prefs.setString('cf_device_id', _deviceId!);
    }
    setStaticDeviceId(_deviceId!);

    // ✅ RemoteChangeNotifier: اضبط معرّف جهازنا الحالي لتمييز تغييراتنا
    // عن تغييرات الأجهزة الأخرى.
    RemoteChangeNotifier.instance.setMyDeviceId(_deviceId!);

    // ✅ P0-B: استعادة علامة "full sync مكتملة" من الجلسة السابقة
    _fullSyncCompleted = prefs.getBool(_kFullSyncCompletedKey) ?? false;
    _timestampNormalizationDone =
        prefs.getBool(_kTimestampNormalizationDoneKey) ?? false;
    _lastPullCursor = prefs.getInt('cf_last_pull_cursor') ?? 0;

    // ✅ (مراجعة #2+#16) استعادة حالة الحجر الصحي للصفوف اليتيمة —
    // يجب أن تعيش عبر الجلسات حتى يُقارب bootstrap خلال دورات متتالية.
    _loadQuarantineState(prefs);

    // ✅ (2026-09-08) صيانة ذاتية للمؤشر المسموم بوحدات مختلطة:
    // نسخ migration قديمة خلّفت طوابع updated_at بالميلي ثانية (‎>1e11)
    // في D1 بينما كاتب الخادم الحالي يختم بالثواني. مؤشر يقف في نطاق
    // الميلي يجعل كل الصفوف الثواني-الجديدة غير مرئية إلى الأبد
    // (‎WHERE updated_at > cursor). الطوابع الثواني تبقى تحت 1e11 حتى
    // سنة ~5138 — أي مؤشر محفوظ أكبر من ذلك = تسمم مؤكد → تصفير كامل
    // (cursor + علامة full sync + علم bootstrap) ليعيد الجهاز سحباً
    // كاملاً نظيفاً بعد نشر worker الإصلاح.
    if (_lastPullCursor > maxSanePullCursorFuture) {
      debugPrint(
        '🚨 poisoned pull cursor detected ($_lastPullCursor — ms/sentinel '
        'class, bound $maxSanePullCursorFuture) — '
        'resetting to 0 and forcing a fresh full sync',
      );
      // ✅ (2026-09-09) حدث نادر لكنه جوهري — يظهر في مركز أخطاء
      // المزامنة حتى يعرف المستخدم لماذا بدأ الجهاز سحباً كاملاً من
      // جديد.
      logError(
        title: 'مؤشر سحب مسموم (طوابع ميلي-ثانية) — تصفير وإعادة سحب كامل',
        message:
            'المؤشر المحفوظ $_lastPullCursor تجاوز الحد الآمن '
            '$maxSanePullCursor. صُفّر المؤشر وعلامة full sync '
            'ليبدأ الجهاز سحباً كاملاً نظيفاً من الـ Worker.',
        category: ErrorCategory.sync,
        source: 'sync:init',
      );
      _lastPullCursor = 0;
      _fullSyncCompleted = false;
      await prefs.setInt('cf_last_pull_cursor', 0);
      await prefs.remove(_kFullSyncCompletedKey);
      // علم «تم السحب الكامل بعد التخطي» — نفس مفتاح BootstrapFullPull
      // (تفادي استيراد دائري؛ المفتاح موثق في الطرفين).
      await prefs.remove('appwrite_pull_after_drive_skip_done');
    }

    // ✅ (2026-09-05) استعادة عدادات الإحصائيات الحقيقية بين الجلسات.
    await _loadSyncStats();

    // ✅ P0-H: استعادة أي سجلات عالقة في 'processing' من جلسة سابقة
    // (crash recovery). أي سجل 'processing' قبل restart هو بالتأكيد عالق
    // لأن الـ worker الذي حجزه مات مع إنهاء التطبيق.
    try {
      final outboxDao = OutboxDao(_db!);
      final reclaimed = await outboxDao.reclaimAllStuckProcessingOnStartup();
      if (reclaimed > 0) {
        debugPrint(
          '🔧 [P0-H] Reclaimed $reclaimed stuck outbox entries on init',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to reclaim stuck outbox entries: $e');
    }

    // Retry login up to N times for transient network failures (DNS,
    // socket). المسار الكسول من sync() يمرر 1 حتى لا يحجب زر السحب
    // 45 ثانية كاملة على شبكة محجوبة.
    final maxAttempts = loginAttempts.clamp(1, 10);
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _httpClient
            .post(
              Uri.parse('${CloudflareConfig.workerUrl}/api/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'username': CloudflareConfig.username,
                'password': CloudflareConfig.password,
                'device_id': _deviceId,
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _token = data['token'] as String?;
          Env.cloudflareAuthToken = _token;
          _initError = null;
          // ✅ نجاح تسجيل الدخول يصفّر تبريد المحاولة الكسولة.
          _lastLazyInitAttempt = null;
          debugPrint(
            '✅ CloudflareSyncManager initialized — device: $_deviceId '
            '(attempt $attempt/$maxAttempts)',
          );
          return;
        } else {
          _initError = 'Login failed: ${response.statusCode}';
          debugPrint('⚠️ Cloudflare login failed: ${response.body}');
          // ✅ سجل في شاشة تتبع الأخطاء
          logHttpError(
            title: 'فشل تسجيل الدخول (Cloudflare)',
            statusCode: response.statusCode,
            responseBody: response.body,
            source: 'sync:login',
          );
          return;
        }
      } catch (e) {
        // ✅ سجل في شاشة تتبع الأخطاء
        logError(
          title: 'استثناء أثناء تسجيل الدخول',
          message: e.toString(),
          category: ErrorCategory.auth,
          source: 'sync:login',
        );
        final errStr = e.toString();
        final isTransient =
            errStr.contains('Failed host lookup') ||
            errStr.contains('No address associated with hostname') ||
            errStr.contains('SocketException') ||
            errStr.contains('HandshakeException') ||
            errStr.contains('TimeoutException');

        if (isTransient && attempt < maxAttempts) {
          debugPrint(
            '⚠️ Cloudflare init attempt $attempt failed (transient), retrying in 2s: $e',
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        // Final attempt failed — set actionable error message
        if (errStr.contains('Failed host lookup') ||
            errStr.contains('No address associated with hostname')) {
          _initError =
              'لا يمكن الوصول إلى خادم Cloudflare (${CloudflareConfig.workerUrl}). '
              'تأكد من اتصالك بالإنترنت وأن الشبكة لا تحظر الدومين workers.dev. '
              'الخطأ الأصلي: $e';
        } else if (errStr.contains('SocketException') ||
            errStr.contains('HandshakeException')) {
          _initError =
              'فشل الاتصال بخادم Cloudflare. تحقق من الشبكة وأعد المحاولة. '
              'الخطأ الأصلي: $e';
        } else if (errStr.contains('TimeoutException')) {
          _initError =
              'تعذّر الوصول إلى خادم المزامنة خلال المهلة (15 ثانية). '
              'حاول التطبيق تلقائياً المسار البديل (DoH + اتصال مباشر) — إن '
              'استمر الفشل فالشبكة نفسها لا تصل إلى workers.dev: جرّب '
              'تغيير الشبكة (Wi-Fi/بيانات) أو VPN. الخطأ الأصلي: $e';
        } else {
          _initError = 'Init error: $e';
        }
        debugPrint('⚠️ CloudflareSyncManager init error: $e');
        return;
      }
    }
  }

  bool _isTokenExpired(String token) {
    try {
      final parts = token.split('.');
      // التوكنات المحقونة في اختبارات العقد ليست JWT؛ يتركها هذا الحارس
      // كما هي، بينما كل توكن Worker الحقيقي يمر عبر فحص exp أدناه.
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = (payload as Map<String, dynamic>)['exp'];
      // ✅ (2026-09-15) مواءمة عقد التوكن طويل الأجل: غياب exp مقصود —
      // JWT_EXPIRY_HOURS="0" يصدر توكنات بلا exp والقبول بالتوقيع وحده
      // (مطابق لـ verifyToken في worker). اعتبارها منتهية هنا كان سيصنع
      // حلقة دخول لانهائية: null → login → توكن بلا exp → «منتهي» → null.
      // الإبطال المقصود يدوي فقط (تدوير JWT_SECRET) فيُكشف عبر 401.
      if (exp == null) return false;
      // قيمة exp مشوهة (ليست رقمًا) → نعاملها كمنتهية لعدم الثقة فيها،
      // فتشعل إعادة الدخول بدل الاعتماد على توكن غير مفهوم.
      if (exp is! num) return true;
      // هامش دقيقة يمنع بدء دورة طويلة بتوكن سينتهي أثناءها — للتوكنات
      // القديمة المحمّلة exp فقط (توافق خلفي قبل نشر العقد الجديد).
      return exp.toInt() <= DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60;
    } catch (_) {
      return true;
    }
  }

  // ─── Register Device ────────────────────────────────────────
  Future<String> registerDevice() async {
    if (_token == null || _deviceId == null) {
      throw StateError('Not initialized');
    }

    final response = await _httpClient
        .post(
          Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
          headers: {
            'Authorization': 'Bearer $_token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': _deviceId,
            'platform': 'android',
            // ✅ (2026-09-05) هوية الصف المتزامن — تتقارب مسارات REST
            // وoutbox على صف واحد في D1 (نفس local_uuid).
            'localUuid': _deviceId,
          }),
        )
        // 20s (كانت 10s): المسار السريع قد يستهلك حتى 6s قبل تشغيل
        // المسار البديل (DoH + نفق) — 10s كانت تقطع البديل قبل اكتماله.
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      debugPrint('✅ Device registered: $_deviceId');
      // ✅ (2026-09-05) devices كيان متزامن في النطاق الافتراضي
      // (تعليمات المستخدم): كتابة محلية + outbox — السجل يُرفع عبر
      // push ويُسحب عبر delta لكل الأجهزة.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = _deviceSyncPayload(platform: 'android', now: now);
      await _writeLocalDeviceRow(payload);
      final deviceRowUuid = payload['local_uuid'] as String?;
      if (deviceRowUuid != null && deviceRowUuid.isNotEmpty) {
        try {
          await outboxDao.merge(
            entity: 'devices',
            op: 'create',
            localUuid: deviceRowUuid,
            payload: payload,
            clientTs: now,
          );
        } catch (e) {
          debugPrint('⚠️ devices outbox enqueue failed: $e');
        }
      }
      return _deviceId!;
    }
    // ✅ سجل في شاشة تتبع الأخطاء
    logHttpError(
      title: 'فشل تسجيل الجهاز',
      statusCode: response.statusCode,
      responseBody: response.body,
      source: 'sync:device_register',
    );
    throw Exception('Device registration failed: ${response.statusCode}');
  }

  // ─── Set FCM Token ──────────────────────────────────────────
  Future<void> setFcmToken(String token) async {
    if (_token == null || _deviceId == null) return;

    try {
      await _httpClient
          .post(
            Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': _deviceId,
              'fcmToken': token,
              'platform': 'android',
            }),
          )
          // 20s (كانت 10s) — نفس سبب registerDevice أعلاه.
          .timeout(const Duration(seconds: 20));
      debugPrint('✅ FCM token set for device: $_deviceId');
      // ✅ (2026-09-05) devices كيان متزامن: كتابة محلية + outbox update.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = _deviceSyncPayload(
        fcmToken: token,
        platform: 'android',
        now: now,
      );
      await _writeLocalDeviceRow(payload);
      final deviceRowUuid = payload['local_uuid'] as String?;
      if (deviceRowUuid != null && deviceRowUuid.isNotEmpty) {
        try {
          await outboxDao.merge(
            entity: 'devices',
            op: 'update',
            localUuid: deviceRowUuid,
            payload: payload,
            clientTs: now,
          );
        } catch (e) {
          debugPrint('⚠️ devices outbox enqueue failed: $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Set FCM token error: $e');
    }
  }

  // ─── Device sync row (local landing zone + outbox) ────────
  // ✅ (2026-09-05) حمولة مزامنة devices بصيغة snake_case مطابقة لأعمدة
  // جدول D1 (schema.sql + migrations/0004). الهوية: local_uuid =
  // deviceId (مستقر وفريد لكل تثبيت) — عمود device_id الموحّد هو
  // هوية الجهاز وعمود SyncFields.device_id (جهاز الكاتب) معاً.
  Map<String, dynamic> _deviceSyncPayload({
    required int now,
    String? fcmToken,
    String? platform,
    String? deviceName,
  }) {
    final deviceId = _deviceId ?? '';
    return <String, dynamic>{
      'local_uuid': deviceId,
      'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (platform != null) 'platform': platform,
      if (fcmToken != null) 'fcm_token': fcmToken,
      'status': 'active',
      'is_active': 1,
      'last_active': now,
      'updated_at': now,
      'last_modified': now,
      'last_modified_epoch': now,
      'version': 1,
      'origin': 'local',
      'vector_clock': jsonEncode(<String, int>{
        if (deviceId.isNotEmpty) deviceId: 1,
      }),
    };
  }

  /// كتابة/تحديث صف الجهاز محلياً (landing zone السحب ومصدر رفع D1).
  /// فشل الكتابة المحلية مساعد فقط — لا يُفشل التسجيل.
  Future<void> _writeLocalDeviceRow(Map<String, dynamic> syncPayload) async {
    try {
      final db = _db;
      if (db == null) return;
      final localUuid = syncPayload['local_uuid'] as String?;
      if (localUuid == null || localUuid.isEmpty) return;

      final existingRows = await db
          .customSelect(
            'SELECT id, version FROM devices WHERE local_uuid = ? LIMIT 1',
            variables: [Variable.withString(localUuid)],
          )
          .get();
      if (existingRows.isNotEmpty) {
        final existingVersion =
            (existingRows.first.data['version'] as int?) ?? 0;
        final fields = Map<String, dynamic>.from(syncPayload)
          ..remove('local_uuid')
          ..remove('created_at')
          ..['version'] = existingVersion + 1;
        final setClauses = fields.keys.map((c) => '$c = ?').join(', ');
        await db.customStatement(
          'UPDATE devices SET $setClauses WHERE local_uuid = ?',
          [...fields.values, localUuid],
        );
      } else {
        final row = <String, dynamic>{
          ...syncPayload,
          'device_name': syncPayload['device_name'] ?? '',
          'status': syncPayload['status'] ?? 'active',
          'is_active': syncPayload['is_active'] ?? 1,
          'created_at':
              (syncPayload['created_at'] ?? syncPayload['updated_at']) as int,
          'created_at_epoch': 0,
        }..remove('id');
        final columns = row.keys.join(', ');
        final placeholders = row.keys.map((_) => '?').join(', ');
        await db.customStatement(
          'INSERT OR REPLACE INTO devices ($columns) '
          'VALUES ($placeholders)',
          row.values.toList(),
        );
      }
    } catch (e) {
      debugPrint('⚠️ devices local row write failed: $e');
    }
  }

  // ─── Sync (push + pull) ─────────────────────────────────────
  ///
  /// ✅ P0-I: قفل re-entrancy — يمنع تشغيل عمليتي sync متداخلتين.
  /// قبل هذا الإصلاح، كان autoSync timer + onResume + manualSync
  /// يمكن أن يتداخلوا وكلهم يقرأون/يكتبون نفس outbox.
  /// نُعيد SyncResult خاص للإشارة للتخطّي (وليس خطأ).
  ///
  /// ✅ P0-B: إذا لم تكن full sync مكتملة بعد، فإن sync() ينفّذ full pull
  /// (cursor=0 implicit since not completed) ولا يضع checkpoint نهائي
  /// إلا بعد اكتمال pagination حتى exhaustion.
  Future<SyncResult> sync({
    bool push = true,
    bool pull = true,
    // ✅ توافق Drop-in (perf call-sites: dashboard_screen deltaOnly،
    // dashboard_sync_button/enhanced_sync_button forcePull):
    // deltaOnly = سحب دلتا فقط بلا رفع ولا full-sync bootstrap —
    // نفس عقد realtimeTriggeredPull؛ forcePull = طلب صريح من المستخدم
    // — المدير الحالي لا يملك حارس فاصل زمني على sync() (الأداء مُدار
    // بالـ auto-sync timer وP0-I)، فيُقبل ويُنفّذ السحب كالمعتاد.
    bool deltaOnly = false,
    bool forcePull = false,
  }) async {
    // ✅ المرحلة 6 (Dual-Run): مفتاح الإيقاف عن بُعد — disabled يعني
    // عودة آمنة للمحلي بلا مزامنة سحابية (خطة الرجوع: دقائق).
    if (!await CloudflareDualRunService().isCloudflareSyncEnabled()) {
      debugPrint('⏸️ Cloudflare sync disabled remotely (kill switch)');
      return SyncResult(
        status: SyncStatus.idle,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'Cloudflare sync disabled remotely (kill switch)',
      );
    }
    // ✅ (2026-09-05) مفتاح الإيقاف المحلي — «تفعيل مزامنة Appwrite»
    // في شاشة إعدادات المزامنة (appwrite_sync_enabled، افتراضه مفعّل).
    // سابقاً كان يوقف الحلقات الخلفية فقط بينما المزامنة اليدوية
    // تتجاهله — سلوك إنتاج غير متوقع. OFF يعني OFF لكل المسارات.
    try {
      final prefs = await SharedPreferences.getInstance();
      final locallyEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
      if (!locallyEnabled) {
        debugPrint('⏸️ Sync disabled locally (appwrite_sync_enabled=false)');
        return SyncResult(
          status: SyncStatus.idle,
          timestamp: DateTime.now(),
          duration: Duration.zero,
          errorMessage: 'Sync disabled locally (appwrite_sync_enabled=false)',
        );
      }
    } catch (_) {
      // فشل قراءة التفضيل لا يجوز أن يمنع المزامنة (fail-open مثل المفتاح البعيد).
    }
    if ((_token == null || _isTokenExpired(_token!)) &&
        (forcePull || _db != null)) {
      // ✅ (2026-09-10) إعادة تهيئة كسولة: كان فشل تسجيل الدخول عند
      // الإقلاع (شبكة محجوبة/DoH معطّل) يتطلب إعادة فتح التطبيق حرفياً —
      // أي سحب لاحق ينتهي بـ«Not initialized» حتى لو شفيت الشبكة
      // والتطبيق مفتوح. الآن sync() يجرّب تسجيل الدخول مرة واحدة
      // (محاولة واحدة + تبريد 60 ثانية) قبل إعلان الفشل.
      //
      // ✅ (2026-09-13) إصلاح «لا يسجل دخول تلقائياً» — تقرير مستخدم
      // بلقطة شاشة (v1.2.0.4541): السحب اليدوي كان يُصطدم بحارسين
      // يمنعان أي محاولة دخول رغم أن الشبكة والاعتمادات المدمجة سليمتان:
      //  1) حارس _db != null: مدير لم يكتمل تهيئته بعد (ضغط المستخدم
      //     سحباً خلال ثوانٍ الإقلاع الأولى) يفشل فوراً بلا أي محاولة.
      //  2) تبريد 60 ثانية: محاولة إقلاع فاشلة واحدة تُصمّد كل السحب
      //     اليدوي لدقيقة كاملة حتى مع شفاء الشبكة (وهذا ما ظهر في
      //     اللقطة: فحص الاتصال نجح والسحب رُفض).
      // الآن: forcePull (طلب المستخدم الصريح) يتجاوز التبريد ويسمح
      // بتهيئة مدير عذراء كاملة — بينما حلقات الخلفية/الدلتا تبقى
      // خاضعة للحارسين كما هي (عقود الاختبارات Hermetic سليمة:
      // كل اختبارات التبريد تنادي sync() بلا forcePull).
      //
      // ⚠️ حارس _db != null يبقى للمسار العادي (بلا forcePull): مدير
      // عذراء بلا تهيئة يبقى «Not initialized» فوراً — لا قاعدة بيانات
      // ولا IO ثقيل من مسار مزامنة لم يُهيأ (عقد اختبارات الويدجت).
      final now = DateTime.now();
      final last = _lastLazyInitAttempt;
      final cooldownPassed =
          last == null || now.difference(last) >= lazyInitCooldown;
      if (forcePull || cooldownPassed) {
        _lastLazyInitAttempt = now;
        debugPrint(
          '🔄 [Sync] token missing/expired — lazy re-login attempt '
          '(cooldown ${lazyInitCooldown.inSeconds}s'
          '${forcePull ? ', bypassed: manual forcePull' : ''})',
        );
        try {
          await initialize(loginAttempts: 1);
        } catch (e) {
          debugPrint('⚠️ [Sync] lazy re-login failed: $e');
        }
      }
    }
    if (_token == null) {
      return SyncResult(
        status: SyncStatus.failed,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'Not initialized',
      );
    }
    // يجب أن يسبق Delta-only تهيئة الدخول الكسولة. قبل هذا الترتيب كان
    // التطبيق العائد من الخلفية يملك full-sync مكتملة لكن توكنه غير محمّل،
    // فيعود المسار مبكراً ولا يحاول تسجيل الدخول حتى مع forcePull اليدوي.
    if (deltaOnly) {
      if (_syncInProgress) {
        return SyncResult(
          status: SyncStatus.idle,
          timestamp: DateTime.now(),
          duration: Duration.zero,
          errorMessage: 'Sync already in progress',
        );
      }
      _syncInProgress = true;
      bool ok = false;
      // ✅ (2026-09-15) عدّاد السحب يجب أن يصل للنتيجة — كان الإصلاح
      // السابق يهمل القيمة المرجعة من _pullChanges فيُبلّغ الواجهة
      // «0 سجلات» بعد كل سحب دلتا ناجح (عقد sync_pull_contract_test).
      int pulled = 0;
      String? deltaError;
      try {
        pulled = await _pullChanges(deltaOnly: true);
        ok = true;
      } catch (e) {
        deltaError = e.toString();
      } finally {
        _syncInProgress = false;
      }
      return SyncResult(
        status: ok ? SyncStatus.success : SyncStatus.idle,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        recordsPulled: pulled,
        errorMessage: ok ? null : deltaError,
      );
    }

    // ✅ P0-I: قفل re-entrancy
    if (_syncInProgress) {
      debugPrint('⚠️ Sync already in progress — skipping this call');
      return SyncResult(
        status: SyncStatus.idle,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'Sync already in progress',
      );
    }
    _syncInProgress = true;

    final startTime = DateTime.now();
    _currentStatus = SyncStatus.syncing;
    _statusController.add(SyncStatus.syncing);
    // ✅ (2026-09-08) عقد «فشل الدورة السابقة لا يلوّث هذه الدورة»:
    // تُفرَّغ المجموعة عند بداية كل دورة، فتصف «فشل آخر مزامنة» حرفياً.
    // قبل هذا: خطأ جدول عابر واحد كان يجعل كل الدورات اللاحقة
    // «فاشلة جزئياً» إلى الأبد حتى بعد شفاء الجدول.
    _failedCollectionsInLastSync.clear();
    int recordsPushed = 0;
    int recordsPulled = 0;
    String? errorMessage;

    // ✅ (2026-09-08) فصل دورة الدفع عن السحب — محاور إعادة الهيكلة:
    // كان الدفع والسحب في try واحدة: أي استثناء من _pushOutbox (مثل
    // «Push network error») يقطع السحب كلياً — جهاز عاجز عن الرفع
    // (شبكة صاعدة فقط، DNS، timeout) كان يفقد السحب أيضاً وتبقى
    // بياناته الخلفية قديمة إلى الأبد. الآن لكل دورة try/catch مستقل
    // والتقارير مستقلة، والفشل المجمّع يُبنى من كلا الطرفين.
    String? pushError;
    String? pullError;
    try {
      if (push) {
        try {
          recordsPushed = await _pushOutbox();
        } catch (e) {
          pushError = e.toString();
          logError(
            title: 'فشل دورة الدفع (السحب مستمر)',
            message: pushError,
            category: ErrorCategory.sync,
            source: 'sync:push',
          );
        }
      }
      if (pull) {
        try {
          recordsPulled = await _pullChanges(deltaOnly: deltaOnly);
        } catch (e) {
          pullError = e.toString();
          // _pullChanges يسجّل أخطاءه بنفسه (شبكة/HTTP/JSON) —
          // هنا نلتقط فقط لفصل الدورات ومنع القفز للـ catch الخارجي.
        }
      }

      // ✅ P0-B/P0-C: لا نعتبر المزامنة "نجحت" إلا إذا لم تكن هناك
      // collections فاشلة ولا خطأ دفع ولا خطأ سحب في هذه الدورة.
      if (pushError == null &&
          pullError == null &&
          _failedCollectionsInLastSync.isEmpty) {
        _currentStatus = SyncStatus.success;
        _statusController.add(SyncStatus.success);
        _lastError = null;
      } else {
        // ✅ P0-C: فشل جزئي أو كلي — الـ checkpoint عولج داخل _pullChanges
        // (تراجع إلى ما قبل أول صفحة معطوبة)، والحالة failed لإعلام
        // المستخدم وإعادة المحاولة.
        _currentStatus = SyncStatus.failed;
        _statusController.add(SyncStatus.failed);
        final parts = <String>[
          if (pushError != null) 'push: $pushError',
          if (pullError != null) 'pull: $pullError',
          if (_failedCollectionsInLastSync.isNotEmpty)
            'failed collections: ${_failedCollectionsInLastSync.join(', ')}',
        ];
        errorMessage = 'Partial sync failure — ${parts.join(' | ')}';
        _lastError = errorMessage;
        logError(
          title: 'فشل مزامنة جزئي',
          message: errorMessage,
          category: ErrorCategory.sync,
          source: 'sync:sync()',
        );
      }
    } catch (e) {
      _currentStatus = SyncStatus.failed;
      _statusController.add(SyncStatus.failed);
      errorMessage = e.toString();
      _lastError = errorMessage;
      // ✅ سجل في شاشة تتبع الأخطاء (إذا لم يكن مسجلاً بالفعل)
      // الدفع/السحب يسجلون بمفردهم — هذا لالتقاط أي استثناء آخر
      if (!errorMessage.contains('Push failed') &&
          !errorMessage.contains('Pull failed') &&
          !errorMessage.contains('Login failed') &&
          !errorMessage.contains('Device registration')) {
        logError(
          title: 'فشل المزامنة',
          message: errorMessage,
          category: ErrorCategory.sync,
          source: 'sync:sync()',
        );
      }
    } finally {
      _syncInProgress = false;
    }

    // ✅ (2026-09-05) تسجيل نتائج الدورة الفعلية في الإحصائيات —
    // نقطة اكتمال وحيدة بعد try/catch؛ الحروب المبكرة (kill switch،
    // deltaOnly، قفل re-entrancy) تعود قبلها فلا تُحتسب دورات.
    await _recordSyncOutcome(
      success: _currentStatus == SyncStatus.success,
      pushed: recordsPushed,
      pulled: recordsPulled,
      startedAt: startTime,
    );

    return SyncResult(
      status: _currentStatus,
      timestamp: startTime,
      duration: DateTime.now().difference(startTime),
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      errorMessage: errorMessage,
    );
  }

  // ─── Push outbox to D1 ──────────────────────────────────────
  Future<int> _pushOutbox() async {
    if (_db == null) return 0;

    // ✅ (fix R1) احترام تهدئة 429 — نفحص قبل أي reclaim حتى لا تبقى
    // السجلات عالقة في حالة processing طوال فترة التهدئة.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _pushCooldownUntil.millisecondsSinceEpoch) {
      final remaining = _pushCooldownUntil.difference(DateTime.now()).inSeconds;
      debugPrint(
        '⏳ Push: rate-limit cooldown نشط — تخطي الدفعة ($remaining(s) متبقية)',
      );
      return 0;
    }

    int totalPushed = 0;

    final outboxDao = OutboxDao(_db!);

    // ✅ (2026-09-06) استرجاع السجلات العالقة قبل التفريغ — reclaimForPush
    // وُجدت لهذا الغرض تحديداً (وثيقتها في outbox_dao.dart: «يُستدعى في
    // بداية طور الرفع») لكن الاستدعاء ضاع عند إعادة كتابة المدير السحابي.
    // بدونه: سجلات 'processing' عالقة (جلسة رفع انقطعت) تُحصى في عدّاد زر
    // الرفع (countUndeliveredToPrimary تشمل processing) بينما حلقة الرفع
    // أدناه تختار pending/failed فقط → زر «رفع التغييرات» يبقى مفعّلاً
    // للأبد ولا يفرّغ العداد. failed ≤ 5 محاولات تُعاد أيضاً إلى pending
    // — الضغط على الزر طلب صريح من المستخدم بإعادة المحاولة.
    try {
      await outboxDao.reclaimForPush();
    } catch (e) {
      // فشل الاسترجاع لا يجوز أن يمنع رفع السجلات السليمة
      debugPrint('⚠️ reclaimForPush failed (push continues): $e');
    }

    // ✅ حلقة الرفع: تكرر حتى يفرغ outbox من كل السجلات العالقة
    // هذا يضمن أن زر "رفع التغييرات" يرفع كل التغييرات دفعة واحدة
    // وليس فقط أول 25 سجل.
    //
    // ✅ (مراجعة 2026-09-09 #14) احترام سقف المحاولات: reclaimForPush
    // يعيد failed بـ attempts ≤ 5 إلى pending عمداً ويترك الأعلى من ذلك
    // للمؤقت الدوري retryFailedWithBackoff (backoff كل 30 دقيقة) — لكن
    // هذا الاختيار كان يلتقط failed بأي عدد محاولات فبطل الـ backoff
    // كلياً: سجل سام (رفض خادمي مزمن) يُدفع في كل دورة بلا تهدئة.
    // الآن: failed فوق السقف لا يُختار هنا (كما صمّم reclaimForPush)،
    // والفشل المؤقت المتكرر يبلغ dead-letter بعد _pushDeadLetterThreshold
    // محاولة (في _pushBatch) فلا تبقى سجلات عالقة في failed للأبد.
    //
    // ✅ (مراجعة #14 — الجزء الدقيق) ما فشل في هذا الاستدعاء لا يُعاد
    // اختياره في نفس الاستدعاء: كان الحلقة تعيد دفع الفاشل بعد كل
    // تكرار ناجح واحد (تقدم صفّ واحد يكفي لاستمرار الحلقة) — نفس
    // بطلان الـ backoff على المستوى الدقيق.
    final failedThisCall = <int>{};
    while (true) {
      final query = outboxDao.select(outboxDao.outbox)
        ..where(
          (t) =>
              t.processingStatus.equals('pending') |
              (t.processingStatus.equals('failed') &
                  t.attempts.isSmallerOrEqualValue(
                    _maxFailedAttemptsPerPushCycle,
                  )),
        )
        ..orderBy([(t) => OrderingTerm.asc(t.clientTs)])
        ..limit(CloudflareConfig.batchSize);
      if (failedThisCall.isNotEmpty) {
        query.where((t) => t.id.isNotIn(failedThisCall));
      }
      final pending = await query.get();

      if (pending.isEmpty) break;

      final outcome = await _pushBatch(pending);
      totalPushed += outcome.pushed;
      failedThisCall.addAll(outcome.failedIds);

      // إذا فشل الرفع (0 سجل مرفوع), توقف — ستبقى العالقة
      if (outcome.pushed == 0) break;

      debugPrint(
        '📤 Pushed ${outcome.pushed} operations (total: $totalPushed)',
      );
    }

    return totalPushed;
  }

  /// رفع دفعة واحدة من outbox
  ///
  /// ✅ P0-G (push-side OCC): نفرّق بوضوح بين:
  ///   - 404 / "not found" → السجل غير موجود على remote، يمكن إدراجه
  ///   - 409 / "conflict" → stale version، نطبّق resolveConflict
  ///   - 400 / validation → خطأ بيانات، نضع السجل في dead-letter
  ///   - 401/403 → خطأ auth، لا نلمس السجل (سينجح بعد re-auth)
  ///   - 5xx / network → فشل مؤقت، إعادة المحاولة لاحقاً
  ///
  /// يعيد (pushed, failedIds): failedIds هي السجلات التي فُصل حالها
  /// في هذه الدفعة (failed/dead) — تحجرها الحلقة المستدعية من إعادة
  /// اختيارها في نفس الاستدعاء (مراجعة #14).
  Future<({int pushed, Set<int> failedIds})> _pushBatch(
    List<OutboxData> pending,
  ) async {
    if (pending.isEmpty) return (pushed: 0, failedIds: const <int>{});

    final outboxDao = OutboxDao(_db!);

    final operations = <Map<String, dynamic>>[];
    for (final item in pending) {
      // ✅ عقد الدفع (2026-09-05): snake_case + local_uuid + vector_clock —
      // البناء الكامل في buildPushOperation (sync/payload_normalizer.dart)
      // ليُحارس العقد باختبارات تشغّل المنتجين الحقيقيين للكيانات.
      operations.add(
        await buildPushOperation(item, resolveRowVectorClock: _rowVectorClock),
      );
      if (_deviceId != null) {
        operations.last['deviceId'] = _deviceId;
      }
    }

    // ─── gzip compress the push payload for faster upload ───
    final jsonPayload = jsonEncode({'operations': operations});
    final jsonBytes = utf8.encode(jsonPayload);
    final gzipCodec = GZipCodec(); // default level 6 = good balance
    final compressedBytes = gzipCodec.encode(jsonBytes);

    final http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse('${CloudflareConfig.workerUrl}/api/sync/push'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
              'Content-Encoding': 'gzip',
              // ✅ (fix R-min5) أزلنا Content-Length اليدوي — حزمة http تحسبه
              // من الجسم فعلياً، والتكرار مع gzip يربك بعض البروكسيات.
            },
            body: compressedBytes,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      // ✅ P0-G: خطأ شبكة (DNS, timeout, socket) — ليس 404!
      // نُعيد السجلات لحالة pending لإعادة المحاولة لاحقاً.
      // لا نضعها كـ failed لأنها قد تنجح في الدورة التالية.
      logError(
        title: 'فشل شبكة أثناء الرفع',
        message: e.toString(),
        category: ErrorCategory.network,
        source: 'sync:push',
      );
      // إعادة السجلات إلى pending (reclaim)
      for (final item in pending) {
        try {
          await (outboxDao.update(
            outboxDao.outbox,
          )..where((t) => t.id.equals(item.id))).write(
            const OutboxCompanion(
              processingStatus: Value('pending'),
              processingStartedAt: Value(null),
              processingWorker: Value(null),
            ),
          );
        } catch (_) {
          // تجاهل — ستُلتقط لاحقاً
        }
      }
      // أعد الخطأ للمتصل، _pushOutbox ستتوقف عند pushed==0
      throw Exception('Push network error: $e');
    }

    if (response.statusCode != 200) {
      // ✅ سجل في شاشة تتبع الأخطاء
      logHttpError(
        title: 'فشل رفع التغييرات (Push)',
        statusCode: response.statusCode,
        responseBody: response.body,
        source: 'sync:push',
      );

      // ✅ (fix R1) 429 — نقرأ Retry-After (هيدر بالثواني، أو epoch في الجسم)
      // ونبرمج تهدئة قبل إعادة المحاولة بدل العضّ على الحد في كل دورة.
      if (response.statusCode == 429) {
        int? cooldownSec;
        final raHeader =
            response.headers['retry-after'] ?? response.headers['Retry-After'];
        if (raHeader != null) cooldownSec = int.tryParse(raHeader.trim());
        if (cooldownSec == null) {
          try {
            final errBody = jsonDecode(response.body);
            if (errBody is Map && errBody['retry_after'] is num) {
              final ra = (errBody['retry_after'] as num).toInt();
              final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              // الخادم يرسل epoch (ثوانٍ) في الجسم — نحوّله لمدة نسبية
              cooldownSec = ra > nowSec ? (ra - nowSec) : ra;
            }
          } catch (_) {}
        }
        if (cooldownSec == null || cooldownSec <= 0) cooldownSec = 60;
        if (cooldownSec > 600) cooldownSec = 600;
        _pushCooldownUntil = DateTime.now().add(Duration(seconds: cooldownSec));
        debugPrint('⏳ Push: 429 — تهدئة $cooldownSecث قبل المحاولة القادمة');
      }

      // ✅ P0-G: 401/403 → لا نلمس السجلات (ستُعاد المحاولة بعد re-auth)
      // 5xx → نعيد السجلات لـ pending
      if (response.statusCode == 401 || response.statusCode == 403) {
        // ✅ (2026-09-15) عقد التوكن طويل الأجل: 401 هنا يعني التوكن
        // أُبطل يدوياً (تدوير JWT_SECRET) — أَبطلُه محلياً فوراً ليشعل
        // البوابة `if (_token == null)` إعادة الدخول الكسولة في المزامنة
        // القادمة، بدل حلقة 401 دائمة حتى إعادة تشغيل التطبيق.
        _token = null;
        Env.cloudflareAuthToken = null;
        _lastLazyInitAttempt = null;
        // auth issue — أعِد السجلات لـ pending بدل failed
        for (final item in pending) {
          try {
            await (outboxDao.update(
              outboxDao.outbox,
            )..where((t) => t.id.equals(item.id))).write(
              const OutboxCompanion(
                processingStatus: Value('pending'),
                processingStartedAt: Value(null),
                processingWorker: Value(null),
              ),
            );
          } catch (_) {}
        }
      }
      throw Exception('Push failed: ${response.statusCode}');
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final results = result['results'] as List? ?? [];
    int successCount = 0;
    // ✅ (2026-09-09) تجميع عمليات الرفض الفردية من Worker لعرضها
    // في مركز أخطاء المزامنة (validation_error/conflict/مؤقت).
    final workerRejections = <String>[];
    // ✅ (مراجعة #14) السجلات التي فُصل حالها في هذه الدفعة.
    final failedIds = <int>{};

    // ✅ (مراجعة 2026-09-09 #3) فهرسة الدفعة بمفتاح idempotencyKey:
    // كانت firstFirst بـ orElse: () => pending.first — ناتج خادمي لمفتاح
    // لا يعود لأي سجل في الدفعة (تكرار/تشوه) كان يحذف أول سجل في
    // الدفعة من الـ outbox فقُدّ بياناته (نجاح خادمي لغيره!). الآن:
    // مفتاح مجهول يُتجاهل بسجل، ولا يُحذف إلا السجل المطابق فعلاً.
    final pendingByKey = <String, OutboxData>{
      for (final item in pending)
        if (item.idempotencyKey != null && item.idempotencyKey!.isNotEmpty)
          item.idempotencyKey!: item,
    };
    final returnedKeys = <String>{};

    for (final r in results) {
      final item = r as Map<String, dynamic>;
      final key = item['idempotencyKey'] as String?;
      final success = item['success'] as bool? ?? false;
      final opStatus =
          item['status']
              as String?; // ✅ P0-G: 'ok','not_found','conflict','validation_error'
      final errorMsg = item['error'] as String?;

      if (key == null) continue;
      returnedKeys.add(key);

      final outboxItem = pendingByKey[key];
      if (outboxItem == null) {
        // ✅ (مراجعة #3) مفتاح لا يعود لأي سجل في الدفعة — يُتجاهل
        // بلا مساس بأي صف (كان orElse يحذف pending.first)، ويُسجل
        // في مركز الأخطاء لملاحظة أي خلل في عقد النتائج.
        debugPrint(
          '⚠️ Push: worker result key not in this batch — ignored (no '
          'outbox row touched): $key',
        );
        workerRejections.add(
          'unknown_key | $key | ناتج لمفتاح لا يعود لأي عملية في الدفعة',
        );
        continue;
      }

      if (success) {
        // ✅ (F1 2026-09-22) عقد delete-vs-update: opStatus='deleted' يعني
        // أن الخادم رفض التعديل لأن الصف محذوف ناعماً — الحذف يفوز حتماً.
        // ليست إخفاقاً شبكياً (لا إعادة محاولة): السجل يُحذف من outbox
        // مع ختم محلي مطابق وقيَم الخسارة في مركز الأخطاء لوعي المستخدم.
        if (opStatus == 'deleted') {
          workerRejections.add(
            'deleted | $key | تعديل ${outboxItem.entity}/'
            '${outboxItem.localUuid} خسر عمداً لصالح حذف متزامن — '
            'الحذف يفوز (عقد delete-vs-update) وسجل edit_on_deleted '
            'مكتوب خادمياً',
          );
          await _tombstoneLocalRowAfterLostEdit(
            entity: outboxItem.entity,
            localUuid: outboxItem.localUuid,
          );
        }
        await (outboxDao.delete(
          outboxDao.outbox,
        )..where((t) => t.id.equals(outboxItem.id))).go();
        successCount++;
      } else {
        workerRejections.add(
          '${opStatus ?? "unknown"} | $key | ${errorMsg ?? "بدون تفاصيل"}',
        );
        // ✅ P0-G: نفرّق بين أنواع الفشل
        // - 'conflict' (409): تعارض إصدار — نطبّق resolveConflict لاحقاً
        // - 'validation_error' (400): خطأ بيانات دائم — dead-letter
        // - 'not_found' (404): لا يمكن أن يحدث في push (يحدث في pull)
        // - أي شيء آخر: فشل مؤقت — failed + إعادة محاولة
        final isPermanentError =
            opStatus == 'validation_error' ||
            errorMsg != null && errorMsg.contains('validation') ||
            errorMsg != null && _permanentPushErrorPattern.hasMatch(errorMsg);
        final isConflict =
            opStatus == 'conflict' ||
            errorMsg != null && errorMsg.contains('conflict');
        // ✅ (مراجعة #14) سقف الـ dead-letter: كل الأسباب غير الـ
        // validation تبلغ الحالة النهائية dead بعد العتبة — لا إعادة
        // دفع صامتة لا نهائية للتسجيلات السامّة.
        final nextAttempts = outboxItem.attempts + 1;
        final overDeadLetterCap = nextAttempts >= _pushDeadLetterThreshold;

        if (isPermanentError) {
          // ✅ P0-G: خطأ دائم — ضع السجل في dead-letter
          await outboxDao.setDead(
            outboxItem.id,
            errorMsg ?? 'Permanent validation error',
            nextAttempts,
          );
          failedIds.add(outboxItem.id);
        } else if (isConflict) {
          // ✅ P0-F: تعارض — علّمه كـ failed مع lastError واضح
          // conflict resolver سيلتقطه لاحقاً عبر getConflicts()
          if (overDeadLetterCap) {
            await outboxDao.setDead(
              outboxItem.id,
              'CONFLICT تجاوز الحد الأقصى ($_pushDeadLetterThreshold '
              'محاولة): ${errorMsg ?? "version mismatch"}',
              nextAttempts,
            );
          } else {
            await outboxDao.setError(
              outboxItem.id,
              'CONFLICT: ${errorMsg ?? "version mismatch"}',
              nextAttempts,
            );
          }
          failedIds.add(outboxItem.id);
        } else if (overDeadLetterCap) {
          await outboxDao.setDead(
            outboxItem.id,
            'تجاوز الحد الأقصى للمحاولات ($_pushDeadLetterThreshold): '
            '${errorMsg ?? "فشل مؤقت مزمن"}',
            nextAttempts,
          );
          failedIds.add(outboxItem.id);
        } else {
          // فشل مؤقت — إعادة المحاولة في الدورة القادمة
          await (outboxDao.update(
            outboxDao.outbox,
          )..where((t) => t.id.equals(outboxItem.id))).write(
            OutboxCompanion(
              processingStatus: const Value('failed'),
              attempts: Value(nextAttempts),
              lastError: Value(errorMsg ?? 'Unknown push failure'),
            ),
          );
          failedIds.add(outboxItem.id);
        }
      }
    }

    // ✅ (مراجعة 2026-09-09 #15) مطابقة النتائج مع المُرسَل: كل مفتاح
    // أُرسل يجب أن يعود ناتجاً — العملية التي سقطت من مصفوفة results
    // (تشوه استجابة/سقوط خادمي) كانت تبقى في outbox بحالتها بلا أثر
    // بينما الدورة تُحسب «ناجحة». الآن تُعامَل كفشل مؤقت (أو dead عند
    // تجاوز السقف) فتُرى في الإحصائيات ومركز الأخطاء ولا تُفقد.
    final missingResults = pendingByKey.keys
        .where((k) => !returnedKeys.contains(k))
        .toList(growable: false);
    if (missingResults.isNotEmpty) {
      for (final key in missingResults) {
        final item = pendingByKey[key]!;
        final nextAttempts = item.attempts + 1;
        workerRejections.add(
          'missing_result | $key | لم يُعَد ناتج لهذه العملية من الخادم',
        );
        if (nextAttempts >= _pushDeadLetterThreshold) {
          await outboxDao.setDead(
            item.id,
            'لم يُعَد ناتج من الخادم بعد $_pushDeadLetterThreshold محاولة '
            '(results ناقصة)',
            nextAttempts,
          );
        } else {
          await (outboxDao.update(
            outboxDao.outbox,
          )..where((t) => t.id.equals(item.id))).write(
            OutboxCompanion(
              processingStatus: const Value('failed'),
              attempts: Value(nextAttempts),
              lastError: const Value(
                'لم يُعَد ناتج لهذه العملية من الخادم (results ناقصة)',
              ),
            ),
          );
        }
        failedIds.add(item.id);
      }
      debugPrint(
        '⚠️ Push: ${missingResults.length} op(s) missing from worker '
        'results — marked for retry',
      );
    }

    // ✅ (2026-09-09) تسجيل عمليات الرفض في مركز أخطاء المزامنة —
    // أول 5 عمليات مع الحالة والمفتاح ورسالة الخادم. (بعد مطابقة
    // missing-results حتى تُشمل عمليات السقوط من results.)
    if (workerRejections.isNotEmpty) {
      logError(
        title:
            'Worker رفض ${workerRejections.length} من ${pending.length} '
            'عملية رفع',
        message: workerRejections.take(5).join('\n'),
        category: ErrorCategory.worker,
        source: 'worker:push',
      );
    }
    debugPrint('📤 Pushed $successCount/${pending.length} operations');
    return (pushed: successCount, failedIds: failedIds);
  }

  /// يقرأ ساعة المتجه الحالية لصف الكيان المحلي — العقد المرجعي الذي
  /// يفهمه الـ worker في OCC (database.ts detectConflict). تُعاد null
  /// للكيانات بلا جدول محلي (blacklist) أو الصفوف المفقودة — عندها
  /// يهيّئ الـ worker ساعة جديدة {deviceId: 1} (سلوك create الأصلي).
  Future<String?> _rowVectorClock(String entity, String localUuid) async {
    final table = CloudflareConfig.tableNameFor(entity);
    if (table == null || _db == null) return null;
    try {
      final row = await _db!
          .customSelect(
            'SELECT vector_clock FROM $table WHERE local_uuid = ? LIMIT 1',
            variables: [Variable<String>(localUuid)],
          )
          .getSingleOrNull();
      final vc = row?.data['vector_clock'] as String?;
      if (vc == null || vc.isEmpty || vc == '{}') return null;
      return vc;
    } catch (_) {
      // جدول محلي غير موجود (blacklist) أو صف محذوف — {} يهيئها الـ worker
      return null;
    }
  }

  // ─── Pull changes from D1 ───────────────────────────────────
  /// يُظهر سبب الخادم الفعلي (حقل detail/detail error في جسم 500 —
  /// عادة اسم الجدول/العمود الناقص في D1) بدل رمز الحالة وحده، حتى
  /// تُشخَّص أعطال السحب من رسالة الزر نفسها.
  String _pullHttpError(int statusCode, String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final detail = (map['detail'] ?? map['error'])?.toString() ?? '';
      final short = detail.length > 220
          ? '${detail.substring(0, 220)}…'
          : detail;
      return 'Pull HTTP $statusCode${short.isEmpty ? '' : ' — $short'}';
    } catch (_) {
      return 'Pull HTTP $statusCode';
    }
  }

  Future<int> _pullChanges({bool deltaOnly = false}) async {
    if (_db == null) return 0;

    // ✅ (2026-09-22 تسريع full sync) كاش دورة جديدة — لا يُرَث من دورة
    // سابقة (احتياط: صف أب قد يُحذف يدوياً/يُستعاد نسخة احتياطية بين
    // الدورتين، فلا نبني على افتراض بقائه صحيحاً للأبد).
    _fkParentIdCache.clear();

    // ✅ (مراجعة 2026-09-09 #1) مسح تقارب الحذفيات لمرة واحدة —
    // حذفيات تاريخية فاتتها الأجهزة التي سحبت أثناء نافذة العقد
    // القديم (worker كان يفلتر tombstones). نافذة tombstones_only
    // رخيصة ولا تمس المؤشر الرئيسي؛ فشل شبكي يؤجلها للدورة التالية
    // (العلم لا يُضبط إلا على نجاح كامل).
    //
    // ✅ بوابة الأجهزة القائمة فقط: التثبيت الجديد (cursor=0 ولم
    // يكمل full sync) سيجلب كل الحذفيات ضمن سحبه الكامل نفسه بعد
    // نشر worker العقد الجديد — طلب مسح إضافي هنا هدر صرف.
    try {
      final sweepPrefs = await SharedPreferences.getInstance();
      final needsTombstoneSweep =
          !(sweepPrefs.getBool(_kTombstoneSweepDoneKey) ?? false) &&
          (_lastPullCursor > 0 || _fullSyncCompleted);
      if (needsTombstoneSweep) {
        final swept = await _sweepHistoricalTombstones();
        if (swept != null) {
          await sweepPrefs.setBool(_kTombstoneSweepDoneKey, true);
          // ✅ إصلاح البطء: تنظيف مؤشر الاستئناف بعد الاكتمال الكامل —
          // العلم أعلاه كافٍ لمنع أي تشغيل لاحق، والمؤشر القديم لا فائدة
          // من إبقائه في التخزين.
          await sweepPrefs.remove(_kTombstoneSweepCursorKey);
          debugPrint('🧹 Tombstone sweep done: $swept handled');
          if (swept > 0) {
            logError(
              title: 'مسح حذفيات تاريخية: $swept سجلاً',
              message:
                  'اكتمل مسح التقارب لمرة واحدة: حذفيات جهاز آخر لم تصل '
                  'هذا الجهاز أثناء نافذة العقد القديم طُبّقت الآن كحذف '
                  'محلي (العدد يشمل ما لم يكن موجوداً محلياً أصلاً).',
              category: ErrorCategory.sync,
              source: 'sync:pull',
              severity: LogLevel.info,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ tombstone sweep gate failed (pull continues): $e');
    }

    int totalPulled = 0;
    // ✅ (2026-09-10) عدّاد صفحات السحب المنجزة — يغذّي مؤشر التقدم.
    int pagesDone = 0;
    // ✅ سقف الصفحات (H2): يُكسر حلقة pagination عند بلوغه — تُضبط أدناه.
    var hitPageCap = false;
    // كيانات مؤثرة على الحقول المشتقة للحجوزات — يُعاد بناء الليالي
    // والإجماليات المخزنة بعد اكتمال السحب (refreshAllActiveBookings
    // مع enqueueOutbox:false — البيانات المشتقة تُحسب محلياً ولا تُرفع،
    // وإلا حلقة سحب/رفع لا نهائية بين الأجهزة).
    final pulledDerivedEntities = <String>{};
    bool hasMore = true;

    // ✅ (2026-09-09) المؤجّل عبر الصفحات: صفوف أبناء علاقاتها لم تُحلّ
    // بعد (أبهم في صفحة لاحقة أو في نهاية هذا الترتيب الزمني) — تُعاد
    // بعد اكتمال pagination بترتيب الآباء قبل أي إعلان نجاح.
    final deferredRecords = <({String entity, Map<String, dynamic> record})>[];
    // ✅ (2026-09-09) المتعارضة قيداً فريداً حتمياً (UNIQUE) — تُجمَع من
    // التطبيق الأولي وإعادة محاولة المؤجّل معاً وتذهب لسلّم الحجر الصحي
    // (فرصة عادلة ثم عزل) بدل تجميد المؤشر إلى الأبد.
    final conflictedRecords =
        <({String entity, Map<String, dynamic> record})>[];
    // P0-C: save initial cursor to restore on failure
    final initialCursor = _lastPullCursor;
    int pendingCursor = _lastPullCursor;
    bool hadError = false;
    String? errorMessage;

    // Full Sync is explicit (fullSync()). Normal foreground/manual pulls are
    // bounded delta pulls even before the first Bootstrap.
    final wasFullSync = !deltaOnly && !_fullSyncCompleted;
    if (wasFullSync) {
      _isFullSyncInProgress = true;
      _fullSyncRemainingPages = -1;
      debugPrint('🔄 Full sync in progress (cursor=$pendingCursor)');
    }

    // ✅ (2026-09-10) بثّ لقطة البداية فوراً — المؤشر يظهر الصفر قبل
    // أول صفحة، والمستخدم يعرف أن السحب بدأ فعلاً.
    _emitPullProgress(SyncPullProgress(pulledRows: 0, isFullSync: wasFullSync));

    // ✅ (2026-09-09) تسريع السحب الكامل (طلب المستخدم): صفحة أكبر
    // للسحب الكامل — ~7,300 صف على السقف الخادمي للسحب
    // MAX_PULL_BATCH_SIZE=500.
    // ✅ (2026-09-15) الدلتا تصعد إلى [deltaPullBatchSize] (طلب
    // المستخدم: تسريع الدلتا أيضاً) — مستقلة عن [batchSize] الذي يبقى
    // سقف دفع outbox.
    final pageLimit = wasFullSync
        ? CloudflareConfig.fullPullBatchSize
        : CloudflareConfig.deltaPullBatchSize;
    // ✅ (2026-09-10) السحب الكامل يطلب remaining الخادمي للمؤشر الدقيق
    // (COUNT batch واحد) — الدلتا بلا كلفة إضافية.
    // ✅ (2026-09-22 تسريع full sync) طلبه في كل صفحة كان يعني 24 استعلام
    // COUNT خادمي (مُجمَّعة برحلة واحدة عبر db.batch، لكنها لا تزال 24
    // تنفيذاً على D1) × ~32 صفحة = ~768 تنفيذاً لمجرد مؤشر تقدم تقريبي.
    // كل 5 صفحات يكفي لمؤشر تقدم سلس بصرياً (المستخدم لا يلاحظ فرقاً
    // بين تحديث كل صفحة أو كل خمس) ويخفّض الحمل الخادمي ~80%.
    const remainingSampleEveryPages = 5;
    final wantRemaining = wasFullSync;
    bool wantRemainingForPage(int pageIndex) =>
        wantRemaining && pageIndex % remainingSampleEveryPages == 0;
    // ✅ تسريع — تداخل الشبكة مع التطبيق: الصفحة التالية تُجلَب أثناء
    // تطبيق الحالية (prefetch) فيختفي زمن الرحلة خلف كتابة SQLite.
    Future<http.Response>? prefetchFuture;

    // ⚠️ FK OFF أثناء السحب (الجذر الحقيقي لتعطل full sync):
    // أعمدة FK المحلية (مثل booking_nights.booking_local_id →
    // Bookings.id) تحمل قيم id من D1 (auto-increment)، بينما الأرقام
    // المحلية مختلفة تماماً (Drift يخصّص 1,2,3...) — والترتيب بسحب
    // updated_at لا يضمن وصول الأب قبل الابن. مع PRAGMA foreign_keys=ON
    // كانت كل إدراجات booking_nights/payments/notes تفشل صمتاً
    // (تلتقطها try-catch فتضيع السجلات بينما يتحرك الـ cursor) —
    // النتيجة: full sync "ينجح" بدون بيانات. نفس نمط الـ backup
    // services (google_drive_backup_service.dart:1267).
    try {
      await _db!.customStatement('PRAGMA foreign_keys = OFF');
    } catch (e) {
      debugPrint('⚠️ Failed to disable FKs during pull: $e');
    }

    try {
      while (hasMore) {
        // ✅ سقف الصفحات (H2): كاتب ساخن بلا توقف يجب ألا يحبس الدورة —
        // نخرج بنجاح جزئي والمؤشر تقدم عبر ما طُبِّق بسلامة.
        if (pagesDone >= _maxPullPagesPerCycle) {
          hitPageCap = true;
          hasMore = false;
          debugPrint(
            '⚠️ Pull: page cap $_maxPullPagesPerCycle reached — '
            'stopping cycle cleanly, remainder resumes next cycle '
            '(cursor=$pendingCursor)',
          );
          logError(
            title:
                'السحب بلغ سقف الصفحات ($_maxPullPagesPerCycle) — يُستأنف تلقائياً',
            message:
                'طُبِّق $totalPulled سجلاً عبر $pagesDone صفحة سليمة وتقدم '
                'المؤشر إلى $pendingCursor. البقية تُستأنف في الدورة القادمة '
                'تلقائياً (استمرار إنتاج الخادم لصفحات جديدة).',
            category: ErrorCategory.sync,
            source: 'sync:pull',
            severity: LogLevel.warning,
          );
          break;
        }
        final http.Response response;
        try {
          if (prefetchFuture != null) {
            // الصفحة التالية انطلقت أثناء تطبيق السابقة — نقطفها الآن.
            response = await prefetchFuture;
            prefetchFuture = null;
          } else {
            response = await _fetchPullPage(
              pendingCursor,
              pageLimit,
              // ✅ (2026-09-09) السحب الكامل يشمل صفوف الجهاز نفسه
              // لتعلّم ظلّ server_id (إصلاح 107 علاقة غير محلولة).
              excludeOwnDevice: !wasFullSync,
              includeRemaining: wantRemainingForPage(pagesDone),
              // ✅ إصلاح البطء: التطبيع الخادمي (مسح 23 جدولاً) يُطلب في
              // الصفحة الأولى فقط — طلبُه في كل صفحة كان يضاعف زمن السحب
              // ويتجاوز مهلة 30 ثانية فيبدو السحب متوقفاً.
              includeNormalization:
                  pagesDone == 0 && !(_timestampNormalizationDone ?? false),
            );
          }
        } catch (e) {
          // P0-G: network error (DNS, timeout) - not "sync complete"
          hadError = true;
          errorMessage = 'Pull network error: $e';
          logError(
            title: 'Network failure during pull',
            message: e.toString(),
            category: ErrorCategory.network,
            source: 'sync:pull',
          );
          break;
        }

        if (response.statusCode != 200) {
          hadError = true;
          errorMessage = _pullHttpError(response.statusCode, response.body);
          logHttpError(
            title: 'Pull failed',
            statusCode: response.statusCode,
            responseBody: response.body,
            source: 'sync:pull',
          );
          break;
        }

        Map<String, dynamic> data;
        try {
          data = jsonDecode(response.body) as Map<String, dynamic>;
        } catch (e) {
          hadError = true;
          errorMessage = 'Pull JSON parse error: $e';
          logError(
            title: 'Pull JSON parse error',
            message: e.toString(),
            category: ErrorCategory.sync,
            source: 'sync:pull',
          );
          break;
        }

        final changes = data['changes'] as List? ?? [];
        // ✅ (2026-09-08) محور 2 — منع إعلان النجاح مع جداول ناقصة:
        // أخطاء الجداول الخادمية (errors[]) = دورة فاشلة: لا pagination
        // إضافي، لا تحرك checkpoint، لا علامة full sync. الصفوف السليمة
        // في هذه الصفحة تُطبق، والدورة التالية تعيد المحاولة من المؤشر
        // نفسه (idempotent عبر local_uuid) حتى يُشفي الخادم.
        final tableErrors = data['errors'] as List? ?? [];
        for (final e in tableErrors) {
          debugPrint('⚠️ Pull: server skipped table: $e');
          try {
            final map = Map<String, dynamic>.from(e as Map);
            final ent = map['entity']?.toString();
            if (ent != null && ent.isNotEmpty) {
              _failedCollectionsInLastSync.add(ent);
            }
          } catch (_) {
            _failedCollectionsInLastSync.add('unknown-table-error');
          }
        }
        if (tableErrors.isNotEmpty) {
          // ✅ (2026-09-08) سياسة refactor/cloudflare-sync-pipeline:
          // صفحة بها جداول مُتخطّاة توقف السحب فوراً — البيانات ناقصة
          // والاستمرار على السليم يوهم بالاكتمال. لا يتحرك المؤشر إطلاقاً
          // (التراجع لما قبل الدورة) وترمى الدورة كفاشلة.
          hadError = true;
          final skipDetail =
              'Pull skipped ${tableErrors.length} remote table(s): '
              '${tableErrors.join('; ')}';
          errorMessage = skipDetail;
          _failedCollectionsInLastSync.addAll(
            tableErrors.map((e) {
              if (e is Map && e['entity'] != null) {
                return e['entity'].toString();
              }
              return 'pull';
            }),
          );
          // ✅ (2026-09-09) تسجيل أخطاء Worker في مركز أخطاء المزامنة:
          // أخطاء errors[] الخادمية = الجداول التي تخطاها الـ Worker
          // (سبب مباشر لـ«البيانات غير مكتملة») — تُعرض للمستخدم مع
          // اسم الجدول ورسالة الخادم الأصلية.
          logError(
            title: 'Worker تجاوز ${tableErrors.length} جدولاً أثناء السحب',
            message: skipDetail,
            category: ErrorCategory.worker,
            source: 'worker:pull',
          );
        }
        // ✅ (2026-09-09) تسجيل حالة تطبيع الطوابع الزمنية الخادمية:
        // remaining > 0 يعني أن الخادم ما زال يعالج صفوفاً مسموومة
        // (ميلي-ثانية) — تحذير مفيد لتشخيص بطء اكتمال السحب بعد
        // نشر worker الإصلاح، وليس فشلاً للدورة.
        final normalization = data['normalization'];
        if (normalization is Map) {
          final remaining = normalization['remaining'];
          if (remaining is num && remaining <= 0) {
            _timestampNormalizationDone = true;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_kTimestampNormalizationDoneKey, true);
          }
          if (remaining is int && remaining > 0) {
            logError(
              title: 'Worker: تطبيع الطوابع الزمنية غير مكتمل بعد',
              message:
                  'normalized=${normalization['normalized']}, '
                  'remaining=$remaining — سيُستكمل تلقائياً في الدورات '
                  'التالية.',
              category: ErrorCategory.worker,
              source: 'worker:pull',
              severity: LogLevel.warning,
            );
          }
        }
        // P0-C: server-derived cursor is authoritative, not device time
        final serverCursor = int.tryParse(data['cursor']?.toString() ?? '0');
        hasMore = data['has_more'] as bool? ?? false;
        // البيانات ناقصة؛ لا نتابع pagination ولا نحرّك checkpoint.
        if (hadError) hasMore = false;

        // ✅ (2026-09-17) حارس التسمم أثناء التشغيل: مؤشر خادم يتجاوز
        // server_time المُعلن في الرد نفسه بأكثر من هامش سنة = صفوف مسمومة
        // (sentinel 9999999999 أو ميلي) ما زالت تُقدَّم من worker غير مُصلح —
        // لا تُثبَّت أبداً: نُفسد الدورة فوراً (المؤشر يبقى كما كان والدورة
        // القادمة تعيد المحاولة) بدل تعمية الجهاز للأبد. صفوف هذه الصفحة لا
        // تُطبَّق أيضاً — طوابعها المسمومة كانت ستفوز بكل قرارات LWW المحلية
        // (سنة 2286!) إلى الأبد. (مرآة العتبة الخادمية FUTURE_TIMESTAMP_THRESHOLD.)
        final int? serverTime = (data['server_time'] as num?)?.toInt();
        if (serverCursor != null && serverCursor > pendingCursor) {
          final bool cursorSane =
              serverTime == null ||
              serverCursor <= serverTime + maxCursorAheadOfServerSec;
          if (!cursorSane) {
            hadError = true;
            errorMessage =
                'Pull: poisoned server cursor rejected ($serverCursor vs '
                'server_time=$serverTime)';
            logError(
              title: 'مؤشر خادم مسموم رُفض أثناء السحب ($serverCursor)',
              message:
                  'رد السحب يحمل مؤشراً يتجاوز وقت الخادم المُعلن بسنوات — '
                  'صفوف بطوابع sentinel/ميلي ما زالت تُقدَّم (worker غير مُصلح '
                  'أو بيانات مستعادة قديمة). أُفشلت الدورة ولم يتقدم المؤشر، '
                  'ولم تُطبَّق صفوف الصفحة؛ الدورة القادمة تعيد المحاولة '
                  'تلقائياً بعد شفاء الخادم.',
              category: ErrorCategory.sync,
              source: 'sync:pull',
            );
            break;
          }
          pendingCursor = serverCursor;
        }

        // P0-C: apply changes — الدفعة كاملة تُطبّق مع ترجمة FK وفلترة
        // أعمدة وإعادة محاولة المؤجّل (2026-09-09). الصفوف الفاشلة
        // حقيقياً أو غير القابلة للحل تُفسد الدورة كلها أدناه — لا
        // تبتلع صمتاً بعد اليوم.
        final batchRecords = <({String entity, Map<String, dynamic> record})>[];
        for (final change in changes) {
          try {
            final record = Map<String, dynamic>.from(change as Map);
            final entity =
                record['_entity'] as String? ?? _detectEntity(record);
            record.remove('_entity'); // don't store this field in SQLite

            if (entity != null) {
              batchRecords.add((entity: entity, record: record));
            } else {
              debugPrint(
                '⚠️ Pull: skipped record with unknown entity '
                '(keys: ${record.keys.join(',')})',
              );
            }
          } catch (e) {
            // حارس تركيب السجل نفسه (ليس تطبيقه) — يُفسد الدورة أيضاً.
            hadError = true;
            errorMessage = 'Pull: malformed change envelope: $e';
            debugPrint('⚠️ $errorMessage');
          }
        }
        // ✅ تسريع — إطلاق جلب الصفحة التالية قبل تطبيق الحالية:
        // المؤشر معروف من استجابة الصفحة الحالية قبل أي تطبيق، والتطبيق
        // لا يمس الشبكة — التداخل آمن ويخفي زمن الرحلة كاملاً.
        if (hasMore && !hadError) {
          // ✅ الجلب المسبق بلا تطبيع: الصفحة الأولى وحدها تطلب الإصلاح
          // الخادمي — بقية الصفحات سحب صافٍ (includeNormalization الافتراضي
          // false — أُزيل الوسيط الصريح المطابق للقيمة الافتراضية).
          prefetchFuture = _fetchPullPage(
            pendingCursor,
            pageLimit,
            excludeOwnDevice: !wasFullSync,
            // pagesDone لم يتقدم بعد لهذه الصفحة — الصفحة المطلوبة هنا
            // هي pagesDone+1 (التالية)، فيُحسَب التردد على أساسها.
            includeRemaining: wantRemainingForPage(pagesDone + 1),
          );
        }

        // ✅ تسريع — الصفحة كلها في معاملة واحدة: commit واحد لكل صفحة
        // بدل commit لكل صف — أكبر مكسب زمني على تخزين الجهاز
        // (7,300 commit → ~18 commit في السحب الكامل).
        final report = await _db!.transaction(
          () => _applyPulledRecords(
            batchRecords,
            deferredSink: deferredRecords,
            conflictedSink: conflictedRecords,
          ),
        );
        totalPulled += report.appliedCount;

        // ✅ (2026-09-10) بثّ التقدم بعد كل صفحة — «حجم السحب والمتبقي»:
        // pulled = المطبّق تراكمياً، remaining = خادمي (null إن لم يتوفر).
        // بثّ لا ينتظره أحد (broadcast) — صفر تأثير على زمن الدورة.
        pagesDone++;
        _emitPullProgress(
          SyncPullProgress(
            pulledRows: totalPulled,
            remainingRows: data['remaining'] is int
                ? data['remaining'] as int
                : null,
            pages: pagesDone,
            isFullSync: wasFullSync,
          ),
        );

        if (report.errors.isNotEmpty) {
          hadError = true;
          final errorSummary = report.errors.take(2).join(' | ');
          errorMessage =
              'Pull: ${report.errors.length} apply-failure(s): $errorSummary';
          _failedCollectionsInLastSync.add('pull');
          debugPrint('⚠️ $errorMessage');
        }
        pulledDerivedEntities.addAll(
          report.touchedEntities.intersection(_derivedRefreshEntities),
        );

        // P0-C: contradictory state - has_more=true but empty changes
        if (!hadError && changes.isEmpty && hasMore) {
          debugPrint(
            '⚠️ Pull returned has_more=true but empty changes - stopping',
          );
          hasMore = false;
        }
      }

      // ✅ (2026-09-09) الجذر (ب) — إعادة محاولة المؤجّل بعد اكتمال
      // الصفحات: الآباء وصلوا الآن (صفحات لاحقة)، فتُحلّ السلاسل
      // (غرفة → حجز → ليلة / موظف → دورة → دفعة).
      // ✅ (2026-09-15) من بقي بعد هذه المحاولة لا يُفشل الدورة بعد
      // اليوم — يذهب إلى سجل الانتظار أدناه (الحمولة محفوظة والمؤشر
      // يتقدم) بدل تراجع المؤشر وإعادة سحب كل الصفحات كل دورة.
      var unresolvedAfterRetry =
          const <({String entity, Map<String, dynamic> record})>[];
      if (deferredRecords.isNotEmpty || conflictedRecords.isNotEmpty) {
        final retryErrors = <String>[];
        unresolvedAfterRetry = await _retryDeferredRecords(
          deferredRecords,
          onApplied: (entity) {
            totalPulled++;
            pulledDerivedEntities.add(entity);
          },
          errors: retryErrors,
          conflictedSink: conflictedRecords,
        );
        if (retryErrors.isNotEmpty) {
          hadError = true;
          final errorSummary = retryErrors.take(2).join(' | ');
          errorMessage =
              'Pull: ${retryErrors.length} apply-failure(s) on deferred '
              'retry: $errorSummary';
          _failedCollectionsInLastSync.add('pull');
          debugPrint('⚠️ $errorMessage');
          // ✅ (2026-09-09) فشل تطبيق سجلات مؤجلة — يظهر في مركز
          // الأخطاء مع تفاصيل أول خطأين (سبب مباشر لبيانات ناقصة).
          logError(
            title:
                'فشل تطبيق ${retryErrors.length} سجلاً مؤجلاً بعد إعادة '
                'المحاولة',
            message: errorMessage,
            category: ErrorCategory.sync,
            source: 'sync:pull-apply',
          );
        }
      }

      // ✅ (2026-09-15) سجل الانتظار — تسريع السحب وإصلاح تجميد المؤشر
      // (تقرير 2026-09-14: «55 سجل محجوب — تجميد مؤشر السحب»):
      // • محجوبو دورات سابقة (حمولاتهم في [_blockedPending]) يُعاد
      //   حلّهم من حمولتهم هنا — محلي صفر شبكة.
      // • المعزولون سابقاً يُجَرَّب شفاؤهم من حمولاتهم — تحقيق وعد
      //   رسالة الحجر («وصل الأب أو تفريغ المفتاح → يُطبَّق تلقائياً»)
      //   بلا انتظار إعادة بث الصف من الخادم.
      // فشل الدورة يبقى حصراً للأخطاء الحقيقية (شبكة/HTTP/JSON/جداول
      // متخطاة/فشل تطبيق فعلي) — المحجوبون العلاقيون لا يعيدون سحب
      // الصفحات ولا يجمّدون المؤشر بعد اليوم.
      var ledgerDirty = false;
      final quarantinePrefs = await SharedPreferences.getInstance();
      if (_blockedPending.isNotEmpty || _quarantinedRecords.isNotEmpty) {
        if (_blockedPending.isNotEmpty) {
          final ledgerItems = List.of(_blockedPending.values);
          final ledgerErrors = <String>[];
          final ledgerErrored =
              <({String entity, Map<String, dynamic> record})>[];
          final ledgerRemaining = await _retryDeferredRecords(
            ledgerItems,
            onApplied: (entity) {
              totalPulled++;
              pulledDerivedEntities.add(entity);
            },
            errors: ledgerErrors,
            conflictedSink: conflictedRecords,
            erroredSink: ledgerErrored,
          );
          // ✅ (M1) أخطاء التطبيق الحقيقية هنا كانت تُبتلع بصمت (القائمة
          // تُملأ ولا تُقرأ): الآن تظهر في مركز الأخطاء — لكنها لا تُفشل
          // الدورة عمداً: سجلات السجل معروفة-الإشكال وحمولتها محفوظة،
          // وإفشال الدورة عليها يعيد تجميد المؤشر الذي بُني الحجر لمنعه.
          // التوجيه للحجر/الانتظار مقصود، والرؤية للخطأ مقصودة أيضاً.
          if (ledgerErrors.isNotEmpty) {
            final ledgerSummary = ledgerErrors.take(2).join(' | ');
            debugPrint(
              '⚠️ Pull ledger retry: ${ledgerErrors.length} apply-failure(s): '
              '$ledgerSummary',
            );
            logError(
              title:
                  'فشل تطبيق ${ledgerErrors.length} سجلاً من سجل الانتظار '
                  '— بقيت في الحجر/الانتظار',
              message: ledgerSummary,
              category: ErrorCategory.sync,
              source: 'sync:pull-apply',
            );
          }
          // الأخطاء الفعلية (لا تعارض ولا تأجيل) تدخل المحاسبة أيضاً،
          // وما بقي مؤجلاً من السجل كذلك — ليزداد عدّاد حجبه نحو
          // العتبة بدل البقاء في الانتظار إلى الأبد.
          unresolvedAfterRetry = [
            ...unresolvedAfterRetry,
            ...ledgerErrored,
            ...ledgerRemaining,
          ];
          final failedIds = {
            for (final item in ledgerRemaining)
              _quarantineIdentity(
                item.entity,
                item.record['local_uuid']?.toString(),
              ),
          };
          for (final item in ledgerItems) {
            final identity = _quarantineIdentity(
              item.entity,
              item.record['local_uuid']?.toString(),
            );
            if (!failedIds.contains(identity)) {
              // شُفي (أب وصل/مفتاح تحرر) — أو أصبح متعارضاً وسيُحاسب
              // أدناه على نفس الهوية (عدّاده يبقى معلقاً حتى العتبة).
              if (_blockedPending.remove(identity) != null) {
                ledgerDirty = true;
                if (!conflictedRecords.any(
                  (c) =>
                      _quarantineIdentity(
                        c.entity,
                        c.record['local_uuid']?.toString(),
                      ) ==
                      identity,
                )) {
                  _orphanBlockCounts.remove(identity);
                }
              }
            }
          }
        }
        // شفاء المعزولين من حمولاتهم (بسقف لكل دورة).
        if (_quarantinedRecords.isNotEmpty) {
          final retryItems = <({String entity, Map<String, dynamic> record})>[];
          for (final entry in _quarantinedRecords.entries) {
            if (retryItems.length >= _quarantineHealRetryLimit) break;
            final raw = entry.value['record'];
            final entity = entry.value['entity']?.toString();
            if (raw is Map && raw.isNotEmpty && entity != null) {
              retryItems.add((
                entity: entity,
                record: Map<String, dynamic>.from(raw),
              ));
            }
          }
          for (final item in retryItems) {
            try {
              final ok = await _applyChange(item.entity, item.record);
              if (ok) {
                final identity = _quarantineIdentity(
                  item.entity,
                  item.record['local_uuid']?.toString(),
                );
                if (_quarantinedRecords.remove(identity) != null) {
                  _orphanBlockCounts.remove(identity);
                  ledgerDirty = true;
                  totalPulled++;
                  pulledDerivedEntities.add(item.entity);
                  debugPrint(
                    '🏥 Pull: quarantined ${item.entity}/'
                    '${item.record['local_uuid']} healed — parent arrived '
                    'or key freed',
                  );
                }
              }
            } catch (_) {
              // ما زال محجوباً — يبقى معزولاً بصمت (المحاولة محلية
              // صفرية الكلفة).
            }
          }
        }
      }

      // ✅ (2026-09-15) المحاسبة — سلّم الانتظار ثم الحجر بلا تجميد
      // مؤشر: كل المحجوبين (بقية المؤجّل + المتعارضون من التطبيق
      // الأولي وإعادة المحاولات) يُحاسبون مرة واحدة لكل هوية في
      // الدورة، وتُحفظ حمولتهم في سجل الانتظار؛ وبعد العتبة ينتقلون
      // لسجل الحجر. لا hadError هنا: الصفحات سليمة والمؤشر يتقدم —
      // الفئتان لا تُشفيان بإعادة سحب الصفحات أصلاً، وإعادة المحاولة
      // من الحمولة أوفر وأصح.
      final quarantinePoolByIdentity =
          <String, ({String entity, Map<String, dynamic> record})>{
            for (final item in [
              ...unresolvedAfterRetry,
              ...conflictedRecords,
            ])
              _quarantineIdentity(
                item.entity,
                item.record['local_uuid']?.toString(),
              ): item,
          };
      if (quarantinePoolByIdentity.isNotEmpty) {
        final toWait = <({String entity, Map<String, dynamic> record})>[];
        final toQuarantine = <({String entity, Map<String, dynamic> record})>[];
        for (final entry in quarantinePoolByIdentity.entries) {
          final count = (_orphanBlockCounts[entry.key] ?? 0) + 1;
          _orphanBlockCounts[entry.key] = count;
          if (count >= _quarantineBlockThreshold) {
            toQuarantine.add(entry.value);
          } else {
            toWait.add(entry.value);
          }
        }

        if (toQuarantine.isNotEmpty) {
          final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final newlyQuarantined =
              <({String entity, Map<String, dynamic> record})>[];
          for (final item in toQuarantine) {
            final identity = _quarantineIdentity(
              item.entity,
              item.record['local_uuid']?.toString(),
            );
            // ✅ (2026-09-09) إشعار الحجر فقط للهويات المعزولة حديثاً —
            // السجل المعزول سابقاً يعاد عزله صامتاً بلا إزعاج.
            if (!_quarantinedRecords.containsKey(identity)) {
              newlyQuarantined.add(item);
            }
            // ✅ (2026-09-15) الحمولة تُحفظ مع الحجر — أساس الشفاء
            // الدوري من الحمولة أعلاه.
            _quarantinedRecords[identity] = <String, dynamic>{
              'entity': item.entity,
              'local_uuid': item.record['local_uuid']?.toString(),
              'first_seen': nowSec,
              'updated_at': item.record['updated_at'],
              'record': item.record,
            };
            // خرج من سجل الانتظار (إن كان فيه) — الحجر يحل محله.
            if (_blockedPending.remove(identity) != null) {
              ledgerDirty = true;
            }
          }
          if (newlyQuarantined.isNotEmpty) {
            final quarantinedNames = [
              for (final item in newlyQuarantined.take(3))
                '${item.entity}/${item.record['local_uuid']}',
            ];
            debugPrint(
              '🏥 Pull: quarantined ${newlyQuarantined.length} unresolvable '
              'record(s): ${quarantinedNames.join(', ')}',
            );
            logError(
              title:
                  'سجلات يتيماً أو متعارضة المفتاح الفريد '
                  '(${newlyQuarantined.length}) — عُزلت واكملت المزامنة '
                  'بقية البيانات',
              message:
                  'السجلات: ${quarantinedNames.join(', ')} — أبُها مفقود '
                  'خادمياً أو مفتاحها الفريد مشغول بصف محلي حتى بعد '
                  '$_quarantineBlockThreshold دورات من سجل الانتظار '
                  '(يتيم بنيوي: أب محذوف يدوياً من D1، أو نسخة مكررة من '
                  'استعادة نسخة احتياطية). عُزلت في سجل الحجر مع حمولتها '
                  'ويتقدم المؤشر — وصول الأب أو تفريغ المفتاح أو وصول '
                  'tombstone يُطبّقها تلقائياً من الحمولة في دورة لاحقة.',
              category: ErrorCategory.sync,
              source: 'sync:pull-apply',
              severity: LogLevel.warning,
            );
          }
        }

        if (toWait.isNotEmpty) {
          // ✅ (2026-09-15) تحت العتبة = حمولة محفوظة في سجل الانتظار،
          // تُعاد محاولتها من الحمولة في بداية كل دورة سحب — لا تراجع
          // مؤشر ولا إعادة سحب صفحات (التصميم القديم كان يجمّد المؤشر
          // هنا ويعيد سحب كل شيء حتى تكتمل العتبة).
          final newEntries = <String>{};
          for (final item in toWait) {
            final identity = _quarantineIdentity(
              item.entity,
              item.record['local_uuid']?.toString(),
            );
            if (!_blockedPending.containsKey(identity)) {
              newEntries.add(identity);
            }
            _blockedPending[identity] = item;
          }
          ledgerDirty = true;
          // صمام الأمان: سقف السجل — الفائض الأقرب للعتبة يُعزل فوراً
          // (حمولته تبقى في الحجر للشفاء الدوري).
          if (_blockedPending.length > _blockedPendingCap) {
            final overflow =
                (_blockedPending.keys.toList()..sort(
                      (a, b) => (_orphanBlockCounts[b] ?? 0).compareTo(
                        _orphanBlockCounts[a] ?? 0,
                      ),
                    ))
                    .take(_blockedPending.length - _blockedPendingCap)
                    .toList();
            final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            for (final identity in overflow) {
              final item = _blockedPending.remove(identity)!;
              if (!_quarantinedRecords.containsKey(identity)) {
                _quarantinedRecords[identity] = <String, dynamic>{
                  'entity': item.entity,
                  'local_uuid': item.record['local_uuid']?.toString(),
                  'first_seen': nowSec,
                  'updated_at': item.record['updated_at'],
                  'record': item.record,
                };
              }
            }
            debugPrint(
              '🏥 Pull: waiting-ledger cap $_blockedPendingCap exceeded — '
              'force-quarantined ${overflow.length} record(s)',
            );
          }
          if (newEntries.isNotEmpty) {
            final names = newEntries.take(3).toList();
            logError(
              title:
                  '${newEntries.length} سجل مؤجل (أب غير محلول أو تعارض '
                  'مفتاح فريد) — في سجل الانتظار والمؤشر يتقدم',
              message:
                  'السجلات: ${names.join(', ')} — حُفظت حمولتها كاملة في '
                  'سجل الانتظار وسيُعاد حلّها من الحمولة في بداية كل دورة '
                  'سحب دون إعادة سحب أي صفحة (التصميم قبل 2026-09-15 كان '
                  'يراجع المؤشر ويعيد سحب كل البيانات كل دورة حتى اكتمال '
                  'عتبة الحجر). بعد $_quarantineBlockThreshold دورات تُنقل '
                  'لسجل الحجر تلقائياً.',
              category: ErrorCategory.sync,
              source: 'sync:pull-apply',
              severity: LogLevel.warning,
            );
          }
        }

        ledgerDirty = true;
      }

      // ✅ (M2) فرض سقف الحجر بعد كل محاسبة — الإخلاء بالأقدم first_seen.
      if (_quarantinedRecords.length > _quarantineCap) {
        final ordered = _quarantinedRecords.entries.toList()
          ..sort(
            (a, b) => _quarantineFirstSeen(
              a.value,
            ).compareTo(_quarantineFirstSeen(b.value)),
          );
        final victims = ordered
            .take(_quarantinedRecords.length - _quarantineCap)
            .toList();
        for (final victim in victims) {
          _quarantinedRecords.remove(victim.key);
          _orphanBlockCounts.remove(victim.key);
        }
        ledgerDirty = true;
        debugPrint(
          '🏥 Pull: quarantine cap $_quarantineCap exceeded — '
          'evicted ${victims.length} oldest record(s)',
        );
      }
      if (ledgerDirty) {
        await _persistQuarantineState(quarantinePrefs);
      }
    } finally {
      // ✅ استهلاك أي استجابة صفحة معلّقة انطلقت ولم تُقطف (خطأ منتصف
      // الدورة) — إغلاق نظيف دون تعطيل مسار الخطأ الحالي.
      if (prefetchFuture != null) {
        try {
          await prefetchFuture.timeout(const Duration(seconds: 10));
        } catch (_) {
          // الجلب المعلق فاشل — لا يهم: الدورة فشلت لسبب سابق أصلأً.
        }
        prefetchFuture = null;
      }
      try {
        await _db!.customStatement('PRAGMA foreign_keys = ON');
      } catch (e) {
        debugPrint('⚠️ Failed to re-enable FKs after pull: $e');
      }
      if (wasFullSync) {
        _isFullSyncInProgress = false;
        _fullSyncRemainingPages = 0;
      }
      // ✅ (2026-09-10) لقطة النهاية في finally — تُبثّ في النجاح والفشل
      // معاً (throw المسار الفاشل يحدث بعد هذا الكتلة): remaining صفر
      // عند النجاح، ورسالة الخطأ عند الفشل. نفس التدفق غير الحاجب.
      _emitPullProgress(
        SyncPullProgress(
          pulledRows: totalPulled,
          // ✅ سقف الصفحات (H2) = نهاية دورة لا نهاية بيانات: remaining
          // مجهول لا صفر — المؤشر يبقى غير-محدد بصدق.
          remainingRows: (hadError || hitPageCap) ? null : 0,
          pages: pagesDone,
          isFullSync: wasFullSync,
          isDone: true,
          errorMessage: hadError ? errorMessage : null,
        ),
      );
    }

    // P0-C: only advance checkpoint in prefs on full success
    final prefs = await SharedPreferences.getInstance();
    if (!hadError) {
      // ✅ (2026-09-17) حارس التثبيت النهائي (طبقة دفاع ثالثة): حارس
      // التشغيل أعلاه يحتاج server_time للحكم الديناميكي — worker قديم
      // بلا الحقل كان سيمرر السم. هنا حد ثابت صرف (مرآة عتبة الخادم
      // 2e9): pendingCursor فوقه لا يُخزَّن أبداً بل يُصفَّر مع علامة
      // full sync ليبدأ الجهاز سحباً كاملاً نظيفاً في الدورة القادمة.
      if (pendingCursor > maxSanePullCursorFuture) {
        logError(
          title: 'منع تثبيت مؤشر مسموم في نهاية الدورة ($pendingCursor)',
          message:
              'المؤشر المرشح للتثبيت تجاوز الحد الثابت الآمن '
              '$maxSanePullCursorFuture (سنة 2033) رغم نجاح الدورة الظاهري — '
              'طوابع sentinel/ميلي من worker غير مُصلح. صُفّر المؤشر وعلامة '
              'full sync لتعاد المزامنة الكاملة نظيفة بعد شفاء الخادم.',
          category: ErrorCategory.sync,
          source: 'sync:pull',
        );
        _lastPullCursor = 0;
        _fullSyncCompleted = false;
        await prefs.setInt('cf_last_pull_cursor', 0);
        await prefs.remove(_kFullSyncCompletedKey);
        debugPrint(
          '🚨 install guard: poisoned pendingCursor $pendingCursor rejected '
          '— cursor reset to 0, full sync flag cleared',
        );
      } else {
        _lastPullCursor = pendingCursor;
        await prefs.setInt('cf_last_pull_cursor', _lastPullCursor);

        // P0-B: mark full sync as completed only on full success
        // ✅ سقف الصفحات (H2) ليس نفاداً — علامة full-sync تبقى false
        // والدورة القادمة تُكمل من المؤشر المتقدم.
        if (wasFullSync && !hitPageCap) {
          _fullSyncCompleted = true;
          await prefs.setBool(_kFullSyncCompletedKey, true);
          debugPrint('✅ Full sync completed - device is now delta-ready');
        }

        debugPrint(
          '📥 Pulled $totalPulled changes (cursor: $initialCursor -> $_lastPullCursor)',
        );
      }
    } else {
      // ✅ (2026-09-08) محور 2 — سياسة «لا نجاح مع جداول ناقصة»:
      // لا يتحرك checkpoint إطلاقاً عند أي خطأ (شبكة/HTTP/JSON أو
      // جداول خادمية متخطّاة): صفوف الجدول المتخطى بين المؤشرين لم
      // تُرسَل أصلاً، والتراجع الكامل يضمن أن الدورة التالية تعيد سحب
      // كل ما بين الحدين (idempotent عبر local_uuid) ولا شيء يُفقد.
      _lastPullCursor = initialCursor;
      _failedCollectionsInLastSync.add('pull');
      debugPrint(
        '⚠️ Pull failed - checkpoint NOT advanced (stayed at $initialCursor). Error: $errorMessage',
      );
      throw Exception('Pull failed: $errorMessage');
    }

    // ✅ بناء مشتق بعد السحب (2026-09-05): الليالي (booking_nights)
    // والإجماليات المخزنة صفوف مشتقة تُعاد الحسبة محلياً على كل جهاز
    // (bookings_adapter.dart:183-186) — سحب تغييرات bookings/payments/
    // adjustments دون إعادة بناء يترك الجهاز الآخر بأرقام قديمة.
    // enqueueOutbox:false — مشتق لا يُرفع، وإلا حلقة لا نهائية.
    // ✅ (2026-09-08) يُنفّذ الآن في الدورة السليمة والمتدهورة معاً —
    // الصفوف السليمة المطبقة في دورة متدهورة تحتاج إعادة بناء أيضاً.
    if (pulledDerivedEntities.isNotEmpty && totalPulled > 0) {
      await _refreshDerivedAfterPull();
    }

    return totalPulled;
  }

  // ─── أدوات الفلترة وترجمة الهوية (2026-09-09) ──────────────

  /// جلب صفحة واحدة من السحب — مستخرجة لتسمح بالتداخل (prefetch):
  /// الصفحة التالية تنطلق قبل تطبيق الحالية (تسريع السحب الكامل).
  ///
  /// ✅ (2026-09-09) إصلاح «107 سجلاً بعلاقات أب غير محلولة»:
  /// استبعاد صفوف الجهاز نفسه (echo filter خطة 2.5) كان يمنع الجهاز
  /// أبداً من تعلّم ظلّ server_id لصفوفه هو (مثلاً: موظف أنشأه محلياً
  /// ورفعه — الـ D1 عيّن له id لا يعرفه الجهاز لأن السحب يستبقه).
  /// سحبات رواتب/دورات هذا الجهاز المسحوبة لاحقاً تحمل employee_id
  /// بفضاء D1 — تبحث عن employees.server_id ولا تجده → تأجيل →
  /// تجميد المؤشر. الآن: السحب الكامل يشمل صفوف الجهاز (تُطبَّق
  /// idempotent عبر local_uuid مع LWW) فيُبنى الظلّ لكل الأباء —
  /// والدلتا تستمر باستبعاد الصدى حفاظاً على خفة النافذة.
  Future<http.Response> _fetchPullPage(
    int cursor,
    int limit, {
    required bool excludeOwnDevice,
    bool includeRemaining = false,
    bool includeNormalization = false,
  }) {
    return _httpClient
        .get(
          Uri.parse('${CloudflareConfig.workerUrl}/api/sync/pull').replace(
            queryParameters: {
              'cursor': cursor.toString(),
              'limit': limit.toString(),
              // ✅ خطة 2.5: لا تُعد إلينا سجلات دفعناها نحن (echo) —
              // الخادم يستثني device_id الخاص بنا من نتيجة السحب.
              // السحب الكامل وحده يستثني هذا الفلتر (تعليق الدالة).
              if (excludeOwnDevice)
                if (_deviceId case final ownDevice? when ownDevice.isNotEmpty)
                  'exclude_device': ownDevice,
              // ✅ (2026-09-10) السحب الكامل فقط: COUNT خادمي للمتبقي
              // (مؤشر التقدم الدقيق) — الدلتا بلا كلفة إضافية.
              if (includeRemaining) 'include_remaining': '1',
              if (includeNormalization) 'normalize_timestamps': '1',
            },
          ),
          headers: {'Authorization': 'Bearer $_token'},
        )
        // ✅ (2026-09-17) 60 ثانية بدل 30: العميل المرِن قد ينفق 6 ثوانٍ
        // في المسار السريع ثم حتى 30 ثانية في نفق CONNECT الاحتياطي
        // (36 ثانية إجمالاً) — المهلة الخارجية 30 كانت تُجهض مسار
        // الاحتياط قبل اكتماله بـ TimeoutException «Future not completed»
        // على الشبكات المتدهورة (تقرير الإنتاج 2026-09-16 05:43). الصفحة
        // 200 صف × 22 جدولاً + تطبيع الصفحة الأولى تستحق الرحلة الكاملة.
        .timeout(const Duration(seconds: 60));
  }

  /// أعمدة الجدول المحلي (PRAGMA table_info) مع كاش — أساس الفلترة
  /// ضد انحراف المخطط بين الخادم والعميل.
  Future<Set<String>> _localColumns(String tableName) async {
    final cached = _localColumnsCache[tableName];
    if (cached != null) return cached;
    final rows = await _db!.customSelect('PRAGMA table_info($tableName)').get();
    final cols = <String>{
      for (final row in rows)
        if (row.data['name'] != null) row.data['name'].toString(),
    };
    _localColumnsCache[tableName] = cols;
    return cols;
  }

  /// يسقط من الصف الوارد كل عمود لا يوجد في الجدول المحلي.
  ///
  /// الجذر (أ) لـ «لم يتم سحب كل البيانات»: بقايا مخطط D1 القديم
  /// (sync_timestamp وأشباهها) كانت تُفشل INSERT بكامل الصف بـ
  /// «no such column» صمتاً بينما المؤشر يتقدم. الآن: العمود الغريب
  /// يُسقَط بسجل (مرة لكل تركيبة جدول/أعمدة) والصف يُطبَّق.
  Future<Map<String, dynamic>> _filterToLocalColumns(
    String tableName,
    Map<String, dynamic> record,
  ) async {
    final cols = await _localColumns(tableName);
    if (cols.isEmpty) return Map<String, dynamic>.of(record);
    final out = <String, dynamic>{};
    final dropped = <String>[];
    record.forEach((key, value) {
      if (cols.contains(key)) {
        out[key] = value;
      } else {
        dropped.add(key);
      }
    });
    if (dropped.isNotEmpty) {
      _logFkOnce(
        'dropped unknown column(s) for $tableName: ${dropped.join(', ')}',
      );
    }
    return out;
  }

  /// يبحث عن id الأب المحلي بعمود ومفتاح — null إن لم يوجد.
  Future<Object?> _lookupLocalParentId(
    String parentTable,
    String keyColumn,
    Object? keyValue,
  ) async {
    final cacheKey = '$parentTable|$keyColumn|$keyValue';
    final cached = _fkParentIdCache[cacheKey];
    if (cached != null) return cached;
    try {
      final row = await _db!
          .customSelect(
            'SELECT id FROM $parentTable WHERE $keyColumn = ? LIMIT 1',
            variables: [Variable(keyValue)],
          )
          .getSingleOrNull();
      final id = row?.data['id'] as Object?;
      // نتيجة موجبة فقط تُحفظ — راجع تعليق [_fkParentIdCache] أعلاه.
      if (id != null) {
        _fkParentIdCache[cacheKey] = id;
      }
      return id;
    } catch (e) {
      _logFkOnce('parent lookup failed $parentTable.$keyColumn: $e');
      return null;
    }
  }

  /// هل يوجد صف في [parentTable] بمفتاح طبيعي معطى؟
  Future<bool> _parentKeyExists(
    String parentTable,
    String keyColumn,
    Object? keyValue,
  ) async {
    try {
      final row = await _db!
          .customSelect(
            'SELECT 1 AS hit FROM $parentTable WHERE $keyColumn = ? LIMIT 1',
            variables: [Variable(keyValue)],
          )
          .getSingleOrNull();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  void _logFkOnce(String message) {
    if (_fkLogSeen.add(message)) {
      debugPrint('🔗 Pull/FK: $message');
    }
  }

  /// يترجم مؤشرات FK الخادمية في [record] (المُفلتر) إلى الهوية المحلية
  /// — قبل أي مسار كتابة (إدراج/تحديث/دمج تعارض).
  ///
  /// ترتيب الحل لكل قاعدة:
  ///  1. uuid-cache على الابن (المفتاح العالمي بين الأجهزة).
  ///  2. ظلّ server_id على الأب = id الخادم D1 (سُجِّل عند تطبيق الأب).
  ///  3. فضاء Appwrite القديم: server_booking_id على الابن ضد الأب.
  ///  4. صف موجود محلياً — تحديث لاحق: احتفظ بقيمته المحلية الحالية.
  ///  5. مؤشر ثانوي (nullWhenUnresolvable) → NULL بدل تعطيل السحب.
  ///  غير ذلك → false: الصف يُؤجَّل لإعادة المحاولة بعد اكتمال السحب
  ///  (الأب قد يصل في صفحة لاحقة)، وما بقي بعد المحاولات = دورة فاشلة.
  Future<bool> _resolveForeignKeysForRecord({
    required String entity,
    required Map<String, dynamic> record,
    required Map<String, dynamic>? existing,
  }) async {
    final rules = _fkRulesByEntity[entity];
    if (rules == null || rules.isEmpty) return true;

    for (final rule in rules) {
      final wireValue = record[rule.column];

      if (rule.kind == _FkKind.numericPointer) {
        if (wireValue == null) {
          if (record.containsKey(rule.column) && !rule.nullable) {
            // null صريح على عمود NOT NULL — علاقة مفقودة خادمياً.
            if (existing != null) {
              record[rule.column] = existing[rule.column];
              continue;
            }
            return false;
          }
          continue; // غائب عن السلك أو قابل للـ null — لا مؤشر
        }

        final serverValue = wireValue is int
            ? wireValue
            : int.tryParse(wireValue.toString());
        Object? resolved;
        if (serverValue != null) {
          // 1) uuid-cache: المفتاح العالمي.
          final cacheKey = rule.uuidCacheColumn == null
              ? null
              : record[rule.uuidCacheColumn]?.toString();
          if (cacheKey != null && cacheKey.isNotEmpty) {
            resolved = await _lookupLocalParentId(
              rule.parentTable,
              'local_uuid',
              cacheKey,
            );
          }
          // 2) ظلّ server_id للأب.
          resolved ??= await _lookupLocalParentId(
            rule.parentTable,
            'server_id',
            serverValue,
          );
          // 3) فضاء Appwrite القديم.
          if (resolved == null && rule.legacyServerBookingId) {
            final legacy = record['server_booking_id'];
            final legacyInt = legacy is int
                ? legacy
                : int.tryParse(legacy?.toString() ?? '');
            if (legacyInt != null) {
              resolved = await _lookupLocalParentId(
                rule.parentTable,
                'server_booking_id',
                legacyInt,
              );
            }
          }
        }

        if (resolved != null) {
          record[rule.column] = resolved;
          continue;
        }
        // 4) صف موجود محلياً — لا تفسد علاقة مثبتة سابقاً.
        if (existing != null) {
          record[rule.column] = existing[rule.column];
          continue;
        }
        // 5) مؤشر ثانوي غير جوهري — NULL ولا يُعطَّل السحب.
        if (rule.nullWhenUnresolvable && rule.nullable) {
          record[rule.column] = null;
          _logFkOnce(
            'null-substituted $entity.${rule.column} '
            '(wire=$wireValue, no resolvable parent)',
          );
          continue;
        }
        return false; // صف جديد بلا أب — يُؤجَّل
      } else {
        // naturalKey: القيمة نفسها عالمية — المطلوب وجود الأب فقط.
        if (wireValue == null || wireValue.toString().isEmpty) continue;
        final exists = await _parentKeyExists(
          rule.parentTable,
          rule.parentKeyColumn,
          wireValue,
        );
        if (exists) continue;
        if (existing != null) {
          record[rule.column] = existing[rule.column];
          continue;
        }
        return false; // الأب غير موجود بعد — يُؤجَّل
      }
    }
    return true;
  }

  // ─── Apply change to local Drift DB ─────────────────────────
  ///
  /// ✅ P0-F: إذا كان السجل البعيد أحدث ويسبب تعارضاً مع تعديل محلي معلّق
  /// (لم يُرفع بعد في outbox)، نُطبّق SmartConflictResolver ونكتب النتيجة
  /// المدمجة محلياً + نُعيدها لـ outbox ليتم رفعها للخادم (end-to-end).
  /// قبل هذا الإصلاح، كان السجل المحلي الأحدث يُحتفظ به فقط دون إعادة رفع،
  /// مما يسبب "stale divergence" — الخادم لا يعرف بالقيمة المحلية النهائية.
  ///
  /// ✅ (2026-09-09) العقد الجديد: true = طُبّق (أو سُكت عنه بعذر)،
  /// false = مؤجَّل (علاقة FK بلا أب بعد — يعاد بعد اكتمال السحب)،
  /// ويرمي استثناءً على أخطاء قاعدة البيانات الحقيقية — لا تُبتلع صمتاً.
  Future<bool> _applyChange(String entity, Map<String, dynamic> record) async {
    if (_db == null) return true;

    if (record.isEmpty) return true;

    // ✅ إصلاح «الحذف لا يصل إلى الأجهزة الأخرى» (مراجعة 2026-09-09 #1):
    // العقد المصحح — tombstone يصل في الدلتا من Worker المصلح ويُطبَّق
    // كحذف ناعم محلي. الحارس القديم كان يتجاهله فلا يتعلم الجهاز حذف
    // جهاز آخر أبداً (تناقض مع عقد deleteRecord الخادمي).
    if (record['deleted_at'] != null) {
      return _applyTombstone(entity, record);
    }

    // ✅ عقد القائمة السوداء (2026-09-05): صفوف blacklist بلا جدول Drift
    // محلي — تخزينها في shift_notes الموسومة created_by='blacklist'
    // (blacklist_repository.dart:92). قبل هذا التحويل كان سحب صفوف
    // blacklist من D1 يفشل صمتاً (no such table: blacklist) ولا تصل
    // القائمة السوداء للأجهزة الأخرى أبداً.
    if (entity == 'blacklist') {
      final converted = CloudflareD1Service.blacklistShiftNoteRowFromD1(record);
      if (converted == null) return true;
      entity = 'shift_notes';
      record = converted;
    }

    final tableName = CloudflareConfig.tableNameFor(entity);
    if (tableName == null) {
      debugPrint('⚠️ Pull: no local table for entity "$entity" — skipped');
      return true;
    }

    final localUuid = record['local_uuid'] as String?;
    if (localUuid == null) return true;

    final remoteUpdatedAt = record['updated_at'] as int? ?? 0;

    // ✅ (2026-09-09) الجذر (أ): فلترة الأعمدة ضد المخطط المحلي — أي
    // عمود خادمي غريب (sync_timestamp من مخطط D1 القديم وأشباهه)
    // يُسقَط بسجل بدل أن يُسقط الصف كله بـ «no such column» صمتاً.
    final filtered = await _filterToLocalColumns(tableName, record);

    // ✅ (2026-09-09) الجذر (ب) خطوة 1 — ظلّ هوية الخادم: id الصف على
    // D1 يُخزَّن في عمود server_id المحلي (موجود في كل جداول SyncFields)
    // فيصير سجلَّ ترجمة دائماً «D1 id → صف محلي» تعتمده الأبناء.
    final wireId = filtered['id'];
    if (wireId is int &&
        (await _localColumns(tableName)).contains('server_id')) {
      filtered['server_id'] = wireId;
    }

    // اقرأ السجل المحلي كاملاً (للـ conflict resolution)
    final existing = await _db!
        .customSelect(
          'SELECT * FROM $tableName WHERE local_uuid = ?',
          variables: [Variable<String>(localUuid)],
        )
        .getSingleOrNull();
    final existingData = existing == null
        ? null
        : Map<String, dynamic>.from(existing.data);

    // ✅ (2026-09-09) الجذر (ب) خطوة 2 — ترجمة مؤشرات FK الخادمية إلى
    // الهوية المحلية قبل أي مسار كتابة. false = صف جديد بلا أب بعد.
    final relationsResolved = await _resolveForeignKeysForRecord(
      entity: entity,
      record: filtered,
      existing: existingData,
    );
    if (!relationsResolved) {
      // ✅ (مراجعة #2+#16) سجل معزول سابقاً وما زال أبُه مفقوداً —
      // يُتخطى (لا يُؤجَّل ولا يُفشل الدورة): الحجر سبق أن منحه
      // فرصته العادلة، وبقية البيانات يجب ألا تُرهق بسببه.
      if (_isQuarantined(entity, localUuid)) {
        debugPrint(
          '⏭️ Pull: quarantined $entity/$localUuid still unresolvable — '
          'skipped (parent still missing server-side)',
        );
        return true;
      }
      debugPrint(
        '⏸️ Pull: deferred $entity/$localUuid — parent not pulled yet',
      );
      return false;
    }

    if (existing != null) {
      final localData = Map<String, dynamic>.from(existing.data);
      final localUpdatedAt = localData['updated_at'] as int? ?? 0;
      final localId = localData['id'];

      // ✅ معالجة الحذف الناعم (soft delete) - البعيد يقول "محذوف"
      final deletedAt = record['deleted_at'];
      if (deletedAt != null) {
        // ✅ P0-E: حتى لو كان المحلي أحدث، نطبّق الـ tombstone لأنه قرار نهائي
        // من جهاز آخر. التعديل المعلّق في outbox يبقى فيه حتى الرفع، لكن
        // حسمه صار حتمياً بعقد delete-vs-update (F1 2026-09-22): الخادم
        // يرفض التعديل على صف محذوف بـ opStatus:'deleted' فيُحذف من
        // outbox ويُختم محلياً بوعي (انظر _tombstoneLocalRowAfterLostEdit)
        // — لا قبول صامت يحدّث tombstone ثم يمحو نسخة الجهاز بلا أثر.
        await _db!.customStatement(
          'UPDATE $tableName SET deleted_at = ?, updated_at = ?, last_modified = ? WHERE id = ?',
          [deletedAt, remoteUpdatedAt, remoteUpdatedAt, localId],
        );
        debugPrint('  🗑️ $entity/$localUuid: soft delete applied');

        // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'delete',
          ),
        );
        return true;
      }

      // ✅ تخطي إذا كان السجل المحلي أحدث (LWW الأساسي)
      if (localUpdatedAt > remoteUpdatedAt) {
        // ✅ (fix M3) حارس انزياح الساعة: الطابع المحلي الأحدث لا يعني أن
        // المحتوى أحدث — ساعة الجهاز قد تكون متقدمة. الخادم يزيد version
        // عند كل كتابة، فإن كان الوارد من نسخة أعلى فهذا دليل مستقل عن
        // الساعات على أنه الأحدث ونمضي به إلى مسار التطبيق/الدمج أدناه.
        // بدون هذا: الجهاز متباعد الساعة يُسقط كل الوارد دائماً بينما
        // المؤشر يتقدم فوقه فيلا لن يعود الصف في أي دلتا قادمة (فقد دائم).
        final localVersion = localData['version'] as int? ?? 0;
        final remoteVersion = record['version'] as int? ?? 0;
        if (remoteVersion <= localVersion) {
          // ✅ P0-F: تحقق هل يوجد تعديل محلي معلّق في outbox.
          // إذا كان موجود، فنحن في حالة "تعارض" - السجل المحلي أحدث لكنه لم
          // يُرفع بعد. السجل البعيد أقدم لكنه على الخادم. هذا تعارض محتمل
          // لكن LWW هنا يعطي الأولوية للمحلي. سنرفع المحلي في الـ sync القادمة.
          debugPrint(
            '  ⏭️ $entity/$localUuid: محلي أحدث ($localUpdatedAt > $remoteUpdatedAt, v$localVersion >= v$remoteVersion) — تخطي',
          );
          return true;
        }
        debugPrint(
          '  ↩️ $entity/$localUuid: طابع محلي أحدث لكن version الوارد أعلى '
          '(v$remoteVersion > v$localVersion) — احتمال انزياح ساعة: تطبيق الوارد',
        );
      }

      // ✅ P0-F: السجل البعيد أحدث. طبّق SmartConflictResolver للتحقق
      // هل هو تعارض حقيقي (concurrent) أم مجرد تحديث تسلسلي؟
      // إذا كان تعارضاً حقيقياً ونتيجته مدمجة، نرفعها للخادم عبر outbox.
      final localVcStr = (localData['vector_clock'] as String?) ?? '{}';
      final remoteVcStr = (record['vector_clock'] as String?) ?? '{}';
      final localVc = VectorClock.fromString(localVcStr);
      final remoteVc = VectorClock.fromString(remoteVcStr);

      // إذا كانت الـ vector clocks متزامنة (concurrent)، فهذا تعارض حقيقي
      // نستخدم SmartConflictResolver لحله على مستوى الحقول.
      if (localVc.isNotEmpty &&
          remoteVc.isNotEmpty &&
          localVc.isConcurrent(remoteVc)) {
        final resolution = SmartConflictResolver.resolve(
          entity: entity,
          localData: localData,
          remoteData: filtered,
          commonAncestor: null, // لا نحتفظ بـ ancestor حالياً
        );

        // اكتب النتيجة المدمجة محلياً
        final mergedData = resolution.mergedData;
        final cleanRecord = Map<String, dynamic>.from(mergedData);
        cleanRecord.remove('id');
        // ✅ (2026-09-17) حارس عقد الأعمدة: مخرجات المحلّل تُكتب في UPDATE
        // خام مباشرة — أي مفتاح ليس عموداً فيزيائياً في الجدول المحلي
        // (بقايا camelCase أو حقول مستقبلية غريبة) يُسقَط هنا بدل أن
        // يُسقط الصف كله بـ SqliteException «no such column» (مرآة جذر
        // (أ) على مسار الدمج — عطل app_users/user_1 الإنتاجي).
        final safeRecord = await _filterToLocalColumns(tableName, cleanRecord);
        if (safeRecord.isEmpty) {
          debugPrint(
            '  ⏭️ $entity/$localUuid: merged record has no local columns '
            '— skipped',
          );
          return true;
        }
        final setClauses = safeRecord.keys.map((c) => '$c = ?').join(', ');
        final values = safeRecord.values.map(_toDriftValue).toList();
        await _db!.customStatement(
          'UPDATE $tableName SET $setClauses WHERE id = ?',
          [...values, localId],
        );

        // ✅ P0-F: إذا كانت النتيجة تحتاج رفع للخادم (pushedToRemote=true)،
        // اكتبها في outbox ليتم رفعها في الـ sync القادمة.
        if (resolution.pushedToRemote) {
          try {
            final outboxDao = OutboxDao(_db!);
            await outboxDao.merge(
              entity: entity,
              op: 'update',
              localUuid: localUuid,
              payload: mergedData,
              clientTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
            debugPrint(
              '  🤝 $entity/$localUuid: conflict resolved + queued for re-upload',
            );
          } catch (e) {
            debugPrint('  ⚠️ Failed to queue merged conflict result: $e');
          }
        }

        // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح (merged conflict)
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'update',
          ),
        );
        return true;
      }

      // ✅ لا يوجد تعارض متزامن — البعيد أحدث تسلسلياً، اطبّقه مباشرة
      final cleanRecord = Map<String, dynamic>.from(filtered);
      cleanRecord.remove('id');
      final setClauses = cleanRecord.keys.map((c) => '$c = ?').join(', ');
      final values = cleanRecord.values.map(_toDriftValue).toList();
      await _db!.customStatement(
        'UPDATE $tableName SET $setClauses WHERE id = ?',
        [...values, localId],
      );

      // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح (sequential update)
      unawaited(
        RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: entity,
          record: record,
          op: 'update',
        ),
      );
    } else {
      // ✅ سجل جديد — أدخله
      // ✅ (2026-09-09) إصلاح تجميد السحب (398 ليلة): نسخة خادمية مكررة
      // منطقياً (local_uuid جديد على مفتاح طبيعي موجود محلياً) لا تُدرج —
      // تُدمج بـ LWW في الصف المحلي الموجود. كان INSERT يرمي
      // SqliteException(2067) فيُفشل كل دورة سحب بلا شفاء (المراجعة
      // كانت تُثبّت «لا OR IGNORE» — وهذا مختلف: تعارض هوية محتوى
      // مكرر وليس فقدان بيانات، والصف المحلي واحد يبقى ضماناً).
      final dedupHandled = await _dedupNaturalKeyOnInsert(
        entity: entity,
        tableName: tableName,
        filtered: filtered,
        remoteUpdatedAt: remoteUpdatedAt,
      );
      if (dedupHandled) return true;

      // ✅ (2026-09-09) INSERT صريح بلا OR IGNORE: تجاهل القيود صمتاً
      // كان يعني صفوفاً تضيع بلا أثر. أعمدة الصف مُفلترة وعلاقاته
      // مُترجمة أعلاه — أي فشل هنا حقيقي ويُفشل الدورة بدل كتمه.
      final cleanRecord = Map<String, dynamic>.from(filtered);
      cleanRecord.remove('id');

      final columns = cleanRecord.keys.join(', ');
      final placeholders = cleanRecord.keys.map((_) => '?').join(', ');
      final values = cleanRecord.values.map(_toDriftValue).toList();
      await _db!.customStatement(
        'INSERT INTO $tableName ($columns) VALUES ($placeholders)',
        values,
      );

      // ✅ RemoteChangeNotifier: إشعار بعد apply ناجح
      // (نتحقق من التأثير الفعلي عبر SELECT — INSERT OR IGNORE قد تجاهله)
      final inserted = await _db!
          .customSelect(
            'SELECT 1 FROM $tableName WHERE local_uuid = ? AND updated_at = ?',
            variables: [
              Variable<String>(localUuid),
              Variable<int>(remoteUpdatedAt),
            ],
          )
          .getSingleOrNull();
      if (inserted != null) {
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'create',
          ),
        );
      }
    }

    // ✅ (مراجعة #2+#16) تطبيق ناجح لسجل كان معزولاً — يُمسح من الحجر
    // (بلا كتابة prefs إلا فعلاً كان في الحجر).
    await _clearQuarantine(entity, localUuid);

    return true;
  }

  /// ✅ (2026-09-09) مسبار المفتاح الطبيعي قبل INSERT — إصلاح تجميد
  /// السحب (398 ليلة + 381 مجموعة مكررة مؤكدة على D1).
  ///
  /// صف وارد بـ local_uuid جديد لكن مفتاحه الطبيعي ([_naturalUniqueKeys])
  /// موجود محلياً = نسخة مكررة منطقياً لنفس الصف (سطر restore نسخة
  /// احتياطية، أو نسخة خادمية مقابل إعادة بناء محلية origin='auto_fix').
  /// العقد:
  ///  • الوارد أحدث (updated_at) → بياناته تُدمج في الصف المحلي الموجود
  ///    (هويته id/local_uuid/server_id تبقى — الظل يخص نسخته الأصلية).
  ///  • الوارد أقدم أو يساوي → يُتخطى (المحلي الأحدث يفوز).
  ///  • لا صف محلي بالمفتاح → false: يُكمل إلى INSERT الطبيعي.
  ///
  /// يعيد true إذا عولج الصف كنسخة مكررة (تطبيق/تخطٍّ بعذر) — لا INSERT.
  Future<bool> _dedupNaturalKeyOnInsert({
    required String entity,
    required String tableName,
    required Map<String, dynamic> filtered,
    required int remoteUpdatedAt,
  }) async {
    final keys = _naturalUniqueKeys[entity];
    if (keys == null || keys.isEmpty) return false;

    final keyValues = <Object?>[];
    for (final key in keys) {
      final value = filtered[key];
      if (value == null || value.toString().isEmpty) {
        // مفتاح طبيعي ناقص على السلك — لا مسبار (سيكمل INSERT العادي
        // وسيُحارَب فشله بالمسار الاعتيادي).
        return false;
      }
      keyValues.add(value);
    }

    final whereClause = keys.map((k) => '$k = ?').join(' AND ');
    final existingRow = await _db!
        .customSelect(
          'SELECT id, updated_at FROM $tableName WHERE $whereClause LIMIT 1',
          variables: [for (final v in keyValues) Variable(v)],
        )
        .getSingleOrNull();
    if (existingRow == null) return false;

    final localId = existingRow.data['id'];
    final localUpdatedAt =
        (existingRow.data['updated_at'] as num?)?.toInt() ?? 0;

    if (remoteUpdatedAt > localUpdatedAt) {
      // LWW: الوارد أحدث — بياناته تُدمج في الصف المحلي. أعمدة الهوية
      // (id/local_uuid/server_id) لا تُمسّ: الهوية المحلية هي المرجع،
      // والظلّ يخص نسخة الصف الأصلية على الخادم.
      final data = Map<String, dynamic>.of(filtered)
        ..remove('id')
        ..remove('local_uuid')
        ..remove('server_id');
      if (data.isNotEmpty) {
        final setClauses = data.keys.map((c) => '$c = ?').join(', ');
        await _db!.customStatement(
          'UPDATE $tableName SET $setClauses WHERE id = ?',
          [...data.values.map(_toDriftValue), localId],
        );
      }
      debugPrint(
        '  ♻️ $entity: نسخة مكررة منطقياً دُمجت LWW في الصف المحلي '
        '#$localId (wire updated_at=$remoteUpdatedAt > local=$localUpdatedAt)',
      );
    } else {
      debugPrint(
        '  ⏭️ $entity: نسخة مكررة منطقياً أقدم من المحلي — تخطٍّ '
        '(wire updated_at=$remoteUpdatedAt <= local=$localUpdatedAt)',
      );
    }
    // ✅ إشعار المستمعين — بيانات الليلة قد تغيّرت بالدمج.
    unawaited(
      RemoteChangeNotifier.instance.onRemoteChangeApplied(
        entity: entity,
        record: filtered,
        op: 'update',
      ),
    );
    return true;
  }

  /// يطبّق دفعة صفوف مسحوبة مع إعادة محاولة المؤجّل بترتيب الآباء.
  ///
  /// تُمرّ الصفوف بثلاث محاولات كحد أقصى: الأولى بترتيب الوصول، وما دُوّن
  /// تأجيله يعاد بترتيب أولوية الآباء (غرفة → حجز → ليلة…) حتى تكتمل
  /// السلسلة (موظف → دورة → دفعة). من لم تُحلّ علاقته بعد المحاولات
  /// يعود في التقرير (unresolvable) وتُفسد الدورة — سياسة «لا نجاح
  /// مع جداول ناقصة» على طرف العميل أيضاً.
  ///
  /// ✅ (2026-09-09) الصفوف التي ترمي تعارض قيد فريد حتمي (UNIQUE) لا
  /// تُفشل الدورة مباشرة بعد اليوم — تُجمَع في conflictedSink وتذهب
  /// إلى سلّم الحجر الصحي في المستدعي (فرصة عادلة ثم عزل) بدل تجميد
  /// المؤشر إلى الأبد (السلوك الذي جمّد 398 ليلة).
  @visibleForTesting
  Future<PullApplyReport> applyPulledRecords(
    List<({String entity, Map<String, dynamic> record})> records,
  ) => _applyPulledRecords(records);

  Future<PullApplyReport> _applyPulledRecords(
    List<({String entity, Map<String, dynamic> record})> records, {
    List<({String entity, Map<String, dynamic> record})>? deferredSink,
    List<({String entity, Map<String, dynamic> record})>? conflictedSink,
  }) async {
    var applied = 0;
    final touched = <String>{};
    final errors = <String>[];
    var pending = List.of(records);

    for (var pass = 0; pass < 3 && pending.isNotEmpty; pass++) {
      // رتّب كل محاولة، بما فيها الأولى، حتى لا يعتمد نجاح السحب على
      // ترتيب updated_at العابر الذي يعيده الخادم. هذا يضمن وصول الآباء
      // (rooms/employees/bookings) قبل الأبناء (nights/payments/salary_*),
      // ويقلل دورات التأجيل وإعادة المحاولة في السحب الأولي.
      pending.sort(
        (a, b) => (_pullApplyPriority[a.entity] ?? 9).compareTo(
          _pullApplyPriority[b.entity] ?? 9,
        ),
      );
      final stillPending = <({String entity, Map<String, dynamic> record})>[];
      for (final item in pending) {
        try {
          final ok = await _applyChange(item.entity, item.record);
          if (ok) {
            applied++;
            touched.add(item.entity);
          } else {
            stillPending.add(item);
          }
        } catch (e) {
          // ✅ (2026-09-09) تعارض قيد فريد حتمي → سلّم الحجر في المستدعي
          // بدل فشل الدورة إلى الأبد.
          if (conflictedSink != null && _isUniqueConstraintError(e)) {
            conflictedSink.add(item);
          } else {
            // فشل تطبيق حقيقي — يظهر في التقرير ويُفسد الدورة (لا كتم).
            errors.add('${item.entity}/${item.record['local_uuid']}: $e');
          }
        }
      }
      final progressed = stillPending.length < pending.length;
      pending = stillPending;
      if (!progressed) break;
    }

    // ✅ المؤجّل عبر الصفحات: داخل حلقة السحب يُجمَع في sink واحد
    // ويُعاد حلّه بعد اكتمال كل الصفحات (الأب قد يكون في صفحة لاحقة)،
    // فلا يُفشل الصفُّ النظيف دورتَه لمجرد أن أباه لم يصل بعد.
    var unresolvableCount = 0;
    if (deferredSink != null) {
      deferredSink.addAll(pending);
      unresolvableCount = 0;
    } else {
      unresolvableCount = pending.length;
      if (pending.isNotEmpty) {
        final names = [
          for (final item in pending.take(5))
            '${item.entity}/${item.record['local_uuid']}',
        ];
        debugPrint(
          '⏸️ Pull: ${pending.length} record(s) deferred-unresolved: '
          '${names.join(', ')}',
        );
      }
    }

    return PullApplyReport(
      appliedCount: applied,
      deferredCount: unresolvableCount,
      touchedEntities: touched,
      unresolvable: [
        for (final item in pending.take(
          deferredSink == null ? pending.length : 0,
        ))
          '${item.entity}/${item.record['local_uuid']}',
      ],
      errors: errors,
    );
  }

  /// إعادة محاولة الصفوف المؤجلة عبر الصفحات — بعد اكتمال pagination.
  /// يُعاد بترتيب أولوية الآباء حتى محاولتين إضافيتين، ويعيد ما بقي
  /// غير محلول (يُفسد الدورة عند النهاية: تجميد المؤشر بلا full sync).
  ///
  /// ✅ (2026-09-09) الصفوف التي ترمي تعارض قيد فريد (UNIQUE) تُجمَع
  /// في [conflictedSink] وتذهب لسلّم الحجر الصحي — لم تعد ترمي الدورة
  /// إلى تجميد أبدي (كان سبب تجميد 398 ليلة: تُحلّ علاقتها في إعادة
  /// المحاولة ثم يصطدم INSERT بالمفتاح الفريد فيرمي استثناءً).
  Future<List<({String entity, Map<String, dynamic> record})>>
  _retryDeferredRecords(
    List<({String entity, Map<String, dynamic> record})> deferred, {
    required void Function(String entity) onApplied,
    required List<String> errors,
    List<({String entity, Map<String, dynamic> record})>? conflictedSink,
    List<({String entity, Map<String, dynamic> record})>? erroredSink,
  }) async {
    var remaining = List.of(deferred);
    for (var pass = 0; pass < 2 && remaining.isNotEmpty; pass++) {
      remaining.sort(
        (a, b) => (_pullApplyPriority[a.entity] ?? 9).compareTo(
          _pullApplyPriority[b.entity] ?? 9,
        ),
      );
      final stillPending = <({String entity, Map<String, dynamic> record})>[];
      for (final item in remaining) {
        try {
          final ok = await _applyChange(item.entity, item.record);
          if (ok) {
            onApplied(item.entity);
          } else {
            stillPending.add(item);
          }
        } catch (e) {
          if (conflictedSink != null && _isUniqueConstraintError(e)) {
            conflictedSink.add(item);
          } else {
            errors.add('${item.entity}/${item.record['local_uuid']}: $e');
            // ✅ (2026-09-15) الصف الفاشل فعلياً يصل للمستدعي عبر
            // [erroredSink] ليدخل محاسبة سجل الانتظار بدل التسرب
            // الصامت من القوائم (فشل ≠ مؤجل ≠ متعارض).
            erroredSink?.add(item);
          }
        }
      }
      final progressed = stillPending.length < remaining.length;
      remaining = stillPending;
      if (!progressed) break;
    }
    return remaining;
  }

  /// ✅ (2026-09-09) كشف تعارض القيد الفريد (SqliteException 2067 —
  /// SQLITE_CONSTRAINT_UNIQUE وأخواتها). مطابقة نصية على رسالة SQLite
  /// القياسية لأن حزمة sqlite3 تلف الاستثناء بمشتقات متعددة عبر drift.
  bool _isUniqueConstraintError(Object error) =>
      error.toString().contains('UNIQUE constraint failed');

  // ─── تطبيق tombstone + الحجر الصحي + مسح التقارب (مراجعة 2026-09-09) ──

  /// ✅ (مراجعة #1) تطبيق tombstone واردة في الدلتا: حذف ناعم للصف
  /// المحلي المطابق بـ local_uuid — أو لا شيء إن لم يصل الصف لهذا
  /// الجهاز قطّ. P0-E: tombstone يفوز حتى على تعديل محلي أحدث معلّق
  /// في outbox — قرار الحذف نهائي من الجهاز المصدر (نفس دلالات
  /// المسار الميت القديم في المسار update). blacklist يُترجم إلى
  /// shift_notes الموسومة created_by='blacklist'.
  Future<bool> _applyTombstone(
    String entity,
    Map<String, dynamic> record,
  ) async {
    if (_db == null) return true;

    var tableName = CloudflareConfig.tableNameFor(entity);
    var extraWhere = '';
    if (entity == 'blacklist') {
      tableName = 'shift_notes';
      extraWhere =
          " AND created_by = '${CloudflareConfig.blacklistStorageTag}'";
    }
    if (tableName == null) {
      debugPrint('⏭️ Tombstone: no local table for "$entity" — skipped');
      return true;
    }
    final localUuid = record['local_uuid'] as String?;
    if (localUuid == null || localUuid.isEmpty) return true;

    final deletedAt = record['deleted_at'];
    final updatedAt = record['updated_at'] as int? ?? 0;
    try {
      final existing = await _db!
          .customSelect(
            'SELECT id FROM $tableName WHERE local_uuid = ?$extraWhere',
            variables: [Variable<String>(localUuid)],
          )
          .getSingleOrNull();
      if (existing == null) {
        // الصف لم يصل هذا الجهاز قط — لا شيء يُحذف (idempotent).
        debugPrint(
          '⏭️ Tombstone: $entity/$localUuid not present locally — no-op',
        );
        await _clearQuarantine(entity, localUuid);
        return true;
      }
      final localId = existing.data['id'];
      final cols = await _localColumns(tableName);
      if (cols.contains('deleted_at')) {
        final hasLastModified = cols.contains('last_modified');
        await _db!.customStatement(
          'UPDATE $tableName SET deleted_at = ?, updated_at = ?'
          '${hasLastModified ? ', last_modified = ?' : ''} WHERE id = ?',
          [deletedAt, updatedAt, if (hasLastModified) updatedAt, localId],
        );
      } else {
        // جدول بلا حذف ناعم — الحذف الوحيد الممكن هو الصلب.
        await _db!.customStatement('DELETE FROM $tableName WHERE id = ?', [
          localId,
        ]);
      }
      debugPrint('  🗑️ $entity/$localUuid: remote tombstone applied');
      unawaited(
        RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: entity,
          record: record,
          op: 'delete',
        ),
      );
      // ✅ (H1) الحذفية البعيدة بأولوية P0-E — أي عملية outbox معلقة لنفس
      // الصف (تعديل محلي متزامن لم يُرفع) صارت لاغية منطقياً: دفعها لاحقاً
      // يُحدِّث صفاً محذوفاً على الخادم (churn نسخة + إعادة بث الحذفية لكل
      // الأجهزة) دون أي أثر مرئي. تُستبدل بحذف تأكيدي idempotent.
      await _supersedePendingOpsWithTombstone(
        entity: entity,
        localUuid: localUuid,
        deletedAt: deletedAt,
        updatedAt: updatedAt,
      );
      await _clearQuarantine(entity, localUuid);
    } catch (e) {
      // فشل قاعدة بيانات حقيقي — يُفسد الدورة (لا كتم).
      throw Exception('Tombstone apply failed for $entity/$localUuid: $e');
    }
    return true;
  }

  /// ✅ (H1) إبطال عمليات outbox المعلقة عند تطبيق حذفية بعيدة.
  ///
  /// العقد المعتمد (مؤكد من `OutboxDao.merge`):
  ///  • صف واحد لكل (entity, local_uuid) في pending/processing، وعملية
  ///    'delete' معلقة لا يستبدلها update أبداً — والـ update المعلقة
  ///    يستبدلها delete (نفس عقد الحذف المحلي في الـ DAOs).
  ///  • حمولة الحذف الرقيقة صالحة: `buildPushOperation` يضمّن local_uuid
  ///    تلقائياً، و`deleteRecord` الخادمي idempotent على صف محذوف.
  ///
  /// لذلك: الاستبدال يحدث **فقط** عند وجود عملية معلقة غير-حذف فعلاً —
  /// لا يُنشأ أي op جديد لكل tombstone تُسحب (لا دفع زائف)، ودفع الحذف
  /// التأكيدي أرخص من دفع تحديث قديم فوق صف محذوف (الذي كان يقفز
  /// بالنسخة ويعيد بث الحذفية لكل الأجهزة).
  /// مساعد بحت: فشله لا يُفشل الحذفية (التقارب سليم بدونه).
  Future<void> _supersedePendingOpsWithTombstone({
    required String entity,
    required String localUuid,
    required Object? deletedAt,
    required int updatedAt,
  }) async {
    final db = _db;
    if (db == null) return;
    try {
      final rows = await db
          .customSelect(
            'SELECT op FROM outbox WHERE entity = ? AND local_uuid = ? '
            'AND processing_status IN (?, ?) LIMIT 1',
            variables: [
              Variable.withString(entity),
              Variable.withString(localUuid),
              Variable.withString('pending'),
              Variable.withString('processing'),
            ],
          )
          .get();
      final hasLiveOp = rows.any(
        (row) => (row.data['op'] as String?) != 'delete',
      );
      if (!hasLiveOp) return;
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await OutboxDao(db).merge(
        entity: entity,
        op: 'delete',
        localUuid: localUuid,
        payload: <String, dynamic>{
          'local_uuid': localUuid,
          'deleted_at': deletedAt,
          'updated_at': updatedAt,
        },
        clientTs: nowSec,
      );
      debugPrint(
        '  🗑️ $entity/$localUuid: remote tombstone superseded pending '
        'local op(s) — confirmatory delete queued',
      );
    } catch (e) {
      debugPrint('⚠️ tombstone outbox supersede skipped: $e');
    }
  }

  // ─── الحجر الصحي للصفوف اليتيمة (مراجعة #2+#16) ──────────────

  /// ✅ (F1 2026-09-22) ختم محلي بعد خسارة تعديل لصالح حذف — عقد
  /// delete-vs-update: الخادم رفض التعديل المعلّق (opStatus:'deleted')
  /// لأن الصف محذوف ناعماً عنده. نُطابق النسخة المحلية بوعي (idempotent:
  /// السيناريو الشائع تكون النسخة المحلية مطموعة سلفاً من السحب) —
  /// بلا supersede لا confirmatory-delete: العملية الخاسرة تُحذف من
  /// outbox فوراً وهي نفسها، وإعادة ختم الخادم تصل عبر الدلتا كالمعتاد.
  Future<void> _tombstoneLocalRowAfterLostEdit({
    required String entity,
    required String localUuid,
  }) async {
    final db = _db;
    if (db == null) return;
    try {
      var tableName = CloudflareConfig.tableNameFor(entity);
      var extraWhere = '';
      if (entity == 'blacklist') {
        tableName = 'shift_notes';
        extraWhere =
            " AND created_by = '${CloudflareConfig.blacklistStorageTag}'";
      }
      if (tableName == null) return;
      final existing = await db
          .customSelect(
            'SELECT id, deleted_at FROM $tableName WHERE local_uuid = ?'
            '$extraWhere',
            variables: [Variable.withString(localUuid)],
          )
          .getSingleOrNull();
      if (existing == null) return; // الصف لم يصل هذا الجهاز قط — لا شيء
      if (existing.data['deleted_at'] != null) {
        debugPrint(
          '  🗑️ $entity/$localUuid: already tombstoned locally — '
          'edit loss acknowledged (delete-vs-update contract)',
        );
        return;
      }
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await db.customStatement(
        'UPDATE $tableName SET deleted_at = ?, updated_at = ? WHERE id = ?',
        [nowSec, nowSec, existing.data['id']],
      );
      debugPrint(
        '  🗑️ $entity/$localUuid: local edit lost to deletion — '
        'row tombstoned to match server (delete-vs-update contract)',
      );
    } catch (e) {
      // التطابق النهائي سيأتي من tombstone الدلتا على أي حال —
      // هذا الختم المحلي تسريعٌ للوعي لا شرط للصحة.
      debugPrint('⚠️ post-rejection local tombstone skipped: $e');
    }
  }

  String _quarantineIdentity(String entity, String? localUuid) =>
      '$entity/$localUuid';

  /// ✅ (M2) طابع first_seen للمقارنة أثناء الإخلاء — غياب/تشوه = 0
  /// (الأقدم) فيُخلى أولاً بأمان.
  int _quarantineFirstSeen(Map<String, dynamic> entry) =>
      (entry['first_seen'] as num?)?.toInt() ?? 0;

  void _loadQuarantineState(SharedPreferences prefs) {
    try {
      final countsRaw = prefs.getString(_kQuarantineCountsKey);
      if (countsRaw != null && countsRaw.isNotEmpty) {
        final decoded = jsonDecode(countsRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          _orphanBlockCounts[key] = (value as num?)?.toInt() ?? 0;
        });
      }
      final quarantinedRaw = prefs.getString(_kQuarantinedKey);
      if (quarantinedRaw != null && quarantinedRaw.isNotEmpty) {
        final decoded = jsonDecode(quarantinedRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map) {
            _quarantinedRecords[key] = Map<String, dynamic>.from(value);
          }
        });
      }
      // ✅ (2026-09-15) استعادة سجل الانتظار (الحمولات المحجوبة تحت
      // العتبة) — تعيش عبر الجلسات كالحجر، وإلا فُقدت حمولة سجل
      // محجوب عند إعادة تشغيل التطبيق وعاد الحجب من الصفر.
      final pendingRaw = prefs.getString(_kBlockedPendingKey);
      if (pendingRaw != null && pendingRaw.isNotEmpty) {
        final decoded = jsonDecode(pendingRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map &&
              value['entity'] != null &&
              value['record'] is Map) {
            _blockedPending[key] = (
              entity: value['entity'].toString(),
              record: Map<String, dynamic>.from(value['record'] as Map),
            );
          }
        });
      }
      if (_orphanBlockCounts.isNotEmpty ||
          _quarantinedRecords.isNotEmpty ||
          _blockedPending.isNotEmpty) {
        debugPrint(
          '🏥 Quarantine state restored: ${_orphanBlockCounts.length} '
          'counter(s), ${_quarantinedRecords.length} quarantined, '
          '${_blockedPending.length} pending',
        );
      }
    } catch (e) {
      debugPrint('⚠️ quarantine state load failed: $e');
    }
  }

  Future<void> _persistQuarantineState(SharedPreferences prefs) async {
    try {
      // ✅ (M2) تقليم عدّادات يتيمة لا تنتمي لأي سجل — تمنع نمو الخريطة
      // بلا حد عبر الجلسات (الشفاء/الإخلاء يزيلان السجلات وقد يُبقيان
      // العدّاد).
      _orphanBlockCounts.removeWhere(
        (key, _) =>
            !_quarantinedRecords.containsKey(key) &&
            !_blockedPending.containsKey(key),
      );
      await prefs.setString(
        _kQuarantineCountsKey,
        jsonEncode(_orphanBlockCounts),
      );
      await prefs.setString(_kQuarantinedKey, jsonEncode(_quarantinedRecords));
      // ✅ (2026-09-15) حمولات سجل الانتظار تُخزَّن كاملة (persistent).
      await prefs.setString(
        _kBlockedPendingKey,
        jsonEncode({
          for (final entry in _blockedPending.entries)
            entry.key: {
              'entity': entry.value.entity,
              'record': entry.value.record,
            },
        }),
      );
    } catch (e) {
      debugPrint('⚠️ quarantine state persist failed: $e');
    }
  }

  bool _isQuarantined(String entity, String? localUuid) =>
      _quarantinedRecords.containsKey(_quarantineIdentity(entity, localUuid));

  /// يمسح السجل من الحجر وسجل الانتظار وعدّاد الحجب — يكتب prefs فقط
  /// حين يُزال شيء فعلاً. (M3: إغفال سجل الانتظار هنا كان يُبقي حمولة
  /// ميتة تُعاد محاولتها دورة إضافية هدراً.)
  Future<void> _clearQuarantine(String entity, String? localUuid) async {
    final identity = _quarantineIdentity(entity, localUuid);
    final removedLedger = _quarantinedRecords.remove(identity) != null;
    final removedPending = _blockedPending.remove(identity) != null;
    final removedCounter = _orphanBlockCounts.remove(identity) != null;
    if (removedLedger || removedPending || removedCounter) {
      final prefs = await SharedPreferences.getInstance();
      await _persistQuarantineState(prefs);
    }
  }

  /// ✅ (مراجعة #1) مسح تقارب الحذفيات لمرة واحدة: يجلب كل tombstones
  /// الخادمية عبر نافذة tombstones_only الرخيصة (بترتيب updated_at،
  /// بلا مساس بالمؤشر الرئيسي) ويطبّقها كحذف محلي.
  /// يعيد null عند أي فشل شبكي/خادمي (تُعاد المحاولة في الدورة التالية).
  ///
  /// ✅ إصلاح بطء (تقرير مستخدم: «يتأخر كثيراً أثناء سحب التغييرات»)
  /// — ثلاثة تغييرات مقابل النسخة السابقة:
  /// 1. حجم الصفحة كان [CloudflareConfig.batchSize] (100) — وهو سقف
  ///    دفع outbox وليس حجم صفحة سحب — الآن [CloudflareConfig.deltaPullBatchSize]
  ///    (250): رحلات شبكية أقل، وكل رحلة على الشبكات الضعيفة (النفق
  ///    الاحتياطي في resilient_http_client.dart قد يستغرق حتى 36 ثانية)
  ///    مكلفة جداً لتُهدَر على صفحات صغيرة.
  /// 2. التطبيق كان صفاً بصف عبر `_applyChange` بلا معاملة (commit
  ///    منفصل لكل صف) — الآن دفعة الصفحة كاملة عبر `_applyPulledRecords`
  ///    داخل معاملة واحدة، بنفس نمط الحلقة الرئيسية في `_pullChanges`.
  /// 3. الأهم: كان يبدأ من cursor=0 دائماً عند كل استدعاء (العلم `_done`
  ///    لا يُثبَّت إلا عند اكتمال كامل بلا أي خطأ) — أي فشل شبكي جزئي
  ///    كان يُعيد المسح بالكامل من الصفر في الدورة التالية، فتتكرر نفس
  ///    التكلفة الشبكية الثقيلة عند كل ضغطة «سحب التغييرات» على شبكة غير
  ///    مستقرة إلى الأبد. الآن يُحفَظ المؤشر بعد كل صفحة ناجحة
  ///    ([_kTombstoneSweepCursorKey]) ويُستأنف منه، لا من الصفر.
  Future<int?> _sweepHistoricalTombstones() async {
    if (_db == null || _token == null) return null;
    int handled = 0;
    final prefs = await SharedPreferences.getInstance();
    int cursor = prefs.getInt(_kTombstoneSweepCursorKey) ?? 0;
    try {
      while (true) {
        final http.Response response;
        try {
          response = await _httpClient
              .get(
                Uri.parse(
                  '${CloudflareConfig.workerUrl}/api/sync/pull',
                ).replace(
                  queryParameters: <String, String>{
                    'cursor': cursor.toString(),
                    'limit': CloudflareConfig.deltaPullBatchSize.toString(),
                    'tombstones_only': '1',
                    if (_deviceId case final ownDevice?
                        when ownDevice.isNotEmpty)
                      'exclude_device': ownDevice,
                  },
                ),
                headers: {'Authorization': 'Bearer $_token'},
              )
              // ✅ (2026-09-17) 60 ثانية — نفس عقلية _fetchPullPage:
              // headroom فوق مسار fast(6s)+tunnel(30s) للعميل المرِن.
              .timeout(const Duration(seconds: 60));
        } catch (e) {
          debugPrint(
            '⚠️ tombstone sweep network failure (resumable from '
            'cursor=$cursor next cycle): $e',
          );
          return null;
        }
        if (response.statusCode != 200) {
          debugPrint(
            '⚠️ tombstone sweep HTTP ${response.statusCode} '
            '(resumable from cursor=$cursor next cycle)',
          );
          return null;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final changes = data['changes'] as List? ?? [];

        final batchRecords = <({String entity, Map<String, dynamic> record})>[];
        for (final change in changes) {
          try {
            final record = Map<String, dynamic>.from(change as Map);
            final entity =
                record['_entity'] as String? ?? _detectEntity(record);
            record.remove('_entity');
            if (entity == null) continue;
            batchRecords.add((entity: entity, record: record));
          } catch (e) {
            debugPrint('⚠️ tombstone sweep malformed record: $e');
          }
        }
        if (batchRecords.isNotEmpty) {
          final report = await _db!.transaction(
            () => _applyPulledRecords(
              batchRecords,
              deferredSink: <({String entity, Map<String, dynamic> record})>[],
              conflictedSink:
                  <({String entity, Map<String, dynamic> record})>[],
            ),
          );
          handled += report.appliedCount;
          if (report.errors.isNotEmpty) {
            debugPrint(
              '⚠️ tombstone sweep: ${report.errors.length} apply-failure(s) '
              '(best-effort — continuing): ${report.errors.take(2).join(' | ')}',
            );
          }
        }

        final serverCursor =
            int.tryParse(data['cursor']?.toString() ?? '0') ?? 0;
        final hasMore = data['has_more'] as bool? ?? false;
        if (serverCursor > cursor) {
          cursor = serverCursor;
          // ✅ إصلاح البطء: احفظ التقدم فوراً — فشل شبكي لاحق يستأنف من
          // هنا بدل إعادة المسح بالكامل من الصفر.
          await prefs.setInt(_kTombstoneSweepCursorKey, cursor);
        } else if (hasMore && changes.isNotEmpty) {
          // حارس تقدم: مؤشر غير متحرك مع صفوف = حلقة لا نهائية محتملة.
          debugPrint('⚠️ tombstone sweep: cursor stalled — aborting');
          return null;
        }
        if (!hasMore || changes.isEmpty) break;
      }
      return handled;
    } catch (e) {
      debugPrint(
        '⚠️ tombstone sweep failed (resumable from cursor=$cursor): $e',
      );
      return null;
    }
  }

  // ─── Detect entity from record fields ───────────────────────

  /// الكيانات التي تؤثر صفوفها المسحوبة على الحقول المشتقة للحجوزات
  /// (الليالي + الإجماليات المخزنة) — تستدعي إعادة بناء بعد السحب.
  static const Set<String> _derivedRefreshEntities = {
    'bookings',
    'booking_nights',
    'payments',
    'price_adjustments',
    'booking_price_adjustments',
    'payment_voids',
  };

  bool _derivedRefreshRunning = false;

  /// إعادة بناء الحقول المشتقة للحجوزات النشطة بعد سحب تغييرات مؤثرة.
  /// enqueueOutbox:false إجبارياً — البيانات المشتقة تُحسب محلياً على كل
  /// جهاز ولا تُرفع للخادم، وإلا سجّرت الأجهزة في حلقة سحب/رفع لا نهائية.
  Future<void> _refreshDerivedAfterPull() async {
    if (_db == null || _derivedRefreshRunning) return;
    _derivedRefreshRunning = true;
    try {
      final service = BookingDerivedFieldsService(_db!);
      final refreshed = await service.refreshAllActiveBookings(
        enqueueOutbox: false,
      );
      debugPrint('🔄 Derived refresh after pull: $refreshed bookings rebuilt');
    } catch (e) {
      debugPrint('⚠️ Derived refresh after pull failed: $e');
    } finally {
      _derivedRefreshRunning = false;
    }
  }

  // ─── Detect entity from record fields ───────────────────────
  // يحاول تحديد نوع الجدول من حقول السجل المستلم من D1
  String? _detectEntity(Map<String, dynamic> record) {
    // Core entities
    if (record.containsKey('room_number') && record.containsKey('price')) {
      return 'rooms';
    }
    if (record.containsKey('guest_name') &&
        record.containsKey('checkin_date')) {
      return 'bookings';
    }
    if (record.containsKey('amount') && record.containsKey('payment_method')) {
      return 'payments';
    }
    if (record.containsKey('expense_type') &&
        record.containsKey('description')) {
      return 'expenses';
    }
    if (record.containsKey('basic_salary') && record.containsKey('position')) {
      return 'employees';
    }
    if (record.containsKey('debt_reason') &&
        record.containsKey('remaining_amount')) {
      return 'debts';
    }

    // Booking-related
    if (record.containsKey('final_rate') &&
        record.containsKey('hotel_day_key')) {
      return 'booking_nights';
    }
    if (record.containsKey('adjustment_type') &&
        record.containsKey('effective_hotel_day')) {
      return 'booking_price_adjustments';
    }
    if (record.containsKey('note_text') && record.containsKey('alert_type')) {
      return 'booking_notes';
    }
    if (record.containsKey('guest_name') && record.containsKey('id_number')) {
      return 'guest_infos';
    }

    // Shift & cash
    if (record.containsKey('shift_date') && record.containsKey('is_read')) {
      return 'shift_notes';
    }
    if (record.containsKey('transaction_type') &&
        record.containsKey('transaction_time')) {
      return 'cash_transactions';
    }

    // Salary
    if (record.containsKey('cycle_key') &&
        record.containsKey('expected_amount')) {
      return 'salary_cycles';
    }
    if (record.containsKey('payment_date_iso') &&
        record.containsKey('cycle_id')) {
      return 'salary_payments';
    }
    if (record.containsKey('withdrawal_type') && record.containsKey('amount')) {
      return 'salary_withdrawals';
    }
    if (record.containsKey('previous_cycle_start') &&
        record.containsKey('new_cycle_start')) {
      return 'salary_carry_over_logs';
    }

    // Adjustments & audit
    if (record.containsKey('target_type') &&
        record.containsKey('target_uuid')) {
      return 'price_adjustments';
    }
    if (record.containsKey('operation_type') &&
        record.containsKey('entity_type')) {
      return 'audit_logs';
    }
    if (record.containsKey('void_reason') && record.containsKey('voided_by')) {
      return 'payment_voids';
    }

    // inventory_items — minimum_quantity لا يوجد في أي جدول متزامن آخر
    // (local_db.dart:1032 — InventoryItems فقط).
    if (record.containsKey('minimum_quantity')) {
      return 'inventory_items';
    }

    // inventory_transactions — movement_type + balance_after فريدان معاً
    // (local_db.dart:1046-1048 — لا يملكهما payments ولا salary_withdrawals
    // اللذان يستخدمان amount/withdrawal_type).
    if (record.containsKey('movement_type') &&
        record.containsKey('balance_after')) {
      return 'inventory_transactions';
    }

    // devices — device_name لا يوجد إلا في جدول devices
    // (local_db.dart:1135 — الكيانات الأخرى تستخدم name/guest_name/username).
    if (record.containsKey('device_name')) {
      return 'devices';
    }

    // blacklist — reported_by لا يوجد إلا في صفوف القائمة السوداء
    // (جدول blacklist في D1 — يُحوَّل لـ shift_notes في _applyChange).
    if (record.containsKey('reported_by')) {
      return 'blacklist';
    }

    // app_users — حسابات مستخدمي التطبيق (كيان النطاق الافتراضي
    // 2026-09-05). الثنائي username + credentials_version فريد؛ لا
    // جدول آخر متزامن يملك عمود username.
    if (record.containsKey('username') &&
        record.containsKey('credentials_version')) {
      return 'app_users';
    }

    // hotel_day_ledger is local-only — should not be pulled
    // (but if it arrives, we skip it)

    return null;
  }

  // ─── Convert value for Drift ────────────────────────────────
  dynamic _toDriftValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is List || value is Map) {
      return jsonEncode(value);
    }
    return value;
  }

  // ─── Auto Sync ──────────────────────────────────────────────
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      // Fire-and-forget: sync errors are handled by catchError, not awaited
      // because Timer.periodic callback is synchronous.
      unawaited(
        sync(deltaOnly: true).catchError((Object e) {
          debugPrint('⚠️ Auto-sync error: $e');
          return SyncResult(
            status: SyncStatus.failed,
            timestamp: DateTime.now(),
            duration: Duration.zero,
            errorMessage: e.toString(),
          );
        }),
      );
    });
    debugPrint('⏰ Auto-sync started: every ${interval.inMinutes} minutes');
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// ✅ (2026-09-06) هل مؤقّت المزامنة التلقائية نشط الآن؟
  /// يُستخدم في بطاقة «بيانات الاتصال التلقائي مع Cloudflare» لعرض
  /// حالة المحرك الفعلية (لا نية الإعداد المخزّنة فقط).
  bool get isAutoSyncRunning => _autoSyncTimer != null;

  // ─── Reset / Clear ──────────────────────────────────────────
  void reset() {
    _token = null;
    _deviceId = null;
    _lastError = null;
    _currentStatus = SyncStatus.idle;
    _lastLazyInitAttempt = null;
  }

  Future<void> resetSyncState() async {
    // ✅ (2026-09-05) كانت تكتفي بضبط الحالة الظاهرة بينما الرسالة
    // تعرض «تم إعادة تعيين مؤشر المزامنة المحلي فقط» — كذب. الآن
    // تُصفّر cursor السحب وعلامة full-sync فعلياً (نفس clearHistory +
    // مسح التخزين) فيبدأ السحب التالي من الصفر — «البدء من جديد».
    _currentStatus = SyncStatus.idle;
    _lastError = null;
    _statusController.add(SyncStatus.idle);
    clearHistory();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('cf_last_pull_cursor');
      await prefs.remove(_kFullSyncCompletedKey);
      debugPrint('🔄 resetSyncState: cursor + fullSync flag cleared');
    } catch (e) {
      debugPrint('⚠️ resetSyncState prefs clear failed: $e');
    }
  }

  /// إعادة تعيين cursor — يُجبر الـ pull التالي على جلب كل البيانات (full sync).
  /// يستخدم عند: تبديل الجهاز، استعادة backup، إصلاح تعارضات.
  ///
  /// ✅ P0-B: يُعيد أيضاً تعيين علامة "full sync مكتملة" لتجبر الجهاز على
  /// إعادة full sync كامل قبل العودة لـ delta mode.
  void clearHistory() {
    _lastPullCursor = 0;
    _fullSyncCompleted = false;
    _failedCollectionsInLastSync.clear();
    debugPrint('🔄 Sync cursor reset — next pull will be full sync');
  }

  /// مزامنة كاملة (full sync) — يعيد تعيين cursor ثم ينفذ pull حتى exhaustion.
  /// يستخدم عند: تبديل الجهاز، استعادة backup، مشاكل في البيانات.
  ///
  /// ✅ P0-B: بعد اكتمال full sync بنجاح، تُضبط علامة _fullSyncCompleted=true
  /// تلقائياً داخل _pullChanges() عند الوصول لـ exhaustion بدون أخطاء.
  /// إذا فشلت full sync جزئياً، تبقى العلامة false ويُعاد المحاولة في
  /// الـ sync التالي تلقائياً (لأن _pullChanges سيرى wasFullSync=true).
  Future<SyncResult> fullSync({bool push = false}) async {
    clearHistory();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cf_last_pull_cursor');
    await prefs.remove(_kFullSyncCompletedKey);
    debugPrint('🔄 Full sync: cursor reset + fullSyncCompleted flag cleared');
    return sync(push: push);
  }

  // ─── Push all local data ────────────────────────────────────
  // ✅ توافق Drop-in (perf google_drive_backup_service يستدعيها
  // بـ skipDeleted ويتوقع Map<String,int> فيه 'errors'): الرفع
  // الفعلي للبيانات يجري عبر outbox/push العادي — هذه الدالة
  // للتوافق وتُرجع صفراً لكل جدول.
  Future<Map<String, int>> pushAllLocalDataToAppwrite({
    bool skipDeleted = false,
  }) async {
    debugPrint(
      '⚠️ pushAllLocalDataToAppwrite: cloudflare path uses outbox push — '
      'returning zeroed stats (skipDeleted: $skipDeleted)',
    );
    return const <String, int>{'errors': 0};
  }

  /// ✅ توافق Drop-in (perf google_drive_login_screen / appwrite_settings
  /// يستدعيها ويتوقع Future<bool>): سحب كامل — نفس sync(pull: true)
  /// بلا رفع؛ نجاحها = لا فشل جزئي.
  Future<bool> pullAllDataWithDisabledFK() async {
    final result = await fullSync();
    return result.isSuccess;
  }

  /// ✅ توافق Drop-in (perf providers تسجّل ref.onDispose(manager.dispose)).
  /// singleton مشترك — لا يُغلق _statusController (broadcast stream
  /// مستهلك من شاشات أخرى)؛ تنظيف محدود فقط.
  void dispose() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  /// ✅ (2026-09-05) الأجهزة المسجلة — تُقرأ الآن من جدول devices المحلي
  /// (landing zone السحب — تُغذّى من D1 عبر pull) بدل القائمة الفارغة؛
  /// الشاشة مبنية على D1 عبر المزامنة كما تنص الخطة المعلقة سابقاً.
  Future<List<AppwriteDevice>> getRegisteredDevices() async {
    final db = _db;
    if (db == null) return const <AppwriteDevice>[];
    try {
      final rows = await db
          .customSelect(
            'SELECT * FROM devices WHERE deleted_at IS NULL '
            'ORDER BY COALESCE(last_active, updated_at) DESC',
          )
          .get();
      DateTime? epochToDateTime(dynamic v) {
        if (v is int && v > 0) {
          return DateTime.fromMillisecondsSinceEpoch(v * 1000);
        }
        return null;
      }

      DateTime? isoToDateTime(dynamic v) {
        if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
        return null;
      }

      return rows.map((r) {
        final d = r.data;
        return AppwriteDevice(
          id: (d['device_id'] as String?) ?? '',
          deviceName: (d['device_name'] as String?) ?? '',
          deviceModel: (d['device_model'] as String?) ?? '',
          osVersion: (d['os_version'] as String?) ?? '',
          lastSeen: isoToDateTime(d['last_seen']) ?? DateTime.now(),
          lastActive: epochToDateTime(d['last_active']),
          status: (d['status'] as String?) ?? 'active',
          createdAt: epochToDateTime(d['created_at']) ?? DateTime.now(),
          updatedAt: epochToDateTime(d['updated_at']) ?? DateTime.now(),
          version: (d['version'] as int?) ?? 1,
          origin: d['origin'] as String?,
          localUuid: d['local_uuid'] as String?,
        );
      }).toList();
    } catch (e) {
      debugPrint('⚠️ getRegisteredDevices failed: $e');
      return const <AppwriteDevice>[];
    }
  }

  // ─── Device ID generation ───────────────────────────────────
  String _generateDeviceId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'cf_dev_${now.toRadixString(36)}';
  }

  // ─── Audit log (stub — same interface as AppwriteSyncManager) ─
  final List<Map<String, dynamic>> _auditLog = [];
  List<Map<String, dynamic>> get auditLog => List.unmodifiable(_auditLog);

  void logToAudit({
    required String userMessage,
    required String aiResponse,
    required String executionResult,
    required bool wasConfirmed,
    String? commandType,
    String? commandDescription,
  }) {
    _auditLog.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'userMessage': userMessage,
      'aiResponse': aiResponse,
      'executionResult': executionResult,
      'wasConfirmed': wasConfirmed,
      'commandType': commandType,
      'commandDescription': commandDescription,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_auditLog.length > 100) _auditLog.removeAt(0);
  }

  void clearAuditLog() => _auditLog.clear();

  // ─── Stubs for methods called by existing screens ──────────

  /// ✅ (2026-09-06) عقد صادق لزر «رفع التغييرات» في dashboard.
  ///
  /// سابقاً: `sync(pull: false).then((r) => r.recordsPushed)` — كانت تُسقط
  /// `SyncResult.status` بالكامل، فأي فشل (شبكة :723-751، non-200 :753-779،
  /// kill switch :502-510، تعطيل محلي :515-526، غير مهيأ :541-548، دورة
  /// جارية :551-559) كان يُترجم عند المستدعي إلى نجاح مع 0 سجل، لأن
  /// `pushedCount >= 0` صادق دائماً (dashboard_sync_button.dart:536).
  /// النتيجة الإنتاجية: snackbar أخضر «✅ تم رفع التغييرات بنجاح!» بينما
  /// الـ outbox ما زال ممتلئاً — تضليل بنفس نمط pushAllLocalData المُصلح
  /// أعلاه (2026-09-05).
  ///
  /// الآن: ترمي [StateError] عند أي حالة غير `success`، وتُرجع العدد
  /// عند نجاح فعلي فقط. المستدعي dashboard_sync_button يلتقط الاستثناء
  /// في try/catch لكل هدف (:539-546) فيُظهر snackbar أحمر مع «إعادة».
  Future<int> pushLocalChanges() async {
    // ✅ (2026-09-13) forcePull: الرفع اليدوي طلب مستخدم صريح — يتجاوز
    // تبريد الدخول الكسول في sync() فيجرّب admin/admin المدمجة فوراً
    // بدل StateError('Not initialized') رغم أن الشبكة سليمة (نفس عقد
    // زر السحب اليدوي forcePull: true).
    final r = await sync(pull: false, forcePull: true);
    if (r.status != SyncStatus.success) {
      throw StateError(r.errorMessage ?? 'Push failed (${r.status.name})');
    }
    return r.recordsPushed;
  }

  /// ✅ (2026-09-05) كانت تُرجع 0 دائماً (stub) بينما زر «بدء الرفع»
  /// في الإعدادات يعرض «تم رفع البيانات بنجاح» دون رفع أي شيء —
  /// تضليل إنتاجي. الآن تنفّذ الرفع الفعلي عبر outbox push (نفس
  /// مسار pushLocalChanges) وتعيد عدد السجلات المرفوعة، وترمي
  /// استثناء عند فشل الدورة ليُظهره try/catch الشاشة بدل نجاح زائف.
  Future<int> pushAllLocalData() async {
    final r = await sync(pull: false);
    if (r.status == SyncStatus.failed) {
      throw StateError(r.errorMessage ?? 'Push failed');
    }
    return r.recordsPushed;
  }

  Future<void> pushAllEntities() async {}

  /// ✅ (2026-09-05) إحصائيات حقيقية بدل {} — عدادات دورات المدير
  /// (تعيش في SharedPreferences) + عدّ Outbox الفعلي (المعلّق
  /// غير المسلَّم + الفاشل). المفاتيح هي نفسها التي تقرأها
  /// شاشات الإحصائيات (appwrite_settings_screen، appwrite_sync_stats_screen).
  Future<Map<String, dynamic>> getSyncStatistics() async {
    final stats = <String, dynamic>{
      'totalSyncs': _statTotalSyncs,
      'successfulSyncs': _statSuccessfulSyncs,
      'failedSyncs': _statFailedSyncs,
      'totalRecordsPushed': _statTotalPushed,
      'totalRecordsPulled': _statTotalPulled,
      'totalConflicts': 0,
      'successRate': _statTotalSyncs == 0
          ? 0.0
          : _statSuccessfulSyncs / _statTotalSyncs,
      'lastSyncTime': _statLastSyncTime?.toIso8601String(),
      'outboxCount': 0,
      'fullSyncCompleted': _fullSyncCompleted,
      'lastError': _lastError,
    };
    final db = _db;
    if (db != null) {
      try {
        final pending = await OutboxDao(
          db,
        ).countUndeliveredToPrimary(sources: const ['local']);
        stats['outboxCount'] = pending;
      } catch (e) {
        debugPrint('⚠️ getSyncStatistics outbox count failed: $e');
      }
    }
    return stats;
  }

  /// تحميل عدادات الإحصائيات المحفوظة — يُستدعى من initialize().
  Future<void> _loadSyncStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSyncStatsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _statTotalSyncs = (map['totalSyncs'] as num?)?.toInt() ?? 0;
      _statSuccessfulSyncs = (map['successfulSyncs'] as num?)?.toInt() ?? 0;
      _statFailedSyncs = (map['failedSyncs'] as num?)?.toInt() ?? 0;
      _statTotalPushed = (map['totalPushed'] as num?)?.toInt() ?? 0;
      _statTotalPulled = (map['totalPulled'] as num?)?.toInt() ?? 0;
      final lastMs = (map['lastSyncMs'] as num?)?.toInt();
      _statLastSyncTime = lastMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastMs);
    } catch (e) {
      debugPrint('⚠️ _loadSyncStats failed: $e');
    }
  }

  /// تسجيل نتيجة دورة مزامنة مكتملة وحفظها.
  Future<void> _recordSyncOutcome({
    required bool success,
    required int pushed,
    required int pulled,
    required DateTime startedAt,
  }) async {
    _statTotalSyncs++;
    if (success) {
      _statSuccessfulSyncs++;
    } else {
      _statFailedSyncs++;
    }
    _statTotalPushed += pushed;
    _statTotalPulled += pulled;
    _statLastSyncTime = startedAt;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSyncStatsKey,
        jsonEncode(<String, dynamic>{
          'totalSyncs': _statTotalSyncs,
          'successfulSyncs': _statSuccessfulSyncs,
          'failedSyncs': _statFailedSyncs,
          'totalPushed': _statTotalPushed,
          'totalPulled': _statTotalPulled,
          'lastSyncMs': startedAt.millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      debugPrint('⚠️ _recordSyncOutcome persist failed: $e');
    }
  }

  Future<void> reinitializeAfterConfigChange() async {
    await initialize(forceRetry: true);
  }

  // ─── Pull remote changes (delta) — used by UnifiedSyncOrchestrator ──
  Future<bool> pullRemoteChanges() async {
    final result = await sync();
    return result.isSuccess;
  }

  // ─── Pull ALL remote data — used by appwrite_settings_screen ──
  // ✅ توافق Drop-in: perf screen يتوقع Future<bool>.
  Future<bool> pullAllRemoteData() async {
    final result = await fullSync();
    return result.isSuccess;
  }

  /// ✅ توافق Drop-in (perf auth_local_store يستخدم manager.outboxDao
  /// لدمج app_users من النسخ الاحتياطية): الوصول لـ OutboxDao على نفس
  /// قاعدة drift الخاصة بالمدير.
  OutboxDao get outboxDao => OutboxDao(_db!);

  // AppwriteService compatibility (some files pass this)
  dynamic get appwriteService => null;

  /// ✅ المرحلة 3: مدخل السحب المُشغَّل من Realtime (عقد RemoteChangePull).
  ///
  /// - delta-only حصراً: لا يبدأ Full Sync أبداً من حدث realtime.
  /// - حارس re-entrancy (P0-I): sync() نفسه محمي، لكن نتجنب هنا
  ///   إهدار دورة على "already in progress".
  /// - push أولاً ثم pull داخل sync() — الترتيب يضمن أن التغييرات
  ///   المحلية المعلّقة تُرفع قبل الاستماع للبعيدة (نفس عقد Outbox).
  Future<bool> realtimeTriggeredPull({bool forcePull = false}) async {
    if (_syncInProgress) {
      debugPrint('⏭️ Realtime pull skipped — sync already in progress');
      return false;
    }
    // Delta pull فقط: الرفع الفوري مسؤولية AutoOutboxSyncWatcher،
    // ولا يجوز لمسار السحب التفاضلي أن يبدأ Full Sync أو يرفع بيانات.
    final result = await sync(
      push: false,
      forcePull: forcePull,
      deltaOnly: true,
    );
    return result.isSuccess;
  }
}

// ═══ Backward compatibility aliases ═══════════════════════════
// All files that imported AppwriteSyncManager will get these aliases
// No need to change any imports or references in existing code.

typedef AppwriteSyncManager = CloudflareSyncManager;
typedef AppwriteRealtimeSync = CloudflareRealtimeSync;
