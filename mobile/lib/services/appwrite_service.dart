import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'appwrite_config.dart';
import 'appwrite_config_manager.dart';
import 'appwrite_logger.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_cache_manager.dart';
import 'appwrite_network_helper.dart';

/// خدمة Appwrite الأساسية - عمليات CRUD مع فحص اتصال سريع وتلقائي
class AppwriteService {
  // ====================== نمط المفرد (Singleton) ======================
  factory AppwriteService() => _instance;
  AppwriteService._internal();
  static final AppwriteService _instance = AppwriteService._internal();

  // ====================== المتغيرات الخاصة ======================
  late final Client _client;
  late final Databases _databases;

  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();
  final _cache = AppwriteCacheManager();
  final _networkHelper = AppwriteNetworkHelper();

  bool _initialized = false;

  // ====================== التوابع العامة للوصول ======================
  Client get client {
    _ensureInitializedSync();
    return _client;
  }

  Databases get databases {
    _ensureInitializedSync();
    return _databases;
  }

  bool get isInitialized => _initialized;

  // ====================== التهيئة ======================
  /// تهيئة الخدمة - تستدعى تلقائياً عند الحاجة
  Future<void> initialize() async {
    if (_initialized) return;

    final endpoint = AppwriteConfigManager.endpoint;
    final projectId = AppwriteConfigManager.projectId;
    final apiKey = AppwriteConfigManager.apiKey;

    _client = Client().setEndpoint(endpoint).setProject(projectId);
    if (apiKey.isNotEmpty) {
      _client.addHeader('X-Appwrite-Key', apiKey);
    }

    _databases = Databases(_client);
    _initialized = true;
    _logger.info('✅ AppwriteService initialized', tag: 'INIT');
  }

  /// تحقق متزامن (للاستخدام الداخلي في getters)
  void _ensureInitializedSync() {
    if (!_initialized) {
      throw StateError('AppwriteService not initialized. Call initialize() first.');
    }
  }

  /// تحقق غير متزامن مع تهيئة تلقائية
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  // ====================== دوال مساعدة ======================
  List<String> _applyPagingQueries(
    List<String> baseQueries, {
    required int limit,
    required int offset,
  }) {
    final effectiveQueries = List<String>.from(baseQueries);
    final hasLimit = effectiveQueries.any((q) => q.startsWith('limit('));
    final hasOffset = effectiveQueries.any((q) => q.startsWith('offset('));

    if (!hasLimit) {
      effectiveQueries.add(Query.limit(limit));
    }
    if (offset > 0 && !hasOffset) {
      effectiveQueries.add(Query.offset(offset));
    }
    return effectiveQueries;
  }

  Future<List<models.Document>> _listAllDocumentsInternal({
    required String collectionId,
    List<String> queries = const [],
    bool useCache = true,
    bool useRetry = true,
    int? maxLimit,
  }) async {
    await _ensureInitialized();

    final cacheKey = '${collectionId}_${queries.join('_')}_all';
    if (useCache) {
      final cached = _cache.get<List<models.Document>>(cacheKey);
      if (cached != null) {
        _logger.debug('📦 Cache hit for $cacheKey', tag: 'CACHE');
        return cached;
      }
    }

    final allDocuments = <models.Document>[];
    int pageOffset = 0;
    const pageSize = AppwriteConfig.maxPageSize;

    while (true) {
      if (maxLimit != null && allDocuments.length >= maxLimit) break;

      final currentPageSize = maxLimit != null
          ? (maxLimit - allDocuments.length).clamp(1, pageSize)
          : pageSize;

      final pagedQueries = _applyPagingQueries(
        queries,
        limit: currentPageSize,
        offset: pageOffset,
      );

      Future<List<models.Document>> performOperation() async {
        final documentList = await _databases.listDocuments(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          queries: pagedQueries,
        );
        return documentList.documents;
      }

      final pageDocs = useRetry
          ? await _networkHelper.withRetryAndTimeout(
              operation: performOperation,
              operationName: 'listDocuments($collectionId)',
              timeout: AppwriteConfig.longTimeout,
            )
          : await _networkHelper.withTimeout(
              operation: performOperation,
              operationName: 'listDocuments($collectionId)',
              timeout: AppwriteConfig.longTimeout,
            );

      if (pageDocs.isEmpty) break;

      allDocuments.addAll(pageDocs);
      if (pageDocs.length < currentPageSize) break;

      pageOffset += pageSize;
    }

    if (useCache) {
      _cache.set(cacheKey, allDocuments, ttl: AppwriteConfig.cacheExpiry);
    }

    _logger.info('📄 Fetched ${allDocuments.length} documents from $collectionId', tag: 'CRUD');
    return allDocuments;
  }

