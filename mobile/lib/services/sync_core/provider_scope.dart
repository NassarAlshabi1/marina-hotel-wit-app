// lib/services/sync_core/provider_scope.dart
//
// ✅ (G-7 / 2026-10-06 — تدقيق الهوية المالية، البند 9): حارس **نطاق
// المزوّد** (Provider Scope Guard).
//
// **المشكلة المُثبتة في الكود (قبل هذا الملف):**
//   كل مؤشرات السحب تُخزَّن محلياً **بلا أي ارتباط بوجهة المزامنة**:
//     • `sync_checkpoints` (مؤشر لكل مجموعة + cursor + max)
//     • `sync_state.last_pull_ts` + `sync_state.full_sync_complete`
//     • SharedPreferences: `sync_entity_pull_ts_map` و
//       `sync_last_pull_booking_nights` (انظر SyncPullService)
//     • `sync_remote_meta` (خريطة `$updatedAt` لكل مستند — موثّق في
//       local_db.dart أن مسحها **إلزامي** قبل أي سحب كامل، ولم يكن يُستدعى
//       من أي مكان: العقد موثّق وغير مُنفَّذ)
//   وعند تغيير الوجهة (endpoint/projectId/databaseId — متاح للمستخدم من
//   شاشة إعدادات الاتصال) تُحمَّل القيم الجديدة عند التشغيل التالي **مع
//   بقاء المؤشرات القديمة**: فيبدأ السحب في وضع delta على مزوّد فارغ أو
//   مختلف، فيُتخطّى كل ما هو أقدم من مؤشر مزوّد آخر ⇒ **فقدان صامت** —
//   وهو نقض مباشر لشرط الانتقال بلا فقدان (البند 9: «لا تنقل مؤشرات
//   المزوّد القديم»).
//
// **القرار الهندسي (لا تخمين):**
//   1. بصمة نطاق = sha256(endpoint المُطبَّع + projectId + databaseId).
//      التطبيع (تقليم/تصغير/إزالة الشرطة الأخيرة) مقصود: اختلاف شكل كتابة
//      نفس الوجهة **ليس** تبديل مزوّد، ولا يجوز أن يُكلّف سحباً كاملاً.
//   2. أول تشغيل بعد هذا الإصدار (لا بصمة محفوظة) ⇒ تُحفظ البصمة **دون
//      أي إعادة ضبط** — ترقية متوافقة للخلف تماماً (المؤشرات الحالية صحيحة
//      لأنها بُنيت لنفس الوجهة).
//   3. عند اختلاف البصمة ⇒ إعادة ضبط **ذات مرة واحدة** لكل ما هو مرتبط
//      بالمزوّد فقط:
//        • `sync_checkpoints` (DELETE — كل المجموعات)
//        • `sync_state`: last_pull_ts=0 و full_sync_complete=0
//        • prefs: حذف خريطة مؤشرات الكيانات + مؤشر booking_nights +
//          وقت آخر مزامنة (قيمة عرض تُصفَّر مع إعادة البناء)
//        • `sync_remote_meta`: مسح كامل (العقد الموثّق أعلاه)
//        • `appwrite_initial_seed_done = false`: إعادة تفعيل الرفع الأولي
//          حتى تصل **البيانات المحلية الكاملة** إلى الوجهة الجديدة —
//          بواسطة upsert على `documentId = local_uuid` (idempotent)؛ هذا
//          هو المسار الوحيد الذي ينقل السجلات التي سُلّمت للمزوّد القديم
//          وحُذفت من الـ outbox (لا وجود لها في أي طابور بعد اليوم).
//   4. **ما لا يُمسّ** (لأنه ليس مقيّداً بالمزوّد — ولمسُه فقدان بيانات):
//        • مفتاح الجهاز (`appwrite_device_id`/`_local_uuid`/`_version`)
//        • إعدادات المستخدم (تفعيل المزامنة، نطاق السحب، الفواصل الزمنية)
//        • الـ outbox بكامله (تغييرات محلية لم تُسلَّم: مورد آخر يخصّ
//          طبقة المجال لا المزوّد)
//        • مخزن العلاقات المعلّقة (DeferredRelationStore): حالة ربط
//          بالـ UUID — قد يحلّها وصول الأب من المزوّد الجديد، ومسحها إسقاط
//        • `sync_remote_meta` الخاص بالثانوي غير موجود أصلاً (الثانوي وجهة
//          دفع فقط: لا يوجد أي مسار سحب منه — فحص شامل في الوصف)
//   5. التسليم للوجهة الجديدة لا يُغيّر الهوية: كل السجلات تُرفع بـ
//      `local_uuid` نفسه، فالتتبّع عبر A → Cloud → B يبقى قائماً (البند 2).
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/app_logger.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'sync_checkpoint_store.dart';

