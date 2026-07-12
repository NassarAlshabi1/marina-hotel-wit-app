/// ⚠️ تحذير أمني: لا تُدمج أسرار حقيقية كقيم افتراضية!
///
/// يجب تمرير جميع الأسرار عبر --dart-define عند البناء:
/// ```bash
/// flutter run \
///   --dart-define=BASE_API_URL=https://your-api.com/api/v1 \
///   --dart-define=TELEGRAM_BOT_TOKEN=your_bot_token \
///   --dart-define=TELEGRAM_CHAT_ID=your_chat_id \
///   --dart-define=WHATSAPP_PHONE_NUMBER=your_phone \
///   --dart-define=WHATSAPP_API_KEY=your_api_key \
///   --dart-define=WHATSAPP_API_TOKEN=your_token \
///   --dart-define=WHATSAPP_INSTANCE_ID=your_instance_id \
///   --dart-define=HOTEL_CONTACT_PHONE=your_phone \
///   --dart-define=AGENT_ROUTER_API_KEY=your_agent_router_key \
///   --dart-define=AGENT_ROUTER_BASE_URL=https://openrouter.ai/api/v1
/// ```
///
/// القيم الافتراضية الفارغة تعني أن الميزة ستكون معطلة حتى يتم توفير القيمة.
class Env {
  /// Base URL for API v1
  ///
  /// للمحاكي Android: استخدم 10.0.2.2
  /// للمحاكي iOS: استخدم localhost
  /// للجهاز الحقيقي: استخدم IP الحاسوب على الشبكة المحلية (مثل: 192.168.1.x)
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Telegram Secrets
  // ═══════════════════════════════════════════════════════════════

  /// Telegram Bot Token — يجب تمريره عبر --dart-define
  static const String telegramBotToken = String.fromEnvironment(
    'TELEGRAM_BOT_TOKEN',
  );

  /// Telegram Chat ID — يجب تمريره عبر --dart-define
  static const String telegramChatId = String.fromEnvironment(
    'TELEGRAM_CHAT_ID',
  );

  // ═══════════════════════════════════════════════════════════════
  //  WhatsApp / CallMeBot Secrets
  // ═══════════════════════════════════════════════════════════════

  /// رقم هاتف WhatsApp المستقبل (CallMeBot) — يجب تمريره عبر --dart-define
  static const String whatsappPhoneNumber = String.fromEnvironment(
    'WHATSAPP_PHONE_NUMBER',
  );

  /// مفتاح API CallMeBot — يجب تمريره عبر --dart-define
  static const String whatsappApiKey = String.fromEnvironment(
    'WHATSAPP_API_KEY',
  );

  // ═══════════════════════════════════════════════════════════════
  //  WhatsApp GreenAPI Secrets
  // ═══════════════════════════════════════════════════════════════

  /// WhatsApp GreenAPI Token — يجب تمريره عبر --dart-define
  static const String whatsappApiToken = String.fromEnvironment(
    'WHATSAPP_API_TOKEN',
  );

  /// WhatsApp GreenAPI Instance ID — يجب تمريره عبر --dart-define
  static const String whatsappInstanceId = String.fromEnvironment(
    'WHATSAPP_INSTANCE_ID',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Hotel Contact
  // ═══════════════════════════════════════════════════════════════

  /// رقم هاتف الفندق (يظهر في رسائل الديون) — يجب تمريره عبر --dart-define
  static const String hotelContactPhone = String.fromEnvironment(
    'HOTEL_CONTACT_PHONE',
  );

  // ═══════════════════════════════════════════════════════════════
  //  AgentRouter AI
  // ═══════════════════════════════════════════════════════════════

  /// مفتاح AgentRouter API — يجب تمريره عبر --dart-define
  static const String agentRouterApiKey = String.fromEnvironment(
    'AGENT_ROUTER_API_KEY',
  );

  /// رابط AgentRouter API الأساسي — يجب تمريره عبر --dart-define
  static const String agentRouterBaseUrl = String.fromEnvironment(
    'AGENT_ROUTER_BASE_URL',
    defaultValue: 'https://openrouter.ai/api/v1',
  );

  // ═══════════════════════════════════════════════════════════════
  //  FCM Server Key (للإرسال المباشر من التطبيق)
  // ═══════════════════════════════════════════════════════════════
  // ⚠️ أمني: هذا المفتاح حساس! احصل عليه من:
  // Firebase Console → Project Settings → Cloud Messaging → Server Key
  // مرّره عبر --dart-define=FCM_SERVER_KEY=your_key
  //
  // ملاحظة: Legacy Server Key مُهمَل من Google لكنه يعمل للإرسال المباشر.
  // للإنتاج، استبدل هذا بـ Appwrite Function + Firebase Admin SDK.
  static const String fcmServerKey = String.fromEnvironment(
    'FCM_SERVER_KEY',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Convenience checks
  // ═══════════════════════════════════════════════════════════════

  /// هل تم تكوين Telegram؟
  static bool get isTelegramConfigured =>
      telegramBotToken.isNotEmpty && telegramChatId.isNotEmpty;

  /// هل تم تكوين WhatsApp CallMeBot؟
  static bool get isWhatsAppCallMeBotConfigured =>
      whatsappPhoneNumber.isNotEmpty && whatsappApiKey.isNotEmpty;

  /// هل تم تكوين WhatsApp GreenAPI؟
  static bool get isWhatsAppGreenApiConfigured =>
      whatsappApiToken.isNotEmpty && whatsappInstanceId.isNotEmpty;

  /// هل تم تكوين API الأساسي؟
  static bool get isApiConfigured => baseApiUrl.isNotEmpty;

  /// هل تم تكوين AgentRouter AI؟
  static bool get isAgentRouterConfigured => agentRouterApiKey.isNotEmpty;

  /// هل تم تكوين FCM للإرسال المباشر؟
  static bool get isFcmSendConfigured => fcmServerKey.isNotEmpty;
}
