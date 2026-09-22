// sync_service.dart — غلاف توافقي رفيع فوق محرك Cloudflare الوحيد.
//
// ✅ (2026-09-17) إغلاق باب ازدواجية المحركات نهائياً:
// هذا الملف كان يحتوي محرك مزامنة PHP كاملاً (~1100 سطر منطق فعلي من
// أصل 1265): DeltaSyncService.compute() + ApiService.syncPush/syncPull
// إلى خادم XAMPP ميت (hotelmarina.com/MARINA_HOTEL_PORTABLE/api/v1 —
// لا يستجيب أصلاً) + تطبيق الصفوف الواردة يدوياً. الشاشات التسع التي
// تستدعي syncServiceProvider.runSync() كانت تحصل على مهلات/فشل صامت
// بينما تعتقد أنها «تزامنت» — والمسار لا يمكنه لمس Cloudflare معمارياً.
//
// الاستبدال: runSync() يفوّض الآن إلى CloudflareSyncManager.sync()
// (نفس عقد زر المزامنة في الشاشة الرئيسية — المسار الوحيد المعتمد:
// outbox → POST /api/sync/push → Worker → D1، والسحب عبر
// GET /api/sync/pull). delta_sync_service.dart حُذف بالكامل مع هذه
// التغييرة؛ الواجهة العامة (runSync + statusStream + syncStatusProvider)
// أُبقيت كما هي لتسع شاشات وستة ملفات اختبار قائمة دون أي تعديل.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/repository_providers.dart';
import '../utils/debug_log.dart';
import 'appwrite_sync_manager.dart' hide SyncStatus;
import 'local_db.dart';
import 'sync_enums.dart' as cf;

/// مراحل دورة المزامنة اليدوية كما تستهلكها الواجهات القائمة.
enum SyncStatus { idle, pushing, pulling, error }

class SyncService {
  SyncService(this.db);

  final AppDatabase db;

  final _status = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _status.stream;

  /// مزامنة يدوية (رفع + سحب) عبر محرك Cloudflare الوحيد.
  ///
  /// عقد الأخطاء متوافق مع الاستدعاءات القائمة في الشاشات التسع:
  /// - الفشل الحقيقي (status == failed) يُرمى كاستثناء — تعرضه الشاشات
  ///   كرسالة «فشلت المزامنة: ...» تماماً كما كان عقد المحرك القديم.
  /// - kill-switch / الإيقاف عن بُعد (idle) يعود بصمت — لا معنى لإزعاج
  ///   المستخدم برسالة فشل لقرار إداري مقصود.
  /// - partial تُعامل كنجاح: الصفوف المحجورة (الحجر الصحي) يعالجها
  ///   النظام ذاتياً في الدورات القادمة — نفس سلوك زر الشاشة الرئيسية.
  Future<void> runSync() async {
    final manager = AppwriteSyncManager.instance;

    _status.add(SyncStatus.pushing);
    final SyncResult result = await manager.sync(
      forcePull: true,
    );

    if (result.status == cf.SyncStatus.failed) {
      _status.add(SyncStatus.error);
      dlog(() => '❌ فشل في المزامنة: ${result.errorMessage}');
      throw StateError(result.errorMessage ?? 'sync failed');
    }

    _status.add(SyncStatus.idle);
    dlog(
      () =>
          '✅ تمت المزامنة (رفع ${result.recordsPushed}، '
          'سحب ${result.recordsPulled}، تعارضات ${result.conflicts})',
    );
  }

  /// تنظيف الموارد
  void dispose() {
    unawaited(_status.close());
  }
}

final syncServiceProvider = Provider<SyncService>(
  (ref) => SyncService(ref.read(databaseProvider)),
);

final syncStatusProvider = StreamProvider<SyncStatus>(
  (ref) => ref.read(syncServiceProvider).statusStream,
);
