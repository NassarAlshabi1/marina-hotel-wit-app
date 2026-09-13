import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'local_db.dart';

enum RecoveryAction { retry, skip, rollback, escalate, pause }

enum ErrorSeverity { low, medium, high, critical }

class SyncError {
  SyncError({
    required this.id,
    required this.operation,
    required this.table,
    required this.message,
    required this.severity,
    required this.isRetriable,
    this.recordId,
    this.stackTrace,
    DateTime? timestamp,
    this.retryCount = 0,
  }) : timestamp = timestamp ?? DateTime.now();
  final String id;
  final String operation;
  final String table;
  final String? recordId;
  final String message;
  final String? stackTrace;
  final ErrorSeverity severity;
  final bool isRetriable;
  final DateTime timestamp;
  int retryCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'operation': operation,
    'table': table,
    'recordId': recordId,
    'message': message,
    'severity': severity.name,
    'isRetriable': isRetriable,
    'timestamp': timestamp.toIso8601String(),
    'retryCount': retryCount,
  };
}

class RecoveryResult {
  const RecoveryResult({
    required this.success,
    required this.actionTaken,
    required this.duration,
    this.message,
  });
  final bool success;
  final RecoveryAction actionTaken;
  final String? message;
  final Duration duration;
}

class RollbackPoint {
  const RollbackPoint({required this.id, required this.description, required this.timestamp, required this.snapshot});
  final String id;
  final String description;
  final DateTime timestamp;
  final Map<String, List<Map<String, dynamic>>> snapshot;
}

class SyncErrorRecovery {
  SyncErrorRecovery._();
  static SyncErrorRecovery? _instance;
  // ignore: prefer_constructors_over_static_methods
  static SyncErrorRecovery get instance => _instance ??= SyncErrorRecovery._();

  final List<SyncError> _errorLog = [];
  final List<RollbackPoint> _rollbackPoints = [];
  static const int _maxErrors = 100;
  static const int _maxRollbackPoints = 5;

  final _errorController = StreamController<SyncError>.broadcast();
  Stream<SyncError> get errorStream => _errorController.stream;

  List<SyncError> get recentErrors => List.unmodifiable(_errorLog);

  void logError(SyncError error) {
    _errorLog.insert(0, error);
    if (_errorLog.length > _maxErrors) {
      _errorLog.removeLast();
    }
    _errorController.add(error);
    debugPrint('❌ [Recovery] ${error.severity.name}: ${error.message}');
  }

  SyncError createError({
    required String operation,
    required String table,
    required dynamic exception,
    String? recordId,
    StackTrace? stackTrace,
  }) {
    final severity = _classifyError(exception);
    final isRetriable = _isRetriable(exception);

    return SyncError(
      id: '${DateTime.now().millisecondsSinceEpoch}_${table}_$operation',
      operation: operation,
      table: table,
      recordId: recordId,
      message: exception.toString(),
      stackTrace: stackTrace?.toString(),
      severity: severity,
      isRetriable: isRetriable,
    );
  }

  // ✅ P1-10 fix: تصنيف الأخطاء عبر AppwriteException.code بدل مطابقة نصية
  ErrorSeverity _classifyError(dynamic exception) {
    // فحص AppwriteException.code أولاً
    if (exception is AppwriteException) {
      final code = exception.code ?? 0;
      // 4xx — أخطاء العميل (غالباً غير قابلة لإعادة المحاولة)
      if (code == 400 || code == 401 || code == 403 || code == 404) {
        return code == 401 || code == 403 ? ErrorSeverity.high : ErrorSeverity.medium;
      }
      // 429 — rate limit (قابل لإعادة المحاولة)
      if (code == 429) return ErrorSeverity.medium;
      // 5xx — أخطاء الخادم (قابلة لإعادة المحاولة)
      if (code >= 500) return ErrorSeverity.low;
    }

    // fallback: مطابقة نصية للأنواع غير AppwriteException
    final message = exception.toString().toLowerCase();
    if (message.contains('network') || message.contains('connection') || message.contains('timeout')) {
      return ErrorSeverity.low;
    }
    if (message.contains('conflict') || message.contains('version')) {
      return ErrorSeverity.medium;
    }
    if (message.contains('permission') || message.contains('unauthorized') || message.contains('forbidden')) {
      return ErrorSeverity.high;
    }
    if (message.contains('corrupt') || message.contains('integrity') || message.contains('fatal')) {
      return ErrorSeverity.critical;
    }
    return ErrorSeverity.medium;
  }