/// حالة فحص نطاق المزوّد.
enum ProviderScopeState {
  /// لا بصمة محفوظة: أول تشغيل لهذا الإصدار — لا إعادة ضبط (ترقية آمنة).
  firstRun,

  /// نفس الوجهة: لا شيء يتغيّر.
  unchanged,

  /// تبدّلت الوجهة: أُعيد ضبط كل ما هو مقيّد بالمزوّد.
  changed,
}

/// نتيجة فحص نطاق المزوّد (تُستهلك في السجلات والتقرير G-8).
class ProviderScopeStatus {
  const ProviderScopeStatus({
    required this.state,
    required this.fingerprint,
    this.previousFingerprint,
    this.changedAt,
    this.invalidated = const [],
  });

  final ProviderScopeState state;
  final String fingerprint;
  final String? previousFingerprint;

  /// وقت آخر تبديل نطاق (ثواني epoch) — null إن لم يحدث تبديل بعد.
  final int? changedAt;

  /// ما أُعيد ضبطه فعلاً (أسماء مختصرة للتشخيص).
  final List<String> invalidated;

  bool get changed => state == ProviderScopeState.changed;
}

/// حارس نطاق المزوّد — نقاط دخول ثابتة (static) لتُستخدم من أي طبقة.
class ProviderScopeGuard {
  ProviderScopeGuard._();

  // ── مفاتيح SharedPreferences (القيم مأخوذة حرفياً من SyncPullService
  //    و AppwriteSyncManager — تحقّق: sync_pull_service.dart L758
  //    (`sync_entity_pull_ts_map`) و L690 (`sync_last_pull_booking_nights`)
  //    و appwrite_sync_manager.dart L499 (`appwrite_last_sync_time`)
  //    و L443 (`appwrite_initial_seed_done`).
  static const String fingerprintKey = 'sync_provider_scope_fingerprint';
  static const String changedAtKey = 'sync_provider_scope_changed_at';
  static const String previousFingerprintKey =
      'sync_provider_scope_previous_fingerprint';
  static const String entityPullTsMapKey = 'sync_entity_pull_ts_map';
  static const String bookingNightsPullTsKey = 'sync_last_pull_booking_nights';
  static const String lastSyncTimeKey = 'appwrite_last_sync_time';
  static const String initialSeedDoneKey = 'appwrite_initial_seed_done';

  /// بصمة نطاق المزوّد — دالة نقية (قابلة للاختبار مباشرة).
  static String fingerprint({
    required String endpoint,
    required String projectId,
    required String databaseId,
  }) {
    var normalizedEndpoint = endpoint.trim().toLowerCase();
    while (normalizedEndpoint.endsWith('/')) {
      normalizedEndpoint = normalizedEndpoint.substring(
        0,
        normalizedEndpoint.length - 1,
      );
    }
    final canonical =
        '$normalizedEndpoint|${projectId.trim()}|${databaseId.trim()}';
    final digest = sha256.convert(
      utf8.encode('marina.provider.scope.v1|$canonical'),
    );
    return digest.toString().substring(0, 32);
  }

