import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:http/http.dart' as http;

import '../services/appwrite_cache_manager.dart';
import '../services/appwrite_logger.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/cloudflare_config.dart';
import '../services/daos/outbox_dao.dart';
import '../services/providers.dart';
import '../services/unified_sync_orchestrator.dart';
import '../services/worker_endpoints.dart';
import '../utils/env.dart';

/// مزود مدير المزامنة
/// ✅ (2026-09-05) Cloudflare-only: AppwriteSyncManager هو
/// CloudflareSyncManager (typedef) — لا خدمة Appwrite بعد الآن.
final appwriteSyncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  final database = ref.watch(databaseProvider);
  final manager = AppwriteSyncManager(database: database);

  ref.onDispose(manager.dispose);

  return manager;
});

/// ✅ (2026-09-10) مؤشرات المزامنة الحيّة — تدفق حالة
/// [CloudflareSyncManager] الحقيقية (syncing/success/failed/idle).
///
/// كان `SyncIndicator` يستمع إلى `syncStateProvider` من SyncOrchestrator
/// الذي لا يُهيّأ أبداً (لا adapters تسجَّل ولا أحد يستدعي initialize)
/// فبقي المؤشر فارغاً إلى الأبد — بينما التدفق الحقيقي للمدير
/// (syncStatusStream) لا يستمعه أحد. هذا الـ Provider هو الجسر:
/// UI ← StreamProvider ← syncStatusStream ← دورة sync() الفعلية.
///
/// نبثّ الحالة الحالية فور الاشتراك (الـ broadcast stream الأصلي لا
/// يُعيد آخر حدث، فبقي UI على AsyncLoading إلى الأبد قبل هذا).
final cloudflareSyncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final manager = ref.watch(appwriteSyncManagerProvider);
  late StreamController<SyncStatus> controller;
  controller = StreamController<SyncStatus>(
    onListen: () {
      controller.add(manager.currentStatus);
      manager.syncStatusStream.listen(
        controller.add,
        onError: controller.addError,
        cancelOnError: false,
      );
    },
  );
  ref.onDispose(controller.close);
  return controller.stream;
});

/// مزود لقطة حالة تسجيل الدخول للمدير (token/initError/جهاز) —
/// تُقرأ كل مرة تُبنى فيها الشاشة (غير تفاعلية: Manger لا يبثّ تغيّر
/// token كبثّ، لذا تُحدَّث عند إعادة القراءة بعد initialize اليدوي).
final cloudflareLoginSnapshotProvider = Provider<Map<String, Object?>>((ref) {
  final manager = ref.watch(appwriteSyncManagerProvider);
  return <String, Object?>{
    'isLoggedIn': manager.isAvailable,
    'initError': manager.initError,
    'lastError': manager.lastError,
    'deviceId': manager.currentDeviceId,
    'username': CloudflareConfig.username,
    'workerUrl': CloudflareConfig.workerUrl,
  };
});

/// ✅ (2026-09-10) مؤشر تقدم السحب الكامل — طلب المستخدم: «مؤشر السحب
/// الكامل يجب أن أعرف مسار حجم السحب والمتبقي ويجب أن لا يعيق الانتقال».
/// تدفق [SyncPullProgress] الحقيقي (pulled/remaining/pages) — بثّ غير
/// حاجب: الشاشات تتنقل بحرية والمؤشر يحدّث نفسه من الخلفية.
///
/// نبثّ lastPullProgress فور الاشتراك (الشاشة المتأخرة لا تنتظر الصفحة
/// القادمة)، ثم كل تحديث لاحق من دورة السحب.
final cloudflarePullProgressProvider = StreamProvider<SyncPullProgress>((
  ref,
) {
  final manager = ref.watch(appwriteSyncManagerProvider);
  late StreamController<SyncPullProgress> controller;
  controller = StreamController<SyncPullProgress>(
    onListen: () {
      controller.add(manager.lastPullProgress);
      manager.syncPullProgressStream.listen(
        controller.add,
        onError: controller.addError,
        cancelOnError: false,
      );
    },
  );
  ref.onDispose(controller.close);
  return controller.stream;
});

final unifiedSyncOrchestratorProvider = Provider<UnifiedSyncOrchestrator>((
  ref,
) {
  // ✅ إصلاح Gemini: استخدام ref.watch بدلاً من ref.read داخل provider
  final appwriteSync = ref.watch(appwriteSyncManagerProvider);
  final db = ref.watch(databaseProvider);
  final orch = UnifiedSyncOrchestrator.instance;
  unawaited(orch.initialize(appwrite: appwriteSync, database: db));
  return orch;
});

