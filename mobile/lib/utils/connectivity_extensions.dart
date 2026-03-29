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
