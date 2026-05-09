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
///   --dart-define=HOTEL_CONTACT_PHONE=your_phone
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
    defaultValue: '',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Telegram Secrets
  // ═══════════════════════════════════════════════════════════════

  /// Telegram Bot Token — يجب تمريره عبر --dart-define
  static const String telegramBotToken = String.fromEnvironment(
    'TELEGRAM_BOT_TOKEN',
    defaultValue: '',
  );

  /// Telegram Chat ID — يجب تمريره عبر --dart-define
  static const String telegramChatId = String.fromEnvironment(
    'TELEGRAM_CHAT_ID',
    defaultValue: '',
  );

  // ═══════════════════════════════════════════════════════════════
  //  WhatsApp / CallMeBot Secrets
  // ═══════════════════════════════════════════════════════════════

  /// رقم هاتف WhatsApp المستقبل (CallMeBot) — يجب تمريره عبر --dart-define
  static const String whatsappPhoneNumber = String.fromEnvironment(
    'WHATSAPP_PHONE_NUMBER',
    defaultValue: '',
  );

  /// مفتاح API CallMeBot — يجب تمريره عبر --dart-define
  static const String whatsappApiKey = String.fromEnvironment(
    'WHATSAPP_API_KEY',
    defaultValue: '',
  );

  // ═══════════════════════════════════════════════════════════════
  //  WhatsApp GreenAPI Secrets
  // ═══════════════════════════════════════════════════════════════

  /// WhatsApp GreenAPI Token — يجب تمريره عبر --dart-define
  static const String whatsappApiToken = String.fromEnvironment(
    'WHATSAPP_API_TOKEN',
    defaultValue: '',
  );

  /// WhatsApp GreenAPI Instance ID — يجب تمريره عبر --dart-define
  static const String whatsappInstanceId = String.fromEnvironment(
    'WHATSAPP_INSTANCE_ID',
    defaultValue: '',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Hotel Contact
  // ═══════════════════════════════════════════════════════════════

  /// رقم هاتف الفندق (يظهر في رسائل الديون) — يجب تمريره عبر --dart-define
  static const String hotelContactPhone = String.fromEnvironment(
    'HOTEL_CONTACT_PHONE',
    defaultValue: '',
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
}
