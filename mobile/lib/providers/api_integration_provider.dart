import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'api_integration_settings_v1';

class WhatsAppIntegrationSettings {
  final bool enabled;
  final String baseUrl;
  final String instanceId;
  final String token;
  final String defaultCountryCode;

  const WhatsAppIntegrationSettings({
    required this.enabled,
    required this.baseUrl,
    required this.instanceId,
    required this.token,
    required this.defaultCountryCode,
  });

  WhatsAppIntegrationSettings copyWith({
    bool? enabled,
    String? baseUrl,
    String? instanceId,
    String? token,
    String? defaultCountryCode,
  }) {
    return WhatsAppIntegrationSettings(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      instanceId: instanceId ?? this.instanceId,
      token: token ?? this.token,
      defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'baseUrl': baseUrl,
        'instanceId': instanceId,
        'token': token,
        'defaultCountryCode': defaultCountryCode,
      };

  factory WhatsAppIntegrationSettings.fromJson(Map<String, dynamic> json) {
    return WhatsAppIntegrationSettings(
      enabled: json['enabled'] as bool? ?? true,
      baseUrl: json['baseUrl'] as String? ?? 'https://7103.api.greenapi.com',
      instanceId: json['instanceId'] as String? ?? 'waInstance7103894450',
      token: json['token'] as String? ?? 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
      defaultCountryCode: json['defaultCountryCode'] as String? ?? '+967',
    );
  }
}

class AppwriteIntegrationSettings {
  final bool enabled;
  final String endpoint;
  final String projectId;
  final String databaseId;
  final String apiKey;

  const AppwriteIntegrationSettings({
    required this.enabled,
    required this.endpoint,
    required this.projectId,
    required this.databaseId,
    required this.apiKey,
  });

  AppwriteIntegrationSettings copyWith({
    bool? enabled,
    String? endpoint,
    String? projectId,
    String? databaseId,
    String? apiKey,
  }) {
    return AppwriteIntegrationSettings(
      enabled: enabled ?? this.enabled,
      endpoint: endpoint ?? this.endpoint,
      projectId: projectId ?? this.projectId,
      databaseId: databaseId ?? this.databaseId,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'endpoint': endpoint,
        'projectId': projectId,
        'databaseId': databaseId,
        'apiKey': apiKey,
      };

  factory AppwriteIntegrationSettings.fromJson(Map<String, dynamic> json) {
    return AppwriteIntegrationSettings(
      enabled: json['enabled'] as bool? ?? false,
      endpoint: json['endpoint'] as String? ?? 'https://fra.cloud.appwrite.io/v1',
      projectId: json['projectId'] as String? ?? '690ff0da0025518570c1',
      databaseId: json['databaseId'] as String? ?? 'hotel_db',
      apiKey: json['apiKey'] as String? ?? '',
    );
  }
}

class SupabaseIntegrationSettings {
  final bool enabled;
  final String apiUrl;
  final String anonKey;
  final String serviceRoleKey;
  final String projectRef;

  const SupabaseIntegrationSettings({
    required this.enabled,
    required this.apiUrl,
    required this.anonKey,
    required this.serviceRoleKey,
    required this.projectRef,
  });

  SupabaseIntegrationSettings copyWith({
    bool? enabled,
    String? apiUrl,
    String? anonKey,
    String? serviceRoleKey,
    String? projectRef,
  }) {
    return SupabaseIntegrationSettings(
      enabled: enabled ?? this.enabled,
      apiUrl: apiUrl ?? this.apiUrl,
      anonKey: anonKey ?? this.anonKey,
      serviceRoleKey: serviceRoleKey ?? this.serviceRoleKey,
      projectRef: projectRef ?? this.projectRef,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'apiUrl': apiUrl,
        'anonKey': anonKey,
        'serviceRoleKey': serviceRoleKey,
        'projectRef': projectRef,
      };

  factory SupabaseIntegrationSettings.fromJson(Map<String, dynamic> json) {
    return SupabaseIntegrationSettings(
      enabled: json['enabled'] as bool? ?? false,
      apiUrl: json['apiUrl'] as String? ?? '',
      anonKey: json['anonKey'] as String? ?? '',
      serviceRoleKey: json['serviceRoleKey'] as String? ?? '',
      projectRef: json['projectRef'] as String? ?? '',
    );
  }
}

class ApiIntegrationSettings {
  final WhatsAppIntegrationSettings whatsapp;
  final AppwriteIntegrationSettings appwrite;
  final SupabaseIntegrationSettings supabase;

