import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// نوع الحدث
enum SyncEventType {
  started,
  completed,
  failed,
  conflict,
  retry,
  timeout,
  networkError,
}

/// حدث مزامنة واحد
class SyncEvent {

  // Public factory for creating new events
  factory SyncEvent({
    required SyncEventType type,
    String? message,
    Map<String, dynamic>? metadata,
    String? errorStack,
  }) => SyncEvent._(
    id: _generateId(),
    timestamp: DateTime.now(),
    type: type,
    message: message,
    metadata: metadata,
    errorStack: errorStack,
  );

  // Private constructor for controlled instantiation
  SyncEvent._({
    required this.id,
    required this.timestamp,
    required this.type,
    this.message,
    this.metadata,
    this.errorStack,
  });

  factory SyncEvent.fromJson(Map<String, dynamic> json) => SyncEvent._(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    type: SyncEventType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => SyncEventType.failed,
    ),
    message: json['message'] as String?,
    metadata: json['metadata'] != null
        ? Map<String, dynamic>.from(json['metadata'])
        : null,
    errorStack: json['errorStack'] as String?,
  );
  final String id;
  final SyncEventType type;
  final DateTime timestamp;
  final String? message;
  final Map<String, dynamic>? metadata;
  final String? errorStack;

  static String _generateId() {
    return const Uuid().v4();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'message': message,
    'metadata': metadata,
    'errorStack': errorStack,
  };
}

/// إحصائيات الأداء الحية
class SyncPerformanceStats {

  SyncPerformanceStats({
    required this.totalAttempts,
    required this.successfulSyncs,
    required this.failedSyncs,
    required this.conflictsDetected,
    required this.conflictsResolved,
    required this.successRate,
    required this.averageTime,
    this.lastSyncDuration,
    this.lastSuccessfulSync,
    this.lastFailedSync,
    required this.recentErrors,
  });
  final int totalAttempts;
  final int successfulSyncs;
  final int failedSyncs;
  final int conflictsDetected;
  final int conflictsResolved;
  final double successRate;
  final Duration averageTime;
  final Duration? lastSyncDuration;
  final DateTime? lastSuccessfulSync;
  final DateTime? lastFailedSync;
  final List<String> recentErrors;

  bool get isHealthy => successRate > 0.8 && recentErrors.length < 5;

  String get healthStatus {
    if (successRate > 0.95) return '🟢 ممتاز';
    if (successRate > 0.8) return '🟡 جيد';
    if (successRate > 0.5) return '🟠 متوسط';
    return '🔴 سيء';
  }
}

/// مستوى التنبيه
enum SyncAlertLevel { info, warning, critical }

/// تنبيه مزامنة
class SyncAlert {

  SyncAlert({required this.level, required this.message, required this.stats})
    : timestamp = DateTime.now();
  final SyncAlertLevel level;
  final String message;
  final DateTime timestamp;
  final SyncPerformanceStats stats;

  String get icon {
    switch (level) {
      case SyncAlertLevel.info:
        return 'ℹ️';
      case SyncAlertLevel.warning:
        return '⚠️';
      case SyncAlertLevel.critical:
        return '🚨';
    }
  }
}

/// نظام المراقبة الشامل للمزامنة
///
/// الاستخدام:
/// ```dart
/// final monitor = SyncMonitoringSystem.instance;
/// await monitor.initialize();
///
/// // في كود المزامنة
/// monitor.recordSyncStart();
/// try {
///   // ... المزامنة ...
///   monitor.recordSyncSuccess(recordsSynced: 100);
/// } catch (e) {
///   monitor.recordSyncFailure(error: e);
/// }
///
/// // الاستماع للإحصائيات
/// monitor.statsStream.listen((stats) {
///   print('معدل النجاح: ${stats.successRate}');
/// });
/// ```
class SyncMonitoringSystem {

  SyncMonitoringSystem._();
  static SyncMonitoringSystem? _instance;
  static SyncMonitoringSystem get instance =>
      _instance ??= SyncMonitoringSystem._();

