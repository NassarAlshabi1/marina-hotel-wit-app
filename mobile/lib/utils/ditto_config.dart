/// إعدادات Ditto Cloud
/// 
/// هذا الملف يحتوي على الإعدادات اللازمة للاتصال بـ Ditto Cloud
class DittoConfig {
  /// App ID من Ditto Portal
  /// احصل عليه من: https://portal.ditto.live
  static String appId = const String.fromEnvironment(
    'DITTO_APP_ID',
    defaultValue: 'YOUR_DITTO_APP_ID_HERE',
  );

  /// Online Playground Token (للتطوير والاختبار فقط)
  /// احصل عليه من: https://portal.ditto.live
  static String playgroundToken = const String.fromEnvironment(
    'DITTO_PLAYGROUND_TOKEN',
    defaultValue: 'YOUR_DITTO_PLAYGROUND_TOKEN_HERE',
  );

  /// استخدام Online Playground (true للتطوير، false للإنتاج)
  static bool useOnlinePlayground = const bool.fromEnvironment(
    'DITTO_USE_PLAYGROUND',
    defaultValue: true,
  );

  /// Production License Token (للإنتاج فقط)
  static String? licenseToken = const String.fromEnvironment(
    'DITTO_LICENSE_TOKEN',
    defaultValue: '',
  );

  /// اسم الجهاز للتعريف في Ditto Portal
  static String deviceName = const String.fromEnvironment(
    'DITTO_DEVICE_NAME',
    defaultValue: 'Marina Hotel Mobile',
  );

  /// تفعيل التزامن التلقائي عند بدء التطبيق
  static bool autoStartSync = const bool.fromEnvironment(
    'DITTO_AUTO_START_SYNC',
    defaultValue: true,
  );

  /// تفعيل سجلات التصحيح (Debug Logging)
  static bool enableDebugLogging = const bool.fromEnvironment(
    'DITTO_DEBUG_LOGGING',
    defaultValue: true,
  );

  /// تفعيل المزامنة عبر Bluetooth LE
  static bool enableBluetoothLE = const bool.fromEnvironment(
    'DITTO_ENABLE_BLE',
    defaultValue: false, // معطل - استخدام الإنترنت فقط
  );

  /// تفعيل المزامنة عبر LAN
  static bool enableLAN = const bool.fromEnvironment(
    'DITTO_ENABLE_LAN',
    defaultValue: false, // معطل - استخدام الإنترنت فقط
  );

  /// تفعيل المزامنة عبر WiFi Direct (Android فقط)
  static bool enableWiFiDirect = const bool.fromEnvironment(
    'DITTO_ENABLE_WIFI_DIRECT',
    defaultValue: false, // معطل - استخدام الإنترنت فقط
  );

  /// تفعيل المزامنة عبر الإنترنت مع Ditto Big Peer
  static bool enableCloud = const bool.fromEnvironment(
    'DITTO_ENABLE_CLOUD',
    defaultValue: true, // مفعل - الطريقة الوحيدة للمزامنة
  );

  /// التحقق من صحة الإعدادات
  static bool isConfigured() {
    if (useOnlinePlayground) {
      return appId.isNotEmpty && 
             appId != 'YOUR_DITTO_APP_ID_HERE' &&
             playgroundToken.isNotEmpty && 
             playgroundToken != 'YOUR_DITTO_PLAYGROUND_TOKEN_HERE';
    } else {
      return appId.isNotEmpty && 
             appId != 'YOUR_DITTO_APP_ID_HERE' &&
             licenseToken != null && 
             licenseToken!.isNotEmpty;
    }
  }

  /// الحصول على رسالة تحذير إذا لم يتم الإعداد
  static String? getConfigurationWarning() {
    if (!isConfigured()) {
      return '''
⚠️ لم يتم إعداد Ditto Cloud بعد

الرجاء اتباع الخطوات التالية:

1. افتح https://portal.ditto.live
2. سجل حساب جديد أو سجل دخول
3. أنشئ تطبيق جديد (New App)
4. انسخ App ID و Playground Token
5. أضف القيم في ملف env.dart أو عبر environment variables:

   DITTO_APP_ID=your_app_id_here
   DITTO_PLAYGROUND_TOKEN=your_token_here

للمزيد من المعلومات، اقرأ DITTO_SETUP_GUIDE.md
      ''';
    }
    return null;
  }
}
