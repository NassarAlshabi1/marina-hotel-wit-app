// lib/services/analytics_service.dart
// خدمة التحليلات والمراقبة
// analytics_service.dart - خدمة التحليلات والمراقبة

import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// أحداث المزامنة المهمة للتتبع
enum SyncAnalyticsEvent {
  syncStarted,
  syncCompleted,
  syncFailed,
  dataPushed,
  dataPulled,
  conflictResolved,
  offlineModeEntered,
  onlineModeEntered,
  batchPushCompleted,
  batchPushFailed,
  retryAttempt,
  maxRetriesReached,
}

/// إحصائيات المزامنة
class SyncStats {
  const SyncStats({
    required this.totalPushOperations,
    required this.totalPullOperations,
    required this.totalConflicts,
    required this.totalFailures,
    required this.totalRetries,
    required this.averageSyncTime,
    required this.isHealthy,
    this.lastSyncTime,
  });
  final int totalPushOperations;
  final int totalPullOperations;
  final int totalConflicts;
  final int totalFailures;
  final int totalRetries;
  final Duration averageSyncTime;
  final DateTime? lastSyncTime;
  final bool isHealthy;

  SyncStats copyWith({
    int? totalPushOperations,
    int? totalPullOperations,
    int? totalConflicts,
    int? totalFailures,
    int? totalRetries,
    Duration? averageSyncTime,
    DateTime? lastSyncTime,
    bool? isHealthy,
  }) => SyncStats(
    totalPushOperations: totalPushOperations ?? this.totalPushOperations,
    totalPullOperations: totalPullOperations ?? this.totalPullOperations,
    totalConflicts: totalConflicts ?? this.totalConflicts,
    totalFailures: totalFailures ?? this.totalFailures,
    totalRetries: totalRetries ?? this.totalRetries,
    averageSyncTime: averageSyncTime ?? this.averageSyncTime,
    lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    isHealthy: isHealthy ?? this.isHealthy,
  );

  Map<String, dynamic> toJson() => {
    'totalPushOperations': totalPushOperations,
    'totalPullOperations': totalPullOperations,
    'totalConflicts': totalConflicts,
    'totalFailures': totalFailures,
    'totalRetries': totalRetries,
    'averageSyncTimeMs': averageSyncTime.inMilliseconds,
    'lastSyncTime': lastSyncTime?.toIso8601String(),
    'isHealthy': isHealthy,
    'failureRate': totalPushOperations > 0
        ? totalFailures / totalPushOperations
        : 0.0,
    'retryRate': totalPushOperations > 0
        ? totalRetries / totalPushOperations
        : 0.0,
  };
}

/// خدمة التحليلات للمزامنة
class AnalyticsService {
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();
  static final AnalyticsService _instance = AnalyticsService._internal();

  FirebaseAnalytics? _analytics;
  bool _isEnabled = true;

  // إحصائيات جلسة واحدة
  int _sessionPushCount = 0;
  int _sessionPullCount = 0;
  int _sessionConflicts = 0;
  int _sessionFailures = 0;
  int _sessionRetries = 0;
  DateTime? _lastSyncStartTime;

  /// تهيئة الخدمة
  Future<void> initialize() async {
    if (!_isEnabled) {
      return;
    }

    try {
      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(true);
      developer.log('✅ AnalyticsService initialized', name: 'AnalyticsService');
    } catch (e) {
      developer.log(
        '⚠️ Analytics initialization failed: $e',
        name: 'AnalyticsService',
      );
      // لا نوقف التطبيق بسبب فشل التحليلات
    }
  }

