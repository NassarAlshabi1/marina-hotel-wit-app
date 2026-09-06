import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloudflare_d1_service.dart';
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
