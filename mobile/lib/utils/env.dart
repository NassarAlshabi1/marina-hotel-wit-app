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
  static String baseApiUrl = const String.fromEnvironment('BASE_API_URL');

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
  //  FCM Legacy Server Key (للإرسال المباشر من التطبيق — مهمل لكنه يعمل)
  // ═══════════════════════════════════════════════════════════════
  // ⚠️ أمني: هذا المفتاح حساس! احصل عليه من:
  // Firebase Console → Project Settings → Cloud Messaging → Server Key
  // مرّره عبر --dart-define=FCM_SERVER_KEY=your_key
  //
  // ملاحظة: Legacy Server Key مُهمَل من Google لكنه يعمل للإرسال المباشر.
  // يُفضّل استخدام FCM HTTP v1 عبر [fcmServiceAccountJson] أدناه.
  static const String fcmServerKey = String.fromEnvironment('FCM_SERVER_KEY');

  // ═══════════════════════════════════════════════════════════════
  //  FCM HTTP v1 (الطريقة الموصى بها — عبر حساب خدمة Firebase)
  // ═══════════════════════════════════════════════════════════════
  // مرّر JSON حساب الخدمة (base64-encoded بدون newlines) عبر:
  //   --dart-define=FCM_SERVICE_ACCOUNT_JSON=$(base64 -w0 fcm-key.json)
  //
  // مرّر project_id من حساب الخدمة عبر:
  //   --dart-define=FCM_PROJECT_ID=aden-flutter
  //
  // آلية العمل:
  //   1. التطبيق يفك base64 → JSON → private_key + client_email
  //   2. يبني JWT موقّع بـ RS256 (pointycastle)
  //   3. يطلب access_token من https://oauth2.googleapis.com/token
  //   4. يستخدم الـ token للإرسال عبر
  //      https://fcm.googleapis.com/v1/projects/{project_id}/messages:send
  //
  // ⚠️ أمني: مفتاح حساب الخدمة حساس جداً! أي شخص يملكه يستطيع إرسال إشعارات
  //    لكل مستخدمي Firebase project. ضعه في GitHub Secret (وليس في الكود).
  //    البديل الأكثر أماناً: Appwrite Function + Firebase Admin SDK على الخادم.
  static const String fcmServiceAccountJson = String.fromEnvironment(
    'FCM_SERVICE_ACCOUNT_JSON',
  );

  static const String fcmProjectId = String.fromEnvironment(
    'FCM_PROJECT_ID',
  );

  // ═══════════════════════════════════════════════════════════════
  //  PostHog Analytics (Session Replay + Feature Flags + Product Analytics)
  // ═══════════════════════════════════════════════════════════════
  // PostHog Cloud — مجاني حتى 1M حدث/شهر + 5K session replay/شهر
  // احصل على المفتاح من: https://app.posthog.com/project/settings
  // مرّره عبر:
  //   --dart-define=POSTHOG_API_KEY=phc_xxxxx
  //   --dart-define=POSTHOG_HOST=https://app.posthog.com  (اختياري، افتراضي Cloud)

  /// PostHog API Key — يجب تمريره عبر --dart-define
  static const String posthogApiKey = String.fromEnvironment(
    'POSTHOG_API_KEY',
  );

  /// PostHog Host — افتراضي: Cloud (https://app.posthog.com)
  /// للـ self-hosted: مرّر عنوان خادمك (مثل: https://posthog.yourdomain.com)
  static const String posthogHost = String.fromEnvironment(
    'POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
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

  /// هل تم تكوين FCM v1 (HTTP v1 + service account)؟
  /// الطريقة الموصى بها — تتفوق على Legacy Server Key.
  static bool get isFcmV1Configured =>
      fcmServiceAccountJson.isNotEmpty && fcmProjectId.isNotEmpty;

  /// هل تم تكوين FCM Legacy (Server Key)؟ — مهمل لكنه يعمل.
  static bool get isFcmLegacyConfigured => fcmServerKey.isNotEmpty;

  /// هل تم تكوين FCM للإرسال المباشر (أي طريقة)؟
  static bool get isFcmSendConfigured =>
      isFcmV1Configured || isFcmLegacyConfigured;

  /// هل تم تكوين PostHog؟
  static bool get isPosthogConfigured => posthogApiKey.isNotEmpty;

  // ═══════════════════════════════════════════════════════════════
  //  Cloudflare Worker API
  // ═══════════════════════════════════════════════════════════════
  static const String cloudflareWorkerUrl = String.fromEnvironment(
    'CLOUDFLARE_WORKER_URL',
    defaultValue: 'https://marina-hotel-api.adenmarina2.workers.dev',
  );

  static const String cloudflareUsername = String.fromEnvironment(
    'CLOUDFLARE_USERNAME',
  );

  static const String cloudflarePassword = String.fromEnvironment(
    'CLOUDFLARE_PASSWORD',
  );

  /// Auth token (set at runtime after login)
  static String? cloudflareAuthToken;

  /// هل تم تكوين Cloudflare؟
  static bool get isCloudflareConfigured => cloudflareWorkerUrl.isNotEmpty;
}
