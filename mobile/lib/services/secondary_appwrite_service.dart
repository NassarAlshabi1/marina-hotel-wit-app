import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'secondary_appwrite_config.dart';

/// خدمة Appwrite الثانوية — تستخدم Appwrite SDK الرسمي (مثل Primary)
///
/// توفّر واجهة upsert للوجهة الثانوية. تُستخدم من SecondarySyncManager
/// فقط لتسليم سجلات outbox إلى خادم Appwrite الثانوي.
///
/// ❗ هذه الخدمة للكتابة فقط (push). السحب (pull) غير مُدعوم في هذه النسخة.
class SecondaryAppwriteService {
  /// Factory singleton — يُرجع نفس الكائن دائماً.
  factory SecondaryAppwriteService() =>
      _instance ??= SecondaryAppwriteService._();

  SecondaryAppwriteService._();
  static SecondaryAppwriteService? _instance;

  // ignore: prefer_constructors_over_static_methods
  static SecondaryAppwriteService get instance => SecondaryAppwriteService();

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
  /// نفس منطق Primary upsert، لكن على Secondary endpoint.
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

    // الخطوة 1: محاولة updateDocument
    try {
      // ignore: deprecated_member_use
      return await _databases!.updateDocument(
        databaseId: dbId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
    } on AppwriteException catch (updateError) {
      if (!isNotFound(updateError)) {
        // إذا 409 على update (نادر) → نحاول create
        if (isAlreadyExists(updateError)) {
          try {
            // ignore: deprecated_member_use
            return await _databases!.createDocument(
              databaseId: dbId,
              collectionId: collectionId,
              documentId: documentId,
              data: data,
            );
          } on AppwriteException catch (createError2) {
            if (isAlreadyExists(createError2)) {
              // ignore: deprecated_member_use
              return _databases!.updateDocument(
                databaseId: dbId,
                collectionId: collectionId,
                documentId: documentId,
                data: data,
              );
            }
            rethrow;
          }
        }
        rethrow;
      }
      // المتابعة إلى createDocument (حالة 404)
    }

    // الخطوة 2: update فشل بـ 404 → createDocument
    try {
      // ignore: deprecated_member_use
      return await _databases!.createDocument(
        databaseId: dbId,
        collectionId: collectionId,
        documentId: documentId,
        data: data,
      );
    } on AppwriteException catch (createError) {
      // الخطوة 3: create فشل بـ 409 (race) → نعيد update
      if (isAlreadyExists(createError)) {
        // ignore: deprecated_member_use
        return _databases!.updateDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        );
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
      // ignore: deprecated_member_use
      await _databases!.deleteDocument(
        databaseId: SecondaryAppwriteConfig.databaseId,
        collectionId: collectionId,
        documentId: documentId,
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
