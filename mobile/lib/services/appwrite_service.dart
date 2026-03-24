import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'appwrite_config.dart';
import 'appwrite_config_manager.dart';
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
  // ignore: unused_field
  final _errorHandler = AppwriteErrorHandler();
  final _cache = AppwriteCacheManager();
  final _networkHelper = AppwriteNetworkHelper();

  bool _initialized = false;

  /// Getter للوصول إلى Client من الخارج إذا لزم الأمر
  Client get client => _client;
  Databases get databases => _databases;

  /// التهيئة الأولية
  Future<void> initialize() async {
    if (_initialized) return;

    final endpoint = AppwriteConfigManager.endpoint;
    final projectId = AppwriteConfigManager.projectId;
    final apiKey = AppwriteConfigManager.apiKey;

    _client = Client().setEndpoint(endpoint).setProject(projectId);
    if (apiKey.isNotEmpty) {
      _client.addHeader('X-Appwrite-Key', apiKey);
    }

    // إزالة selfSigned في الإنتاج، مفيدة للتطوير
    // _client.setSelfSigned(status: true);

    _databases = Databases(_client);
    _initialized = true;
    _logger.info('AppwriteService initialized', tag: 'INIT');
  }

  void _ensureInitialized() {
    if (!_initialized) {
      initialize();
      // أو رمي استثناء إذا كان يجب أن تكون مهيأة مسبقاً
      // throw Exception('AppwriteService not initialized');
    }
  }

  // ---------------------------------------------------------------------------
  // Generic Helpers
  // ---------------------------------------------------------------------------

  /// دالة مساعدة عامة لإضافة Query للصفحات
  List<String> _applyPagingQueries(
    List<String> baseQueries, {
    required int limit,
    required int offset,
  }) {
    final effectiveQueries = List<String>.from(baseQueries);

    // التحقق من وجود Limit/Offset مسبقاً لتجنب التكرار
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
    required List<String> queries,
    bool useCache = true,
    bool useRetry = true,
  }) async {
    final cacheKey = '${collectionId}_${queries.join('_')}_all';
    if (useCache) {
      final cached = _cache.get<List<models.Document>>(cacheKey);
      if (cached != null) {
        _logger.debug('Cache hit for $cacheKey', tag: 'CACHE');
        return cached;
      }
    }

    final allDocuments = <models.Document>[];
    int pageOffset = 0;
    final pageSize = AppwriteConfig.maxPageSize;

    while (true) {
      final pagedQueries = _applyPagingQueries(
        queries,
        limit: pageSize,
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

      if (pageDocs.isEmpty) {
        break;
      }

      allDocuments.addAll(pageDocs);

      if (pageDocs.length < pageSize) {
        break;
      }

      pageOffset += pageSize;
    }

    if (useCache) {
      _cache.set(cacheKey, allDocuments, ttl: AppwriteConfig.cacheExpiry);
    }

    _logger.info(
      'Fetched total ${allDocuments.length} documents from $collectionId',
      tag: 'CRUD',
    );
    return allDocuments;
  }

  Future<int> deleteAllDocuments({
    required String collectionId,
    List<String>? queries,
  }) async {
    _ensureInitialized();

    try {
      final documents = await listAllDocuments(
        collectionId: collectionId,
        queries: queries,
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
            'Failed to delete document ${doc.$id} from $collectionId',
            error: e,
            tag: 'CRUD',
          );
        }
      }
      return deleted;
    } catch (e) {
      _logger.error(
        'Failed to delete all documents from $collectionId',
        error: e,
        tag: 'CRUD',
      );
      rethrow;
    }
  }

  Future<List<models.Document>> listAllDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
  }) {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: collectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> _upsertDocumentInternal({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final cleanData = Map<String, dynamic>.from(data)..remove('id');
    final localUuid = cleanData['localUuid']?.toString() ?? documentId;

    // 1. محاولة جلب المستند الحالي للتحقق من التعارض (Optimistic Concurrency Control)
    try {
      final existing = await _databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );

      // 2. التحقق مما إذا كان المحلي أحدث من البعيد
      final shouldUpdate = _shouldUpdateRemote(existing.data, cleanData);

      if (!shouldUpdate) {
        _logger.info(
          'Skipping update for $collectionId/$documentId: Remote is newer or concurrent',
          tag: 'SYNC',
        );
        return existing; // نعتبر العملية ناجحة ولكن لم نغير شيئاً
      }

      // 3. التحديث إذا كان المحلي أحدث
      return await _networkHelper.withRetryAndTimeout(
        operation: () => _databases.updateDocument(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          documentId: documentId,
          data: cleanData,
        ),
        operationName: 'updateDocument',
      );
    } on AppwriteException catch (e) {
      // 404 Not Found -> البحث بـ localUuid أولاً ثم إنشاء مستند جديد
      if (e.code == 404) {
        // ✅ البحث عن المستند بـ localUuid (قد يكون document ID مختلف)
        try {
          final searchResult = await _databases.listDocuments(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: collectionId,
            queries: [Query.equal('localUuid', localUuid)],
          );

          if (searchResult.documents.isNotEmpty) {
            // وجدنا المستند بـ document ID مختلف - استخدمه للتحديث
            final actualDocId = searchResult.documents.first.$id;
            _logger.info(
              'Found document by localUuid, actual ID: $actualDocId (requested: $documentId)',
              tag: 'SYNC',
            );
            
            final shouldUpdate = _shouldUpdateRemote(
              searchResult.documents.first.data, 
              cleanData
            );
            
            if (!shouldUpdate) {
              return searchResult.documents.first;
            }
            
            return await _networkHelper.withRetryAndTimeout(
              operation: () => _databases.updateDocument(
                databaseId: AppwriteConfigManager.databaseId,
                collectionId: collectionId,
                documentId: actualDocId,
                data: cleanData,
              ),
              operationName: 'updateDocument(found_by_localUuid)',
            );
          }
        } catch (searchError) {
          _logger.debug(
            'Search by localUuid failed: $searchError',
            tag: 'SYNC',
          );
        }

        // لم نجد المستند - إنشاء جديد
        try {
          return await _networkHelper.withRetryAndTimeout(
            operation: () => _databases.createDocument(
              databaseId: AppwriteConfigManager.databaseId,
              collectionId: collectionId,
              documentId: documentId,
              data: cleanData,
            ),
            operationName: 'createDocument',
          );
        } on AppwriteException catch (createError) {
          // ✅ إذا كان المستند موجوداً بالفعل، نحاول البحث عنه مرة أخرى ثم التحديث
          if (createError.code == 409 ||
              createError.message?.contains('document_already_exists') == true) {
            _logger.info(
              'Document $documentId already exists (race condition), searching again...',
              tag: 'SYNC',
            );
            
            // البحث عن المستند بـ localUuid
            try {
              final searchResult = await _databases.listDocuments(
                databaseId: AppwriteConfigManager.databaseId,
                collectionId: collectionId,
                queries: [Query.equal('localUuid', localUuid)],
              );

              if (searchResult.documents.isNotEmpty) {
                final actualDocId = searchResult.documents.first.$id;
                return await _networkHelper.withRetryAndTimeout(
                  operation: () => _databases.updateDocument(
                    databaseId: AppwriteConfigManager.databaseId,
                    collectionId: collectionId,
                    documentId: actualDocId,
                    data: cleanData,
                  ),
                  operationName: 'updateDocument(fallback)',
                );
              }
            } catch (_) {}
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// تحديد ما إذا كان يجب تحديث المستند البعيد بناءً على البيانات المحلية القادمة
  bool _shouldUpdateRemote(
    Map<String, dynamic> remote,
    Map<String, dynamic> local,
  ) {
    // 1. استخدام Vector Clock إذا توفر
    final remoteClockStr = remote['vectorClock']?.toString() ??
        remote['vector_clock']?.toString();
    final localClockStr =
        local['vectorClock']?.toString() ?? local['vector_clock']?.toString();

    if (remoteClockStr != null && localClockStr != null) {
      try {
        // نستخدم التنسيق البسيط للمقارنة إذا لم نرد استيراد VectorClock هنا
        // أو يمكننا استيراده إذا كان متاحاً في هذا المجلد
        // للموثوقية، سنفترض أننا نريد تحديث البعيد فقط إذا كان المحلي أحدث
        // بناءً على الطوابع الزمنية كحل احتياطي قوي
      } catch (e) {
        // فشل التحليل
      }
    }

    // 2. استخدام الطوابع الزمنية (updatedAt / lastModified)
    final remoteTs = _extractTs(remote);
    final localTs = _extractTs(local);

    if (remoteTs != null && localTs != null) {
      return localTs > remoteTs;
    }

    // 3. افتراضياً، نحدث إذا لم تتوفر معلومات المقارنة
    return true;
  }

  /// استخراج الطابع الزمني من البيانات
  int? _extractTs(Map<String, dynamic> data) {
    final ts = data['updatedAt'] ??
        data['updated_at'] ??
        data['lastModified'] ??
        data['last_modified'] ??
        data['lastModifiedEpoch'] ??
        data['last_modified_epoch'];

    if (ts is int) return ts;
    if (ts is String) {
      final parsed = DateTime.tryParse(ts);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return null;
  }

  Future<void> _deleteDocumentInternal({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      // نستخدم withTimeout بدلاً من withRetryAndTimeout لأن 404 ليس خطأ يحتاج إعادة محاولة
      // والـ NetworkHelper الآن سيتعامل مع الـ 404 كخطأ غير قابل لإعادة المحاولة
      await _networkHelper.withRetryAndTimeout(
        operation: () => _databases.deleteDocument(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          documentId: documentId,
        ),
        operationName: 'deleteDocument',
      );
    } catch (e) {
      // إذا كان الخطأ هو 404 (document_not_found)، نتجاهله لأنه يعني أن المستند محذوف بالفعل
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('404') || errorStr.contains('document_not_found')) {
        _logger.debug(
          'Document $documentId already deleted from $collectionId',
          tag: 'CRUD',
        );
        return;
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Specific Entity Operations
  // ---------------------------------------------------------------------------

  // Rooms
  Future<List<models.Document>> listRooms({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.roomsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertRoom(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.roomsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteRoom(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.roomsCollectionId,
      documentId: documentId,
    );
  }

  // Bookings
  Future<List<models.Document>> listBookings({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.bookingsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertBooking(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBooking(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.bookingsCollectionId,
      documentId: documentId,
    );
  }

  // Employees
  Future<List<models.Document>> listEmployees({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.employeesCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertEmployee(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.employeesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteEmployee(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.employeesCollectionId,
      documentId: documentId,
    );
  }

  // Expenses
  Future<List<models.Document>> listExpenses({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.expensesCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertExpense(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.expensesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteExpense(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.expensesCollectionId,
      documentId: documentId,
    );
  }

  // Payments
  Future<List<models.Document>> listPayments({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.paymentsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertPayment(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.paymentsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deletePayment(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.paymentsCollectionId,
      documentId: documentId,
    );
  }

  // Debts
  Future<List<models.Document>> listDebts({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.debtsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertDebt(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.debtsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteDebt(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.debtsCollectionId,
      documentId: documentId,
    );
  }

  // Shift Notes
  Future<List<models.Document>> listShiftNotes({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.shiftNotesCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertShiftNote(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.shiftNotesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteShiftNote(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.shiftNotesCollectionId,
      documentId: documentId,
    );
  }

  // Booking Notes
  Future<List<models.Document>> listBookingNotes({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.bookingNotesCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertBookingNote(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingNotesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBookingNote(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.bookingNotesCollectionId,
      documentId: documentId,
    );
  }

  // Booking Nights
  Future<List<models.Document>> listBookingNights({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertBookingNight(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBookingNight(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      documentId: documentId,
    );
  }

  // Cash Transactions
  Future<List<models.Document>> listCashTransactions({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.cashTransactionsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertCashTransaction(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.cashTransactionsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteCashTransaction(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.cashTransactionsCollectionId,
      documentId: documentId,
    );
  }

  // Salary Cycles
  Future<List<models.Document>> listSalaryCycles({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.salaryCyclesCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertSalaryCycle(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.salaryCyclesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteSalaryCycle(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.salaryCyclesCollectionId,
      documentId: documentId,
    );
  }

  // Salary Payments
  Future<List<models.Document>> listSalaryPayments({
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertSalaryPayment(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteSalaryPayment(String documentId) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      documentId: documentId,
    );
  }

  // Generic methods for delta sync
  Future<List<models.Document>> listDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
  }) async {
    _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: collectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: collectionId,
      documentId: documentId,
    );
  }

  Future<models.Document> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: collectionId,
      documentId: documentId,
      data: data,
    );
  }

  /// اختبار اتصال سريع (قراءة فقط)
  Future<bool> quickConnectionTest() async {
    try {
      _ensureInitialized();

      await _networkHelper.withTimeout(
        operation: () => _databases.listDocuments(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: AppwriteConfig.roomsCollectionId,
        ),
        operationName: 'quickConnectionTest',
        timeout: const Duration(seconds: 5),
      );

      _logger.info('Quick connection test successful', tag: 'CONNECTION');
      return true;
    } catch (e) {
      _logger.warning(
        'Quick connection test failed',
        error: e,
        tag: 'CONNECTION',
      );
      return false;
    }
  }

  /// اختبار شامل للاتصال (قراءة وكتابة وحذف)
  Future<Map<String, dynamic>> fullConnectionTest() async {
    final results = <String, dynamic>{
      'tests': <String, dynamic>{},
      'overall_success': false,
    };

    _ensureInitialized();

    final testCollection = AppwriteConfig.syncLogsCollectionId;
    final testDocumentId = ID.unique();
    final now = DateTime.now().millisecondsSinceEpoch;

    try {
      // 1. اختبار الاتصال الأساسي (Ping)
      results['tests']['ping'] = await quickConnectionTest();

      // 2. اختبار الكتابة (Create)

      try {
        await _networkHelper.withTimeout(
          operation: () => _databases.createDocument(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: testCollection,
            documentId: testDocumentId,
            data: {
              'localUuid': testDocumentId,
              'deviceId': 'connection_test',
              'syncType': 'test',
              'startTime': DateTime.now().toIso8601String(),
              'status': 'test',
              'timestamp': now,
              'createdAt': now,
              'updatedAt': now,
              'lastModified': now,
            },
          ),
          operationName: 'createDocument(Test)',
          timeout: const Duration(seconds: 10),
        );
        results['tests']['write'] = true;
      } catch (e) {
        results['tests']['write'] = false;
        results['tests']['write_error'] = e.toString();
      }

      // 3. اختبار القراءة (Read)
      if (results['tests']['write'] == true) {
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

      // حساب الحالة النهائية
      final tests = results['tests'] as Map<String, dynamic>;
      results['overall_success'] =
          tests['ping'] == true &&
          (tests['write'] == true || tests['write'] == null) &&
          (tests['read'] == true || tests['read'] == null) &&
          (tests['delete'] == true || tests['delete'] == null);

      if (results['overall_success'] == true) {
        _logger.info('Full connection test passed', tag: 'CONNECTION_TEST');
      } else {
        _logger.warning(
          'Full connection test failed: $results',
          tag: 'CONNECTION_TEST',
        );
      }

      return results;
    } catch (e) {
      _logger.error(
        'Full connection test fatal error',
        error: e,
        tag: 'CONNECTION_TEST',
      );
      results['overall_success'] = false;
      results['error'] = e.toString();
      return results;
    } finally {
      // تنظيف (في حالة بقاء المستند)
      if (results['tests'] != null &&
          (results['tests'] as Map)['write'] == true &&
          (results['tests'] as Map)['delete'] != true) {
        try {
          final testCollection = AppwriteConfig.syncLogsCollectionId;
          await _databases.deleteDocument(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: testCollection,
            documentId: testDocumentId,
          );
        } catch (_) {
          // Ignore cleanup errors
        }
      }
    }
  }

  /// اختبار الاتصال (alias لـ fullConnectionTest)
  Future<Map<String, dynamic>> testConnection() => fullConnectionTest();

  /// Getter للتحقق من حالة التهيئة
  bool get isInitialized => _initialized;

  /// قراءة مستند واحد
  Future<models.Document> getDocument({
    required String collectionId,
    required String documentId,
  }) async {
    _ensureInitialized();
    return await _networkHelper.withTimeout(
      operation: () => _databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      ),
      operationName: 'getDocument($collectionId/$documentId)',
    );
  }

  /// إنشاء مستند جديد
  Future<models.Document> createDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    _ensureInitialized();
    return await _networkHelper.withTimeout(
      operation: () => _databases.createDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      ),
      operationName: 'createDocument($collectionId/$documentId)',
    );
  }

  /// تحديث مستند موجود
  Future<models.Document> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    _ensureInitialized();
    return await _networkHelper.withTimeout(
      operation: () => _databases.updateDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      ),
      operationName: 'updateDocument($collectionId/$documentId)',
    );
  }

  /// إنشاء سجل مزامنة
  Future<models.Document> createSyncLog(Map<String, dynamic> data) async {
    return await createDocument(
      collectionId: AppwriteConfig.syncLogsCollectionId,
      documentId: data['localUuid'] ?? 'ID.unique()',
      data: data,
    );
  }

  /// جلب سجلات المزامنة
  Future<List<models.Document>> listSyncLogs({
    List<String>? queries,
    bool useCache = true,
  }) async {
    return await listDocuments(
      collectionId: AppwriteConfig.syncLogsCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  /// إنشاء جهاز
  Future<models.Document> createDevice(Map<String, dynamic> data) async {
    return await createDocument(
      collectionId: AppwriteConfig.devicesCollectionId,
      documentId: data['localUuid'] ?? 'ID.unique()',
      data: data,
    );
  }

  /// جلب الأجهزة
  Future<List<models.Document>> listDevices({
    List<String>? queries,
    bool useCache = true,
  }) async {
    return await listDocuments(
      collectionId: AppwriteConfig.devicesCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  /// الحصول على معلومات المشروع
  Map<String, String> getProjectInfo() {
    return {
      'endpoint': AppwriteConfig.endpoint,
      'projectId': AppwriteConfig.projectId,
      'databaseId': AppwriteConfigManager.databaseId,
      'initialized': _initialized.toString(),
    };
  }
}