  Future<int> deleteAllDocuments({
    required String collectionId,
    List<String>? queries,
  }) async {
    await _ensureInitialized();

    try {
      final documents = await _listAllDocumentsInternal(
        collectionId: collectionId,
        queries: queries ?? [],
        useCache: false,
      );

      var deleted = 0;
      for (final doc in documents) {
        try {
          await _networkHelper.withRetryAndTimeout(
            operation: () => _databases.deleteDocument(
              databaseId: AppwriteConfigManager.databaseId,
              collectionId: collectionId,
              documentId: doc.$id,
            ),
            operationName: 'deleteDocument($collectionId)',
          );
          deleted++;
        } catch (e) {
          _logger.warning(
            '⚠️ Failed to delete document ${doc.$id} from $collectionId',
            error: e,
            tag: 'CRUD',
          );
        }
      }
      return deleted;
    } catch (e) {
      _logger.error('❌ Failed to delete all documents from $collectionId', error: e, tag: 'CRUD');
      rethrow;
    }
  }

  Future<List<models.Document>> listAllDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return _listAllDocumentsInternal(
      collectionId: collectionId,
      queries: queries ?? [],
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> _upsertDocumentInternal({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();

    final cleanData = Map<String, dynamic>.from(data)..remove('id');
    try {
      return await _networkHelper.withRetryAndTimeout(
        operation: () => _databases.updateDocument(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          documentId: documentId,
          data: cleanData,
        ),
        operationName: 'updateDocument($collectionId)',
      );
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        return await _networkHelper.withRetryAndTimeout(
          operation: () => _databases.createDocument(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: collectionId,
            documentId: documentId,
            data: cleanData,
          ),
          operationName: 'createDocument($collectionId)',
        );
      }
      _errorHandler.handleError(e, context: 'upsertDocument($collectionId)');
      rethrow;
    }
  }

  Future<void> _deleteDocumentInternal({
    required String collectionId,
    required String documentId,
  }) async {
    await _ensureInitialized();

    try {
      await _networkHelper.withRetryAndTimeout(
        operation: () => _databases.deleteDocument(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          documentId: documentId,
        ),
        operationName: 'deleteDocument($collectionId)',
      );
    } on AppwriteException catch (e) {
      if (e.code == 404) return;
      _errorHandler.handleError(e, context: 'deleteDocument($collectionId)');
      rethrow;
    }
  }

  // ====================== دوال الكيانات المحددة ======================
  // Rooms
  Future<List<models.Document>> listRooms({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.roomsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertRoom(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.roomsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteRoom(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.roomsCollectionId,
      documentId: documentId,
    );
  }

  // Bookings
  Future<List<models.Document>> listBookings({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.bookingsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertBooking(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBooking(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.bookingsCollectionId,
      documentId: documentId,
    );
  }

  // Employees
  Future<List<models.Document>> listEmployees({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.employeesCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertEmployee(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.employeesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteEmployee(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.employeesCollectionId,
      documentId: documentId,
    );
  }

  // Expenses
  Future<List<models.Document>> listExpenses({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.expensesCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertExpense(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.expensesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteExpense(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.expensesCollectionId,
      documentId: documentId,
    );
  }

  // Payments
  Future<List<models.Document>> listPayments({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.paymentsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertPayment(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.paymentsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deletePayment(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.paymentsCollectionId,
      documentId: documentId,
    );
  }

  // Debts
  Future<List<models.Document>> listDebts({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.debtsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertDebt(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.debtsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteDebt(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.debtsCollectionId,
      documentId: documentId,
    );
  }

  // Shift Notes
  Future<List<models.Document>> listShiftNotes({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.shiftNotesCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertShiftNote(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.shiftNotesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteShiftNote(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.shiftNotesCollectionId,
      documentId: documentId,
    );
  }

  // Booking Notes
  Future<List<models.Document>> listBookingNotes({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.bookingNotesCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertBookingNote(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingNotesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBookingNote(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.bookingNotesCollectionId,
      documentId: documentId,
    );
  }

  // Booking Nights
  Future<List<models.Document>> listBookingNights({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertBookingNight(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBookingNight(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      documentId: documentId,
    );
  }

  // Cash Transactions
  Future<List<models.Document>> listCashTransactions({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.cashTransactionsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertCashTransaction(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.cashTransactionsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteCashTransaction(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.cashTransactionsCollectionId,
      documentId: documentId,
    );
  }

  // Salary Cycles
  Future<List<models.Document>> listSalaryCycles({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.salaryCyclesCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertSalaryCycle(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.salaryCyclesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteSalaryCycle(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.salaryCyclesCollectionId,
      documentId: documentId,
    );
  }

  // Salary Payments
  Future<List<models.Document>> listSalaryPayments({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> upsertSalaryPayment(String documentId, Map<String, dynamic> data) {
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteSalaryPayment(String documentId) {
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      documentId: documentId,
    );
  }

  // ====================== دوال عامة للمزامنة ======================
  Future<List<models.Document>> listDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listAllDocuments(
      collectionId: collectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) {
    return _deleteDocumentInternal(
      collectionId: collectionId,
      documentId: documentId,
    );
  }

  Future<models.Document> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return _upsertDocumentInternal(
      collectionId: collectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<models.Document> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    await _ensureInitialized();
    return _networkHelper.withTimeout(
      operation: () => _databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      ),
      operationName: 'getDocument($collectionId/$documentId)',
    );
  }

  Future<models.Document> createDocument({
    required String collectionId,
    String? documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();
    final finalDocId = documentId ?? ID.unique(); // ✅ تصحيح: استدعاء الدالة
    return _networkHelper.withTimeout(
      operation: () => _databases.createDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: finalDocId,
        data: data,
      ),
      operationName: 'createDocument($collectionId)',
    );
  }

  Future<models.Document> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();
    return _networkHelper.withTimeout(
      operation: () => _databases.updateDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      ),
      operationName: 'updateDocument($collectionId/$documentId)',
    );
  }

  // ====================== دوال خاصة بالسجلات والأجهزة ======================
  Future<models.Document> createSyncLog(Map<String, dynamic> data) async {
    final documentId = data['localUuid'] ?? ID.unique(); // ✅ تصحيح
    return createDocument(
      collectionId: AppwriteConfig.syncLogsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<List<models.Document>> listSyncLogs({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.syncLogsCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  Future<models.Document> createDevice(Map<String, dynamic> data) async {
    final documentId = data['localUuid'] ?? ID.unique(); // ✅ تصحيح
    return createDocument(
      collectionId: AppwriteConfig.devicesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<List<models.Document>> listDevices({
    List<String>? queries,
    bool useCache = true,
    int? maxLimit,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.devicesCollectionId,
      queries: queries,
      useCache: useCache,
      maxLimit: maxLimit,
    );
  }

  // ====================== دوال اختبار الاتصال (سريعة وتلقائية) ======================

  /// اختبار اتصال سريع (أقل من 3 ثوانٍ) مع إعادة محاولة تلقائية
  Future<bool> quickConnectionTest({int maxRetries = 2}) async {
    await _ensureInitialized();

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        // محاولة قراءة مستند واحد فقط من مجموعة rooms (أو أي مجموعة موجودة)
        await _networkHelper.withTimeout(
          operation: () => _databases.listDocuments(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: AppwriteConfig.roomsCollectionId,
            queries: [Query.limit(1)], // نجلب مستنداً واحداً فقط
          ),
          operationName: 'quickConnectionTest',
          timeout: const Duration(seconds: 3), // مهلة قصيرة جداً
        );

        _logger.info('✅ Quick connection test passed', tag: 'CONNECTION');
        return true;
      } catch (e) {
        attempt++;
        _logger.warning('⚠️ Connection attempt $attempt failed', error: e, tag: 'CONNECTION');
        if (attempt > maxRetries) {
          _logger.error('❌ All connection attempts failed', tag: 'CONNECTION');
          return false;
        }
        // انتظار قصير قبل إعادة المحاولة
        await Future.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    return false;
  }

  /// اختبار شامل (اختياري) مع دورة حياة كاملة على مجموعة اختبار مخصصة
  Future<Map<String, dynamic>> fullConnectionTest() async {
    await _ensureInitialized();

    final results = <String, dynamic>{
      'tests': <String, dynamic>{},
      'overall_success': false,
    };

    // استخدام مجموعة اختبار ثابتة (يجب أن تكون موجودة في قاعدة البيانات)
    const testCollection = 'test_connection'; // يمكن جعلها قابلة للتكوين
    final testDocumentId = ID.unique();
    final now = DateTime.now().toIso8601String();

    try {
      // 1. اختبار الاتصال السريع
      results['tests']['quick'] = await quickConnectionTest();

      // 2. اختبار الكتابة (Create)
      try {
        await _networkHelper.withTimeout(
          operation: () => _databases.createDocument(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: testCollection,
            documentId: testDocumentId,
            data: {
              'test': true,
              'timestamp': now,
              'createdAt': now,
            },
          ),
          operationName: 'createDocument(Test)',
          timeout: const Duration(seconds: 5),
        );
        results['tests']['create'] = true;
      } catch (e) {
        results['tests']['create'] = false;
        results['tests']['create_error'] = e.toString();
      }

      // 3. اختبار القراءة (Read)
      if (results['tests']['create'] == true) {
        try {
          await _networkHelper.withTimeout(
            operation: () => _databases.getDocument(
              databaseId: AppwriteConfigManager.databaseId,
              collectionId: testCollection,
              documentId: testDocumentId,
            ),
            operationName: 'getDocument(Test)',
            timeout: const Duration(seconds: 5),
          );
          results['tests']['read'] = true;
        } catch (e) {
          results['tests']['read'] = false;
          results['tests']['read_error'] = e.toString();
        }

        // 4. اختبار الحذف (Delete)
        try {
          await _networkHelper.withTimeout(
            operation: () => _databases.deleteDocument(
              databaseId: AppwriteConfigManager.databaseId,
              collectionId: testCollection,
              documentId: testDocumentId,
            ),
            operationName: 'deleteDocument(Test)',
            timeout: const Duration(seconds: 5),
          );
          results['tests']['delete'] = true;
        } catch (e) {
          results['tests']['delete'] = false;
          results['tests']['delete_error'] = e.toString();
        }
      }

      // حساب النجاح الكلي
      final tests = results['tests'] as Map<String, dynamic>;
      results['overall_success'] = tests['quick'] == true &&
          (tests['create'] == true || tests['create'] == null) &&
          (tests['read'] == true || tests['read'] == null) &&
          (tests['delete'] == true || tests['delete'] == null);

      _logger.info(
        results['overall_success'] ? '✅ Full test passed' : '⚠️ Full test failed',
        tag: 'CONNECTION_TEST',
      );
    } catch (e) {
      _logger.error('💥 Full test fatal error', error: e, tag: 'CONNECTION_TEST');
      results['error'] = e.toString();
    } finally {
      // تنظيف في حالة بقاء المستند
      if (results['tests'] != null &&
          (results['tests'] as Map)['create'] == true &&
          (results['tests'] as Map)['delete'] != true) {
        try {
          await _databases.deleteDocument(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: testCollection,
            documentId: testDocumentId,
          );
        } catch (_) {
          // تجاهل أخطاء التنظيف
        }
      }
    }

    return results;
  }

  /// اسم مستعار لـ fullConnectionTest
  Future<Map<String, dynamic>> testConnection() => fullConnectionTest();

  // ====================== معلومات المشروع ======================
  Map<String, String> getProjectInfo() {
    return {
      'endpoint': AppwriteConfig.endpoint,
      'projectId': AppwriteConfig.projectId,
      'databaseId': AppwriteConfigManager.databaseId,
      'initialized': _initialized.toString(),
    };
  }
}
