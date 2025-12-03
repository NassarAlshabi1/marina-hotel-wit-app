import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_cache_manager.dart';
import 'appwrite_network_helper.dart';

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
  final _networkHelper = AppwriteNetworkHelper();
  
  bool _initialized = false;

  /// Getter للوصول إلى Client من الخارج
  Client get client => _client;

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
    bool useRetry = true,
  }) async {
    _ensureInitialized();
    
    try {
      _logger.debug('Creating document in $collectionId', tag: 'CRUD');
      
      Future<models.Document> performOperation() {
        return _databases.createDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: collectionId,
          documentId: documentId ?? 'unique()',
          data: data,
        );
      }

      final document = useRetry
          ? await _networkHelper.withRetryAndTimeout(
              operation: performOperation,
              operationName: 'createDocument($collectionId)',
            )
          : await _networkHelper.withTimeout(
              operation: performOperation,
              operationName: 'createDocument($collectionId)',
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
    bool useRetry = true,
  }) async {
    _ensureInitialized();
    
    try {
      _logger.debug('Updating document $documentId in $collectionId', tag: 'CRUD');
      
      Future<models.Document> performOperation() {
        return _databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        );
      }

      final document = useRetry
          ? await _networkHelper.withRetryAndTimeout(
              operation: performOperation,
              operationName: 'updateDocument($collectionId)',
            )
          : await _networkHelper.withTimeout(
              operation: performOperation,
              operationName: 'updateDocument($collectionId)',
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

  /// قائمة المستندات مع Pagination
  Future<List<models.Document>> listDocuments({
    required String collectionId,
    List<String>? queries,
    int? limit,
    int offset = 0,
    bool useCache = true,
    bool useRetry = true,
  }) async {
    _ensureInitialized();
    
    final pageSize = limit ?? AppwriteConfig.defaultPageSize;
    final effectiveLimit = pageSize > AppwriteConfig.maxPageSize 
        ? AppwriteConfig.maxPageSize 
        : pageSize;
    
    try {
      // التحقق من الذاكرة المؤقتة
      final cacheKey = '${collectionId}_${queries?.join('_') ?? 'all'}_${effectiveLimit}_$offset';
      if (useCache) {
        final cached = _cache.get<List<models.Document>>(cacheKey);
        if (cached != null) {
          _logger.debug('Cache hit for $cacheKey', tag: 'CACHE');
          return cached;
        }
      }

      _logger.debug(
        'Listing documents from $collectionId (limit: $effectiveLimit, offset: $offset)',
        tag: 'CRUD',
      );
      
      Future<List<models.Document>> performOperation() async {
        final documentList = await _databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: collectionId,
          queries: queries,
        );
        return documentList.documents;
      }

      final documents = useRetry
          ? await _networkHelper.withRetryAndTimeout(
              operation: performOperation,
              operationName: 'listDocuments($collectionId)',
              timeout: AppwriteConfig.defaultTimeout,
            )
          : await _networkHelper.withTimeout(
              operation: performOperation,
              operationName: 'listDocuments($collectionId)',
              timeout: AppwriteConfig.defaultTimeout,
            );

      // حفظ في الذاكرة المؤقتة
      if (useCache) {
        _cache.set(cacheKey, documents, ttl: AppwriteConfig.cacheExpiry);
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

  /// جلب جميع المستندات مع Pagination تلقائي
  Future<List<models.Document>> listAllDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    
    final allDocuments = <models.Document>[];
    int offset = 0;
    const pageSize = AppwriteConfig.defaultPageSize;
    
    while (true) {
      final documents = await listDocuments(
        collectionId: collectionId,
        queries: queries,
        limit: pageSize,
        offset: offset,
        useCache: useCache,
      );
      
      if (documents.isEmpty) break;
      
      allDocuments.addAll(documents);
      
      // إذا كانت النتائج أقل من pageSize، يعني وصلنا للنهاية
      if (documents.length < pageSize) break;
      
      offset += pageSize;
    }
    
    _logger.info('Fetched total ${allDocuments.length} documents from $collectionId', tag: 'CRUD');
    return allDocuments;
  }

  Future<models.Document> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    try {
      return await createDocument(
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
    } catch (error) {
      if (error is AppwriteError && error.code == 'CONFLICT_ERROR') {
        return await updateDocument(
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        );
      }
      rethrow;
    }
  }

  // ============ Collection-Specific Methods ============

  // Rooms
  Future<models.Document> createRoom(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.roomsCollectionId, data: data);
  
  Future<models.Document> upsertRoom(String documentId, Map<String, dynamic> data) =>
      upsertDocument(
        collectionId: AppwriteConfig.roomsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<models.Document> updateRoom(String documentId, Map<String, dynamic> data) =>
      updateDocument(
        collectionId: AppwriteConfig.roomsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<void> deleteRoom(String documentId) =>
      deleteDocument(collectionId: AppwriteConfig.roomsCollectionId, documentId: documentId);
  
  Future<List<models.Document>> listRooms({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.roomsCollectionId, useCache: useCache);
  
  Future<models.Document?> getRoom(String id, {bool useCache = true}) =>
      getDocument(collectionId: AppwriteConfig.roomsCollectionId, documentId: id, useCache: useCache);

  // Bookings
  Future<models.Document> createBooking(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.bookingsCollectionId, data: data);
  
  Future<models.Document> upsertBooking(String documentId, Map<String, dynamic> data) =>
      upsertDocument(
        collectionId: AppwriteConfig.bookingsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<models.Document> updateBooking(String documentId, Map<String, dynamic> data) =>
      updateDocument(
        collectionId: AppwriteConfig.bookingsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<void> deleteBooking(String documentId) =>
      deleteDocument(collectionId: AppwriteConfig.bookingsCollectionId, documentId: documentId);
  
  Future<List<models.Document>> listBookings({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.bookingsCollectionId, useCache: useCache);
  
  Future<models.Document?> getBooking(String id, {bool useCache = true}) =>
      getDocument(collectionId: AppwriteConfig.bookingsCollectionId, documentId: id, useCache: useCache);

  // Payments
  Future<models.Document> createPayment(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.paymentsCollectionId, data: data);
  
  Future<models.Document> upsertPayment(String documentId, Map<String, dynamic> data) =>
      upsertDocument(
        collectionId: AppwriteConfig.paymentsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<models.Document> updatePayment(String documentId, Map<String, dynamic> data) =>
      updateDocument(
        collectionId: AppwriteConfig.paymentsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<void> deletePayment(String documentId) =>
      deleteDocument(collectionId: AppwriteConfig.paymentsCollectionId, documentId: documentId);
  
  Future<List<models.Document>> listPayments({bool useCache = true}) =>
      listDocuments(collectionId: AppwriteConfig.paymentsCollectionId, useCache: useCache);

  // Expenses
  Future<models.Document> createExpense(Map<String, dynamic> data) =>
      createDocument(collectionId: AppwriteConfig.expensesCollectionId, data: data);
  
  Future<models.Document> upsertExpense(String documentId, Map<String, dynamic> data) =>
      upsertDocument(
        collectionId: AppwriteConfig.expensesCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<models.Document> updateExpense(String documentId, Map<String, dynamic> data) =>
      updateDocument(
        collectionId: AppwriteConfig.expensesCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<void> deleteExpense(String documentId) =>
      deleteDocument(collectionId: AppwriteConfig.expensesCollectionId, documentId: documentId);
  
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
  
  Future<models.Document> upsertDebt(String documentId, Map<String, dynamic> data) =>
      upsertDocument(
        collectionId: AppwriteConfig.debtsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<models.Document> updateDebt(String documentId, Map<String, dynamic> data) =>
      updateDocument(
        collectionId: AppwriteConfig.debtsCollectionId,
        documentId: documentId,
        data: data,
      );
  
  Future<void> deleteDebt(String documentId) =>
      deleteDocument(collectionId: AppwriteConfig.debtsCollectionId, documentId: documentId);
  
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

  /// اختبار الاتصال الشامل - CRUD كامل
  /// 
  /// يختبر جميع عمليات CRUD (Create, Read, Update, Delete) على مجموعة اختبارية
  /// Returns: Map يحتوي على تفاصيل نتائج الاختبار
  Future<Map<String, dynamic>> testConnection({
    bool fullCrudTest = false,
    String? testCollectionId,
  }) async {
    final results = <String, dynamic>{
      'overall_success': false,
      'timestamp': DateTime.now().toIso8601String(),
      'tests': <String, dynamic>{},
    };

    try {
      _ensureInitialized();
      
      final testCollection = testCollectionId ?? AppwriteConfig.roomsCollectionId;
      
      // 1. اختبار القراءة (Read)
      try {
        _logger.debug('Testing READ operation...', tag: 'CONNECTION_TEST');
        final docs = await _networkHelper.withTimeout(
          operation: () => _databases.listDocuments(
            databaseId: AppwriteConfig.databaseId,
            collectionId: testCollection,
          ),
          operationName: 'testConnection_read',
          timeout: const Duration(seconds: 10),
        );
        
        results['tests']['read'] = {
          'success': true,
          'documents_found': docs.documents.length,
          'duration_ms': 'N/A',
        };
        _logger.info('READ test successful', tag: 'CONNECTION_TEST');
      } catch (e) {
        results['tests']['read'] = {
          'success': false,
          'error': e.toString(),
        };
        _logger.error('READ test failed', error: e, tag: 'CONNECTION_TEST');
      }

      // إذا كان اختبار كامل، نختبر Create, Update, Delete
      if (fullCrudTest) {
        String? testDocumentId;
        
        try {
          // 2. اختبار الإنشاء (Create)
          _logger.debug('Testing CREATE operation...', tag: 'CONNECTION_TEST');
          final testData = {
            'test_field': 'test_value_${DateTime.now().millisecondsSinceEpoch}',
            'created_at': DateTime.now().toIso8601String(),
          };
          
          final createdDoc = await _networkHelper.withTimeout(
            operation: () => _databases.createDocument(
              databaseId: AppwriteConfig.databaseId,
              collectionId: testCollection,
              documentId: 'unique()',
              data: testData,
            ),
            operationName: 'testConnection_create',
            timeout: const Duration(seconds: 10),
          );
          
          testDocumentId = createdDoc.$id;
          results['tests']['create'] = {
            'success': true,
            'document_id': testDocumentId,
          };
          _logger.info('CREATE test successful: $testDocumentId', tag: 'CONNECTION_TEST');

          // 3. اختبار التحديث (Update)
          _logger.debug('Testing UPDATE operation...', tag: 'CONNECTION_TEST');
          final updatedData = {
            'test_field': 'updated_value_${DateTime.now().millisecondsSinceEpoch}',
          };
          
          await _networkHelper.withTimeout(
            operation: () => _databases.updateDocument(
              databaseId: AppwriteConfig.databaseId,
              collectionId: testCollection,
              documentId: testDocumentId!,
              data: updatedData,
            ),
            operationName: 'testConnection_update',
            timeout: const Duration(seconds: 10),
          );
          
          results['tests']['update'] = {'success': true};
          _logger.info('UPDATE test successful', tag: 'CONNECTION_TEST');

          // 4. اختبار الحذف (Delete)
          _logger.debug('Testing DELETE operation...', tag: 'CONNECTION_TEST');
          await _networkHelper.withTimeout(
            operation: () => _databases.deleteDocument(
              databaseId: AppwriteConfig.databaseId,
              collectionId: testCollection,
              documentId: testDocumentId!,
            ),
            operationName: 'testConnection_delete',
            timeout: const Duration(seconds: 10),
          );
          
          results['tests']['delete'] = {'success': true};
          _logger.info('DELETE test successful', tag: 'CONNECTION_TEST');
          testDocumentId = null; // تم الحذف بنجاح

        } catch (e) {
          _logger.error('CRUD test failed', error: e, tag: 'CONNECTION_TEST');
          
          if (!results['tests'].containsKey('create')) {
            results['tests']['create'] = {'success': false, 'error': e.toString()};
          } else if (!results['tests'].containsKey('update')) {
            results['tests']['update'] = {'success': false, 'error': e.toString()};
          } else if (!results['tests'].containsKey('delete')) {
            results['tests']['delete'] = {'success': false, 'error': e.toString()};
          }

          // تنظيف: حذف المستند الاختباري إذا كان موجوداً
          if (testDocumentId != null) {
            try {
              await _databases.deleteDocument(
                databaseId: AppwriteConfig.databaseId,
                collectionId: testCollection,
                documentId: testDocumentId,
              );
              _logger.debug('Cleaned up test document: $testDocumentId', tag: 'CONNECTION_TEST');
            } catch (cleanupError) {
              _logger.warning('Failed to cleanup test document', error: cleanupError, tag: 'CONNECTION_TEST');
            }
          }
        }
      }

      // تحديد النجاح الإجمالي
      final allTests = results['tests'] as Map<String, dynamic>;
      results['overall_success'] = allTests.values.every((test) => test['success'] == true);
      results['tests_count'] = allTests.length;
      results['successful_tests'] = allTests.values.where((test) => test['success'] == true).length;
      
      _logger.info(
        'Connection test completed: ${results['successful_tests']}/${results['tests_count']} tests passed',
        tag: 'CONNECTION_TEST',
      );
      
      return results;
    } catch (e) {
      _logger.error('Connection test failed', error: e, tag: 'CONNECTION_TEST');
      results['overall_success'] = false;
      results['error'] = e.toString();
      return results;
    }
  }

  /// اختبار اتصال سريع (قراءة فقط)
  Future<bool> quickConnectionTest() async {
    try {
      _ensureInitialized();
      
      await _networkHelper.withTimeout(
        operation: () => _databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.roomsCollectionId,
        ),
        operationName: 'quickConnectionTest',
        timeout: const Duration(seconds: 5),
      );
      
      _logger.info('Quick connection test successful', tag: 'CONNECTION');
      return true;
    } catch (e) {
      _logger.warning('Quick connection test failed', error: e, tag: 'CONNECTION');
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
