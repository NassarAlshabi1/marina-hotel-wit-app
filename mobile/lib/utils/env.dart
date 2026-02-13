class Env {
  /// Base URL for API v1
  ///
  /// للمحاكي Android: استخدم 10.0.2.2
  /// للمحاكي iOS: استخدم localhost
  /// للجهاز الحقيقي: استخدم IP الحاسوب على الشبكة المحلية (مثل: 192.168.1.x)
  ///
  /// لتغيير URL عند البناء:
  /// flutter run --dart-define=BASE_API_URL=http://192.168.1.5/marina-hotel-wit-app/api/v1
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://10.0.0.222:8080/api/v1',
  );
}
