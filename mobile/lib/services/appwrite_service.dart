import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';

import 'appwrite_cache_manager.dart';
import 'appwrite_config.dart';
import 'appwrite_config_manager.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_health_checker.dart';
import 'appwrite_logger.dart';
import 'appwrite_network_helper.dart';
import 'secondary_appwrite_config.dart';

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
    int? maxRecords,
  }) async {
    // ✅ Manual failover: if active, read from Secondary instead of Primary
    // This covers all entity reads (listRooms, listBookings, listPayments, etc.)
    if (SecondaryAppwriteConfig.isFailoverActive &&
        SecondaryAppwriteConfig.isPullEnabled &&
        SecondaryAppwriteConfig.isEnabled &&
        SecondaryAppwriteConfig.isConfigured) {
      debugPrint(
          '🔄 [Failover] Manual failover active — reading from Secondary');
      return _listFromSecondary(collectionId, queries);
    }

    final cacheKey = '${collectionId}_${queries.join('_')}_all';
    if (useCache) {
      final cached = _cache.get<List<models.Document>>(cacheKey);
      if (cached != null) {
        _logger.debug('Cache hit for $cacheKey', tag: 'CACHE');
        return cached;
      }
    }

    final allDocuments = <models.Document>[];
    const pageSize = AppwriteConfig.maxPageSize;
    // ✅ P1-4 fix: cursor pagination بدل offset لمنع إسقاط/تكرار السجلات
    String? cursorAfterId;

    try {
      while (true) {
        final pagedQueries = List<String>.from(queries);
        // ✅ P1-4: ترتيب ثابت بـ $id لضمان ترقيم مؤشّري حتمي.
        // ⚠️ إصلاح (PR #451 r3521832510): يجب إضافة orderAsc على كل صفحة،
        // ليس فقط الأولى. cursor pagination يتطلب ترتيباً متطابقاً عبر
        // جميع الصفحات وإلا فاشل Appwrite بـ "cursor requires consistent
        // sort order" أو يُرجع نتائج خاطئة. pagedQueries يُعاد بناؤه
        // من queries (بدون الترتيب) في كل تكرار، لذا يجب إعادة إضافته.
        pagedQueries.add(Query.orderAsc('\$id'));
        pagedQueries.add(Query.limit(pageSize));
        // ✅ P1-4: استخدام cursorAfter بدل offset
        if (cursorAfterId != null) {
          pagedQueries.add(Query.cursorAfter(cursorAfterId));
        }

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

        // ✅ قطع عند بلوغ maxRecords (مثلاً السحب الأولي لـ booking_nights)
        if (maxRecords != null && allDocuments.length >= maxRecords) {
          if (allDocuments.length > maxRecords) {
            allDocuments.removeRange(maxRecords, allDocuments.length);
          }
          break;
        }

        if (pageDocs.length < pageSize) {
          break;
        }

        // ✅ P1-4: تحديث المؤشّر بآخر $id في الصفحة
        cursorAfterId = pageDocs.last.$id;
      }
    } catch (primaryError) {
      // ✅ Failover: إذا فشل Primary و Secondary مُفعّل للسحب (Pull)، نقرأ منه
      if (SecondaryAppwriteConfig.isEnabled &&
          SecondaryAppwriteConfig.isPullEnabled &&
          SecondaryAppwriteConfig.isConfigured) {
        debugPrint(
            '🔄 [Failover] Primary listDocuments failed ($primaryError), '
            'falling back to Secondary for $collectionId');
        try {
          final secondaryDocs = await _listFromSecondary(
            collectionId,
            queries,
          );
          // نضع النتيجة في الكاش لتفادي إعادة Failover المتكرر
          if (useCache) {
            _cache.set(cacheKey, secondaryDocs, ttl: AppwriteConfig.cacheExpiry);
          }
          return secondaryDocs;
        } catch (secondaryError) {
          debugPrint(
              '❌ [Failover] Secondary also failed for $collectionId: $secondaryError');
          // نرمي خطأ Primary الأصلي لأنه المصدر الرئيسي
          rethrow;
        }
      }
      rethrow;
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

  // ════════════════════════════════════════════════════════════════════
  // ✅ Failover: قراءة من Secondary عند فشل Primary
  // ════════════════════════════════════════════════════════════════════
  //
  // عند تعطل Primary (شبكة/خادم)، نقرأ تلقائياً من Secondary (إذا كان
  // متاحاً). هذا يضمن استمرارية عمل التطبيق حتى أثناء انقطاع Primary.
  //
  // الكتابة (push) تظل تعمل عبر outbox — السجلات تُحفظ محلياً وتُرفع
  // للوجهتين عند توفّرهما. لا حاجة لـ failover في الكتابة.

/// يقرأ مستندات من Primary، وإذا فشل يقرأ من Secondary (Failover)
  ///
  /// [collectionId] — معرف الـ collection
  /// [queries] — استعلامات Appwrite
  /// [useCache] — استخدام الكاش (يفضّل تعطيله عند الحاجة لبيانات حديثة)
  /// [healthState] — حالة الوجهتين (إن وُجدت) لتخطّي Primary إذا كان معطّلاً
  Future<List<models.Document>> listDocumentsWithFailover({
    required String collectionId,
    required List<String> queries,
    bool useCache = true,
    AppwriteHealthState? healthState,
  }) async {
    // ✅ الفحص يتم في _listAllDocumentsInternal مسبقاً
    try {
      return await _listAllDocumentsInternal(
        collectionId: collectionId,
        queries: queries,
        useCache: useCache,
      );
    } catch (e) {
      // إذا فشل Primary و Secondary متاح، نقرأ منه
      if (SecondaryAppwriteConfig.isEnabled &&
          SecondaryAppwriteConfig.isConfigured) {
        debugPrint(
            '⚠️ [Failover] Primary failed ($e), falling back to Secondary');
        return _listFromSecondary(collectionId, queries);
      }
      rethrow;
    }
  }

  /// يقرأ مستند واحد من Primary، وإذا فشل يقرأ من Secondary
  Future<models.Document> getDocumentWithFailover({
    required String collectionId,
    required String documentId,
    AppwriteHealthState? healthState,
  }) async {
    await _ensureInitialized();

    // ✅ إذا كان المستخدم قد فعل Failover يدوياً، نقرأ مباشرة من Secondary
    if (SecondaryAppwriteConfig.isFailoverActive &&
        SecondaryAppwriteConfig.isPullEnabled &&
        SecondaryAppwriteConfig.isEnabled &&
        SecondaryAppwriteConfig.isConfigured) {
      debugPrint(
          '🔄 [Failover] Manual failover active — reading from Secondary for getDocument');
      return _getFromSecondary(collectionId, documentId);
    }

    // إذا كانت حالة Primary معروفة بأنها معطّلة، نقرأ مباشتاً من Secondary
    if (healthState != null &&
        healthState.shouldFailover &&
        SecondaryAppwriteConfig.isEnabled &&
        SecondaryAppwriteConfig.isConfigured) {
      return _getFromSecondary(collectionId, documentId);
    }

    try {
      // ignore: deprecated_member_use
      return await _databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      );
    } catch (e) {
      if (SecondaryAppwriteConfig.isEnabled &&
          SecondaryAppwriteConfig.isConfigured) {
        debugPrint(
            '⚠️ [Failover] getDocument Primary failed ($e), falling back to Secondary');
        return _getFromSecondary(collectionId, documentId);
      }
      rethrow;
    }
  }

  /// قراءة مستندات من Secondary مباشرة
  Future<List<models.Document>> _listFromSecondary(
    String collectionId,
    List<String> queries,
  ) async {
    final client = Client()
        .setEndpoint(SecondaryAppwriteConfig.endpoint)
        .setProject(SecondaryAppwriteConfig.projectId);
    final apiKey = SecondaryAppwriteConfig.apiKey;
    if (apiKey.isNotEmpty) {
      client.addHeader('X-Appwrite-Key', apiKey);
    }
    final db = Databases(client);

    final allDocuments = <models.Document>[];
    int pageOffset = 0;
    const pageSize = AppwriteConfig.maxPageSize;

    while (true) {
      final pagedQueries = _applyPagingQueries(
        queries,
        limit: pageSize,
        offset: pageOffset,
      );
      // ignore: deprecated_member_use
      final result = await db.listDocuments(
        databaseId: SecondaryAppwriteConfig.databaseId,
        collectionId: collectionId,
        queries: pagedQueries,
      ).timeout(const Duration(seconds: 30));
      if (result.documents.isEmpty) break;
      allDocuments.addAll(result.documents);
      if (result.documents.length < pageSize) break;
      pageOffset += pageSize;
    }
    return allDocuments;
  }

  /// قراءة مستند واحد من Secondary مباشرة
  Future<models.Document> _getFromSecondary(
    String collectionId,
    String documentId,
  ) async {
    final client = Client()
        .setEndpoint(SecondaryAppwriteConfig.endpoint)
        .setProject(SecondaryAppwriteConfig.projectId);
    final apiKey = SecondaryAppwriteConfig.apiKey;
    if (apiKey.isNotEmpty) {
      client.addHeader('X-Appwrite-Key', apiKey);
    }
    final db = Databases(client);
    // ignore: deprecated_member_use
    return db.getDocument(
      databaseId: SecondaryAppwriteConfig.databaseId,
      collectionId: collectionId,
      documentId: documentId,
    );
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
          await _networkHelper.withRetryAndTimeout(
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

  /// استخراج اسم السمة غير المعروفة من خطأ Appwrite (إن وُجد).
  ///
  /// عند إرسال حقل غير موجود في مخطط Appwrite تُعيد الخدمة:
  ///   document_invalid_structure: Unknown attribute: "X" (400)
  /// نلتقط اسم الحقل "X" لإزالته ثم إعادة المحاولة، بدل فشل السجل كاملاً.
  /// يُعيد null إذا لم يكن الخطأ من هذا النوع.
  static final RegExp _unknownAttrPattern =
      RegExp(r'Unknown attribute:\s*"([^"]+)"');

  String? _extractUnknownAttribute(AppwriteException e) {
    final type = e.type ?? '';
    final msg = e.message ?? e.toString();
    final isStructureError = e.code == 400 &&
        (type.contains('document_invalid_structure') ||
            msg.contains('Invalid document structure') ||
            msg.contains('Unknown attribute'));
    if (!isStructureError) return null;
    final match = _unknownAttrPattern.firstMatch(msg);
    return match?.group(1);
  }

  /// غلاف عام حول عملية الرفع الفعلية يجعل المزامنة صامدة أمام انحراف
  /// المخطط بين التطبيق و Appwrite Cloud: إذا رفض الخادم حقلاً غير معروف
  /// (Unknown attribute)، نُزيل ذلك الحقل فقط ونعيد المحاولة — فبدل أن
  /// يفشل السجل بالكامل، يُرفَع بباقي الحقول الصحيحة.
  Future<models.Document> _upsertDocumentInternal({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    var workingData = Map<String, dynamic>.from(data);
    // حد أعلى للمحاولات = عدد الحقول (كل محاولة تُزيل حقلاً واحداً على الأكثر).
    final maxRetries = workingData.length + 1;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _upsertDocumentOnce(
          collectionId: collectionId,
          documentId: documentId,
          data: workingData,
        );
      } on AppwriteException catch (e) {
        final unknownAttr = _extractUnknownAttribute(e);
        if (unknownAttr != null &&
            workingData.containsKey(unknownAttr) &&
            attempt < maxRetries) {
          workingData = Map<String, dynamic>.from(workingData)
            ..remove(unknownAttr);
          _logger.warning(
            '⚠️ حقل غير معروف في مخطط Appwrite — تمت إزالته وإعادة المحاولة: '
            '$collectionId.$unknownAttr (شغّل unified_appwrite_setup.js '
            'لإضافته إلى المخطط)',
            tag: 'SCHEMA_DRIFT',
          );
          continue;
        }
        rethrow;
      }
    }
  }

  Future<models.Document> _upsertDocumentOnce({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    final dbId = AppwriteConfigManager.databaseId;

    bool isNotFound(AppwriteException e) =>
        e.code == 404 ||
        (e.type ?? '').contains('document_not_found') ||
        e.toString().contains('document_not_found');

    bool isAlreadyExists(AppwriteException e) =>
        e.code == 409 ||
        (e.type ?? '').contains('document_already_exists') ||
        (e.type ?? '').contains('conflict') ||
        e.toString().contains('document_already_exists');

    // ✅ إصلاح حرج (2026-06-28): معالجة مستندات بـ ID بدون شرطات
    //
    // بعض المستندات القديمة خُزّنت في Appwrite بـ ID بدون شرطات:
    //   0ac7942fd83e4081934815e60752b560  (32 حرف متصل)
    // بينما التطبيق يرسل:
    //   0ac7942f-d83e-4081-9348-15e60752b560  (UUID قياسي بشرطات)
    //
    // النتيجة:
    //   updateDocument(with-dashes) → 404
    //   createDocument(with-dashes) → 409 (ID محجوز!)
    //
    // الحل: نولّد الصيغة البديلة للـ ID ونجرّبها إذا فشلت الأولى.
    final altDocumentId = documentId.contains('-')
        ? documentId.replaceAll('-', '')  // إزالة الشرطات
        : '';  // ID أصلاً بدون شرطات — لا بديل

    // مساعد لتنفيذ updateDocument بـ ID محدد
    Future<models.Document> doUpdate(
      String id, {
      bool suppressErrorLog = false,
    }) async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases.updateDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: id,
          data: data,
        ),
        operationName: 'updateDocument',
        suppressErrorLog: suppressErrorLog,
      );
    }

    // مساعد لتنفيذ createDocument
    Future<models.Document> doCreate() async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases.createDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        ),
        operationName: 'createDocument',
        suppressErrorLog: true,
      );
    }

    // ─── الخطوة 1: updateDocument بالـ ID الأصلي (بالشرطات) ───
    try {
      return await doUpdate(documentId, suppressErrorLog: true);
    } on AppwriteException catch (updateError) {
      if (!isNotFound(updateError)) {
        // 409 على update → نادر، نحاول create
        if (isAlreadyExists(updateError)) {
          try { return await doCreate(); }
          on AppwriteException catch (e2) {
            if (isAlreadyExists(e2)) {
              try { return await doUpdate(documentId); }
              catch (e3) { rethrow; }
            }
            rethrow;
          }
        }
        rethrow;
      }
      // 404 — متوقع للسجلات الجديدة أو المستندات بدون شرطات
    }

    // ─── الخطوة 1.5: قبل الإنشاء، جرّب تحديث الـ ID البديل (بدون شرطات) ───
    //
    // ✅ إصلاح جذري للتكرار: المستند قد يكون موجودًا بصيغة بدون شرطات فقط.
    // في هذه الحالة update(بشرطات) يعطي 404 ثم create(بشرطات) ينجح
    // فتُنشأ نسخة مكررة (نفس UUID بصيغتين). لذا نحدّث المستند البديل في مكانه
    // إن وُجد، ونتجنّب الإنشاء المكرر تمامًا.
    if (altDocumentId.isNotEmpty) {
      try {
        return await doUpdate(altDocumentId, suppressErrorLog: true);
      } on AppwriteException catch (altError) {
        if (!isNotFound(altError)) {
          rethrow; // خطأ آخر غير 404
        }
        // 404 على البديل أيضًا — المستند غير موجود بأي صيغة → ننتقل للإنشاء
      }
    }

    // ─── الخطوة 2: createDocument ───
    try {
      return await doCreate();
    } on AppwriteException catch (createError) {
      if (isAlreadyExists(createError)) {
        // ─── الخطوة 3: create فشل بـ 409 → المستند موجود بـ ID مختلف ───
        //
        // ✅ إصلاح (2026-06-28): تجربة ID البديل فقط — بلا حذف/ترحيل
        //
        // الدرس السابق: الترحيل الذاتي (delete + create) كان يخاطر بحذف
        // بيانات من Appwrite Cloud إذا فشل create بعد delete.
        // بدلاً من ذلك: نجرب updateDocument بالـ ID البديل (بدون شرطات).
        // إذا نجح → البيانات محدّثة في مكانها الصحيح.
        // إذا فشل → السجل يبقى في outbox لإعادة المحاولة. لا حذف.

        if (altDocumentId.isNotEmpty) {
          try {
            _logger.debug(
              'upsert: trying alt ID (no dashes): $altDocumentId',
              tag: 'UPSERT',
            );
            return await doUpdate(altDocumentId, suppressErrorLog: true);
          } on AppwriteException catch (altError) {
            if (!isNotFound(altError)) {
              rethrow; // خطأ آخر غير 404
            }
            // 404 على ID البديل — المستند موجود بصيغة أخرى أو مشكلة في DB
          }
        }

        // محاولة أخيرة: updateDocument بالـ ID الأصلي
        try {
          return await doUpdate(documentId, suppressErrorLog: true);
        } on AppwriteException catch (finalErr) {
          if (isNotFound(finalErr)) {
            _logger.warning(
              '⚠️ upsert: document exists (409) but unreachable by any ID format. '
              'collection=$collectionId, docId=$documentId',
              tag: 'UPSERT',
            );
          }
          rethrow;
        }
      }
      // create فشل بخطأ آخر (وليس 409)
      _logger.error(
        'upsert: createDocument failed. '
        'collection=$collectionId, docId=$documentId. Error: $createError',
        tag: 'UPSERT',
      );
      rethrow;
    }
  }

  Future<void> _deleteDocumentInternal({
    required String collectionId,
    required String documentId,
  }) async {
    try {
      await _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases.deleteDocument(
          databaseId: AppwriteConfigManager.databaseId,
          collectionId: collectionId,
          documentId: documentId,
        ),
        operationName: 'deleteDocument',
      );
    } on AppwriteException catch (e) {
      if (e.code == 404) {
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
    int? maxRecords,
  }) async {
    await _ensureInitialized();
    return _listAllDocumentsInternal(
      collectionId: AppwriteConfig.bookingNightsCollectionId,
      queries: queries ?? [],
      useCache: useCache,
      maxRecords: maxRecords,
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
  Future<List<models.Document>> listRows({
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

  Future<void> deleteRow({
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

      await _networkHelper.withTimeout(
        // ignore: deprecated_member_use
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
        await _networkHelper.withTimeout(
          // ignore: deprecated_member_use
          operation: () => _databases.listDocuments(
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
        await _networkHelper.withTimeout(
          // ignore: deprecated_member_use
          operation: () => _databases.listDocuments(
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
        await _networkHelper.withTimeout(
          // ignore: deprecated_member_use
          operation: () => _databases.listDocuments(
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
  Future<models.Document> getRow({
    required String collectionId,
    required String documentId,
    // ✅ إصلاح #2-D: كتم 404 المتوقع في فحص OCC. عند استدعاء getRow من
    // _occCheckAndMerge، 404 يعني ببساطة أن المستند جديد (لم يُرفع بعد)
    // — وهو سلوك متوقع وليس خطأ. تمرير suppressErrorLog: true يخفضه من
    // ERROR إلى debug في السجل.
    bool suppressErrorLog = false,
  }) async {
    await _ensureInitialized();
    // ✅ Manual failover: if active, read from Secondary instead
    if (SecondaryAppwriteConfig.isFailoverActive &&
        SecondaryAppwriteConfig.isPullEnabled &&
        SecondaryAppwriteConfig.isEnabled &&
        SecondaryAppwriteConfig.isConfigured) {
      debugPrint(
          '🔄 [Failover] Manual failover active — reading document from Secondary');
      return _getFromSecondary(collectionId, documentId);
    }
    return _networkHelper.withTimeout(
      // ignore: deprecated_member_use
      operation: () => _databases.getDocument(
        databaseId: AppwriteConfigManager.databaseId,
        collectionId: collectionId,
        documentId: documentId,
      ),
      operationName: 'getRow($collectionId/$documentId)',
      suppressErrorLog: suppressErrorLog,
    );
  }

  /// إنشاء مستند جديد
  Future<models.Document> createRow({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();
    var workingData = Map<String, dynamic>.from(data);
    final maxRetries = workingData.length + 1;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _networkHelper.withTimeout(
          // ignore: deprecated_member_use
          operation: () => _databases.createDocument(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: collectionId,
            documentId: documentId,
            data: workingData,
          ),
          operationName: 'createRow($collectionId/$documentId)',
        );
      } on AppwriteException catch (e) {
        final unknownAttr = _extractUnknownAttribute(e);
        if (unknownAttr != null &&
            workingData.containsKey(unknownAttr) &&
            attempt < maxRetries) {
          workingData = Map<String, dynamic>.from(workingData)
            ..remove(unknownAttr);
          _logger.warning(
            '⚠️ حقل غير معروف في مخطط Appwrite — أُزيل وأُعيدت المحاولة: '
            '$collectionId.$unknownAttr',
            tag: 'SCHEMA_DRIFT',
          );
          continue;
        }
        rethrow;
      }
    }
  }

  /// تحديث مستند موجود
  Future<models.Document> updateRow({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();
    var workingData = Map<String, dynamic>.from(data);
    final maxRetries = workingData.length + 1;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _networkHelper.withTimeout(
          // ignore: deprecated_member_use
          operation: () => _databases.updateDocument(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: collectionId,
            documentId: documentId,
            data: workingData,
          ),
          operationName: 'updateRow($collectionId/$documentId)',
        );
      } on AppwriteException catch (e) {
        final unknownAttr = _extractUnknownAttribute(e);
        if (unknownAttr != null &&
            workingData.containsKey(unknownAttr) &&
            attempt < maxRetries) {
          workingData = Map<String, dynamic>.from(workingData)
            ..remove(unknownAttr);
          _logger.warning(
            '⚠️ حقل غير معروف في مخطط Appwrite — أُزيل وأُعيدت المحاولة: '
            '$collectionId.$unknownAttr',
            tag: 'SCHEMA_DRIFT',
          );
          continue;
        }
        rethrow;
      }
    }
  }

  /// إنشاء سجل مزامنة
  Future<models.Document> createSyncLog(Map<String, dynamic> data) async {
    return createRow(
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
    return listRows(
      collectionId: AppwriteConfig.syncLogsCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  /// إنشاء جهاز
  Future<models.Document> createDevice(Map<String, dynamic> data) async {
    return createRow(
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
    return listRows(
      collectionId: AppwriteConfig.devicesCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  // ---------------------------------------------------------------------------
  // Convenience Aliases (used by sync managers, delta sync, auth_local_store)
  // These delegate to the existing generic methods above.
  // ---------------------------------------------------------------------------

  /// Alias for [listRows] — used by callers expecting `listDocuments` name.
  Future<List<models.Document>> listDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
  }) {
    return listRows(
      collectionId: collectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  /// Alias for [getRow] — used by callers expecting `getDocument` name.
  Future<models.Document> getDocument({
    required String collectionId,
    required String documentId,
    bool suppressErrorLog = false,
  }) {
    return getRow(
      collectionId: collectionId,
      documentId: documentId,
      suppressErrorLog: suppressErrorLog,
    );
  }

  /// Alias for [updateRow] — used by callers expecting `updateDocument` name.
  Future<models.Document> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return updateRow(
      collectionId: collectionId,
      documentId: documentId,
      data: data,
    );
  }

  /// Alias for [createRow] — used by callers expecting `createDocument` name.
  Future<models.Document> createDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) {
    return createRow(
      collectionId: collectionId,
      documentId: documentId,
      data: data,
    );
  }

  /// Alias for [deleteRow] — used by callers expecting `deleteDocument` name.
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) {
    return deleteRow(
      collectionId: collectionId,
      documentId: documentId,
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
