import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_cache_manager.dart';

/// خدمة Appwrite الأساسية - CRUD Operations
class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();
  factory AppwriteService() => _instance;
  AppwriteService._internal();

  late final Client _client;
  late final Databases _databases;
  
  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();
  final _cache = AppwriteCacheManager();
  
  bool _initialized = false;

  /// تهيئة الخدمة
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // التحقق من صحة الإعدادات
      if (!AppwriteConfig.validateConfig()) {
        throw Exception('Invalid Appwrite configuration');
      }

      // تهيئة Client
      _client = Client()
          .setEndpoint(AppwriteConfig.endpoint)
          .setProject(AppwriteConfig.projectId);
      
      // ⚠️ ملاحظة أمنية مهمة:
      // API Keys يجب استخدامها فقط في server-side applications
      // للتطبيقات Mobile، الأفضل استخدام:
      // 1. Anonymous Sessions للوصول العام
      // 2. Email/Password Authentication للمستخدمين
      // 3. JWT Tokens
      // لكن للتطوير والاختبار، يمكن استخدام الصلاحيات المفتوحة (Any role)

      _databases = Databases(_client);
      
      _initialized = true;
      _logger.info('Appwrite service initialized successfully', tag: 'SERVICE');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize Appwrite service', 
        error: e, 
        stackTrace: stackTrace, 
        tag: 'SERVICE'
      );
      rethrow;
    }
  }

  /// التأكد من التهيئة
  void _ensureInitialized() {
    if (!_initialized) {
      throw Exception('AppwriteService not initialized. Call initialize() first.');
    }
  }

  // ============ Generic CRUD Operations ============

  /// إنشاء مستند جديد
  Future<models.Document> createDocument({
    required String collectionId,
    required Map<String, dynamic> data,
    String? documentId,
  }) async {
    _ensureInitialized();
    
    try {
      _logger.debug('Creating document in $collectionId', tag: 'CRUD');
      
      final document = await _databases.createDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId ?? 'unique()',
        data: data,
      );

      // مسح الذاكرة المؤقتة للمجموعة
      _cache.clearByPattern('^${collectionId}_');
      
      _logger.info('Document created: ${document.$id}', tag: 'CRUD');
      return document;
    } catch (e, stackTrace) {
      final error = _errorHandler.handleError(e, 
        context: 'createDocument($collectionId)', 
        stackTrace: stackTrace
      );
      throw error;
    }
  }

  /// الحصول على مستند
  Future<models.Document?> getDocument({
    required String collectionId,
    required String documentId,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    
    try {
      // التحقق من الذاكرة المؤقتة
      if (useCache) {
        final cacheKey = '${collectionId}_$documentId';
        final cached = _cache.get<models.Document>(cacheKey);
        if (cached != null) {
          _logger.debug('Cache hit for $cacheKey', tag: 'CACHE');
          return cached;
        }
      }

      _logger.debug('Getting document $documentId from $collectionId', tag: 'CRUD');
      
      final document = await _databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );

      // حفظ في الذاكرة المؤقتة
      if (useCache) {
        _cache.set('${collectionId}_$documentId', document);
      }

      return document;
    } catch (e, stackTrace) {
      if (e.toString().contains('404')) {
        return null; // المستند غير موجود
      }
      final error = _errorHandler.handleError(e, 
        context: 'getDocument($collectionId, $documentId)', 
        stackTrace: stackTrace
      );
      throw error;
    }
  }

  /// تحديث مستند
  Future<models.Document> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    _ensureInitialized();
    
    try {
      _logger.debug('Updating document $documentId in $collectionId', tag: 'CRUD');
      
      final document = await _databases.updateDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );

      // تحديث الذاكرة المؤقتة
      _cache.set('${collectionId}_$documentId', document);
      _cache.clearByPattern('^${collectionId}_all');
      
      _logger.info('Document updated: ${document.$id}', tag: 'CRUD');
      return document;
    } catch (e, stackTrace) {
      final error = _errorHandler.handleError(e, 
        context: 'updateDocument($collectionId, $documentId)', 
        stackTrace: stackTrace
      );
      throw error;
    }
  }

  /// حذف مستند
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    _ensureInitialized();
    
    try {
      _logger.debug('Deleting document $documentId from $collectionId', tag: 'CRUD');
      
      await _databases.deleteDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );

      // مسح من الذاكرة المؤقتة
      _cache.remove('${collectionId}_$documentId');
      _cache.clearByPattern('^${collectionId}_all');
      
      _logger.info('Document deleted: $documentId', tag: 'CRUD');
    } catch (e, stackTrace) {
      final error = _errorHandler.handleError(e, 
        context: 'deleteDocument($collectionId, $documentId)', 
        stackTrace: stackTrace
      );
      throw error;
    }
  }

  /// قائمة المستندات
  Future<List<models.Document>> listDocuments({
    required String collectionId,
    List<String>? queries,
    int limit = 100,
    int offset = 0,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    
    try {
      // التحقق من الذاكرة المؤقتة
      if (useCache && queries == null) {
        final cacheKey = '${collectionId}_all';
        final cached = _cache.get<List<models.Document>>(cacheKey);
        if (cached != null) {
          _logger.debug('Cache hit for $cacheKey', tag: 'CACHE');
          return cached;
        }
      }

      _logger.debug('Listing documents from $collectionId', tag: 'CRUD');
      
      final documentList = await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: collectionId,
        queries: queries,
      );

      final documents = documentList.documents;

      // حفظ في الذاكرة المؤقتة
      if (useCache && queries == null) {
        _cache.set('${collectionId}_all', documents);
      }

      _logger.info('Fetched ${documents.length} documents from $collectionId', tag: 'CRUD');
      return documents;
    } catch (e, stackTrace) {
      final error = _errorHandler.handleError(e, 
        context: 'listDocuments($collectionId)', 
        stackTrace: stackTrace
      );
      throw error;
    }
  }

  // ============ Collection-Specific Methods ============

  // Rooms
  Future<models.Document> createRoom(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.roomsCollectionId, data: data);
  
  Future<List<models.Document>> listRooms({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.roomsCollectionId, useCache: useCache);
  
  Future<models.Document?> getRoom(String id, {bool useCache = true}) =>
      getDocument(collectionId: AppwriteConfig.roomsCollectionId, documentId: id, useCache: useCache);

  // Bookings
  Future<models.Document> createBooking(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.bookingsCollectionId, data: data);
  
  Future<List<models.Document>> listBookings({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.bookingsCollectionId, useCache: useCache);
  
  Future<models.Document?> getBooking(String id, {bool useCache = true}) =>
      getDocument(collectionId: AppwriteConfig.bookingsCollectionId, documentId: id, useCache: useCache);

  // Payments
  Future<models.Document> createPayment(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.paymentsCollectionId, data: data);
  
  Future<List<models.Document>> listPayments({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.paymentsCollectionId, useCache: useCache);

  // Expenses
  Future<models.Document> createExpense(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.expensesCollectionId, data: data);
  
  Future<List<models.Document>> listExpenses({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.expensesCollectionId, useCache: useCache);

  // Employees
  Future<models.Document> createEmployee(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.employeesCollectionId, data: data);
  
  Future<List<models.Document>> listEmployees({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.employeesCollectionId, useCache: useCache);

  // Debts
  Future<models.Document> createDebt(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.debtsCollectionId, data: data);
  
  Future<List<models.Document>> listDebts({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.debtsCollectionId, useCache: useCache);

  // Devices
  Future<models.Document> createDevice(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.devicesCollectionId, data: data);
  
  Future<List<models.Document>> listDevices({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.devicesCollectionId, useCache: useCache);

  // Sync Logs
  Future<models.Document> createSyncLog(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.syncLogsCollectionId, data: data);
  
  Future<List<models.Document>> listSyncLogs({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.syncLogsCollectionId, useCache: useCache);

  // ============ Connection Test ============

  /// اختبار الاتصال
  Future<bool> testConnection() async {
    try {
      _ensureInitialized();
      
      // محاولة الحصول على قائمة فارغة من أي مجموعة
      await _databases.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: ['limit(1)'],
      );
      
      _logger.info('Connection test successful', tag: 'CONNECTION');
      return true;
    } catch (e) {
      _logger.warning('Connection test failed', error: e, tag: 'CONNECTION');
      return false;
    }
  }

  /// الحصول على معلومات المشروع
  Map<String, String> getProjectInfo() {
    return {
      'endpoint': AppwriteConfig.endpoint,
      'projectId': AppwriteConfig.projectId,
      'databaseId': AppwriteConfig.databaseId,
      'initialized': _initialized.toString(),
    };
  }
}