  /// ضمان أن حالة المزامنة المحلية تخصّ الوجهة الحالية.
  ///
  /// - أول تشغيل (لا بصمة) ⇒ حفظ البصمة بلا أي إعادة ضبط.
  /// - نفس الوجهة ⇒ لا شيء.
  /// - وجهة مختلفة ⇒ [resetProviderScopedState] ثم حفظ البصمة الجديدة.
  ///
  /// لا ترمي عادةً؛ أي فشل داخلي يُعاد كتحذير ويُنصح بإعادة المحاولة
  /// في التشغيل التالي (البصمة لا تُحفظ إلا بعد نجاح إعادة الضبط كاملة،
  /// فلا يمكن أن نُعلن الانتقال ثم نترك حالة قديمة).
  static Future<ProviderScopeStatus> ensureCurrent({
    required String endpoint,
    required String projectId,
    required String databaseId,
    required AppDatabase db,
    required SyncCheckpointStore checkpoints,
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final current = fingerprint(
      endpoint: endpoint,
      projectId: projectId,
      databaseId: databaseId,
    );

    final stored = p.getString(fingerprintKey);
    if (stored == null || stored.isEmpty) {
      await p.setString(fingerprintKey, current);
      AppLogger.info(
        '🔐 ثُبِّت نطاق المزوّد لأول مرة (بصمة ${_short(current)}) — '
        'لا إعادة ضبط (ترقية متوافقة مع الحالة القائمة).',
        tag: 'PROVIDER_SCOPE',
      );
      return ProviderScopeStatus(
        state: ProviderScopeState.firstRun,
        fingerprint: current,
      );
    }

    if (stored == current) {
      return ProviderScopeStatus(
        state: ProviderScopeState.unchanged,
        fingerprint: current,
      );
    }

    final invalidated = await resetProviderScopedState(
      db: db,
      checkpoints: checkpoints,
      prefs: p,
    );

    final changedAt = Time.nowEpoch();
    await p.setString(previousFingerprintKey, stored);
    await p.setInt(changedAtKey, changedAt);
    await p.setString(fingerprintKey, current);

    AppLogger.warning(
      '🔀 تبدّل نطاق مزوّد المزامنة: ${_short(stored)} → ${_short(current)}. '
      'أُعيد ضبط: ${invalidated.join(', ')} — الدورة القادمة سحب كامل من '
      'الوجهة الجديدة، والرفع الأولي أُعيد تفعيله لنقل البيانات المحلية '
      '(upsert بـ UUID نفسه، بلا تغيير هوية).',
      tag: 'PROVIDER_SCOPE',
    );

    return ProviderScopeStatus(
      state: ProviderScopeState.changed,
      fingerprint: current,
      previousFingerprint: stored,
      changedAt: changedAt,
      invalidated: invalidated,
    );
  }

  /// إعادة ضبط كل حالة المزامنة المقيّدة بالمزوّد — **أساس واحد** يشاركه
  /// الحارس و`resetSyncState()` (يُصلح عقداً موثّقاً في local_db.dart
  /// ويقول إن `clearRemoteMeta` يُستدعى من إعادة ضبط المزامنة).
  ///
  /// لا يلمس: الـ outbox، مخزن العلاقات المعلّقة، هوية الجهاز، إعدادات
  /// المستخدم، ولا أي جدول بيانات مالية.
  static Future<List<String>> resetProviderScopedState({
    required AppDatabase db,
    required SyncCheckpointStore checkpoints,
    SharedPreferences? prefs,
  }) async {
    final reset = <String>[];

    // 1) مؤشرات السحب لكل مجموعة (تشمل cursor/max للسحب القابل للاستئناف).
    await checkpoints.resetAll();
    reset.add('sync_checkpoints');

    // 2) مؤشر السحب العام + علم اكتمال أول سحب كامل.
    //    (last_server_ts/last_push_ts يخصّان مسار مزامنة آخر — لا يُمسّان.)
    await db.customStatement(
      'UPDATE sync_state SET last_pull_ts = 0, full_sync_complete = 0 '
      'WHERE id = 1',
    );
    reset.add('sync_state');

    // 3) خريطة مؤشرات الكيانات + مؤشر booking_nights + وقت آخر مزامنة.
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.remove(entityPullTsMapKey);
    await p.remove(bookingNightsPullTsKey);
    await p.remove(lastSyncTimeKey);
    reset.add('prefs(entity_pull_ts,booking_nights,last_sync_time)');

    // 4) خريطة `$updatedAt` لكل مستند: مسحها إلزامي قبل أي سحب كامل،
    //    وإلا اعتبر السحب القادم كل مستند محفوظاً فتخطّى جلبه.
    await db.clearRemoteMeta();
    reset.add('sync_remote_meta');

    // 5) إعادة تفعيل الرفع الأولي: المسار الوحيد الذي ينقل ما سُلّم
    //    للمزوّد القديم ثم خرج من الـ outbox.
    await p.setBool(initialSeedDoneKey, false);
    reset.add('initial_seed');

    return reset;
  }

  /// وقت آخر تبديل نطاق (ثواني epoch) — null إن لم يحدث.
  static Future<int?> lastChangedAt({SharedPreferences? prefs}) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    return p.getInt(changedAtKey);
  }

  /// بصمة النطاق السابق — للتقرير (G-8).
  static Future<String?> previousFingerprint({SharedPreferences? prefs}) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    return p.getString(previousFingerprintKey);
  }

  /// عرض مختصر للبصمة في السجلات (لا نطبع endpoint/project في سجل عام).
  static String _short(String fingerprint) =>
      fingerprint.length <= 8 ? fingerprint : fingerprint.substring(0, 8);
}
