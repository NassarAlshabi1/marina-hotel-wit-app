import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloudflare_d1_service.dart';
import '../services/cloudflare_direct_api_service.dart';
import '../services/cloudflare_sync_manager.dart';
import '../services/daos/outbox_dao.dart';
import '../services/local_db.dart';
import 'appwrite_providers.dart' show connectionStatusProvider;
import 'repository_providers.dart' show databaseProvider;

// ✅ (2026-09-06) مزودات «بيانات الاتصال التلقائي مع Cloudflare».
// تجمع — من مصادرها الحقيقية — كل ما يلزم لعرض حالة الارتباط التلقائي:
//  1) اتصال Cloudflare Worker (/health) عبر connectionStatusProvider.
//  2) نية المزامنة التلقائية وفترتها من SharedPreferences (نفس مفاتيح
//     unified_sync_settings_screen.dart — المصدر الفعلي للكتابة).
//  3) حالة محرك المزامنة الفعلية (isAutoSyncRunning على المدير).
//  4) آخر مزامنة ناجحة من sync_log.
//  5) عدد سجلات outbox المعلقة التي لم تُسلَّم للسحابة بعد.
// كل المزودات autoDispose: لا مؤقتات ولا استعلامات حية خارج الشاشة.

/// مفتاح تفعيل المزامنة التلقائية — نفس
/// unified_sync_settings_screen._autoSyncKey (مصدر الكتابة).
const String kCloudflareAutoSyncEnabledKey = 'appwrite_auto_sync_enabled';

/// مفتاح فترة المزامنة التلقائية بالدقائق — نفس
/// unified_sync_settings_screen._syncIntervalKey (مصدر الكتابة).
const String kCloudflareAutoSyncIntervalKey = 'appwrite_sync_interval_minutes';

/// لقطة حالة المزامنة التلقائية مع Cloudflare.
class AutoSyncSnapshot {
  const AutoSyncSnapshot({
    required this.enabled,
    required this.intervalMinutes,
    required this.engineRunning,
  });

  /// نية المستخدم المخزّنة (إعداد «المزامنة التلقائية»).
  final bool enabled;

  /// الفترة المضبوطة بالدقائق (الافتراضي 15).
  final int intervalMinutes;

  /// هل مؤقّت المزامنة التلقائية فعلياً نشط في المدير الآن؟
  final bool engineRunning;
}

/// لقطة إعدادات + محرك المزامنة التلقائية.
final autoSyncSnapshotProvider = FutureProvider.autoDispose<AutoSyncSnapshot>((
  ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  final manager = CloudflareSyncManager.instance;
  return AutoSyncSnapshot(
    enabled: prefs.getBool(kCloudflareAutoSyncEnabledKey) ?? true,
    intervalMinutes: prefs.getInt(kCloudflareAutoSyncIntervalKey) ?? 15,
    engineRunning: manager.isAutoSyncRunning,
  );
});

/// آخر مزامنة ناجحة من sync_log (الأحدث أولاً)، أو null إن لا يوجد.
final lastSuccessfulSyncProvider = FutureProvider.autoDispose<SyncLogData?>((
  ref,
) async {
  final db = ref.read(databaseProvider);
  final logs = await SyncAuditDao(db).fetchRecentLogs(10);
  for (final log in logs) {
    if (log.status == 'success') {
      return log;
    }
  }
  return null;
});

/// عدد سجلات outbox المعلقة التي لم تُسلَّم للرئيسي (Cloudflare) بعد —
/// نفس عدّاد زر «رفع التغييرات» في لوحة التحكم (delivered_to_primary=0
/// وغير النهائية) مقصوراً على المصدر المحلي.
final pendingUploadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final db = ref.read(databaseProvider);
  return OutboxDao(db).countUndeliveredToPrimary(sources: ['local']);
});

