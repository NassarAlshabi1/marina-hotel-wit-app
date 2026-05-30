import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/env.dart';

class ApiConfig {

  const ApiConfig({
    required this.baseUrl,
    this.apiKey,
    this.connectTimeout = 15,
    this.receiveTimeout = 20,
    this.enableLogging = false,
    this.useSsl = true,
    this.customHeaders = const {},
  });

  factory ApiConfig.fromJson(Map<String, dynamic> json) {
    return ApiConfig(
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String?,
      connectTimeout: json['connectTimeout'] as int? ?? 15,
      receiveTimeout: json['receiveTimeout'] as int? ?? 20,
      enableLogging: json['enableLogging'] as bool? ?? false,
      useSsl: json['useSsl'] as bool? ?? true,
      customHeaders: Map<String, String>.from((json['customHeaders'] ?? <String, dynamic>{}) as Map),
    );
  }
  final String baseUrl;
  final String? apiKey;
  final int connectTimeout;
  final int receiveTimeout;
  final bool enableLogging;
  final bool useSsl;
  final Map<String, String> customHeaders;

  ApiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    int? connectTimeout,
    int? receiveTimeout,
    bool? enableLogging,
    bool? useSsl,
    Map<String, String>? customHeaders,
  }) {
    return ApiConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      enableLogging: enableLogging ?? this.enableLogging,
      useSsl: useSsl ?? this.useSsl,
      customHeaders: customHeaders ?? this.customHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'connectTimeout': connectTimeout,
    'receiveTimeout': receiveTimeout,
    'enableLogging': enableLogging,
    'useSsl': useSsl,
    'customHeaders': customHeaders,
  };

  static final ApiConfig defaultConfig = ApiConfig(
    baseUrl: Env.baseApiUrl,
  );
}

class ApiConfigService {
  factory ApiConfigService() => instance;
  ApiConfigService._internal();
  static final ApiConfigService instance = ApiConfigService._internal();

  static const String _configKey = 'php_api_config';
  static const String _serverListKey = 'php_server_list';

  ApiConfig _currentConfig = ApiConfig.defaultConfig;
  ApiConfig get currentConfig => _currentConfig;

  final List<ServerInfo> _serverList = [];
  List<ServerInfo> get serverList => List.unmodifiable(_serverList);

  final ValueNotifier<ApiConfig> configNotifier = ValueNotifier(
    ApiConfig.defaultConfig,
  );

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final configJson = prefs.getString(_configKey);
    if (configJson != null) {
      try {
        final json = jsonDecode(configJson) as Map<String, dynamic>;
        _currentConfig = ApiConfig.fromJson(json);
        configNotifier.value = _currentConfig;
      } catch (e) {
        debugPrint('خطأ في تحميل إعدادات API: $e');
      }
    }
    await _loadServerList();
  }

  Future<void> _loadServerList() async {
    final prefs = await SharedPreferences.getInstance();
    final serverListJson = prefs.getString(_serverListKey);
    if (serverListJson != null) {
      try {
        final list = jsonDecode(serverListJson) as List;
        _serverList.clear();
        _serverList.addAll(
          list.map((e) => ServerInfo.fromJson(e as Map<String, dynamic>)),
        );
      } catch (e) {
        debugPrint('خطأ في تحميل قائمة السيرفرات: $e');
      }
    }
  }

  Future<void> saveConfig(ApiConfig config) async {
    _currentConfig = config;
    configNotifier.value = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
    AppLogger.info('تم حفظ إعدادات API: ${config.baseUrl}');
  }

  Future<void> updateBaseUrl(String url) async {
    await saveConfig(_currentConfig.copyWith(baseUrl: url));
  }

  Future<void> updateApiKey(String? key) async {
    await saveConfig(_currentConfig.copyWith(apiKey: key));
  }

  Future<void> updateTimeouts({int? connect, int? receive}) async {
    await saveConfig(
      _currentConfig.copyWith(connectTimeout: connect, receiveTimeout: receive),
    );
  }

  Future<void> toggleLogging(bool enable) async {
    await saveConfig(_currentConfig.copyWith(enableLogging: enable));
  }

  Future<void> toggleSsl(bool enable) async {
    await saveConfig(_currentConfig.copyWith(useSsl: enable));
  }

  Future<void> addServer(ServerInfo server) async {
    _serverList.removeWhere((s) => s.id == server.id);
    _serverList.insert(0, server);
    await _saveServerList();
  }

  Future<void> removeServer(String serverId) async {
    _serverList.removeWhere((s) => s.id == serverId);
    await _saveServerList();
  }

  Future<void> selectServer(String serverId) async {
    final server = _serverList.firstWhere(
      (s) => s.id == serverId,
      orElse: () => throw Exception('السيرفر غير موجود'),
    );
    await saveConfig(
      _currentConfig.copyWith(baseUrl: server.url, apiKey: server.apiKey),
    );
  }

  Future<void> _saveServerList() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_serverList.map((s) => s.toJson()).toList());
    await prefs.setString(_serverListKey, json);
  }

  Future<void> resetToDefault() async {
    await saveConfig(ApiConfig.defaultConfig);
  }

  String getFullUrl(String endpoint) {
    final base = _currentConfig.baseUrl.endsWith('/')
        ? _currentConfig.baseUrl.substring(0, _currentConfig.baseUrl.length - 1)
        : _currentConfig.baseUrl;
    final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return '$base$path';
  }

  Map<String, String> getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      ..._currentConfig.customHeaders,
    };
    if (_currentConfig.apiKey != null && _currentConfig.apiKey!.isNotEmpty) {
      headers['X-API-Key'] = _currentConfig.apiKey!;
    }
    return headers;
  }
}

class ServerInfo {

  const ServerInfo({
    required this.id,
    required this.name,
    required this.url,
    this.apiKey,
    required this.addedAt,
    this.isDefault = false,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      apiKey: json['apiKey'] as String?,
      addedAt: DateTime.parse(json['addedAt'] as String),
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }
  final String id;
  final String name;
  final String url;
  final String? apiKey;
  final DateTime addedAt;
  final bool isDefault;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'apiKey': apiKey,
    'addedAt': addedAt.toIso8601String(),
    'isDefault': isDefault,
  };

  ServerInfo copyWith({
    String? id,
    String? name,
    String? url,
    String? apiKey,
    DateTime? addedAt,
    bool? isDefault,
  }) {
    return ServerInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      apiKey: apiKey ?? this.apiKey,
      addedAt: addedAt ?? this.addedAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