  const ApiIntegrationSettings({
    required this.whatsapp,
    required this.appwrite,
    required this.supabase,
  });

  factory ApiIntegrationSettings.defaults() {
    return ApiIntegrationSettings(
      whatsapp: const WhatsAppIntegrationSettings(
        enabled: true,
        baseUrl: 'https://7103.api.greenapi.com',
        instanceId: 'waInstance7103894450',
        token: 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
        defaultCountryCode: '+967',
      ),
      appwrite: const AppwriteIntegrationSettings(
        enabled: false,
        endpoint: 'https://fra.cloud.appwrite.io/v1',
        projectId: '690ff0da0025518570c1',
        databaseId: 'hotel_db',
        apiKey: '',
      ),
      supabase: const SupabaseIntegrationSettings(
        enabled: false,
        apiUrl: '',
        anonKey: '',
        serviceRoleKey: '',
        projectRef: '',
      ),
    );
  }

  ApiIntegrationSettings copyWith({
    WhatsAppIntegrationSettings? whatsapp,
    AppwriteIntegrationSettings? appwrite,
    SupabaseIntegrationSettings? supabase,
  }) {
    return ApiIntegrationSettings(
      whatsapp: whatsapp ?? this.whatsapp,
      appwrite: appwrite ?? this.appwrite,
      supabase: supabase ?? this.supabase,
    );
  }

  Map<String, dynamic> toJson() => {
        'whatsapp': whatsapp.toJson(),
        'appwrite': appwrite.toJson(),
        'supabase': supabase.toJson(),
      };

  factory ApiIntegrationSettings.fromJson(Map<String, dynamic> json) {
    return ApiIntegrationSettings(
      whatsapp: WhatsAppIntegrationSettings.fromJson(
        Map<String, dynamic>.from(json['whatsapp'] as Map? ?? {}),
      ),
      appwrite: AppwriteIntegrationSettings.fromJson(
        Map<String, dynamic>.from(json['appwrite'] as Map? ?? {}),
      ),
      supabase: SupabaseIntegrationSettings.fromJson(
        Map<String, dynamic>.from(json['supabase'] as Map? ?? {}),
      ),
    );
  }
}

class ApiIntegrationSettingsNotifier extends StateNotifier<ApiIntegrationSettings> {
  ApiIntegrationSettingsNotifier() : super(ApiIntegrationSettings.defaults()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) {
      return;
    }
    try {
      final data = jsonDecode(raw);
      state = ApiIntegrationSettings.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (_) {}
  }

  Future<void> _persist(ApiIntegrationSettings value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(value.toJson()));
  }

  Future<void> updateWhatsApp(WhatsAppIntegrationSettings value) async {
    await _persist(state.copyWith(whatsapp: value));
  }

  Future<void> updateAppwrite(AppwriteIntegrationSettings value) async {
    await _persist(state.copyWith(appwrite: value));
  }

  Future<void> updateSupabase(SupabaseIntegrationSettings value) async {
    await _persist(state.copyWith(supabase: value));
  }

  Future<void> reset() async {
    await _persist(ApiIntegrationSettings.defaults());
  }
}

final apiIntegrationSettingsProvider =
    StateNotifierProvider<ApiIntegrationSettingsNotifier, ApiIntegrationSettings>((ref) {
  return ApiIntegrationSettingsNotifier();
});
