class Constants {
  static const appName = 'مارينا بلازا';

  // API Configuration
  // ✅ SECURITY: Default to HTTPS. HTTP is rejected by Dio's badCertificateCallback.
  static const String baseApiUrl = String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'https://hotelmarina.com/MARINA_HOTEL_PORTABLE/api/v1',
  );

  // App Configuration
  static const String appVersion = '1.0.0';
  static const int apiTimeoutSeconds = 30;
}
