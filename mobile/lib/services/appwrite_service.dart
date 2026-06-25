import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;

import 'appwrite_cache_manager.dart';
import 'appwrite_config.dart';
import 'appwrite_config_manager.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_logger.dart';
import 'appwrite_network_helper.dart';
import 'appwrite_sync_utils.dart';

/// خدمة Appwrite الأساسية - CRUD Operations
class AppwriteService {
  factory AppwriteService() => _instance;
  AppwriteService._internal();
  static final AppwriteService _instance = AppwriteService._internal();

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
    if (_initialized) {
      return;
    }

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

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
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
    const pageSize = AppwriteConfig.maxPageSize;

    while (true) {
      final pagedQueries = _applyPagingQueries(
        queries,
        limit: pageSize,
        offset: pageOffset,
      );

      Future<List<models.Document>> performOperation() async {
        // ignore: deprecated_member_use
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
    await _ensureInitialized();

    try {
      final documents = await listAllDocuments(
        collectionId: collectionId,
        queries: queries,
        useCache: false,
      );

      var deleted = 0;
      for (final doc in documents) {
        try {
          await _networkHelper.withRetryAndTimeout<void>(
            // ignore: deprecated_member_use
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
  }) async {
    await _ensureInitialized();
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
    final dbId = AppwriteConfigManager.databaseId;

    // ✅ تطبيع UUID قبل إرساله إلى Appwrite (بدون شرطة + lowercase).
    final normalizedId = AppwriteSyncUtils.normalizeUuid(documentId);

    // ✅ تطبيع حقل localUuid داخل الحمولة أيضاً (إذا وُجد)
    final normalizedData = Map<String, dynamic>.from(data);
    final localUuidInPayload = normalizedData['localUuid'];
    if (localUuidInPayload is String && localUuidInPayload.isNotEmpty) {
      normalizedData['localUuid'] =
          AppwriteSyncUtils.normalizeUuid(localUuidInPayload);
    }

    // نحاول التحديث أولاً (Optimistic) — 404 متوقع في Upsert
    try {
      // ignore: deprecated_member_use
      return await _databases.updateDocument(
        databaseId: dbId,
        collectionId: collectionId,
        documentId: normalizedId,
        data: normalizedData,
      );
    } on AppwriteException catch (e) {
      // 404 Not Found -> Create (هذا السلوك الطبيعي لـ Upsert)
      if (e.code == 404 || (e.type ?? '').contains('document_not_found')) {
        try {
          return _networkHelper.withRetryAndTimeout(
            // ignore: deprecated_member_use
            operation: () => _databases.createDocument(
              databaseId: dbId,
              collectionId: collectionId,
              documentId: normalizedId,
              data: normalizedData,
            ),
            operationName: 'createDocument',
          );
        } on AppwriteException catch (createErr) {
          // ✅ 409 document_already_exists يعني أن المستند موجود فعلاً
          //    لكن ربما بصيغة UUID مختلفة (مع شرطة بدلاً من بدون شرطة،
          //    أو العكس). نحاول update بصيغة الـ ID البديلة.
          if (createErr.code == 409 ||
              (createErr.type ?? '').contains('document_already_exists') ||
              (createErr.message ?? '')
                  .toLowerCase()
                  .contains('already exists')) {
            _logger.warning(
              'upsert($collectionId/$normalizedId): 409 on create — '
              'trying alternative UUID format',
              tag: 'SYNC',
            );

            // ✅ المحاولة 2: update بصيغة الـ ID البديلة
            //    إذا كان normalizedId بدون شرطة، نجرب مع شرطة، والعكس.
            final alternativeId = _getAlternativeUuidFormat(documentId);
            if (alternativeId != null && alternativeId != normalizedId) {
              try {
                // ignore: deprecated_member_use
                final updated = await _databases.updateDocument(
                  databaseId: dbId,
                  collectionId: collectionId,
                  documentId: alternativeId,
                  data: normalizedData,
                );
                _logger.info(
                  'upsert($collectionId): succeeded with alternative format '
                  '$alternativeId — will be normalized on next push',
                  tag: 'SYNC',
                );
                return updated;
              } on AppwriteException catch (altErr) {
                // ✅ المحاولة 3: update بصيغة normalizedId مرة أخيرة
                //    (ربما المستند ظهر للتو بعد تأخر replication)
                if (altErr.code == 404) {
                  _logger.warning(
                    'upsert($collectionId/$normalizedId): alt format also 404 — '
                    'retrying update with normalizedId',
                    tag: 'SYNC',
                  );
                  // ignore: deprecated_member_use
                  return _databases.updateDocument(
                    databaseId: dbId,
                    collectionId: collectionId,
                    documentId: normalizedId,
                    data: normalizedData,
                  );
                }
                rethrow;
              }
            }

            // ✅ fallback أخير: update بصيغة normalizedId
            // ignore: deprecated_member_use
            return _databases.updateDocument(
              databaseId: dbId,
              collectionId: collectionId,
              documentId: normalizedId,
              data: normalizedData,
            );
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// يُرجع الصيغة البديلة للـ UUID:
  /// - إذا كان بدون شرطة (32 حرف) → يُرجع الصيغة مع شرطة (36 حرف)
  /// - إذا كان مع شرطة (36 حرف) → يُرجع الصيغة بدون شرطة (32 حرف)
  /// - إذا لم يكن UUID → يُرجع null
  String? _getAlternativeUuidFormat(String id) {
    if (id.isEmpty) return null;
    final stripped = id.replaceAll('-', '');
    final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
    if (stripped.length != 32 || !hexRegex.hasMatch(stripped)) return null;

    final lower = stripped.toLowerCase();
    // إذا كان أصلياً بدون شرطة → نُرجع مع شرطة
    if (id == lower) {
      return '${lower.substring(0, 8)}-'
          '${lower.substring(8, 12)}-'
          '${lower.substring(12, 16)}-'
          '${lower.substring(16, 20)}-'
          '${lower.substring(20, 32)}';
    }
    // إذا كان أصلياً مع شرطة (أو بصيغة أخرى) → نُرجع بدون شرطة
    return lower;
  }

  Future<void> _deleteDocumentInternal({
    required String collectionId,
    required String documentId,
  }) async {
    // ✅ تطبيع UUID قبل الحذف — نفس السبب كما في _upsertDocumentInternal.
    final normalizedId = AppwriteSyncUtils.normalizeUuid(documentId);
    try {
      await _networkHelper.withRetryAndTimeout<void>(
        // ignore: deprecated_member_use
        operation: () => _databases.deleteDocument(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          documentId: normalizedId,
        ),
        operationName: 'deleteDocument',
      );
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        // ✅ المستند غير موجود بالصيغة بدون شرطة — نجرب الصيغة البديلة
        final alternativeId = _getAlternativeUuidFormat(documentId);
        if (alternativeId != null && alternativeId != normalizedId) {
          try {
            await _networkHelper.withRetryAndTimeout<void>(
              // ignore: deprecated_member_use
              operation: () => _databases.deleteDocument(
                databaseId: AppwriteConfigManager.databaseId,
                collectionId: collectionId,
                documentId: alternativeId,
              ),
              operationName: 'deleteDocument(alt)',
            );
            _logger.info(
              'delete($collectionId): succeeded with alternative format '
              '$alternativeId',
              tag: 'SYNC',
            );
            return;
          } on AppwriteException catch (altErr) {
            if (altErr.code == 404) {
              // Already deleted in both formats, ignore
              return;
            }
            rethrow;
          }
        }
        // Already deleted, ignore
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.roomsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteRoom(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBooking(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.employeesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteEmployee(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.expensesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteExpense(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.paymentsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deletePayment(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.debtsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteDebt(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.shiftNotesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteShiftNote(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingNotesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBookingNote(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBookingNight(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.cashTransactionsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteCashTransaction(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.salaryCyclesCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteSalaryCycle(String documentId) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteSalaryPayment(String documentId) async {
    await _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.salaryPaymentsCollectionId,
      documentId: documentId,
    );
  }

  // GuestInfos
  Future<List<models.Document>> listGuestInfos({
    List<String>? queries,
    bool useCache = true,
  }) async {
    await _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.guestInfosCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertGuestInfo(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.guestInfosCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteGuestInfo(String documentId) async {
    await _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.guestInfosCollectionId,
      documentId: documentId,
    );
  }

  // SalaryWithdrawals
  Future<List<models.Document>> listSalaryWithdrawals({
    List<String>? queries,
    bool useCache = true,
  }) async {
    await _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertSalaryWithdrawal(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteSalaryWithdrawal(String documentId) async {
    await _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
      documentId: documentId,
    );
  }

  // Blacklist
  Future<List<models.Document>> listBlacklist({
    List<String>? queries,
    bool useCache = true,
  }) async {
    await _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.blacklistCollectionId,
      queries: queries ?? [],
      useCache: useCache,
    );
  }

  Future<models.Document> upsertBlacklist(
    String documentId,
    Map<String, dynamic> data,
  ) async {
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: AppwriteConfig.blacklistCollectionId,
      documentId: documentId,
      data: data,
    );
  }

  Future<void> deleteBlacklist(String documentId) async {
    await _ensureInitialized();
    return _deleteDocumentInternal(
      collectionId: AppwriteConfig.blacklistCollectionId,
      documentId: documentId,
    );
  }

  // Generic methods for delta sync
  Future<List<models.Document>> listDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
  }) async {
    await _ensureInitialized();
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
    await _ensureInitialized();
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
    await _ensureInitialized();
    return _upsertDocumentInternal(
      collectionId: collectionId,
      documentId: documentId,
      data: data,
    );
  }

  /// اختبار اتصال سريع (قراءة فقط)
  Future<bool> quickConnectionTest() async {
    try {
      await _ensureInitialized();

      await _networkHelper.withTimeout<models.DocumentList>(
        operation: () =>
            // ignore: deprecated_member_use
            _databases.listDocuments(
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

  /// اختبار شامل للاتصال (قراءة فقط - لا يعتمد على كتابة المستندات)
  Future<Map<String, dynamic>> fullConnectionTest() async {
    final results = <String, dynamic>{
      'tests': <String, dynamic>{},
      'overall_success': false,
    };

    await _ensureInitialized();

    try {
      // 1. اختبار الاتصال الأساسي (Ping) - listDocuments على rooms
      try {
        await _networkHelper.withTimeout<models.DocumentList>(
          operation: () =>
              // ignore: deprecated_member_use
              _databases.listDocuments(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: AppwriteConfig.roomsCollectionId,
            queries: [Query.limit(1)],
          ),
          operationName: 'listDocuments(rooms)',
          timeout: const Duration(seconds: 10),
        );
        results['tests']['rooms'] = true;
      } catch (e) {
        results['tests']['rooms'] = false;
        results['tests']['rooms_error'] = e.toString();
      }

      // 2. اختبار القراءة من bookings
      try {
        await _networkHelper.withTimeout<models.DocumentList>(
          operation: () =>
              // ignore: deprecated_member_use
              _databases.listDocuments(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: AppwriteConfig.bookingsCollectionId,
            queries: [Query.limit(1)],
          ),
          operationName: 'listDocuments(bookings)',
          timeout: const Duration(seconds: 5),
        );
        results['tests']['bookings'] = true;
      } catch (e) {
        results['tests']['bookings'] = false;
        results['tests']['bookings_error'] = e.toString();
      }

      // 3. اختبار القراءة من devices
      try {
        await _networkHelper.withTimeout<models.DocumentList>(
          operation: () =>
              // ignore: deprecated_member_use
              _databases.listDocuments(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: AppwriteConfig.devicesCollectionId,
            queries: [Query.limit(1)],
          ),
          operationName: 'listDocuments(devices)',
          timeout: const Duration(seconds: 5),
        );
        results['tests']['devices'] = true;
      } catch (e) {
        results['tests']['devices'] = false;
        results['tests']['devices_error'] = e.toString();
      }

      // حساب الحالة النهائية - ping يعتمد على rooms فقط
      final tests = results['tests'] as Map<String, dynamic>;
      results['overall_success'] = tests['rooms'] == true;
      results['tests']['ping'] = tests['rooms'];

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
    await _ensureInitialized();
    return _networkHelper.withTimeout(
      // ignore: deprecated_member_use
      operation: () => _databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      ),
      operationName: 'getDocument($collectionId/$documentId)',
    );
  }

  /// قراءة مستند بأمان — يُرجع null بدلاً من رمي استثناء إذا لم يوجد
  /// لا يُسجّل 404 كخطأ لأن البحث عن مستند مفقود أمر طبيعي في المزامنة
  Future<models.Document?> getDocumentSafe({
    required String collectionId,
    required String documentId,
  }) async {
    await _ensureInitialized();
    try {
      // ignore: deprecated_member_use
      return await _databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      ).timeout(AppwriteConfig.defaultTimeout);
    } on AppwriteException catch (e) {
      if (e.code == 404 || e.toString().contains('document_not_found')) {
        _logger.debug(
          'getDocumentSafe($collectionId/$documentId) - مستند غير موجود (طبيعي لسجلات يتيمة)',
          tag: 'SYNC',
        );
        return null;
      }
      _logger.error(
        'getDocumentSafe($collectionId/$documentId) - خطأ: $e',
        error: e,
        tag: 'SYNC',
      );
      rethrow;
    } on TimeoutException {
      _logger.warning(
        'getDocumentSafe($collectionId/$documentId) - انتهت المهلة',
        tag: 'SYNC',
      );
      return null;
    }
  }

  /// إنشاء مستند جديد
  Future<models.Document> createDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();
    return _networkHelper.withTimeout(
      // ignore: deprecated_member_use
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
    await _ensureInitialized();
    return _networkHelper.withTimeout(
      // ignore: deprecated_member_use
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
    return createDocument(
      collectionId: AppwriteConfig.syncLogsCollectionId,
      documentId: (data['localUuid'] ?? 'ID.unique()') as String,
      data: data,
    );
  }

  /// جلب سجلات المزامنة
  Future<List<models.Document>> listSyncLogs({
    List<String>? queries,
    bool useCache = true,
  }) async {
    return listDocuments(
      collectionId: AppwriteConfig.syncLogsCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  /// إنشاء جهاز
  Future<models.Document> createDevice(Map<String, dynamic> data) async {
    return createDocument(
      collectionId: AppwriteConfig.devicesCollectionId,
      documentId: (data['localUuid'] ?? 'ID.unique()') as String,
      data: data,
    );
  }

  /// جلب الأجهزة
  Future<List<models.Document>> listDevices({
    List<String>? queries,
    bool useCache = true,
  }) async {
    return listDocuments(
      collectionId: AppwriteConfig.devicesCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  /// الحصول على معلومات المشروع
  Map<String, String> getProjectInfo() {
    return {
      'endpoint': AppwriteConfigManager.endpoint,
      'projectId': AppwriteConfigManager.projectId,
      'databaseId': AppwriteConfigManager.databaseId,
      'initialized': _initialized.toString(),
    };
  }
}