final unifiedSyncStateProvider = StreamProvider<UnifiedSyncState>((ref) {
  final orch = ref.watch(unifiedSyncOrchestratorProvider);
  ref.onDispose(orch.dispose);
  return orch.stateStream;
});

/// مزود مدير الذاكرة المؤقتة
final appwriteCacheManagerProvider = Provider<AppwriteCacheManager>((ref) {
  return AppwriteCacheManager();
});

/// مزود المسجل
final appwriteLoggerProvider = Provider<AppwriteLogger>((ref) {
  return AppwriteLogger();
});

// ============ State Providers ============

/// مزود حالة الاتصال
final connectionStatusProvider =
    StateNotifierProvider<ConnectionStatusNotifier, ConnectionState>((ref) {
      return ConnectionStatusNotifier(ref);
    });

/// ✅ (2026-09-29) C7: نوع فشل فحص D1 — كل نوع يستحق إجراءً مختلفاً،
/// وجمعها تحت «D1 لا تستجيب» كان يدفع لمعالجات خاطئة (تغيير binding
/// لمشكلة جلسة، أو إعادة شبكة لمشكلة تحديد معدل).
enum D1ProbeFailure {
  /// 401/403 — التوكن مرفوض (تدوير JWT_SECRET). D1 لم تُفحص فعلياً.
  auth,

  /// 429 — تحديد معدل. D1 لم تُفحص فعلياً؛ تُعاد المحاولة تلقائياً.
  rateLimited,

  /// 503 أو d1 != ok — الـ Worker أجاب لكن قاعدة D1/binding لا تستجيب.
  unavailable,

  /// رد غير متوقع (رمز آخر أو جسم غير مفهوم).
  unexpected,

  /// استثناء شبكة أثناء طلب فحص D1 نفسه (بعد نجاح /health).
  network,
}

/// ✅ (2026-09-29) C7: عنوان صادق لكل نوع فشل في فحص D1 — 401/429 لا
/// تعني أن D1 معطلة (لم تُفحص أصلاً)، وإظهارها تحت «D1 لا تستجيب» كان
/// يدفع لمعالجة خاطئة. مشترك مع مؤشر المزامنة.
String d1FailureHeadline(D1ProbeFailure? failure) {
  switch (failure) {
    case D1ProbeFailure.auth:
      return 'السحابة متصلة — جلسة المزامنة مرفوضة (إعادة دخول تلقائية)';
    case D1ProbeFailure.rateLimited:
      return 'السحابة متصلة — كثرة طلبات مؤقتاً';
    case D1ProbeFailure.network:
      return 'السحابة متصلة — انقطع طلب فحص D1';
    case D1ProbeFailure.unavailable:
    case D1ProbeFailure.unexpected:
    case null:
      return 'السحابة متصلة — قاعدة D1 لا تستجيب';
  }
}

class ConnectionState {
  ConnectionState({
    required this.isConnected,
    this.isChecking = false,
    this.errorMessage,
    this.isD1Connected,
    this.d1LatencyMs,
    this.d1Error,
    this.d1Failure,
    this.lastCheckedAt,
  });
  final bool isConnected;
  final bool isChecking;
  final String? errorMessage;

  /// ✅ (2026-09-17) فحص المسار الكامل: هل قاعدة D1 نفسها تستجيب عبر
  /// /api/health/d1 (شبكة → worker → مصادقة → D1)؟
  /// null = لم يُفحص بعد (لا جلسة دخول بعد، أو الـ Worker غير قابل للوصول).
  final bool? isD1Connected;

  /// زمن استجابة استعلام D1 بالميلي ثانية (من الخادم) — null عند الغياب.
  final int? d1LatencyMs;

  /// سبب نصي عند فشل فحص D1 (مثل انتهاء صلاحية الجلسة).
  final String? d1Error;

  /// نوع فشل فحص D1 (null عند النجاح أو عدم الفحص) — للواجهة كي تعرض
  /// عنواناً صادقاً لكل نوع بدل «D1 لا تستجيب» للجميع.
  final D1ProbeFailure? d1Failure;

  /// وقت آخر فحص مكتمل — null يعني «لم يُنفّذ أي فحص بعد» (يمنع وميض
  /// الأحمر عند الإقلاع قبل اكتمال أول فحص تلقائي).
  final DateTime? lastCheckedAt;

  ConnectionState copyWith({
    bool? isConnected,
    bool? isChecking,
    String? errorMessage,
    bool? isD1Connected,
    int? d1LatencyMs,
    String? d1Error,
    D1ProbeFailure? d1Failure,
    DateTime? lastCheckedAt,
  }) {
    return ConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      errorMessage: errorMessage ?? this.errorMessage,
      isD1Connected: isD1Connected ?? this.isD1Connected,
      d1LatencyMs: d1LatencyMs ?? this.d1LatencyMs,
      d1Error: d1Error ?? this.d1Error,
      d1Failure: d1Failure ?? this.d1Failure,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    );
  }
}

