import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

enum MutexAcquireResult {
  acquired,
  timeout,
  maxRetriesExceeded,
}

class MutexAcquireResponse {
  final MutexAcquireResult result;
  final int attempts;
  final Duration totalWaitTime;

  const MutexAcquireResponse({
    required this.result,
    required this.attempts,
    required this.totalWaitTime,
  });

  bool get isAcquired => result == MutexAcquireResult.acquired;
}

class SyncMutex {
  Completer<void>? _completer;
  bool _locked = false;
  String? _lockHolder;
  DateTime? _lockAcquiredAt;
  int _totalAcquisitions = 0;
  int _totalTimeouts = 0;

  bool get isLocked => _locked;
  String? get lockHolder => _lockHolder;
  DateTime? get lockAcquiredAt => _lockAcquiredAt;
  Duration? get lockDuration => _lockAcquiredAt != null 
      ? DateTime.now().difference(_lockAcquiredAt!) 
      : null;

  Map<String, dynamic> get stats => {
    'isLocked': _locked,
    'lockHolder': _lockHolder,
    'lockDuration': lockDuration?.inMilliseconds,
    'totalAcquisitions': _totalAcquisitions,
    'totalTimeouts': _totalTimeouts,
  };

  Future<bool> acquire({Duration? timeout, String? holder}) async {
    final response = await acquireWithRetry(
      timeout: timeout,
      maxRetries: 1,
      holder: holder,
    );
    return response.isAcquired;
  }

  Future<MutexAcquireResponse> acquireWithRetry({
    Duration? timeout,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    double backoffMultiplier = 2.0,
    Duration maxDelay = const Duration(seconds: 5),
    String? holder,
  }) async {
    final startTime = DateTime.now();
    int attempts = 0;
    Duration currentDelay = initialDelay;

    while (attempts < maxRetries) {
      attempts++;

      final acquired = await _tryAcquire(timeout: timeout);
      if (acquired) {
        _lockHolder = holder;
        _lockAcquiredAt = DateTime.now();
        _totalAcquisitions++;
        
        debugPrint('🔒 [Mutex] قفل مكتسب${holder != null ? " بواسطة $holder" : ""} (محاولة $attempts)');
        
        return MutexAcquireResponse(
          result: MutexAcquireResult.acquired,
          attempts: attempts,
          totalWaitTime: DateTime.now().difference(startTime),
        );
      }

      if (attempts < maxRetries) {
        final jitter = Random().nextInt(100);
        final delayWithJitter = currentDelay + Duration(milliseconds: jitter);
        
        debugPrint('⏳ [Mutex] انتظار ${delayWithJitter.inMilliseconds}ms قبل المحاولة ${attempts + 1}/$maxRetries');
        await Future.delayed(delayWithJitter);
        
        currentDelay = Duration(
          milliseconds: min(
            (currentDelay.inMilliseconds * backoffMultiplier).round(),
            maxDelay.inMilliseconds,
          ),
        );
      }
    }

    _totalTimeouts++;
    debugPrint('⚠️ [Mutex] فشل الحصول على القفل بعد $attempts محاولات');
    
    return MutexAcquireResponse(
      result: MutexAcquireResult.maxRetriesExceeded,
      attempts: attempts,
      totalWaitTime: DateTime.now().difference(startTime),
    );
  }

  Future<bool> _tryAcquire({Duration? timeout}) async {
    final startTime = DateTime.now();

    while (_locked) {
      if (timeout != null && DateTime.now().difference(startTime) > timeout) {
        return false;
      }

      try {
        if (timeout != null) {
          final remaining = timeout - DateTime.now().difference(startTime);
          if (remaining.isNegative) return false;
          await _completer!.future.timeout(remaining);
        } else {
          await _completer!.future;
        }
      } on TimeoutException {
        return false;
      }
    }

    _locked = true;
    _completer = Completer<void>();
    return true;
  }

  void release() {
    if (_locked) {
      final holder = _lockHolder;
      final duration = lockDuration;
      
      _locked = false;
      _lockHolder = null;
      _lockAcquiredAt = null;
      _completer!.complete();
      
      debugPrint('🔓 [Mutex] قفل محرر${holder != null ? " من $holder" : ""}${duration != null ? " (${duration.inMilliseconds}ms)" : ""}');
    }
  }

  Future<T?> runExclusive<T>(
    Future<T> Function() action, {
    Duration? timeout,
    String? holder,
  }) async {
    final acquired = await acquire(timeout: timeout, holder: holder);
    if (!acquired) return null;

    try {
      return await action();
    } finally {
      release();
    }
  }

  Future<MutexRunResult<T>> runExclusiveWithRetry<T>(
    Future<T> Function() action, {
    Duration? timeout,
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    String? holder,
  }) async {
    final acquireResponse = await acquireWithRetry(
      timeout: timeout,
      maxRetries: maxRetries,
      initialDelay: initialDelay,
      holder: holder,
    );

    if (!acquireResponse.isAcquired) {
      return MutexRunResult<T>(
        success: false,
        acquireResult: acquireResponse.result,
        attempts: acquireResponse.attempts,
      );
    }

    try {
      final result = await action();
      return MutexRunResult<T>(
        success: true,
        value: result,
        acquireResult: acquireResponse.result,
        attempts: acquireResponse.attempts,
      );
    } catch (e) {
      return MutexRunResult<T>(
        success: false,
        error: e,
        acquireResult: acquireResponse.result,
        attempts: acquireResponse.attempts,
      );
    } finally {
      release();
    }
  }

  void forceRelease() {
    if (_locked) {
      debugPrint('⚠️ [Mutex] تحرير قسري للقفل${_lockHolder != null ? " من $_lockHolder" : ""}');
      _locked = false;
      _lockHolder = null;
      _lockAcquiredAt = null;
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete();
      }
    }
  }
}

class MutexRunResult<T> {
  final bool success;
  final T? value;
  final Object? error;
  final MutexAcquireResult acquireResult;
  final int attempts;

  const MutexRunResult({
    required this.success,
    this.value,
    this.error,
    required this.acquireResult,
    required this.attempts,
  });

  bool get hasValue => success && value != null;
  bool get hasError => error != null;
}
