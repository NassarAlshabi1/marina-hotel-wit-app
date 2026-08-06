import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'appwrite_config.dart';
import 'appwrite_config_manager.dart';
import 'secondary_appwrite_config.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// حالة كل وجهة من وجهات Appwrite
enum EndpointHealth {
  /// لم يُفحص بعد
  unknown,

  /// الوجهة تعمل بشكل طبيعي
  healthy,

  /// الوجهة لا تستجيب (timeout أو خطأ شبكة)
  unreachable,

  /// خطأ مصادقة/صلاحيات (401/403)
  authError,

  /// خطأ في الإعدادات (مثل عدم التهيئة)
  configError,
}

/// حالة الوجهتين معاً
class AppwriteHealthState {
  const AppwriteHealthState({
    required this.primaryHealth,
    required this.secondaryHealth,
    required this.lastCheckedAt,
    this.primaryLatencyMs,
    this.secondaryLatencyMs,
    this.primaryError,
    this.secondaryError,
  });

  /// الحالة الافتراضية عند بدء التطبيق
  static const initial = AppwriteHealthState(
    primaryHealth: EndpointHealth.unknown,
    secondaryHealth: EndpointHealth.unknown,
    lastCheckedAt: null,
  );

  final EndpointHealth primaryHealth;
  final EndpointHealth secondaryHealth;
  final DateTime? lastCheckedAt;
  final int? primaryLatencyMs;
  final int? secondaryLatencyMs;
  final String? primaryError;
  final String? secondaryError;

  /// هل الوجهة الرئيسية متاحة للقراءة؟
  bool get isPrimaryAvailable =>
      primaryHealth == EndpointHealth.healthy ||
      primaryHealth == EndpointHealth.unknown; // نُحاول قبل الفشل

  /// هل الوجهة الثانوية متاحة للقراءة؟
  bool get isSecondaryAvailable => secondaryHealth == EndpointHealth.healthy;

  /// هل نحتاج لتفعيل وضع Failover (Primary معطّل، Secondary متاح)؟
  bool get shouldFailover =>
      primaryHealth == EndpointHealth.unreachable &&
      secondaryHealth == EndpointHealth.healthy;

  /// الوجهة المُفضّلة للقراءة حالياً (Primary أولاً، ثم Secondary عند الفشل)
  String get preferredReadSource {
    if (shouldFailover) return 'secondary';
    return 'primary';
  }

  AppwriteHealthState copyWith({
    EndpointHealth? primaryHealth,
    EndpointHealth? secondaryHealth,
    DateTime? lastCheckedAt,
    int? primaryLatencyMs,
    int? secondaryLatencyMs,
    String? primaryError,
    String? secondaryError,
  }) {
    return AppwriteHealthState(
      primaryHealth: primaryHealth ?? this.primaryHealth,
      secondaryHealth: secondaryHealth ?? this.secondaryHealth,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      primaryLatencyMs: primaryLatencyMs ?? this.primaryLatencyMs,
      secondaryLatencyMs: secondaryLatencyMs ?? this.secondaryLatencyMs,
      primaryError: primaryError ?? this.primaryError,
      secondaryError: secondaryError ?? this.secondaryError,
    );
  }

  @override
  String toString() =>
      'AppwriteHealthState(primary=$primaryHealth, secondary=$secondaryHealth, '
      'failover=$shouldFailover)';
}

/// Notifier يدير حالة صحة الوجهتين ويوفّرها للـ UI
///
/// ✅ P1-9 FIX (2026-08-06 Audit): تحويل لـ singleton pattern.
/// سابقاً كان main.dart يُنشأ instance #1 ويبدأ الفحص الدوري، بينما
/// Riverpod provider يُنشأ instance #2 منفصل عند أول ref.watch.
/// النتيجة: الـ UI يقرأ من instance #2 الذي state = initial دائماً،
/// ولا يرى تحديثات الفحص الدوري من instance #1.
/// الإصلاح: factory constructor يُرجع نفس الـ instance دائماً،
/// مما يضمن أن main.dart و Riverpod يستخدمان نفس الـ object.
class AppwriteHealthNotifier extends StateNotifier<AppwriteHealthState> {
  AppwriteHealthNotifier._() : super(AppwriteHealthState.initial);

  /// Singleton instance — يُستخدم من main.dart و Riverpod provider.
  static final AppwriteHealthNotifier instance = AppwriteHealthNotifier._();

  /// Factory constructor يُرجع نفس الـ instance دائماً.
  factory AppwriteHealthNotifier() => instance;

  Timer? _checkTimer;
  bool _isChecking = false;

  /// بدء الفحص الدوري كل [interval] (افتراضياً 30 ثانية)
  void startPeriodicCheck({Duration interval = const Duration(seconds: 30)}) {
    stopPeriodicCheck();
    // فحص فوري عند البدء
    checkNow();
    _checkTimer = Timer.periodic(interval, (_) => checkNow());
    dlog(() => '🏥 [HealthChecker] Started periodic check every ${interval.inSeconds}s');
  }

