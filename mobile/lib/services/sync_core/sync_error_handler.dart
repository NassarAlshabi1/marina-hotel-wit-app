import 'dart:async';
import 'package:flutter/foundation.dart';

enum SyncErrorType {
  network,
  timeout,
  authentication,
  permission,
  dataCorruption,
  storageLimit,
  conflictUnresolvable,
  unknown,
}

class SyncError {
  SyncError({required this.type, required this.message, this.originalError, this.stackTrace, this.context})
    : timestamp = DateTime.now();
  final SyncErrorType type;
  final String message;
  final dynamic originalError;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final Map<String, dynamic>? context;

  bool get isRetryable {
    switch (type) {
      case SyncErrorType.network:
      case SyncErrorType.timeout:
        return true;
      case SyncErrorType.authentication:
      case SyncErrorType.permission:
      case SyncErrorType.dataCorruption:
      case SyncErrorType.storageLimit:
      case SyncErrorType.conflictUnresolvable:
        return false;
      case SyncErrorType.unknown:
        return true;
    }
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'context': context,
    'isRetryable': isRetryable,
  };
}

class SyncErrorHandler {
  SyncErrorHandler._();
  static SyncErrorHandler? _instance;
  // ignore: prefer_constructors_over_static_methods
  static SyncErrorHandler get instance => _instance ??= SyncErrorHandler._();

  final _errorController = StreamController<SyncError>.broadcast();
  Stream<SyncError> get errorStream => _errorController.stream;

  final List<SyncError> _errorHistory = [];
  List<SyncError> get errorHistory => List.unmodifiable(_errorHistory);

  static const int _maxHistorySize = 100;

  SyncError handleError(dynamic error, {StackTrace? stackTrace, Map<String, dynamic>? context}) {
    final syncError = _classifyError(error, stackTrace: stackTrace, context: context);

    _recordError(syncError);
    _emitError(syncError);
    _logError(syncError);

    return syncError;
  }

  SyncError _classifyError(dynamic error, {StackTrace? stackTrace, Map<String, dynamic>? context}) {
    if (error == null) {
      return SyncError(
        type: SyncErrorType.unknown,
        message: 'خطأ غير معروف',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') ||
        errorString.contains('connection') ||
        errorString.contains('socket') ||
        errorString.contains('dns')) {
      return SyncError(
        type: SyncErrorType.network,
        message: 'فشل الاتصال بالشبكة',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    if (errorString.contains('timeout') || errorString.contains('timed out')) {
      return SyncError(
        type: SyncErrorType.timeout,
        message: 'انتهت مهلة الاتصال',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    if (errorString.contains('auth') || errorString.contains('unauthorized') || errorString.contains('401')) {
      return SyncError(
        type: SyncErrorType.authentication,
        message: 'فشل المصادقة',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    if (errorString.contains('permission') || errorString.contains('forbidden') || errorString.contains('403')) {
      return SyncError(
        type: SyncErrorType.permission,
        message: 'لا توجد صلاحيات كافية',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    if (errorString.contains('corrupt') || errorString.contains('invalid') || errorString.contains('parse')) {
      return SyncError(
        type: SyncErrorType.dataCorruption,
        message: 'بيانات تالفة أو غير صالحة',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    if (errorString.contains('storage') || errorString.contains('quota') || errorString.contains('space')) {
      return SyncError(
        type: SyncErrorType.storageLimit,
        message: 'مساحة التخزين ممتلئة',
        originalError: error,
        stackTrace: stackTrace,
        context: context,
      );
    }

    return SyncError(
      type: SyncErrorType.unknown,
      message: error.toString(),
      originalError: error,
      stackTrace: stackTrace,
      context: context,
    );
  }

  void _recordError(SyncError error) {
    _errorHistory.add(error);
    if (_errorHistory.length > _maxHistorySize) {
      _errorHistory.removeAt(0);
    }
  }

  void _emitError(SyncError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  void _logError(SyncError error) {
    debugPrint('❌ [SyncError] ${error.type.name}: ${error.message}');
    if (error.context != null) {
      debugPrint('   Context: ${error.context}');
    }
    if (error.stackTrace != null && kDebugMode) {
      debugPrint('   Stack: ${error.stackTrace}');
    }
  }

  List<SyncError> getRecentErrors({int limit = 10}) {
    final start = _errorHistory.length > limit ? _errorHistory.length - limit : 0;
    return _errorHistory.sublist(start);
  }

  Map<SyncErrorType, int> getErrorStatistics() {
    final stats = <SyncErrorType, int>{};
    for (final error in _errorHistory) {
      stats[error.type] = (stats[error.type] ?? 0) + 1;
    }
    return stats;
  }

  void clearHistory() {
    _errorHistory.clear();
  }

  void dispose() {
    _errorController.close();
  }
}
