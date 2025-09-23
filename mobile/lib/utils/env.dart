class Env {
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://192.168.1.100/MARINA_HOTEL_PORTABLE/api/v1',
  );
}
