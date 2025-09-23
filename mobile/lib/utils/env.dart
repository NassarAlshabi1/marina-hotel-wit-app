class Env {
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://127.0.0.1/MARINA_HOTEL_PORTABLE/api/v1',
  );
  // TODO: Wire actual API v1 in next phase.
}
