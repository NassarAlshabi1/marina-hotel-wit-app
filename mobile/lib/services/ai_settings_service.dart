// lib/services/ai_settings_service.dart
// خدمة إعدادات AI — تتيح للمستخدم تغيير إعدادات المساعد الذكي
//
// يدعم:
// - اختيار المزود (Gemini / OpenRouter)
// - اختيار الموديل (gemini-2.5-flash, gemini-2.0-flash, etc.)
// - تخصيص مفتاح API (لـ OpenRouter)
// - تخصيص درجة الحرارة (temperature)
// - تخصيص الحد الأقصى للتوكنز

import 'package:shared_preferences/shared_preferences.dart';

/// مزود خدمة AI
enum AiProviderType {
  gemini('Firebase AI (Gemini)'),
  openrouter('OpenRouter (متعدد الموديلات)');

  const AiProviderType(this.displayName);
  final String displayName;
}

/// الموديلات المتاحة لكل مزود
class AiModelOption {
  final String id;
  final String displayName;
  final String provider;
  final String description;

  const AiModelOption({
    required this.id,
    required this.displayName,
    required this.provider,
    required this.description,
  });

  static const geminiModels = [
    AiModelOption(
      id: 'gemini-2.5-flash',
      displayName: 'Gemini 2.5 Flash',
      provider: 'gemini',
      description: 'الأحدث — سريع وذكي (موصى به)',
    ),
    AiModelOption(
      id: 'gemini-2.5-pro',
      displayName: 'Gemini 2.5 Pro',
      provider: 'gemini',
      description: 'الأقوى — للتحليلات المعقدة (أبطأ)',
    ),
    AiModelOption(
      id: 'gemini-2.0-flash',
      displayName: 'Gemini 2.0 Flash',
      provider: 'gemini',
      description: 'إصدار سابق — مستقر',
    ),
  ];

  static const openrouterModels = [
    AiModelOption(
      id: 'google/gemini-2.5-flash-preview',
      displayName: 'Gemini 2.5 Flash (OpenRouter)',
      provider: 'openrouter',
      description: 'عبر OpenRouter — يتطلب API key',
    ),
    AiModelOption(
      id: 'google/gemini-2.5-pro-preview',
      displayName: 'Gemini 2.5 Pro (OpenRouter)',
      provider: 'openrouter',
      description: 'عبر OpenRouter — للتحليلات المعقدة',
    ),
    AiModelOption(
      id: 'anthropic/claude-3.5-sonnet',
      displayName: 'Claude 3.5 Sonnet',
      provider: 'openrouter',
      description: 'نموذج Anthropic — ممتاز للعربية',
    ),
    AiModelOption(
      id: 'openai/gpt-4o-mini',
      displayName: 'GPT-4o Mini',
      provider: 'openrouter',
      description: 'نموذج OpenAI — سريع واقتصادي',
    ),
    AiModelOption(
      id: 'meta-llama/llama-3.3-70b-instruct',
      displayName: 'Llama 3.3 70B',
      provider: 'openrouter',
      description: 'نموذج Meta — مفتوح المصدر',
    ),
  ];

  static List<AiModelOption> getModelsForProvider(String provider) {
    if (provider == 'gemini') return geminiModels;
    if (provider == 'openrouter') return openrouterModels;
    return [...geminiModels, ...openrouterModels];
  }
}

/// خدمة إعدادات AI
class AiSettingsService {
  factory AiSettingsService() => _instance;
  AiSettingsService._internal();
  static final AiSettingsService _instance = AiSettingsService._internal();
  static AiSettingsService get instance => _instance;

  static const _keyProvider = 'ai_provider';
  static const _keyModel = 'ai_model';
  static const _keyApiKey = 'ai_api_key';
  static const _keyBaseUrl = 'ai_base_url';
  static const _keyTemperature = 'ai_temperature';
  static const _keyMaxTokens = 'ai_max_tokens';
  static const _keySystemPromptExtra = 'ai_system_prompt_extra';

  SharedPreferences? _prefs;

  /// تهيئة الخدمة
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// المزود الحالي
  String get provider {
    return _prefs?.getString(_keyProvider) ?? 'gemini';
  }

  set provider(String value) {
    _prefs?.setString(_keyProvider, value);
  }

  /// الموديل الحالي
  String get model {
    return _prefs?.getString(_keyModel) ?? 'gemini-2.5-flash';
  }

  set model(String value) {
    _prefs?.setString(_keyModel, value);
  }

  /// مفتاح API (لـ OpenRouter)
  String get apiKey {
    return _prefs?.getString(_keyApiKey) ?? '';
  }

  set apiKey(String value) {
    _prefs?.setString(_keyApiKey, value);
  }

  /// عنوان الـ API
  String get baseUrl {
    return _prefs?.getString(_keyBaseUrl) ?? 'https://openrouter.ai/api/v1';
  }

  set baseUrl(String value) {
    _prefs?.setString(_keyBaseUrl, value);
  }

  /// درجة الحرارة (0.0 - 1.0)
  double get temperature {
    return _prefs?.getDouble(_keyTemperature) ?? 0.2;
  }

  set temperature(double value) {
    _prefs?.setDouble(_keyTemperature, value.clamp(0.0, 1.0));
  }

  /// الحد الأقصى للتوكنز
  int get maxTokens {
    return _prefs?.getInt(_keyMaxTokens) ?? 4096;
  }

  set maxTokens(int value) {
    _prefs?.setInt(_keyMaxTokens, value);
  }

  /// تعليمات إضافية للـ system prompt
  String get systemPromptExtra {
    return _prefs?.getString(_keySystemPromptExtra) ?? '';
  }

  set systemPromptExtra(String value) {
    _prefs?.setString(_keySystemPromptExtra, value);
  }

  /// هل الإعدادات مُهيأة لـ OpenRouter؟
  bool get isOpenRouterConfigured {
    return provider == 'openrouter' && apiKey.isNotEmpty;
  }

  /// هل يستخدم Gemini المباشر؟
  bool get isGeminiDirect {
    return provider == 'gemini';
  }

  /// إعادة تعيين كل الإعدادات
  Future<void> resetToDefaults() async {
    await _prefs?.remove(_keyProvider);
    await _prefs?.remove(_keyModel);
    await _prefs?.remove(_keyApiKey);
    await _prefs?.remove(_keyBaseUrl);
    await _prefs?.remove(_keyTemperature);
    await _prefs?.remove(_keyMaxTokens);
    await _prefs?.remove(_keySystemPromptExtra);
  }
}
