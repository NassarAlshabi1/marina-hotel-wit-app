class Env {
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://hotelmarina.com/MARINA_HOTEL_PORTABLE/api/v1',
  );
  // TODO: Wire actual API v1 in next phase.

  // Supabase Login Credentials
  // يمكنك تغيير هذه القيم حسب حساب Supabase الخاص بك
  static String supabaseLoginEmail = const String.fromEnvironment(
    'SUPABASE_LOGIN_EMAIL',
    defaultValue: 'adenmarina2@gmail.com',
  );
  static String supabaseLoginPassword = const String.fromEnvironment(
    'SUPABASE_LOGIN_PASSWORD',
    defaultValue: 'Tottinnbb007',
  );
}