/// تحديث تلقائي دوري لحالة الاتصال بينما الواجهة معروضة: فحص فوري عند
/// التركيب ثم كل 30 ثانية يصيب /health على Cloudflare Worker عبر
/// [connectionStatusProvider]. مؤقّت واحد فقط ويلغى تلقائياً عند
/// مغادرة الشاشة (autoDispose) — لا تسريب ولا استهلاك خلفي.
final connectionAutoRefreshProvider = Provider.autoDispose<void>((ref) {
  Future<void> check() =>
      ref.read(connectionStatusProvider.notifier).checkConnection();
  unawaited(check());
  final timer = Timer.periodic(const Duration(seconds: 30), (_) => check());
  ref.onDispose(timer.cancel);
});

/// بيانات الربط مع Cloudflare (معرّف الحساب / معرّف قاعدة D1 / التوكن).
/// نفس مصدر الحقيقة الذي يكتبه تبويب Cloudflare D1: المعرّفات في
/// SharedPreferences (cf_d1_account_id / cf_d1_database_id) والتوكن في
/// FlutterSecureStorage (cf_d1_api_token) — مع قيم الحساب المعروفة
/// كافتراضيات للمعرّفات.
final cloudflareBindingProvider =
    FutureProvider.autoDispose<CloudflareD1Config>((ref) async {
      return CloudflareD1Settings.load();
    });

/// إظهار التوكن كاملاً بدل الصيغة المموّهة (الافتراضي: مموّه).
/// حالة عرض محلية بحتة — StateProvider يغني عن أي setState.
final bindingTokenVisibleProvider = StateProvider<bool>((ref) => false);

// ═════════════════════════════════════════════════════════════════
//  تسجيل الارتباط عبر API المباشر (api.cloudflare.com)
// ═════════════════════════════════════════════════════════════════

/// حالة تسجيل الارتباط المباشر: idle → running → نتيجة (نجاح/فشل).
class CloudflareDirectCheckState {
  const CloudflareDirectCheckState({
    this.running = false,
    this.result,
    this.errorMessage,
    this.lastRunAt,
  });

  /// هل الفحص المباشر جارٍ الآن؟
  final bool running;

  /// نتيجة آخر فحص ناجح (أو فاشل بتفاصيله داخل [result]).
  final CloudflareDirectCheckResult? result;

  /// خطأ قبل بدء الفحص أصلاً (مثل غياب التوكن) — نص جاهز للعرض.
  final String? errorMessage;

  /// وقت آخر فحص (للعرض).
  final DateTime? lastRunAt;
}

/// مشغّل «تسجيل الارتباط عبر API المباشر».
///
/// يقرأ بيانات الربط المحفوظة (التوكن/الحساب/القاعدة) ثم يفحصها مباشرةً
/// ضد api.cloudflare.com — نفس أسلوب curl المرجعي `/user/tokens/verify` —
/// ويعيد النتيجة المنظمة للعرض في بطاقة الاتصال. القراءة فقط تماماً:
/// لا كتابة على D1 ولا تعديل إعدادات محفوظة.
class CloudflareDirectCheckNotifier
    extends StateNotifier<CloudflareDirectCheckState> {
  CloudflareDirectCheckNotifier() : super(const CloudflareDirectCheckState());

  bool _busy = false;

  Future<void> run() async {
    if (_busy) return; // منع النقر المزدوج
    _busy = true;
    state = CloudflareDirectCheckState(
      running: true,
      lastRunAt: state.lastRunAt,
    );

    try {
      final config = await CloudflareD1Settings.load();
      final service = CloudflareDirectApiService(config);
      final result = await service.registerConnection();
      state = CloudflareDirectCheckState(
        result: result,
        lastRunAt: DateTime.now(),
      );
    } catch (e) {
      // حزام أمان: registerConnection لا يرمي نظرياً، لكن أي عطل غير
      // متوقع (مثل فشل قراءة التخزين الآمن) يُعرض بوضوح بدل انفجار.
      state = CloudflareDirectCheckState(
        errorMessage: 'تعذر تنفيذ الفحص المباشر: $e',
        lastRunAt: DateTime.now(),
      );
    } finally {
      _busy = false;
    }
  }
}

/// مزود تسجيل الارتباط المباشر — يُستخدم من بطاقة الاتصال.
final cloudflareDirectCheckProvider =
    StateNotifierProvider.autoDispose<CloudflareDirectCheckNotifier,
        CloudflareDirectCheckState>((ref) {
      return CloudflareDirectCheckNotifier();
    });
