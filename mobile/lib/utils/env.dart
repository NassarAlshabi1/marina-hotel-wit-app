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

  // Ditto Cloud Configuration
  // ⚠️ معلومات حساسة - لا تشارك هذه البيانات
  static String dittoAppId = const String.fromEnvironment(
    'DITTO_APP_ID',
    defaultValue: '1507d904-d3ed-4ac3-824c-249c18170eee',
  );
  
  static String dittoPlaygroundToken = const String.fromEnvironment(
    'DITTO_PLAYGROUND_TOKEN',
    defaultValue: 'dbae5191-2cb5-4fb5-8aca-9f9d85e0409a',
  );
  
  // API Token للاستخدام المتقدم
  static String dittoApiToken = const String.fromEnvironment(
    'DITTO_API_TOKEN',
    defaultValue: 'Vc4wt9ruMMtlf9zS1wh8RSoqT8HN9aB8CYfeDY95KC4kKSEtkfmgHOupZBkO',
  );
  
  // Cloud Webhook URL
  static String dittoCloudWebhook = const String.fromEnvironment(
    'DITTO_CLOUD_WEBHOOK',
    defaultValue: 'i83inp.cloud.dittolive.app/1507d904-d3ed-4ac3-824c-249c18170eee',
  );
  
  // استخدام وضع Playground للتطوير (true) أو Production (false)
  static bool dittoUsePlayground = const bool.fromEnvironment(
    'DITTO_USE_PLAYGROUND',
    defaultValue: true,
  );
}
