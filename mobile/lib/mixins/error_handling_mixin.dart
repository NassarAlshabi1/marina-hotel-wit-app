import 'package:flutter/foundation.dart';

mixin ErrorHandlingMixin {
  String get logTag => runtimeType.toString();

  Future<T?> tryAsync<T>(
    Future<T> Function() operation, {
    String? operationName,
    void Function(dynamic error, StackTrace stack)? onError,
  }) async {
    try {
      return await operation();
    } catch (e, stack) {
      debugPrint('❌ [$logTag] ${operationName ?? 'Operation'} failed: $e');
      debugPrint('$stack');
      onError?.call(e, stack);
      return null;
    }
  }

  T? trySync<T>(
    T Function() operation, {
    String? operationName,
  }) {
    try {
      return operation();
    } catch (e, stack) {
      debugPrint('❌ [$logTag] ${operationName ?? 'Operation'} failed: $e');
      return null;
    }
  }
}