  /// إيقاف الفحص الدوري
  void stopPeriodicCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// فحص فوري لحالة الوجهتين
  Future<void> checkNow() async {
    if (_isChecking) return; // منع التراكب
    _isChecking = true;

    try {
      final results = await Future.wait([_checkPrimary(), _checkSecondary()]);

      final primaryResult = results[0];
      final secondaryResult = results[1];

      state = AppwriteHealthState(
        primaryHealth: primaryResult.health,
        secondaryHealth: secondaryResult.health,
        lastCheckedAt: DateTime.now(),
        primaryLatencyMs: primaryResult.latencyMs,
        secondaryLatencyMs: secondaryResult.latencyMs,
        primaryError: primaryResult.error,
        secondaryError: secondaryResult.error,
      );

      // ✅ تحديث الـ singleton للوصول من خارج Riverpod
      AppwriteHealthStatus.instance.update(state);

      // تسجيل تغييرات الحالة المهمة
      if (state.shouldFailover) {
        dlog('⚠️ [HealthChecker] FAILOVER ACTIVE — reading from Secondary');
      } else if (primaryResult.health == EndpointHealth.unreachable) {
        dlog('⚠️ [HealthChecker] Primary unreachable but Secondary not available');
      }
    } catch (e) {
      dlog(() => '❌ [HealthChecker] checkNow failed: $e');
    } finally {
      _isChecking = false;
    }
  }

  /// فحص الوجهة الرئيسية
  /// نحاول قراءة مستند واحد من collection 'rooms' كاختبار سريع
  Future<_HealthCheckResult> _checkPrimary() async {
    try {
      final client = Client()
          .setEndpoint(AppwriteConfig.endpoint)
          .setProject(AppwriteConfig.projectId);

      final apiKey = AppwriteConfigManager.apiKey;
      if (apiKey.isNotEmpty) {
        client.addHeader('X-Appwrite-Key', apiKey);
      }

      final db = Databases(client);
      final stopwatch = Stopwatch()..start();

      await db
          // ignore: deprecated_member_use
          .listDocuments(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: AppwriteConfig.roomsCollectionId,
            queries: [Query.limit(1)],
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();
      return _HealthCheckResult(
        health: EndpointHealth.healthy,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on AppwriteException catch (e) {
      final health = (e.code == 401 || e.code == 403)
          ? EndpointHealth.authError
          : EndpointHealth.unreachable;
      return _HealthCheckResult(
        health: health,
        error: '${e.code}: ${e.message}',
      );
    } catch (e) {
      return _HealthCheckResult(
        health: EndpointHealth.unreachable,
        error: e.toString(),
      );
    }
  }

  /// فحص الوجهة الثانوية (فقط إذا كانت مُفعّلة ومُعدّة)
  Future<_HealthCheckResult> _checkSecondary() async {
    if (!SecondaryAppwriteConfig.isEnabled) {
      return const _HealthCheckResult(
        health: EndpointHealth.unknown,
        error: 'Secondary disabled',
      );
    }

    if (!SecondaryAppwriteConfig.isConfigured) {
      return const _HealthCheckResult(
        health: EndpointHealth.configError,
        error: 'Secondary not configured',
      );
    }

    try {
      final client = Client()
          .setEndpoint(SecondaryAppwriteConfig.endpoint)
          .setProject(SecondaryAppwriteConfig.projectId);

      final apiKey = SecondaryAppwriteConfig.apiKey;
      if (apiKey.isNotEmpty) {
        client.addHeader('X-Appwrite-Key', apiKey);
      }

      final db = Databases(client);
      final stopwatch = Stopwatch()..start();

      await db
          // ignore: deprecated_member_use
          .listDocuments(
            databaseId: SecondaryAppwriteConfig.databaseId,
            collectionId: AppwriteConfig.roomsCollectionId,
            queries: [Query.limit(1)],
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();
      return _HealthCheckResult(
        health: EndpointHealth.healthy,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on AppwriteException catch (e) {
      final health = (e.code == 401 || e.code == 403)
          ? EndpointHealth.authError
          : EndpointHealth.unreachable;
      return _HealthCheckResult(
        health: health,
        error: '${e.code}: ${e.message}',
      );
    } catch (e) {
      return _HealthCheckResult(
        health: EndpointHealth.unreachable,
        error: e.toString(),
      );
    }
  }

  @override
  void dispose() {
    // Singleton: intentionally NOT calling super.dispose() so the
    // app-lifetime Timer can keep updating state. Explicit teardown
    // must go through stopPeriodicCheck() (call it on app shutdown).
    // NOTE: verify a shutdown path calls stopPeriodicCheck().
  }
}

/// نتيجة فحص وجهة واحدة
class _HealthCheckResult {
  const _HealthCheckResult({required this.health, this.latencyMs, this.error});

  final EndpointHealth health;
  final int? latencyMs;
  final String? error;
}

/// Provider لحالة صحة الوجهتين
///
/// ✅ P1-9 FIX (2026-08-06 Audit): يُعيد نفس الـ singleton instance
/// الذي يستخدمه main.dart، مما يضمن أن الـ UI يرى تحديثات الفحص الدوري.
final appwriteHealthProvider =
    StateNotifierProvider<AppwriteHealthNotifier, AppwriteHealthState>((ref) {
      return AppwriteHealthNotifier.instance;
    });

/// Singleton للوصول للحالة الحالية من خارج Riverpod (مثل main.dart)
///
/// يُحدّث تلقائياً من قبل AppwriteHealthNotifier عند كل فحص.
class AppwriteHealthStatus {
  AppwriteHealthStatus._();
  static final AppwriteHealthStatus instance = AppwriteHealthStatus._();

  AppwriteHealthState _state = AppwriteHealthState.initial;

  AppwriteHealthState get state => _state;

  void update(AppwriteHealthState newState) {
    _state = newState;
  }

  /// هل نحن في وضع Failover (Primary معطّل، Secondary متاح)؟
  bool get isFailoverActive => _state.shouldFailover;

  /// الوجهة المُفضّلة للقراءة حالياً
  String get preferredReadSource => _state.preferredReadSource;
}