  final List<SyncEvent> _events = [];
  final _statsController = StreamController<SyncPerformanceStats>.broadcast();
  final _alertController = StreamController<SyncAlert>.broadcast();

  Timer? _healthCheckTimer;
  DateTime? _currentSyncStartTime;

  static const int _maxEventsInMemory = 500;
  static const int _maxRecentErrors = 10;
  static const Duration _healthCheckInterval = Duration(minutes: 5);

  Stream<SyncPerformanceStats> get statsStream => _statsController.stream;
  Stream<SyncAlert> get alertsStream => _alertController.stream;
  List<SyncEvent> get events => List.unmodifiable(_events);

  /// تهيئة النظام
  Future<void> initialize() async {
    await _loadHistoricalData();
    await _cleanupOldStoredEvents();
    _startHealthChecks();
    debugPrint('📊 SyncMonitoringSystem: تم التهيئة');
  }

  /// تسجيل بداية المزامنة
  void recordSyncStart({Map<String, dynamic>? metadata}) {
    _currentSyncStartTime = DateTime.now();

    final event = SyncEvent(
      type: SyncEventType.started,
      message: 'بدأت المزامنة',
      metadata: metadata,
    );

    _addEvent(event);
    _updateStats();
  }

  /// تسجيل نجاح المزامنة
  void recordSyncSuccess({
    int? recordsSynced,
    int? conflictsResolved,
    Map<String, dynamic>? metadata,
  }) {
    final duration = _getSyncDuration();

    final event = SyncEvent(
      type: SyncEventType.completed,
      message: 'اكتملت المزامنة بنجاح في ${duration.inSeconds}ث',
      metadata: {
        ...?metadata,
        'duration_seconds': duration.inSeconds,
        'records_synced': recordsSynced,
        'conflicts_resolved': conflictsResolved,
      },
    );

    _addEvent(event);
    _updateStats();
    _checkForAlerts();
  }