  // ✅ P1-10 fix: قابلية إعادة المحاولة عبر AppwriteException.code
  bool _isRetriable(dynamic exception) {
    if (exception is AppwriteException) {
      final code = exception.code ?? 0;
      // 4xx (عدا 429) = غير قابل لإعادة المحاولة
      if (code == 400 || code == 401 || code == 403 || code == 404) return false;
      // 429 + 5xx = قابل لإعادة المحاولة
      if (code == 429 || code >= 500) return true;
    }

    // fallback
    final message = exception.toString().toLowerCase();
    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('timeout') ||
        message.contains('temporary')) {
      return true;
    }
    if (message.contains('permission') || message.contains('corrupt') || message.contains('invalid')) {
      return false;
    }
    return true;
  }

  RecoveryAction suggestRecoveryAction(SyncError error) {
    if (error.severity == ErrorSeverity.critical) {
      return RecoveryAction.rollback;
    }

    if (!error.isRetriable) {
      return RecoveryAction.skip;
    }

    if (error.retryCount >= 3) {
      if (error.severity == ErrorSeverity.high) {
        return RecoveryAction.escalate;
      }
      return RecoveryAction.skip;
    }

    return RecoveryAction.retry;
  }

  Future<RecoveryResult> executeRecovery({
    required SyncError error,
    required RecoveryAction action,
    Future<void> Function()? retryOperation,
    Future<void> Function()? rollbackOperation,
  }) async {
    final startTime = DateTime.now();

    try {
      switch (action) {
        case RecoveryAction.retry:
          if (retryOperation != null) {
            error.retryCount++;
            await Future<void>.delayed(Duration(seconds: error.retryCount * 2));
            await retryOperation();
            return RecoveryResult(
              success: true,
              actionTaken: action,
              message: 'إعادة المحاولة ناجحة',
              duration: DateTime.now().difference(startTime),
            );
          }

        case RecoveryAction.rollback:
          if (rollbackOperation != null) {
            await rollbackOperation();
            return RecoveryResult(
              success: true,
              actionTaken: action,
              message: 'تم التراجع بنجاح',
              duration: DateTime.now().difference(startTime),
            );
          } else if (_rollbackPoints.isNotEmpty) {
            return RecoveryResult(
              success: true,
              actionTaken: action,
              message: 'نقطة استعادة متاحة',
              duration: DateTime.now().difference(startTime),
            );
          }

        case RecoveryAction.skip:
          return RecoveryResult(
            success: true,
            actionTaken: action,
            message: 'تم تخطي العملية',
            duration: DateTime.now().difference(startTime),
          );

        case RecoveryAction.pause:
          return RecoveryResult(
            success: true,
            actionTaken: action,
            message: 'تم إيقاف المزامنة مؤقتاً',
            duration: DateTime.now().difference(startTime),
          );

        case RecoveryAction.escalate:
          return RecoveryResult(
            success: false,
            actionTaken: action,
            message: 'يتطلب تدخل يدوي',
            duration: DateTime.now().difference(startTime),
          );
      }

      return RecoveryResult(
        success: false,
        actionTaken: action,
        message: 'لم يتم تنفيذ أي إجراء',
        duration: DateTime.now().difference(startTime),
      );
    } catch (e) {
      return RecoveryResult(
        success: false,
        actionTaken: action,
        message: 'فشل الاسترداد: $e',
        duration: DateTime.now().difference(startTime),
      );
    }
  }

  Future<void> createRollbackPoint({
    required String id,
    required String description,
    required AppDatabase database,
  }) async {
    try {
      final snapshot = await database.getAllTablesAsJson();

      final rollbackPoint = RollbackPoint(
        id: id,
        description: description,
        timestamp: DateTime.now(),
        snapshot: snapshot.map((k, v) => MapEntry(k, List<Map<String, dynamic>>.from(v as List))),
      );

      _rollbackPoints.insert(0, rollbackPoint);
      if (_rollbackPoints.length > _maxRollbackPoints) {
        _rollbackPoints.removeLast();
      }

      debugPrint('📍 [Recovery] نقطة استعادة: $description');
    } catch (e) {
      debugPrint('⚠️ [Recovery] فشل إنشاء نقطة الاستعادة: $e');
    }
  }

  Future<bool> restoreFromRollbackPoint(String pointId, AppDatabase database) async {
    final point = _rollbackPoints.firstWhere(
      (p) => p.id == pointId,
      orElse: () => throw Exception('نقطة الاستعادة غير موجودة'),
    );

    try {
      await database.applyMergedData(point.snapshot);
      debugPrint('✅ [Recovery] تم الاستعادة من: ${point.description}');
      return true;
    } catch (e) {
      debugPrint('❌ [Recovery] فشل الاستعادة: $e');
      return false;
    }
  }

  List<RollbackPoint> get availableRollbackPoints => List.unmodifiable(_rollbackPoints);

  Map<ErrorSeverity, int> getErrorSummary() {
    final summary = <ErrorSeverity, int>{};
    for (final error in _errorLog) {
      summary[error.severity] = (summary[error.severity] ?? 0) + 1;
    }
    return summary;
  }

  void clearErrors() {
    _errorLog.clear();
  }

  void dispose() {
    _errorController.close();
    _errorLog.clear();
    _rollbackPoints.clear();
    _instance = null;
  }
}
