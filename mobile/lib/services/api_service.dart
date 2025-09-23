import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/env.dart';

class ApiService {
  ApiService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: Env.baseApiUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: _kToken);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (e, handler) async {
        // try refresh on 401
        if (e.response?.statusCode == 401 && await _tryRefresh()) {
          final req = await _retryRequest(e.requestOptions);
          return handler.resolve(req);
        }
        handler.next(e);
      },
    ));
  }
  static final ApiService I = ApiService._internal();

  late final Dio _dio;
  static const _storage = FlutterSecureStorage();
  static const _kToken = 'auth_token';

  Future<bool> _tryRefresh() async {
    try {
      final res = await Dio(BaseOptions(baseUrl: Env.baseApiUrl)).post('/auth/refresh.php');
      if (res.statusCode == 200 && res.data['success'] == true) {
        final token = res.data['data']['token'];
        await _storage.write(key: _kToken, value: token);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Response<dynamic>> _retryRequest(RequestOptions ro) async {
    final opts = Options(method: ro.method, headers: ro.headers);
    return _dio.request<dynamic>(ro.path,
        data: ro.data, queryParameters: ro.queryParameters, options: opts);
  }

  Future<bool> login(String username, String password) async {
    final res = await _dio.post('/auth/login.php', data: jsonEncode({
      'username': username,
      'password': password,
    }));
    if (res.statusCode == 200 && res.data['success'] == true) {
      final token = res.data['data']['token'];
      await _storage.write(key: _kToken, value: token);
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    await _storage.delete(key: _kToken);
  }

  Future<Map<String, dynamic>> listEntity(String entity,
      {int page = 1, int pageSize = 50, int? since, String? filter}) async {
    final qp = {
      'page': page,
      'page_size': pageSize,
      if (since != null) 'since': since,
      if (filter != null && filter.isNotEmpty) 'filter': filter,
    };
    final res = await _dio.get('/$entity.php', queryParameters: qp);
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getEntity(String entity, dynamic id) async {
    final res = await _dio.get('/$entity.php/$id');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> createEntity(
      String entity, Map<String, dynamic> data) async {
    final res = await _dio.post('/$entity.php', data: jsonEncode(data));
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> updateEntity(
      String entity, dynamic id, Map<String, dynamic> data) async {
    final res = await _dio.put('/$entity.php/$id', data: jsonEncode(data));
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> deleteEntity(String entity, dynamic id) async {
    final res = await _dio.delete('/$entity.php/$id');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> syncPush(List<Map<String, dynamic>> changes) async {
    final res = await _dio.post('/sync/push.php', data: jsonEncode({
      'changes': changes,
    }));
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> syncPull(int since) async {
    final res = await _dio.get('/sync/pull.php', queryParameters: {'since': since});
    return Map<String, dynamic>.from(res.data);
  }

  Future<String?> uploadRoomImage(String roomNumber, String filePath) async {
    final form = FormData.fromMap({
      'room_number': roomNumber,
      'image': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post('/uploads/rooms.php', data: form);
    if (res.statusCode == 200 && res.data['success'] == true) {
      return res.data['data']['url'] as String;
    }
    return null;
  }
}
