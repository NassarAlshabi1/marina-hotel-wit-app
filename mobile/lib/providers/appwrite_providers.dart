import 'dart:async';
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
  });
  final bool isConnected;
  final bool isChecking;
  final String? errorMessage;

  ConnectionState copyWith({
    bool? isConnected,
    bool? isChecking,
    String? errorMessage,
  }) {
    return ConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isChecking: isChecking ?? this.isChecking,
      errorMessage: errorMessage ?? this.errorMessage,
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
  ConnectionStatusNotifier(this.ref)
    : super(ConnectionState(isConnected: false));
  final Ref ref;

  /// ✅ (2026-09-05) Cloudflare-only: فحص الاتصال يصيب /health على
  /// Cloudflare Worker — كان يفحص Appwrite Cloud (primary+secondary).
  Future<void> checkConnection() async {
    state = state.copyWith(isChecking: true);
    try {
      final res = await http
          .get(Uri.parse('${CloudflareConfig.workerUrl}/health'))
          .timeout(const Duration(seconds: 8));
      final isConnected = res.statusCode == 200;
      state = ConnectionState(
        isConnected: isConnected,
        errorMessage: isConnected ? null : 'فشل الاتصال بـ Cloudflare Worker',
      );
    } catch (e) {
      state = ConnectionState(
        isConnected: false,
        errorMessage: 'خطأ في الاتصال: $e',
      );
    }
  }
}
