import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_network_helper.dart';
import 'local_db.dart';
import 'secondary_appwrite_config.dart';

/// خدمة Appwrite الثانوية — تستخدم Appwrite SDK الرسمي (مثل Primary)
///
/// توفّر واجهة upsert للوجهة الثانوية. تُستخدم من SecondarySyncManager
/// فقط لتسليم سجلات outbox إلى خادم Appwrite الثانوي.
///
/// ❗ هذه الخدمة للكتابة فقط (push). السحب (pull) غير مُدعوم في هذه النسخة.
///
/// ✅ إصلاح (2026-06-28): استخدام AppwriteNetworkHelper لـ retry/timeout
/// مثل Primary. كتم أخطاء 404 المتوقعة في upsert probe.
class SecondaryAppwriteService {
  /// Factory singleton — يُرجع نفس الكائن دائماً.
  factory SecondaryAppwriteService() =>
      _instance ??= SecondaryAppwriteService._();

  SecondaryAppwriteService._();
  static SecondaryAppwriteService? _instance;

  // ignore: prefer_constructors_over_static_methods
  static SecondaryAppwriteService get instance => SecondaryAppwriteService();

  final _networkHelper = AppwriteNetworkHelper();
  // ignore: unused_field
  final _logger = AppwriteLogger();

  Client? _client;
  Databases? _databases;

  /// تهيئة الاتصال بـ Secondary (lazy)
  Future<void> _ensureInitialized() async {
    if (_databases != null) return;

    if (!SecondaryAppwriteConfig.isConfigured) {
      throw StateError(
        'Secondary Appwrite is not configured. '
        'Call SecondaryAppwriteConfig.saveConfig() first.',
      );
    }

    final apiKey = SecondaryAppwriteConfig.apiKey;
    _client = Client()
        .setEndpoint(SecondaryAppwriteConfig.endpoint)
        .setProject(SecondaryAppwriteConfig.projectId);
    if (apiKey.isNotEmpty) {
      _client!.addHeader('X-Appwrite-Key', apiKey);
    }

    _databases = Databases(_client!);
  }

  /// إبطال الكاش (عند تغيير الإعدادات)
  void invalidate() {
    _client = null;
    _databases = null;
  }

  /// نتيجة اختبار الاتصال
  Future<ConnectionTestResult> testConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _ensureInitialized();
      // ignore: deprecated_member_use
      await _databases!.listDocuments(
        databaseId: SecondaryAppwriteConfig.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      stopwatch.stop();
      return ConnectionTestResult(
        success: true,
        message: '✅ تم الاتصال بنجاح',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [Secondary] testConnection failed: $e');
      return ConnectionTestResult(
        success: false,
        message: '❌ فشل: $e',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// رفع نسخة شاملة من كل البيانات المحلية إلى Secondary
  Future<FullBackupStats> uploadFullBackup({
    required void Function(String collection, int current, int total) onProgress,
    required void Function(String collectionName, int successCount, int failureCount) onCollectionComplete,
  }) async {
    await _ensureInitialized();
    final db = DatabaseManager.instance;
    final stats = FullBackupStats();
    final collectionList = _getAllCollections(db);

    stats.totalCollections = collectionList.length;
    for (final coll in collectionList) {
      int successCount = 0;
      int failureCount = 0;
      final details = <Map<String, dynamic>>[];
      int total = coll.records.length;
      int current = 0;

      for (final record in coll.records) {
        current++;
        onProgress(coll.name, current, total);
        try {
          await upsertDocument(
            collectionId: coll.collectionId,
            documentId: record['localUuid'] as String? ?? '',
            data: record,
          );
          successCount++;
        } catch (e) {
          failureCount++;
          stats.failuresByCollection.putIfAbsent(coll.name, () => []).add(
            FullBackupFailure(documentId: record['localUuid']?.toString(), reason: e.toString()),
          );
        }
      }

      onCollectionComplete(coll.name, successCount, failureCount);
      stats.collectionDetails.add({
        'name': coll.name,
        'total': total,
        'success': successCount,
        'failure': failureCount,
        'isFullySuccessful': failureCount == 0,
      });
      stats.successCount += successCount;
      stats.failureCount += failureCount;
      if (failureCount == 0) stats.fullySuccessfulCollections++;
      else stats.failedCollections++;
      stats.collectionNames.add(coll.name);
    }

    return stats;
  }

  /// Upsert مستند في Secondary — معالجة ID بدون شرطات (مثل Primary)
  Future<models.Document> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();
    final dbId = SecondaryAppwriteConfig.databaseId;

    bool isNotFound(AppwriteException e) =>
        e.code == 404 ||
        (e.type ?? '').contains('document_not_found') ||
        e.toString().contains('document_not_found');

    bool isAlreadyExists(AppwriteException e) =>
        e.code == 409 ||
        (e.type ?? '').contains('document_already_exists') ||
        (e.type ?? '').contains('conflict') ||
        e.toString().contains('document_already_exists');

    // ✅ معالجة ID بدون شرطات (نفس Primary)
    final altDocumentId = documentId.contains('-')
        ? documentId.replaceAll('-', '')
        : '';

    Future<models.Document> doUpdate(
      String id, {
      bool suppressErrorLog = false,
    }) async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.updateDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: id,
          data: data,
        ),
        operationName: 'secondary_updateDocument',
        suppressErrorLog: suppressErrorLog,
      );
    }