  /// تمكين/تعطيل التحليلات
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    unawaited(_analytics?.setAnalyticsCollectionEnabled(enabled));
  }

  /// تسجيل حدث مزامنة
  Future<void> logSyncEvent(
    SyncAnalyticsEvent event, {
    Map<String, dynamic> parameters = const {},
  }) async {
    if (!_isEnabled) {
      return;
    }

    final eventName = _eventToString(event);
    final allParameters = <String, Object>{
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'platform': defaultTargetPlatform.name,
      ...parameters.map((key, value) => MapEntry(key, value as Object)),
    };

    // تسجيل محلي
    developer.log(
      '📊 Analytics: $eventName',
      name: 'AnalyticsService',
      error: allParameters,
    );

    // تحديث الإحصائيات المحلية
    _updateSessionStats(event);

    // إرسال إلى Firebase
    try {
      await _analytics?.logEvent(name: eventName, parameters: allParameters);
    } catch (e) {
      // لا نوقف التطبيق بسبب فشل إرسال التحليلات
    }
  }

  /// تسجيل بدء المزامنة
  Future<void> logSyncStart({required String trigger}) async {
    _lastSyncStartTime = DateTime.now();
    await logSyncEvent(
      SyncAnalyticsEvent.syncStarted,
      parameters: {'trigger': trigger},
    );
  }

  /// تسجيل اكتمال المزامنة
  Future<void> logSyncComplete({
    required int itemsProcessed,
    required Duration duration,
  }) async {
    await logSyncEvent(
      SyncAnalyticsEvent.syncCompleted,
      parameters: {
        'itemsProcessed': itemsProcessed,
        'durationMs': duration.inMilliseconds,
        'itemsPerSecond': itemsProcessed > 0 && duration.inSeconds > 0
            ? itemsProcessed / duration.inSeconds
            : 0.0,
      },
    );
  }

  /// تسجيل فشل المزامنة
  Future<void> logSyncFailure({
    required String error,
    required String operation,
    required int attempt,
  }) async {
    _sessionFailures++;
    await logSyncEvent(
      SyncAnalyticsEvent.syncFailed,
      parameters: {'error': error, 'operation': operation, 'attempt': attempt},
    );
  }

  /// تسجيل دفعة مكتملة
  Future<void> logBatchCompleted({
    required int itemsCount,
    required Duration duration,
  }) async {
    _sessionPushCount += itemsCount;
    await logSyncEvent(
      SyncAnalyticsEvent.batchPushCompleted,
      parameters: {
        'itemsCount': itemsCount,
        'durationMs': duration.inMilliseconds,
      },
    );
  }

  /// تسجيل فشل دفعة
  Future<void> logBatchFailed({
    required String error,
    required int itemsCount,
    required int attempt,
  }) async {
    await logSyncEvent(
      SyncAnalyticsEvent.batchPushFailed,
      parameters: {
        'error': error,
        'itemsCount': itemsCount,
        'attempt': attempt,
      },
    );
  }

  /// تسجيل محاولة إعادة
  Future<void> logRetryAttempt({
    required String operation,
    required int attempt,
    required Duration delay,
  }) async {
    _sessionRetries++;
    await logSyncEvent(
      SyncAnalyticsEvent.retryAttempt,
      parameters: {
        'operation': operation,
        'attempt': attempt,
        'delayMs': delay.inMilliseconds,
      },
    );
  }

  /// تسجيل الوصول للحد الأقصى من المحاولات
  Future<void> logMaxRetriesReached({
    required String operation,
    required int totalAttempts,
  }) async {
    await logSyncEvent(
      SyncAnalyticsEvent.maxRetriesReached,
      parameters: {'operation': operation, 'totalAttempts': totalAttempts},
    );
  }

  /// تسجيل نزاع محلول
  Future<void> logConflictResolved({
    required String resolution,
    required String entityType,
  }) async {
    _sessionConflicts++;
    await logSyncEvent(
      SyncAnalyticsEvent.conflictResolved,
      parameters: {'resolution': resolution, 'entityType': entityType},
    );
  }

  /// الحصول على إحصائيات الجلسة الحالية
  SyncStats getSessionStats() {
    final now = DateTime.now();
    final lastSyncDuration = _lastSyncStartTime != null
        ? now.difference(_lastSyncStartTime!)
        : Duration.zero;

    return SyncStats(
      totalPushOperations: _sessionPushCount,
      totalPullOperations: _sessionPullCount,
      totalConflicts: _sessionConflicts,
      totalFailures: _sessionFailures,
      totalRetries: _sessionRetries,
      averageSyncTime: lastSyncDuration,
      lastSyncTime: _lastSyncStartTime,
      isHealthy: _sessionFailures < 5 && _sessionRetries < 10,
    );
  }

  /// إعادة تعيين إحصائيات الجلسة
  void resetSessionStats() {
    _sessionPushCount = 0;
    _sessionPullCount = 0;
    _sessionConflicts = 0;
    _sessionFailures = 0;
    _sessionRetries = 0;
    _lastSyncStartTime = null;
  }

  /// تحديث إحصائيات الجلسة
  void _updateSessionStats(SyncAnalyticsEvent event) {
    switch (event) {
      case SyncAnalyticsEvent.dataPushed:
        _sessionPushCount++;
      case SyncAnalyticsEvent.dataPulled:
        _sessionPullCount++;
      case SyncAnalyticsEvent.conflictResolved:
        _sessionConflicts++;
      case SyncAnalyticsEvent.syncFailed:
        _sessionFailures++;
      case SyncAnalyticsEvent.retryAttempt:
        _sessionRetries++;
      default:
        break;
    }
  }

  /// تحويل الحدث إلى اسم
  String _eventToString(SyncAnalyticsEvent event) {
    switch (event) {
      case SyncAnalyticsEvent.syncStarted:
        return 'sync_started';
      case SyncAnalyticsEvent.syncCompleted:
        return 'sync_completed';
      case SyncAnalyticsEvent.syncFailed:
        return 'sync_failed';
      case SyncAnalyticsEvent.dataPushed:
        return 'data_pushed';
      case SyncAnalyticsEvent.dataPulled:
        return 'data_pulled';
      case SyncAnalyticsEvent.conflictResolved:
        return 'conflict_resolved';
      case SyncAnalyticsEvent.offlineModeEntered:
        return 'offline_mode_entered';
      case SyncAnalyticsEvent.onlineModeEntered:
        return 'online_mode_entered';
      case SyncAnalyticsEvent.batchPushCompleted:
        return 'batch_push_completed';
      case SyncAnalyticsEvent.batchPushFailed:
        return 'batch_push_failed';
      case SyncAnalyticsEvent.retryAttempt:
        return 'retry_attempt';
      case SyncAnalyticsEvent.maxRetriesReached:
        return 'max_retries_reached';
    }
  }

  /// تسجيل وقت المستخدم على الشاشة
  Future<void> logScreenView({
    required String screenName,
    String? screenClass,
  }) async {
    try {
      await _analytics?.logScreenView(
        screenName: screenName,
        screenClass: screenClass ?? screenName,
      );
    } catch (e) {
      // تجاهل أخطاء التحليلات
    }
  }

  /// تسجيل حدث مخصص
  Future<void> logCustomEvent({
    required String name,
    Map<String, dynamic> parameters = const {},
  }) async {
    if (!_isEnabled) {
      return;
    }

    try {
      await _analytics?.logEvent(
        name: name,
        parameters: parameters.map(
          (key, value) => MapEntry(key, value as Object),
        ),
      );
    } catch (e) {
      // تجاهل الأخطاء
    }
  }
}
