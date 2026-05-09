import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_logger.dart';
import 'api_config_service.dart';

class ApiService {
  ApiService._internal() {
    _initializeDio();
    ApiConfigService.instance.configNotifier.addListener(_onConfigChanged);
  }

  void _initializeDio() {
    final config = ApiConfigService.instance.currentConfig;
    _dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: Duration(seconds: config.connectTimeout),
        receiveTimeout: Duration(seconds: config.receiveTimeout),
        headers: ApiConfigService.instance.getHeaders(),
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: _kToken);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (e, handler) async {
          final code = e.response?.statusCode ?? 0;
          if (code == 401) {
            await _storage.delete(key: _kToken);
          }
          if (code == 429 || code >= 500) {
            await Future<void>.delayed(const Duration(seconds: 1));
            try {
              final req = await _retryRequest(e.requestOptions);
              return handler.resolve(req);
            } catch (e, st) {
              AppLogger.error('فشل إعادة محاولة الطلب', tag: 'API', error: e, stackTrace: st);
            }
          }
          handler.next(e);
        },
      ),
    );

    if (config.enableLogging) {
      _dio.interceptors.add(
        LogInterceptor(
          requestBody: true,
          responseBody: true,
        ),
      );
    }
  }

  void _onConfigChanged() {
    _initializeDio();
  }
  static final ApiService I = ApiService._internal();

  late final Dio _dio;
  static const _storage = FlutterSecureStorage();
  static const _kToken = 'auth_token';

  Future<Response<void>> _retryRequest(RequestOptions ro) async {
    final opts = Options(method: ro.method, headers: ro.headers);
    return _dio.request<dynamic>(
      ro.path,
      data: ro.data,
      queryParameters: ro.queryParameters,
      options: opts,
    );
  }

  Future<Map<String, dynamic>?> login(String username, String password) async {
    final res = await _dio.post<dynamic>(
      '/auth/login.php',
      data: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode == 200 &&
        res.data is Map &&
        res.data['success'] == true) {
      final rawData = res.data['data'];
      if (rawData is Map) {
        final data = Map<String, dynamic>.from(rawData);
        final token = data['token'] as String?;
        final user = data['user'];
        if (token != null) {
          await _storage.write(key: _kToken, value: token);
        }
        if (user is Map) {
          return Map<String, dynamic>.from(user);
        }
      }
      return null;
    }
    return null;
  }

  Future<bool> ping() async {
    try {
      final res = await _dio.get<dynamic>('/auth/ping.php');
      return res.statusCode == 200 && res.data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _kToken);
  }

  Future<Map<String, dynamic>> listEntity(
    String entity, {
    int page = 1,
    int pageSize = 50,
    int? since,
    String? filter,
  }) async {
    final qp = {
      'page': page,
      'page_size': pageSize,
      if (since != null) 'since': since,
      if (filter != null && filter.isNotEmpty) 'filter': filter,
    };
    final res = await _dio.get<dynamic>('/$entity.php', queryParameters: qp);
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getEntity(String entity, dynamic id) async {
    final res = await _dio.get<dynamic>('/$entity.php/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> createEntity(
    String entity,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post<dynamic>('/$entity.php', data: jsonEncode(data));
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> updateEntity(
    String entity,
    dynamic id,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.put<dynamic>('/$entity.php/$id', data: jsonEncode(data));
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> deleteEntity(String entity, dynamic id) async {
    final res = await _dio.delete<dynamic>('/$entity.php/$id');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> syncPush(
    List<Map<String, dynamic>> changes,
  ) async {
    final res = await _dio.post<dynamic>(
      '/sync/push.php',
      data: jsonEncode({'changes': changes}),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> syncPull(int since) async {
    final res = await _dio.get<dynamic>(
      '/sync/pull.php',
      queryParameters: {'since': since},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<String?> uploadRoomImage(String roomNumber, String filePath) async {
    final form = FormData.fromMap({
      'room_number': roomNumber,
      'image': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post<dynamic>('/uploads/rooms.php', data: form);
    if (res.statusCode == 200 && res.data['success'] == true) {
      return res.data['data']['url'] as String;
    }
    return null;
  }
}
