class Env {
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://hotelmarina.com/MARINA_HOTEL_PORTABLE/api/v1',
  );
  static String pocketbaseUrl = const String.fromEnvironment(
    'POCKETBASE_URL',
    defaultValue: 'https://marina-hotel-pocketbase.fly.dev',
  );
}
