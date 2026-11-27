import 'dart:async';

import 'package:flutter/foundation.dart';

import 'debug_log.dart';
import 'performance_monitor.dart';

/// Adds lightweight timing logs to a Dashboard data stream.
///
/// The transformer is disabled in release builds. In debug/profile builds it
/// reports the time to each emission, which makes it possible to compare the
/// first-load latency and subsequent refresh cost before and after changes.
Stream<T> measureDashboardProvider<T>(
  String providerName,
  Stream<T> source, {
  int Function(T value)? itemCount,
}) {
  if (!kDebugMode && !profileInstrumentationEnabled) return source;

  return source.transform(
    StreamTransformer<T, T>.fromBind((stream) {
      final stopwatch = Stopwatch()..start();
      var emission = 0;
      return stream.map((value) {
        emission++;
        final count = itemCount?.call(value);
        final suffix = count == null ? '' : ', items=$count';
        final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
        final message =
            '[DashboardProvider] $providerName #$emission '
            'elapsed=${elapsedMs.toStringAsFixed(1)}ms$suffix';
        if (profileInstrumentationEnabled && !kDebugMode) {
          debugPrint(message);
        } else {
          dlog(message);
        }
        return value;
      });
    }),
  );
}