// ============ Data Providers ============

/// سجلات AppwriteLogger (اسم تاريخي — مسجل عام للتطبيق)
final appwriteLogsProvider = Provider<List<LogEntry>>((ref) {
  return AppwriteLogger().entries;
});

/// مزود إحصائيات المزامنة
final syncStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  final syncManager = ref.watch(appwriteSyncManagerProvider);
  return syncManager.getSyncStatistics();
});

final outboxCountProvider = StreamProvider.autoDispose<int>((ref) {
  final db = ref.watch(databaseProvider);
  final dao = OutboxDao(db);
  // ✅ فصل هندسي: نراقب فقط عناصر source='local' (تغييرات محلية)
  return dao.watchCount(sources: const ['local']);
});

class ConnectionStatusNotifier extends StateNotifier<ConnectionState> {
  ConnectionStatusNotifier(this.ref, {http.Client? client, this.clientFactory})
    : _injectedClient = client,
      super(ConnectionState(isConnected: false));
  final Ref ref;

  /// مصنع العملاء للاختبارات — يحقن عدّاداً لإثبات «عميل جديد لكل
  /// فحص». الإنتاج (null) يبني [http.Client] حقيقياً جديداً كل مرة.
  final http.Client Function()? clientFactory;

  /// عميل محقون للاختبارات فقط — يُستخدم كما هو ولا يُغلق بين الفحوص.
  /// الإنتاج (null) يبني عميلاً جديداً لكل فحص ويغلقه بعده (راجع
  /// [_runCheck]): عميل واحد لعمر الجلسة كان يحتفظ بوصلات keep-alive
  /// ميتة (الخادم/الشبكة يغلقها بصمت) فيفشل كل فحص لاحق → شارة حمراء
  /// دائمة بعد فترة استخدام رغم سلامة الشبكة والمزامنة.
  final http.Client? _injectedClient;

  /// مهلة كل طلب فحص (/health أو /api/health/d1) على مرشح واحد.
  static const Duration _probeTimeout = Duration(seconds: 8);

  /// فحص جارٍ — الاستدعاءات المتزامنة (الإقلاع + المراقب + المؤقت
  /// الدوري + شاشة) تنضم إليه بدل مضاعفة الطلبات وتسابق النتائج.
  Future<void>? _inFlight;

  /// ✅ (2026-09-05) Cloudflare-only: فحص الاتصال يصيب /health على
  /// Cloudflare Worker — كان يفحص Appwrite Cloud (primary+secondary).
  ///
  /// ✅ (2026-09-17) فحص المسار الكامل للبيانات: بعد /health (حياة الـ
  /// Worker) وإن كان حياً وتوفرت جلسة دخول، يُفحص D1 نفسه عبر
  /// /api/health/d1 بمصادقة Bearer — نفس المسار الذي تمر به المزامنة.
  ///
  /// ✅ (2026-09-29) C2: الفحص **مراقب لا حَكَم** — كان أي فشل هنا
  /// (8ث عبر http.Client عادي بلا DoH/نفق) يستدعي reportFailure فيُنزّل
  /// الجسر العامل إلى workers.dev المحجوب لمجرد بطء عابر، فتبدأ كل
  /// طلبات المزامنة التالية بالمرشح المحجوب (رفرفة متصل/غير متصل).
  /// الآن: يجرّب المرشحين بالترتيب (الفعّال أولاً) ويرقّي فقط على دليل
  /// إيجابي (reportSuccess للمرشح الذي أجاب 200). التنزيل حكر على
  /// ResilientHttpClient بعد استنفاد مسارَيه (سريع + نفق) — دليل أقوى.
  Future<void> checkConnection() {
    return _inFlight ??= _runCheck().whenComplete(() => _inFlight = null);
  }

  Future<void> _runCheck() async {
    final http.Client? injected = _injectedClient;
    if (injected != null) {
      return _runCheckWith(injected);
    }
    // عميل جديد لكل فحص: وصلات keep-alive القديمة قد تكون ميتة بصمت
    // (NAT/ISP يغلق الخامل) فيفشل الفحص دائماً — الإغلاق في finally.
    final http.Client client = (clientFactory ?? () => http.Client())();
    try {
      await _runCheckWith(client);
    } finally {
      client.close();
    }
  }

