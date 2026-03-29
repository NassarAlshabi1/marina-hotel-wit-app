import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// إضافات (Extensions) لتبسيط التعامل مع connectivity_plus.
extension ConnectivityResultListX on List<ConnectivityResult> {
  /// هل أي نتيجة تشير لاتصال فعّال (ليس none فقط)؟
  bool get isOnline =>
      isNotEmpty && !every((r) => r == ConnectivityResult.none);

  /// هل جميع النتائج none (لا اتصال)؟
  bool get isOffline => isEmpty || every((r) => r == ConnectivityResult.none);

  /// وصف مختصر للحالة بالعربية.
  String get displayArabic {
    if (isOffline) return 'بدون اتصال';
    if (any((r) => r == ConnectivityResult.wifi)) return 'WiFi';
    if (any((r) => r == ConnectivityResult.mobile)) return 'بيانات الهاتف';
    if (any((r) => r == ConnectivityResult.ethernet)) return 'Ethernet';
    return 'متصل';
  }
}

/// Stream يُنتظر حتى يعود الاتصال.
///
/// يُستخدم هكذا:
/// ```dart
/// await ConnectivityResultListX.waitUntilOnline();
/// ```
extension ConnectivityResultListWaitX on List<ConnectivityResult> {
  /// ينتظر حتى تصبح الشبكة متاحة، مع timeout اختياري.
  static Future<bool> waitUntilOnline({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final connectivity = Connectivity();

    // فحص فوري
    final current = await connectivity.checkConnectivity();
    if (current.isOnline) return true;

    // انتظار التغيير
    final completer = Completer<bool>();

    late final StreamSubscription<List<ConnectivityResult>> subscription;
    subscription = connectivity.onConnectivityChanged.listen((result) {
      if (result.isOnline && !completer.isCompleted) {
        subscription.cancel();
        completer.complete(true);
      }
    });

    // Timeout
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        subscription.cancel();
        completer.complete(false);
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }
}
