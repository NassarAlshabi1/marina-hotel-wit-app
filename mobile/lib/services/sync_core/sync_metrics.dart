// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// معلومات دورة مزامنة واحدة
class SyncSession {
  SyncSession({
    required this.startTime,
    this.endTime,
    this.success = false,
    this.error,
    this.recordsSynced = 0,
    this.conflictsResolved = 0,
  });

  factory SyncSession.fromJson(Map<String, dynamic> json) => SyncSession(
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null
        ? DateTime.parse(json['endTime'] as String)
        : null,
    success: json['success'] as bool? ?? false,
    error: json['error'] as String?,
    recordsSynced: (json['recordsSynced'] as num?)?.toInt() ?? 0,
    conflictsResolved: (json['conflictsResolved'] as num?)?.toInt() ?? 0,
  );
  final DateTime startTime;
  final DateTime? endTime;
  final bool success;
  final String? error;
  final int recordsSynced;
  final int conflictsResolved;

  Duration get duration => (endTime ?? DateTime.now()).difference(startTime);

  Map<String, dynamic> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'success': success,
    'error': error,
    'recordsSynced': recordsSynced,
    'conflictsResolved': conflictsResolved,
  };
}

/// إحصائيات المزامنة
class SyncStats {
  SyncStats({
    required this.totalSyncs,
    required this.successfulSyncs,
    required this.failedSyncs,
    required this.averageDuration,
    required this.successRate,
    required this.totalRecordsSynced,
    required this.totalConflictsResolved,
    this.lastSync,
  });
  final int totalSyncs;
  final int successfulSyncs;
  final int failedSyncs;
  final Duration averageDuration;
  final double successRate;
  final int totalRecordsSynced;
  final int totalConflictsResolved;
  final SyncSession? lastSync;

  String get healthStatus {
    if (successRate > 0.95) {
      return '🟢 ممتاز';
    }
    if (successRate > 0.8) {
      return '🟡 جيد';
    }
    if (successRate > 0.5) {
      return '🟠 متوسط';
    }
    return '🔴 سيء';
  }

  bool get isHealthy => successRate > 0.8;

  @override
  String toString() {
    return 'SyncStats(إجمالي: $totalSyncs, ناجح: $successfulSyncs, '
        'فاشل: $failedSyncs, معدل النجاح: ${(successRate * 100).toStringAsFixed(1)}%)';
  }
}

/// مدير القياسات والإحصائيات
///
/// الاستخدام:
/// ```dart
/// final metrics = SyncMetrics.instance;
///
/// metrics.statsStream.listen((stats) {
///   print('معدل النجاح: ${stats.successRate}');
/// });
///
/// metrics.startSync();
/// // ... عملية المزامنة ...
/// metrics.recordSuccess(recordsSynced: 100);
/// ```
class SyncMetrics {
  SyncMetrics._();
  static SyncMetrics? _instance;
  // ignore: prefer_constructors_over_static_methods
  static SyncMetrics get instance => _instance ??= SyncMetrics._();

  SyncSession? _currentSession;
  final List<SyncSession> _history = [];
  final _statsController = StreamController<SyncStats>.broadcast();

  static const _maxHistorySize = 100;
  static const _prefsKey = 'sync_metrics_history';

  Stream<SyncStats> get statsStream => _statsController.stream;
  List<SyncSession> get history => List.unmodifiable(_history);

  /// بدء دورة مزامنة جديدة
  void startSync() {
    _currentSession = SyncSession(startTime: DateTime.now());
    debugPrint('📊 SyncMetrics: بدأت دورة مزامنة جديدة');
  }

  /// تسجيل نجاح المزامنة
  void recordSuccess({int recordsSynced = 0, int conflictsResolved = 0}) {
    if (_currentSession == null) {
      return;
    }

    final session = SyncSession(
      startTime: _currentSession!.startTime,
      endTime: DateTime.now(),
      success: true,
      recordsSynced: recordsSynced,
      conflictsResolved: conflictsResolved,
    );

    _addToHistory(session);
    _updateStats();

    debugPrint(
      '✅ SyncMetrics: مزامنة ناجحة - ${session.duration.inSeconds}ث، '
      'السجلات: $recordsSynced، التضارب: $conflictsResolved',
    );
  }

  /// تسجيل فشل المزامنة
  void recordFailure(Object error) {
    if (_currentSession == null) {
      return;
    }

    final session = SyncSession(
      startTime: _currentSession!.startTime,
      endTime: DateTime.now(),
      error: error.toString(),
    );

    _addToHistory(session);
    _updateStats();

    debugPrint(
      '❌ SyncMetrics: مزامنة فاشلة - ${session.duration.inSeconds}ث، الخطأ: $error',
    );
  }

  /// إضافة إلى السجل
  void _addToHistory(SyncSession session) {
    _history.add(session);

    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }

    _saveHistory();
  }

  /// تحديث الإحصائيات
  void _updateStats() {
    final stats = calculateStats();
    _statsController.add(stats);
  }

  /// حساب الإحصائيات
  SyncStats calculateStats() {
    if (_history.isEmpty) {
      return SyncStats(
        totalSyncs: 0,
        successfulSyncs: 0,
        failedSyncs: 0,
        averageDuration: Duration.zero,
        successRate: 0.0,
        totalRecordsSynced: 0,
        totalConflictsResolved: 0,
      );
    }

    final successful = _history.where((s) => s.success).toList();
    final failed = _history.where((s) => !s.success).toList();

    final totalDuration = _history.fold<Duration>(
      Duration.zero,
      (sum, session) => sum + session.duration,
    );

    final avgDuration = totalDuration ~/ _history.length;

    return SyncStats(
      totalSyncs: _history.length,
      successfulSyncs: successful.length,
      failedSyncs: failed.length,
      averageDuration: avgDuration,
      successRate: successful.length / _history.length,
      totalRecordsSynced: _history.fold(0, (sum, s) => sum + s.recordsSynced),
      totalConflictsResolved: _history.fold(
        0,
        (sum, s) => sum + s.conflictsResolved,
      ),
      lastSync: _history.last,
    );
  }

  /// حفظ السجل
  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _history.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_prefsKey, jsonList);
    } catch (e) {
      debugPrint('⚠️ SyncMetrics: فشل حفظ السجل: $e');
    }
  }

  /// تحميل السجل
  Future<void> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList(_prefsKey) ?? [];

      _history.clear();
      for (final jsonStr in jsonList) {
        final session = SyncSession.fromJson(
          jsonDecode(jsonStr) as Map<String, dynamic>,
        );
        _history.add(session);
      }

      debugPrint('📊 SyncMetrics: تم تحميل ${_history.length} سجل');
      _updateStats();
    } catch (e) {
      debugPrint('⚠️ SyncMetrics: فشل تحميل السجل: $e');
    }
  }

  /// مسح السجل
  Future<void> clearHistory() async {
    _history.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    _updateStats();
    debugPrint('🗑️ SyncMetrics: تم مسح السجل');
  }

  /// تنظيف الموارد
  void dispose() {
    _statsController.close();
  }
}
