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
import '../services/smart_sync_manager.dart';
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
  final smart = SmartSyncManager.instance;
  final orch = UnifiedSyncOrchestrator.instance;
  unawaited(
    orch.initialize(appwrite: appwriteSync, smart: smart, database: db),
  );
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

class ConnectionState {
  ConnectionState({
    required this.isConnected,
    this.isChecking = false,
    this.errorMessage,
    this.isD1Connected,
    this.d1LatencyMs,
    this.d1Error,
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
    DateTime? lastCheckedAt,
  }) {
    return ConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      errorMessage: errorMessage ?? this.errorMessage,
      isD1Connected: isD1Connected ?? this.isD1Connected,
      d1LatencyMs: d1LatencyMs ?? this.d1LatencyMs,
      d1Error: d1Error ?? this.d1Error,
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
  ConnectionStatusNotifier(this.ref, {http.Client? client})
    : _client = client ?? http.Client(),
      super(ConnectionState(isConnected: false));
  final Ref ref;
  final http.Client _client;

  /// ✅ (2026-09-05) Cloudflare-only: فحص الاتصال يصيب /health على
  /// Cloudflare Worker — كان يفحص Appwrite Cloud (primary+secondary).
  ///
  /// ✅ (2026-09-17) فحص المسار الكامل للبيانات: بعد /health (حياة الـ
  /// Worker) وإن كان حياً وتوفرت جلسة دخول، يُفحص D1 نفسه عبر
  /// /api/health/d1 بمصادقة Bearer — نفس المسار الذي تمر به المزامنة
  /// فعلياً. النجاح/الفشل يُبلَّغان لـ [WorkerEndpoints] فيشارك الفحص
  /// في تثبيت/تدوير نقطة النهاية (sticky failover) كطلبات المزامنة.
  Future<void> checkConnection() async {
    state = state.copyWith(isChecking: true);
    final healthUri = Uri.parse('${CloudflareConfig.workerUrl}/health');
    try {
      final res = await _client
          .get(healthUri)
          .timeout(const Duration(seconds: 8));
      final isConnected = res.statusCode == 200;
      if (isConnected) {
        WorkerEndpoints.reportSuccess(healthUri);
      } else {
        WorkerEndpoints.reportFailure(healthUri);
      }

      // فحص D1 لا معنى له إلا إذا أجاب الـ Worker أصلاً.
      final d1 = isConnected ? await _probeD1() : null;

      state = ConnectionState(
        isConnected: isConnected,
        errorMessage: isConnected ? null : 'فشل الاتصال بـ Cloudflare Worker',
        isD1Connected: d1?.connected,
        d1LatencyMs: d1?.latencyMs,
        d1Error: d1?.error,
        lastCheckedAt: DateTime.now(),
      );
    } catch (e) {
      WorkerEndpoints.reportFailure(healthUri);
      state = ConnectionState(
        isConnected: false,
        errorMessage: 'خطأ في الاتصال: $e',
        lastCheckedAt: DateTime.now(),
      );
    }
  }

  /// فحص D1 عبر النقطة المحمية /api/health/d1 بتوكن الجلسة الحالية
  /// ([Env.cloudflareAuthToken] — يُصدَّر عند الدخول من مدير المزامنة).
  /// يعيد null عند غياب الجلسة (D1 «لم يُفحص» وليس «فاشلاً»).
  Future<_D1ProbeResult?> _probeD1() async {
    final token = Env.cloudflareAuthToken;
    if (token == null || token.isEmpty) {
      return null;
    }
    final uri = Uri.parse('${CloudflareConfig.workerUrl}/api/health/d1');
    try {
      final res = await _client
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 8));
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
          error: 'استجابة غير متوقعة من فحص D1',
        );
      }
      if (res.statusCode == 401) {
        return const _D1ProbeResult(
          connected: false,
          error: 'انتهت صلاحية الجلسة — أعد تسجيل الدخول',
        );
      }
      return _D1ProbeResult(
        connected: false,
        error: 'فحص D1 فشل (HTTP ${res.statusCode})',
      );
    } catch (e) {
      return _D1ProbeResult(connected: false, error: 'خطأ فحص D1: $e');
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

/// نتيجة فحص D1 الداخلية — connected/latencyMs/error فقط.
class _D1ProbeResult {
  const _D1ProbeResult({required this.connected, this.latencyMs, this.error});
  final bool connected;
  final int? latencyMs;
  final String? error;
}
