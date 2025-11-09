/// إعدادات Ditto Cloud للمشروع
class DittoConfig {
  // ✅ إعدادات Ditto Cloud الحقيقية
  
  /// معرف التطبيق من Ditto Cloud Dashboard
  static const String appId = "1507d904-d3ed-4ac3-824c-249c18170eee";
  
  /// رمز Playground من Ditto Cloud Dashboard  
  static const String playgroundToken = "dbae5191-2cb5-4fb5-8aca-9f9d85e0409a";
  
  /// API Token للمصادقة المتقدمة
  static const String apiToken = "Vc4wt9ruMMtlf9zS1wh8RSoqT8HN9aB8CYfeDY95KC4kKSEtkfmgHOupZBkO";
  
  /// عنوان WebSocket للسحابة (من Cloud Webhook)
  static const String webSocketUrl = "wss://i83inp.cloud.dittolive.app";
  
  /// Cloud Webhook URL الكامل
  static const String cloudWebhookUrl = "i83inp.cloud.dittolive.app/1507d904-d3ed-4ac3-824c-249c18170eee";
  
  /// عنوان مخصص للمصادقة (اختياري)
  static const String? customAuthUrl = null;
  
  /// إعدادات البيئة
  static const bool isDevelopment = true;
  static const bool enableDebugLogs = true;
  
  /// إعدادات المزامنة
  static const bool enableCloudSync = false;
  static const bool enableP2PSync = false; // معطل للسحابة فقط
  
  /// إعدادات الأداء
  static const int syncTimeoutSeconds = 30;
  static const int maxRetryAttempts = 3;
  static const int heartbeatIntervalSeconds = 60;
  
  /// التحقق من صحة الإعدادات
  static bool get isConfigured {
    return appId.isNotEmpty &&
           playgroundToken.isNotEmpty &&
           apiToken.isNotEmpty &&
           webSocketUrl.isNotEmpty;
  }
  
  /// رسالة خطأ الإعداد
  static String get configErrorMessage {
    if (!isConfigured) {
      return '''
❌ خطأ في إعدادات Ditto Cloud:

تحقق من أن جميع الإعدادات موجودة:
- App ID: ${appId.isNotEmpty ? '✅' : '❌'}
- Playground Token: ${playgroundToken.isNotEmpty ? '✅' : '❌'}  
- API Token: ${apiToken.isNotEmpty ? '✅' : '❌'}
- WebSocket URL: ${webSocketUrl.isNotEmpty ? '✅' : '❌'}

📝 راجع الدليل في: https://docs.ditto.live/cloud/quickstart
      ''';
    }
    return '';
  }
  
  /// معلومات الإعداد للـ debugging
  static Map<String, dynamic> get debugInfo {
    return {
      'app_id': appId.replaceRange(8, appId.length, '***'),
      'playground_token': playgroundToken.replaceRange(8, playgroundToken.length, '***'),
      'api_token': apiToken.replaceRange(8, apiToken.length, '***'),
      'websocket_url': webSocketUrl,
      'cloud_webhook': cloudWebhookUrl,
      'configured': isConfigured,
      'cloud_sync': enableCloudSync,
      'p2p_sync': enableP2PSync,
      'is_development': isDevelopment,
      'debug_logs': enableDebugLogs,
    };
  }
}