class Env {
  /// Base URL for API v1
  ///
  /// للمحاكي Android: استخدم 10.0.2.2
  /// للمحاكي iOS: استخدم localhost
  /// للجهاز الحقيقي: استخدم IP الحاسوب على الشبكة المحلية (مثل: 192.168.1.x)
  ///
  /// لتغيير URL عند البناء:
  /// flutter run --dart-define=BASE_API_URL=http://192.168.1.5/marina-hotel-wit-app/api/v1
  static String baseApiUrl = const String.fromEnvironment(
    'BASE_API_URL',
    defaultValue: 'http://10.0.0.222:8080/api/v1',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Telegram Secrets
  // ═══════════════════════════════════════════════════════════════

  /// Telegram Bot Token
  ///
  /// لتغيير القيمة عند البناء:
  /// flutter run --dart-define=TELEGRAM_BOT_TOKEN=your_token
  static const String telegramBotToken = String.fromEnvironment(
    'TELEGRAM_BOT_TOKEN',
    defaultValue: '7602573830:AAHkWt9k9nBMJ8NhlpkyTs9wAJn_zAL79Ac',
  );

  /// Telegram Chat ID
  ///
  /// لتغيير القيمة عند البناء:
  /// flutter run --dart-define=TELEGRAM_CHAT_ID=your_chat_id
  static const String telegramChatId = String.fromEnvironment(
    'TELEGRAM_CHAT_ID',
    defaultValue: '5944227208',
  );

  // ═══════════════════════════════════════════════════════════════
  //  WhatsApp / CallMeBot Secrets
  // ═══════════════════════════════════════════════════════════════

  /// رقم هاتف WhatsApp المستقبل (CallMeBot)
  ///
  /// لتغيير القيمة عند البناء:
  /// flutter run --dart-define=WHATSAPP_PHONE_NUMBER=your_phone
  static const String whatsappPhoneNumber = String.fromEnvironment(
    'WHATSAPP_PHONE_NUMBER',
    defaultValue: '967773749389',
  );

  /// مفتاح API CallMeBot
  ///
  /// لتغيير القيمة عند البناء:
  /// flutter run --dart-define=WHATSAPP_API_KEY=your_api_key
  static const String whatsappApiKey = String.fromEnvironment(
    'WHATSAPP_API_KEY',
    defaultValue: '7379268',
  );

  // ═══════════════════════════════════════════════════════════════
  //  WhatsApp GreenAPI Secrets
  // ═══════════════════════════════════════════════════════════════

  /// WhatsApp GreenAPI Token
  ///
  /// لتغيير القيمة عند البناء:
  /// flutter run --dart-define=WHATSAPP_API_TOKEN=your_token
  static const String whatsappApiToken = String.fromEnvironment(
    'WHATSAPP_API_TOKEN',
    defaultValue: 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
  );

  /// WhatsApp GreenAPI Instance ID
  ///
  /// لتغيير القيمة عند البناء:
  /// flutter run --dart-define=WHATSAPP_INSTANCE_ID=your_instance_id
  static const String whatsappInstanceId = String.fromEnvironment(
    'WHATSAPP_INSTANCE_ID',
    defaultValue: 'waInstance7103894450',
  );

  // ═══════════════════════════════════════════════════════════════
  //  Hotel Contact
  // ═══════════════════════════════════════════════════════════════

  /// رقم هاتف الفندق (يظهر في رسائل الديون)
  ///
  /// لتغيير القيمة عند البناء:
  /// flutter run --dart-define=HOTEL_CONTACT_PHONE=your_phone
  static const String hotelContactPhone = String.fromEnvironment(
    'HOTEL_CONTACT_PHONE',
    defaultValue: '9677734587456',
  );
}
