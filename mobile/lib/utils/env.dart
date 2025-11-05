class Env {
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://hotelmarina.com/MARINA_HOTEL_PORTABLE/api/v1',
  );

  static const String supabaseLoginEmail = String.fromEnvironment(
    'SUPABASE_LOGIN_EMAIL',
    defaultValue: '',
  );

  static const String supabaseLoginPassword = String.fromEnvironment(
    'SUPABASE_LOGIN_PASSWORD',
    defaultValue: '',
  );
}