  Future<void> _runCheckWith(http.Client client) async {
    if (!mounted) return;
    state = state.copyWith(isChecking: true);
    final candidates = WorkerEndpoints.candidatesFor(
      Uri.parse(CloudflareConfig.workerUrl),
    );
    Object? lastError;
    int? lastStatus;
    for (final base in candidates) {
      final healthUri = base.replace(path: '/health');
      try {
        final res = await client.get(healthUri).timeout(_probeTimeout);
        if (res.statusCode != 200) {
          lastStatus = res.statusCode;
          continue;
        }
        // دليل إيجابي: هذا المرشح يوصل فعلاً — يُثبَّت للمزامنة أيضاً.
        WorkerEndpoints.reportSuccess(base);
        // فحص D1 على نفس القاعدة التي أجابت (لا على active الذي قد
        // يتغير بين الطلبين).
        final d1 = await _probeD1(client, base);
        if (!mounted) return;
        state = ConnectionState(
          isConnected: true,
          isD1Connected: d1?.connected,
          d1LatencyMs: d1?.latencyMs,
          d1Error: d1?.error,
          d1Failure: d1?.failure,
          lastCheckedAt: DateTime.now(),
        );
        return;
      } catch (e) {
        lastError = e;
      }
    }
    if (!mounted) return;
    state = ConnectionState(
      isConnected: false,
      errorMessage: lastError != null
          ? 'خطأ في الاتصال: $lastError'
          : 'فشل الاتصال بـ Cloudflare Worker'
                '${lastStatus == null ? '' : ' (HTTP $lastStatus)'}',
      lastCheckedAt: DateTime.now(),
    );
  }

  /// فحص D1 عبر النقطة المحمية /api/health/d1 بتوكن الجلسة الحالية
  /// ([Env.cloudflareAuthToken] — يُصدَّر عند الدخول من مدير المزامنة).
  /// يعيد null عند غياب الجلسة (D1 «لم يُفحص» وليس «فاشلاً»).
  Future<_D1ProbeResult?> _probeD1(http.Client client, Uri base) async {
    final token = Env.cloudflareAuthToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    final uri = base.replace(path: '/api/health/d1');
    try {
      final res = await client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(_probeTimeout);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body is Map<String, dynamic> && body['d1'] == 'ok') {
          final latency = body['latency_ms'];
          return _D1ProbeResult(
            connected: true,
            latencyMs: latency is num ? latency.toInt() : null,
          );
        }
        return const _D1ProbeResult(
          connected: false,
          failure: D1ProbeFailure.unexpected,
          error: 'استجابة غير متوقعة من فحص D1',
        );
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        // ✅ (2026-09-29) C7: مواءمة مع مسار الدفع — التوكن المرفوض
        // يُبطَل فوراً فتشتعل إعادة الدخول الكسولة في المزامنة القادمة،
        // بدل تكرار 401 في كل فحص حتى يمر دفع لاحق. الإبطال مشروط بأن
        // يكون هو نفس التوكن المفحوص (لا نمسح جلسة أحدث صدرت أثناء الطلب).
        AppwriteSyncManager.instance.invalidateRejectedToken(token);
        return const _D1ProbeResult(
          connected: false,
          failure: D1ProbeFailure.auth,
          error: 'انتهت صلاحية الجلسة — أعد تسجيل الدخول',
        );
      }
      if (res.statusCode == 429) {
        final retryAfter = res.headers['retry-after'];
        return _D1ProbeResult(
          connected: false,
          failure: D1ProbeFailure.rateLimited,
          error:
              'كثرة طلبات (HTTP 429) — إعادة تلقائية'
              '${retryAfter == null ? '' : ' بعد $retryAfter ث'}',
        );
      }
      if (res.statusCode == 503) {
        return const _D1ProbeResult(
          connected: false,
          failure: D1ProbeFailure.unavailable,
          error: 'فحص D1 فشل (HTTP 503)',
        );
      }
      return _D1ProbeResult(
        connected: false,
        failure: D1ProbeFailure.unexpected,
        error: 'فحص D1 فشل (HTTP ${res.statusCode})',
      );
    } catch (e) {
      return _D1ProbeResult(
        connected: false,
        failure: D1ProbeFailure.network,
        error: 'خطأ فحص D1: $e',
      );
    }
  }

  @override
  void dispose() {
    _injectedClient?.close();
    super.dispose();
  }
}

/// نتيجة فحص D1 الداخلية — connected/latencyMs/error فقط.
class _D1ProbeResult {
  const _D1ProbeResult({
    required this.connected,
    this.latencyMs,
    this.error,
    this.failure,
  });
  final bool connected;
  final int? latencyMs;
  final String? error;
  final D1ProbeFailure? failure;
}