  /// تسجيل فشل المزامنة
  void recordSyncFailure({
    required Object error,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final duration = _getSyncDuration();

    final event = SyncEvent(
      type: SyncEventType.failed,
      message: 'فشلت المزامنة: $error',
      metadata: {...?metadata, 'duration_seconds': duration.inSeconds},
      errorStack: stackTrace?.toString(),
    );

    _addEvent(event);
    _updateStats();
    _checkForAlerts();
    _checkConsecutiveFailures();
  }

  /// تسجيل تضارب
  void recordConflict({
    required String table,
    required String uuid,
    required String resolution,
    Map<String, dynamic>? metadata,
  }) {
    final event = SyncEvent(
      type: SyncEventType.conflict,
      message: 'تضارب في $table/$uuid - الحل: $resolution',
      metadata: metadata,
    );

    _addEvent(event);
  }

  /// تسجيل إعادة محاولة
  void recordRetry({
    required int attemptNumber,
    required int maxAttempts,
    Map<String, dynamic>? metadata,
  }) {
    final event = SyncEvent(
      type: SyncEventType.retry,
      message: 'إعادة محاولة $attemptNumber/$maxAttempts',
      metadata: metadata,
    );

    _addEvent(event);
  }

  /// إضافة حدث للسجل
  void _addEvent(SyncEvent event) {
    _events.add(event);

    if (_events.length > _maxEventsInMemory) {
      _events.removeRange(0, _events.length - _maxEventsInMemory);
    }

    _persistEvent(event);
  }

  /// حساب مدة المزامنة الحالية
  Duration _getSyncDuration() {
    if (_currentSyncStartTime == null) {
      return Duration.zero;
    }
    return DateTime.now().difference(_currentSyncStartTime!);
  }

  /// تحديث الإحصائيات
  void _updateStats() {
    final stats = _calculateStats();
    _statsController.add(stats);
  }

  /// حساب الإحصائيات
  SyncPerformanceStats _calculateStats() {
    final completed = _events
        .where((e) => e.type == SyncEventType.completed)
        .toList();
    final failed = _events
        .where((e) => e.type == SyncEventType.failed)
        .toList();
    final conflicts = _events
        .where((e) => e.type == SyncEventType.conflict)
        .toList();

    final totalAttempts = completed.length + failed.length;
    final successRate = totalAttempts > 0
        ? completed.length / totalAttempts
        : 0.0;

    final durations = completed
        .where((e) => e.metadata?['duration_seconds'] != null)
        .map((e) => Duration(seconds: e.metadata!['duration_seconds'] as int))
        .toList();

    final averageTime = durations.isEmpty
        ? Duration.zero
        : durations.reduce((a, b) => a + b) ~/ durations.length;

    final recentErrors = failed.reversed
        .take(_maxRecentErrors)
        .map((e) => e.message ?? 'خطأ غير معروف')
        .toList();

    return SyncPerformanceStats(
      totalAttempts: totalAttempts,
      successfulSyncs: completed.length,
      failedSyncs: failed.length,
      conflictsDetected: conflicts.length,
      conflictsResolved: conflicts
          .where((e) => e.metadata?['resolved'] == true)
          .length,
      successRate: successRate,
      averageTime: averageTime,
      lastSyncDuration: durations.isNotEmpty ? durations.last : null,
      lastSuccessfulSync: completed.isNotEmpty
          ? completed.last.timestamp
          : null,
      lastFailedSync: failed.isNotEmpty ? failed.last.timestamp : null,
      recentErrors: recentErrors,
    );
  }

  /// فحص صحي دوري
  void _startHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (_) {
      _performHealthCheck();
    });
  }

  /// إجراء الفحص الصحي
  void _performHealthCheck() {
    final stats = _calculateStats();

    if (!stats.isHealthy) {
      _alertController.add(
        SyncAlert(
          level: SyncAlertLevel.warning,
          message:
              'معدل نجاح المزامنة منخفض: ${(stats.successRate * 100).toStringAsFixed(1)}%',
          stats: stats,
        ),
      );
    }

    if (stats.lastSuccessfulSync != null) {
      final timeSinceLastSync = DateTime.now().difference(
        stats.lastSuccessfulSync!,
      );
      if (timeSinceLastSync > const Duration(hours: 2)) {
        _alertController.add(
          SyncAlert(
            level: SyncAlertLevel.warning,
            message:
                'لم تحدث مزامنة ناجحة منذ ${timeSinceLastSync.inHours} ساعة',
            stats: stats,
          ),
        );
      }
    }
  }

  /// فحص الفشل المتتالي
  void _checkConsecutiveFailures() {
    final recentEvents = _events.reversed.take(5).toList();
    final allFailed = recentEvents.every((e) => e.type == SyncEventType.failed);

    if (allFailed && recentEvents.length >= 5) {
      _alertController.add(
        SyncAlert(
          level: SyncAlertLevel.critical,
          message: '⚠️ 5 عمليات مزامنة فاشلة متتالية!',
          stats: _calculateStats(),
        ),
      );
    }
  }

  /// فحص التنبيهات بناءً على الإحصائيات الحالية
  void _checkForAlerts() {
    final stats = _calculateStats();

    if (stats.successRate < 0.5 && stats.totalAttempts >= 3) {
      _alertController.add(
        SyncAlert(
          level: SyncAlertLevel.critical,
          message:
              'معدل نجاح المزامنة منخفض جداً: ${(stats.successRate * 100).toStringAsFixed(1)}%',
          stats: stats,
        ),
      );
    }

    if (stats.recentErrors.length >= 3) {
      _alertController.add(
        SyncAlert(
          level: SyncAlertLevel.warning,
          message: 'تم تسجيل ${stats.recentErrors.length} أخطاء حديثة',
          stats: stats,
        ),
      );
    }
  }

  /// حفظ حدث في التخزين الدائم
  Future<void> _persistEvent(SyncEvent event) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key =
          'sync_events_${DateTime.now().toIso8601String().split('T')[0]}';
      final existing = prefs.getStringList(key) ?? [];
      existing.add(jsonEncode(event.toJson()));

      if (existing.length > 100) {
        existing.removeRange(0, existing.length - 100);
      }

      await prefs.setStringList(key, existing);
    } catch (e) {
      debugPrint('⚠️ SyncMonitoringSystem: فشل حفظ الحدث: $e');
    }
  }

  /// تحميل البيانات التاريخية
  Future<void> _loadHistoricalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      final key = 'sync_events_$today';
      final jsonList = prefs.getStringList(key) ?? [];

      for (final jsonStr in jsonList) {
        final event = SyncEvent.fromJson(jsonDecode(jsonStr));
        _events.add(event);
      }

      debugPrint('📊 SyncMonitoringSystem: تم تحميل ${_events.length} حدث');
    } catch (e) {
      debugPrint('⚠️ SyncMonitoringSystem: فشل تحميل البيانات: $e');
    }
  }

  /// تنظيف السجلات القديمة من التخزين الدائم
  Future<void> _cleanupOldStoredEvents({int keepDays = 7}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final eventKeys = allKeys.where((k) => k.startsWith('sync_events_'));
      final now = DateTime.now();
      int removedCount = 0;

      for (final key in eventKeys) {
        final dateStr = key.replaceFirst('sync_events_', '');
        final date = DateTime.tryParse(dateStr);

        if (date != null && now.difference(date).inDays > keepDays) {
          await prefs.remove(key);
          removedCount++;
        }
      }

      if (removedCount > 0) {
        debugPrint(
          '🗑️ SyncMonitoringSystem: تم حذف $removedCount سجل قديم (أقدم من $keepDays أيام)',
        );
      }
    } catch (e) {
      debugPrint('⚠️ SyncMonitoringSystem: فشل تنظيف السجلات القديمة: $e');
    }
  }

  /// تصدير التقرير
  Future<String> exportReport() async {
    final stats = _calculateStats();

    final report =
        '''
📊 تقرير نظام المزامنة
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📈 الإحصائيات العامة:
  • إجمالي المحاولات: ${stats.totalAttempts}
  • مزامنة ناجحة: ${stats.successfulSyncs}
  • مزامنة فاشلة: ${stats.failedSyncs}
  • معدل النجاح: ${(stats.successRate * 100).toStringAsFixed(1)}%
  • الحالة الصحية: ${stats.healthStatus}

⏱️ الأداء:
  • متوسط الوقت: ${stats.averageTime.inSeconds}ث
  • آخر مزامنة: ${stats.lastSyncDuration?.inSeconds ?? '—'}ث

🔄 التضارب:
  • تم اكتشاف: ${stats.conflictsDetected}
  • تم حلها: ${stats.conflictsResolved}

🕐 التوقيت:
  • آخر نجاح: ${stats.lastSuccessfulSync ?? 'لا يوجد'}
  • آخر فشل: ${stats.lastFailedSync ?? 'لا يوجد'}

❌ الأخطاء الأخيرة:
${stats.recentErrors.isEmpty ? '  لا توجد أخطاء' : stats.recentErrors.map((e) => '  • $e').join('\n')}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
تم إنشاء التقرير في: ${DateTime.now()}
''';

    return report;
  }

  /// مسح البيانات القديمة
  Future<void> clearOldData({
    Duration olderThan = const Duration(days: 7),
  }) async {
    final cutoffDate = DateTime.now().subtract(olderThan);
    _events.removeWhere((e) => e.timestamp.isBefore(cutoffDate));

    debugPrint('🗑️ SyncMonitoringSystem: تم مسح الأحداث الأقدم من $olderThan');
  }

  /// إيقاف النظام
  void dispose() {
    _healthCheckTimer?.cancel();
    _statsController.close();
    _alertController.close();
  }
}
