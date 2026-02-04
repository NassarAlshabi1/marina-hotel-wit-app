import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_config_service.dart';
import '../utils/field_mapper.dart';

enum PhpApiStatus { disconnected, connecting, connected, error }

class PhpApiResult<T> {
  final bool success;
  final T? data;
  final String? message;
  final int? statusCode;
  final Map<String, dynamic>? errors;

  const PhpApiResult({
    required this.success,
    this.data,
    this.message,
    this.statusCode,
    this.errors,
  });

  factory PhpApiResult.success(T data, {String? message}) {
    return PhpApiResult(success: true, data: data, message: message);
  }

  factory PhpApiResult.error(String message, {int? statusCode, Map<String, dynamic>? errors}) {
    return PhpApiResult(
      success: false,
      message: message,
      statusCode: statusCode,
      errors: errors,
    );
  }
}

class PhpApiService {
  PhpApiService._internal() {
    _initializeDio();
    ApiConfigService.instance.configNotifier.addListener(_onConfigChanged);
  }

  static final PhpApiService instance = PhpApiService._internal();
  factory PhpApiService() => instance;

  late Dio _dio;
  static const _storage = FlutterSecureStorage();
  static const _tokenKey = 'php_auth_token';
  static const _userKey = 'php_current_user';

  final _statusController = StreamController<PhpApiStatus>.broadcast();
  Stream<PhpApiStatus> get statusStream => _statusController.stream;

  PhpApiStatus _currentStatus = PhpApiStatus.disconnected;
  PhpApiStatus get currentStatus => _currentStatus;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? get currentUser => _currentUser;