    Future<models.Document> doCreate() async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.createDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        ),
        operationName: 'secondary_createDocument',
        suppressErrorLog: true,
      );
    }

    // الخطوة 1: updateDocument بالـ ID الأصلي
    try {
      return await doUpdate(documentId, suppressErrorLog: true);
    } on AppwriteException catch (updateError) {
      if (!isNotFound(updateError)) {
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
    }

    // الخطوة 2: createDocument
    try {
      return await doCreate();
    } on AppwriteException catch (createError) {
      if (isAlreadyExists(createError)) {
        // ✅ تجربة ID البديل فقط — بلا حذف/ترحيل (نفس Primary)
        if (altDocumentId.isNotEmpty) {
          try {
            return await doUpdate(altDocumentId, suppressErrorLog: true);
          } on AppwriteException catch (altError) {
            if (!isNotFound(altError)) { rethrow; }
          }
        }
        // محاولة أخيرة
        try { return doUpdate(documentId, suppressErrorLog: true); }
        catch (_) { rethrow; }
      }
      rethrow;
    }
  }

  /// حذف مستند من Secondary
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    await _ensureInitialized();
    try {
      await _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.deleteDocument(
          databaseId: SecondaryAppwriteConfig.databaseId,
          collectionId: collectionId,
          documentId: documentId,
        ),
        operationName: 'secondary_deleteDocument',
      );
    } on AppwriteException catch (e) {
      // 404 = المستند غير موجود أصلاً، نتجاهله
      if (e.code == 404) return;
      rethrow;
    }
  }

  /// الحصول على collection ID لكل كيان
  /// نعيد نفس أسماء collections المستخدمة في Primary لضمان التوافق
  String? getCollectionId(String entity) {
    return AppwriteConfig.collectionIdFor(entity);
  }

  /// تجميع كل بيانات الجداول المحلية للرفع الشامل
  List<_CollectionData> _getAllCollections(AppDatabase db) {
    // ignore: inference_failure_on_collection_literal
    return _kSyncCollections.map((coll) {
      final records = coll.rows.map((r) => r).toList();
      return _CollectionData(name: coll.name, collectionId: coll.collectionId, records: records);
    }).toList();
  }
}

/// نتيجة اختبار الاتصال
class ConnectionTestResult {
  ConnectionTestResult({required this.success, required this.message, this.latencyMs});
  final bool success;
  final String message;
  final int? latencyMs;
}

/// إحصائيات رفع نسخة شاملة
class FullBackupStats {
  int totalCollections = 0;
  int fullySuccessfulCollections = 0;
  int failedCollections = 0;
  int successCount = 0;
  int failureCount = 0;
  String? error;
  final List<String> collectionNames = [];
  final List<Map<String, dynamic>> collectionDetails = [];
  final Map<String, List<FullBackupFailure>> failuresByCollection = {};
  final List<FullBackupFailure> failedRecords = [];
  final Map<String, int> errorsByReason = {};
}

/// خطأ في رفع سجل واحد
class FullBackupFailure {
  FullBackupFailure({this.documentId, required this.reason});
  final String? documentId;
  final String reason;
}

/// بيانات جدول للرفع الشامل
class _CollectionData {
  _CollectionData({required this.name, required this.collectionId, required this.records});
  final String name;
  final String collectionId;
  final List<Map<String, dynamic>> records;
}

// ⚠️ هذه القائمة ثابتة مؤقتاً — للرفع الشامل الأولي
// في نسخة مستقبلية: تُبنى ديناميكياً من AdapterRegistry
// ignore: unused_element
const _kSyncCollections = <_CollectionData>[];
