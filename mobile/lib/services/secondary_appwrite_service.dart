import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_network_helper.dart';
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

  /// اختبار الاتصال بـ Secondary
  Future<bool> testConnection() async {
    try {
      await _ensureInitialized();
      // محاولة قراءة أي مستند كاختبار
      // ignore: deprecated_member_use
      await _databases!.listDocuments(
        databaseId: SecondaryAppwriteConfig.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      return true;
    } catch (e) {
      debugPrint('❌ [Secondary] testConnection failed: $e');
      return false;
    }
  }

  /// Upsert مستند في Secondary — المنطق:
  /// 1) نحاول updateDocument أولاً (Optimistic — الغالبية تحديثات)
  /// 2) إذا فشل بـ 404 → المستند غير موجود → createDocument
  /// 3) إذا فشل createDocument بـ 409 (race) → نعيد updateDocument
  ///
  /// ✅ إصلاح (2026-06-28): نفس منطق Primary مع retry/timeout + كتم 404
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

    // ✅ مساعد لتنفيذ updateDocument مع retry/timeout
    // suppressErrorLog=true لكتم 404 المتوقع في المحاولة الأولى
    Future<models.Document> doUpdate({bool suppressErrorLog = false}) async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.updateDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        ),
        operationName: 'secondary_updateDocument',
        suppressErrorLog: suppressErrorLog,
      );
    }

    // ✅ مساعد لتنفيذ createDocument مع retry/timeout
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
      );
    }

    // الخطوة 1: محاولة updateDocument (كتم 404 المتوقع)
    try {
      return await doUpdate(suppressErrorLog: true);
    } on AppwriteException catch (updateError) {
      if (!isNotFound(updateError)) {
        if (isAlreadyExists(updateError)) {
          _logger.debug(
            'secondary upsert: updateDocument(409) → trying createDocument. '
            'collection=$collectionId, docId=$documentId',
            tag: 'SECONDARY_UPSERT',
          );
          try {
            return await doCreate();
          } on AppwriteException catch (createError2) {
            if (isAlreadyExists(createError2)) {
              try {
                return await doUpdate();
              } catch (finalErr) {
                _logger.error(
                  'secondary upsert: Step 5 updateDocument failed. '
                  'collection=$collectionId, docId=$documentId. Error: $finalErr',
                  tag: 'SECONDARY_UPSERT',
                );
                rethrow;
              }
            }
            rethrow;
          }
        }
        rethrow;
      }
      // 404 متوقع — نسجّل كمعلومة DEBUG
      _logger.debug(
        'secondary upsert: updateDocument(404) → record is new, creating. '
        'collection=$collectionId, docId=$documentId',
        tag: 'SECONDARY_UPSERT',
      );
    }

    // الخطوة 2: update فشل بـ 404 → createDocument
    try {
      return await doCreate();
    } on AppwriteException catch (createError) {
      // الخطوة 3: create فشل بـ 409 → نعيد update
      if (isAlreadyExists(createError)) {
        try {
          return await doUpdate();
        } catch (finalErr) {
          _logger.error(
            'secondary upsert: Step 3 updateDocument failed. '
            'collection=$collectionId, docId=$documentId. Error: $finalErr',
            tag: 'SECONDARY_UPSERT',
          );
          rethrow;
        }
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
}