  final _requestLog = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get requestLog => List.unmodifiable(_requestLog);

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
        onRequest: _onRequest,
        onResponse: _onResponse,
        onError: _onError,
      ),
    );

    if (config.enableLogging) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (o) => debugPrint('📡 PHP API: $o'),
      ));
    }
  }

  void _onConfigChanged() {
    _initializeDio();
    debugPrint('🔄 تم تحديث إعدادات Dio');
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.read(key: _tokenKey);
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    _logRequest('REQUEST', options.method, options.path, options.data);
    handler.next(options);
  }

  void _onResponse(Response response, ResponseInterceptorHandler handler) {
    _logRequest(
      'RESPONSE',
      response.requestOptions.method,
      response.requestOptions.path,
      response.data,
      statusCode: response.statusCode,
    );
    handler.next(response);
  }

  Future<void> _onError(
    DioException e,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = e.response?.statusCode ?? 0;

    _logRequest(
      'ERROR',
      e.requestOptions.method,
      e.requestOptions.path,
      e.message,
      statusCode: statusCode,
    );

    if (statusCode == 401) {
      await logout();
      _updateStatus(PhpApiStatus.disconnected);
    }

    if (statusCode == 429 || statusCode >= 500) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final response = await _retryRequest(e.requestOptions);
        return handler.resolve(response);
      } catch (_) {}
    }

    handler.next(e);
  }

  void _logRequest(
    String type,
    String method,
    String path,
    dynamic data, {
    int? statusCode,
  }) {
    if (_requestLog.length > 100) {
      _requestLog.removeAt(0);
    }
    _requestLog.add({
      'type': type,
      'method': method,
      'path': path,
      'data': data?.toString().substring(0, (data.toString().length).clamp(0, 500)),
      'statusCode': statusCode,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<Response<dynamic>> _retryRequest(RequestOptions options) async {
    final opts = Options(method: options.method, headers: options.headers);
    return _dio.request<dynamic>(
      options.path,
      data: options.data,
      queryParameters: options.queryParameters,
      options: opts,
    );
  }

  void _updateStatus(PhpApiStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  Future<PhpApiResult<Map<String, dynamic>>> login(
    String username,
    String password,
  ) async {
    _updateStatus(PhpApiStatus.connecting);
    try {
      final response = await _dio.post(
        '/auth/login.php',
        data: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'];
        final token = data['token'] as String?;
        final user = data['user'] as Map<String, dynamic>?;

        if (token != null) {
          await _storage.write(key: _tokenKey, value: token);
        }
        if (user != null) {
          _currentUser = user;
          await _storage.write(key: _userKey, value: jsonEncode(user));
        }

        _updateStatus(PhpApiStatus.connected);
        return PhpApiResult.success(user ?? {}, message: 'تم تسجيل الدخول بنجاح');
      }

      _updateStatus(PhpApiStatus.error);
      return PhpApiResult.error(
        response.data['message'] ?? 'فشل تسجيل الدخول',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      _updateStatus(PhpApiStatus.error);
      return PhpApiResult.error(
        _getDioErrorMessage(e),
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
    _currentUser = null;
    _updateStatus(PhpApiStatus.disconnected);
  }

  Future<PhpApiResult<bool>> testConnection() async {
    _updateStatus(PhpApiStatus.connecting);
    try {
      final response = await _dio.get('/auth/ping.php');
      if (response.statusCode == 200 && response.data['success'] == true) {
        _updateStatus(PhpApiStatus.connected);
        return PhpApiResult.success(true, message: 'الاتصال ناجح');
      }
      _updateStatus(PhpApiStatus.error);
      return PhpApiResult.error('فشل اختبار الاتصال');
    } on DioException catch (e) {
      _updateStatus(PhpApiStatus.error);
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<Map<String, dynamic>>> getServerInfo() async {
    try {
      final response = await _dio.get('/info.php');
      if (response.statusCode == 200) {
        return PhpApiResult.success(
          Map<String, dynamic>.from(response.data),
          message: 'تم جلب معلومات السيرفر',
        );
      }
      return PhpApiResult.error('فشل جلب معلومات السيرفر');
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<List<Map<String, dynamic>>>> list(
    String entity, {
    int page = 1,
    int pageSize = 50,
    int? since,
    String? filter,
    Map<String, dynamic>? extraParams,
  }) async {
    try {
      final endpoint = FieldMapper.getEndpoint(entity);
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
        if (since != null) 'since': since,
        if (filter != null && filter.isNotEmpty) 'filter': filter,
        ...?extraParams,
      };

      final response = await _dio.get('/$endpoint.php', queryParameters: queryParams);

      if (response.statusCode == 200 && response.data['success'] == true) {
        final rawData = response.data['data'] as List? ?? [];
        final mappedData = FieldMapper.toFlutterList(entity, rawData);
        return PhpApiResult.success(mappedData);
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'فشل جلب البيانات',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<Map<String, dynamic>>> get(
    String entity,
    dynamic id,
  ) async {
    try {
      final endpoint = FieldMapper.getEndpoint(entity);
      final response = await _dio.get('/$endpoint.php/$id');

      if (response.statusCode == 200 && response.data['success'] == true) {
        final rawData = response.data['data'] as Map<String, dynamic>;
        final mappedData = FieldMapper.toFlutterMap(entity, rawData);
        return PhpApiResult.success(mappedData);
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'العنصر غير موجود',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<Map<String, dynamic>>> create(
    String entity,
    Map<String, dynamic> data,
  ) async {
    try {
      final endpoint = FieldMapper.getEndpoint(entity);
      final phpData = FieldMapper.prepareForInsert(entity, data);

      final missingFields = FieldMapper.validateRequiredFields(entity, phpData);
      if (missingFields.isNotEmpty) {
        return PhpApiResult.error(
          'حقول مطلوبة مفقودة: ${missingFields.join(', ')}',
          errors: {'missing_fields': missingFields},
        );
      }

      final response = await _dio.post(
        '/$endpoint.php',
        data: jsonEncode(phpData),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.data['success'] == true) {
          final rawData = response.data['data'] as Map<String, dynamic>? ?? {};
          final mappedData = FieldMapper.toFlutterMap(entity, rawData);
          return PhpApiResult.success(mappedData, message: 'تم الإنشاء بنجاح');
        }
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'فشل إنشاء العنصر',
        statusCode: response.statusCode,
        errors: response.data['errors'] as Map<String, dynamic>?,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<Map<String, dynamic>>> update(
    String entity,
    dynamic id,
    Map<String, dynamic> data,
  ) async {
    try {
      final endpoint = FieldMapper.getEndpoint(entity);
      final phpData = FieldMapper.prepareForUpdate(entity, data);

      final response = await _dio.put(
        '/$endpoint.php/$id',
        data: jsonEncode(phpData),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final rawData = response.data['data'] as Map<String, dynamic>? ?? {};
        final mappedData = FieldMapper.toFlutterMap(entity, rawData);
        return PhpApiResult.success(mappedData, message: 'تم التحديث بنجاح');
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'فشل تحديث العنصر',
        statusCode: response.statusCode,
        errors: response.data['errors'] as Map<String, dynamic>?,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<bool>> delete(String entity, dynamic id) async {
    try {
      final endpoint = FieldMapper.getEndpoint(entity);
      final response = await _dio.delete('/$endpoint.php/$id');

      if (response.statusCode == 200 && response.data['success'] == true) {
        return PhpApiResult.success(true, message: 'تم الحذف بنجاح');
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'فشل حذف العنصر',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<Map<String, dynamic>>> syncPush(
    List<Map<String, dynamic>> changes,
  ) async {
    try {
      final processedChanges = changes.map((change) {
        final entity = change['entity'] as String;
        final data = change['data'] as Map<String, dynamic>;
        return {
          'entity': entity,
          'action': change['action'],
          'data': FieldMapper.toPhpMap(entity, data),
          'local_uuid': change['local_uuid'],
        };
      }).toList();

      final response = await _dio.post(
        '/sync/push.php',
        data: jsonEncode({'changes': processedChanges}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return PhpApiResult.success(
          Map<String, dynamic>.from(response.data),
          message: 'تمت المزامنة بنجاح',
        );
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'فشل دفع التغييرات',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<Map<String, dynamic>>> syncPull(int since) async {
    try {
      final response = await _dio.get(
        '/sync/pull.php',
        queryParameters: {'since': since},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>? ?? {};

        final mappedData = <String, dynamic>{};
        for (final entity in data.keys) {
          if (data[entity] is List) {
            mappedData[entity] = FieldMapper.toFlutterList(
              entity,
              data[entity] as List,
            );
          } else {
            mappedData[entity] = data[entity];
          }
        }

        return PhpApiResult.success(mappedData);
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'فشل سحب البيانات',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<String>> uploadImage(
    String endpoint,
    String filePath, {
    Map<String, dynamic>? extraFields,
  }) async {
    try {
      final formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(filePath),
        ...?extraFields,
      });

      final response = await _dio.post('/$endpoint', data: formData);

      if (response.statusCode == 200 && response.data['success'] == true) {
        final url = response.data['data']['url'] as String?;
        if (url != null) {
          return PhpApiResult.success(url, message: 'تم رفع الصورة');
        }
      }

      return PhpApiResult.error(
        response.data['message'] ?? 'فشل رفع الصورة',
        statusCode: response.statusCode,
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  Future<PhpApiResult<Map<String, dynamic>>> executeCustomQuery(
    String endpoint, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParams,
  }) async {
    try {
      Response response;

      switch (method.toUpperCase()) {
        case 'POST':
          response = await _dio.post(
            endpoint,
            data: data != null ? jsonEncode(data) : null,
            queryParameters: queryParams,
          );
          break;
        case 'PUT':
          response = await _dio.put(
            endpoint,
            data: data != null ? jsonEncode(data) : null,
            queryParameters: queryParams,
          );
          break;
        case 'DELETE':
          response = await _dio.delete(endpoint, queryParameters: queryParams);
          break;
        default:
          response = await _dio.get(endpoint, queryParameters: queryParams);
      }

      return PhpApiResult.success(
        Map<String, dynamic>.from(response.data),
      );
    } on DioException catch (e) {
      return PhpApiResult.error(_getDioErrorMessage(e));
    }
  }

  String _getDioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'انتهت مهلة الاتصال';
      case DioExceptionType.sendTimeout:
        return 'انتهت مهلة إرسال البيانات';
      case DioExceptionType.receiveTimeout:
        return 'انتهت مهلة استقبال البيانات';
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        if (statusCode == 401) return 'غير مصرح - يرجى تسجيل الدخول';
        if (statusCode == 403) return 'ممنوع الوصول';
        if (statusCode == 404) return 'المورد غير موجود';
        if (statusCode == 422) return 'بيانات غير صالحة';
        if (statusCode == 500) return 'خطأ في السيرفر';
        return 'خطأ في الاستجابة: $statusCode';
      case DioExceptionType.cancel:
        return 'تم إلغاء الطلب';
      case DioExceptionType.connectionError:
        return 'خطأ في الاتصال - تحقق من الإنترنت';
      default:
        return e.message ?? 'خطأ غير معروف';
    }
  }

  void clearRequestLog() {
    _requestLog.clear();
  }

  void dispose() {
    _statusController.close();
    ApiConfigService.instance.configNotifier.removeListener(_onConfigChanged);
  }
}
