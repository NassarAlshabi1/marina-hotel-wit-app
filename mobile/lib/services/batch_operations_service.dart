import 'package:appwrite/models.dart' as models;
import 'appwrite_service.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_logger.dart';

/// نتيجة عملية Batch
class BatchResult<T> {

  BatchResult({
    required this.total,
    required this.successful,
    required this.failed,
    required this.successfulItems,
    required this.errors,
  });
  final int total;
  final int successful;
  final int failed;
  final List<T> successfulItems;
  final Map<String, String> errors;

  bool get isFullSuccess => failed == 0;
  bool get isPartialSuccess => successful > 0 && failed > 0;
  bool get isFullFailure => successful == 0;
  double get successRate => total > 0 ? successful / total : 0.0;

  @override
  String toString() =>
      'BatchResult(total: $total, successful: $successful, failed: $failed, rate: ${(successRate * 100).toStringAsFixed(1)}%)';
}

/// خدمة العمليات الجماعية (Batch Operations)
///
/// توفر طرق لتنفيذ عمليات متعددة بشكل متوازي
class BatchOperationsService {
  factory BatchOperationsService() => _instance;
  BatchOperationsService._internal();
  static final BatchOperationsService _instance =
      BatchOperationsService._internal();

  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();
  final _appwriteService = AppwriteService();

  /// حذف عدة مستندات دفعة واحدة
  ///
  /// [databaseId] - معرف قاعدة البيانات
  /// [collectionId] - معرف المجموعة
  /// [documentIds] - قائمة معرفات المستندات
  /// [parallel] - هل التنفيذ متوازي؟ (افتراضي: true)
  Future<BatchResult<String>> deleteDocuments({
    required String databaseId,
    required String collectionId,
    required List<String> documentIds,
    bool parallel = true,
  }) async {
    _logger.info(
      'Deleting ${documentIds.length} documents from $collectionId',
      tag: 'BATCH',
    );

    final successfulItems = <String>[];
    final errors = <String, String>{};

    if (parallel) {
      // تنفيذ متوازي
      final results = await Future.wait(
        documentIds.map((id) async {
          try {
            await _appwriteService.deleteDocument(
              collectionId: collectionId,
              documentId: id,
            );
            return {'id': id, 'success': true};
          } catch (e) {
            return {
              'id': id,
              'success': false,
              'error': _errorHandler.handleError(e).message,
            };
          }
        }),
      );

      // معالجة النتائج
      for (final result in results) {
        if (result['success'] == true) {
          successfulItems.add(result['id'] as String);
        } else {
          errors[result['id'] as String] = result['error'] as String;
        }
      }
    } else {
      // تنفيذ تسلسلي
      for (final id in documentIds) {
        try {
          await _appwriteService.deleteDocument(
            collectionId: collectionId,
            documentId: id,
          );
          successfulItems.add(id);
        } catch (e) {
          errors[id] = _errorHandler.handleError(e).message;
        }
      }
    }

    final result = BatchResult<String>(
      total: documentIds.length,
      successful: successfulItems.length,
      failed: errors.length,
      successfulItems: successfulItems,
      errors: errors,
    );

    _logger.info('Batch delete completed: $result', tag: 'BATCH');
    return result;
  }

  /// إنشاء عدة مستندات دفعة واحدة
  ///
  /// [databaseId] - معرف قاعدة البيانات
  /// [collectionId] - معرف المجموعة
  /// [documents] - قائمة البيانات للإنشاء
  /// [parallel] - هل التنفيذ متوازي؟ (افتراضي: true)
  Future<BatchResult<models.Document>> createDocuments({
    required String databaseId,
    required String collectionId,
    required List<Map<String, dynamic>> documents,
    bool parallel = true,
  }) async {
    _logger.info(
      'Creating ${documents.length} documents in $collectionId',
      tag: 'BATCH',
    );

    final successfulItems = <models.Document>[];
    final errors = <String, String>{};

    if (parallel) {
      // تنفيذ متوازي
      final results = await Future.wait(
        documents.asMap().entries.map((entry) async {
          final index = entry.key;
          final data = entry.value;

          try {
            final doc = await _appwriteService.createDocument(
              collectionId: collectionId,
              documentId: data['localUuid'] ?? 'unique()',
              data: data,
            );
            return {'index': index, 'success': true, 'document': doc};
          } catch (e) {
            return {
              'index': index,
              'success': false,
              'error': _errorHandler.handleError(e).message,
            };
          }
        }),
      );

      // معالجة النتائج
      for (final result in results) {
        if (result['success'] == true) {
          successfulItems.add(result['document'] as models.Document);
        } else {
          errors['document_${result['index']}'] = result['error'] as String;
        }
      }
    } else {
      // تنفيذ تسلسلي
      for (var i = 0; i < documents.length; i++) {
        try {
          final doc = await _appwriteService.createDocument(
            collectionId: collectionId,
            documentId: documents[i]['localUuid'] ?? 'unique()',
            data: documents[i],
          );
          successfulItems.add(doc);
        } catch (e) {
          errors['document_$i'] = _errorHandler.handleError(e).message;
        }
      }
    }

    final result = BatchResult<models.Document>(
      total: documents.length,
      successful: successfulItems.length,
      failed: errors.length,
      successfulItems: successfulItems,
      errors: errors,
    );

    _logger.info('Batch create completed: $result', tag: 'BATCH');
    return result;
  }

  /// تحديث عدة مستندات دفعة واحدة
  ///
  /// [databaseId] - معرف قاعدة البيانات
  /// [collectionId] - معرف المجموعة
  /// [updates] - قائمة التحديثات (كل عنصر: {id, data})
  /// [parallel] - هل التنفيذ متوازي؟ (افتراضي: true)
  Future<BatchResult<models.Document>> updateDocuments({
    required String databaseId,
    required String collectionId,
    required List<Map<String, dynamic>> updates,
    bool parallel = true,
  }) async {
    _logger.info(
      'Updating ${updates.length} documents in $collectionId',
      tag: 'BATCH',
    );

    final successfulItems = <models.Document>[];
    final errors = <String, String>{};

    if (parallel) {
      // تنفيذ متوازي
      final results = await Future.wait(
        updates.map((update) async {
          final id = update['id'] as String;
          final data = update['data'] as Map<String, dynamic>;

          try {
            final doc = await _appwriteService.updateDocument(
              collectionId: collectionId,
              documentId: id,
              data: data,
            );
            return {'id': id, 'success': true, 'document': doc};
          } catch (e) {
            return {
              'id': id,
              'success': false,
              'error': _errorHandler.handleError(e).message,
            };
          }
        }),
      );

      // معالجة النتائج
      for (final result in results) {
        if (result['success'] == true) {
          successfulItems.add(result['document'] as models.Document);
        } else {
          errors[result['id'] as String] = result['error'] as String;
        }
      }
    } else {
      // تنفيذ تسلسلي
      for (final update in updates) {
        final id = update['id'] as String;
        final data = update['data'] as Map<String, dynamic>;

        try {
          final doc = await _appwriteService.updateDocument(
            collectionId: collectionId,
            documentId: id,
            data: data,
          );
          successfulItems.add(doc);
        } catch (e) {
          errors[id] = _errorHandler.handleError(e).message;
        }
      }
    }

    final result = BatchResult<models.Document>(
      total: updates.length,
      successful: successfulItems.length,
      failed: errors.length,
      successfulItems: successfulItems,
      errors: errors,
    );

    _logger.info('Batch update completed: $result', tag: 'BATCH');
    return result;
  }

  /// تنفيذ عمليات مختلطة (إنشاء، تحديث، حذف)
  ///
  /// [operations] - قائمة العمليات
  Future<Map<String, BatchResult>> executeMixedOperations({
    required List<BatchOperation> operations,
    bool parallel = true,
  }) async {
    _logger.info(
      'Executing ${operations.length} mixed operations',
      tag: 'BATCH',
    );

    final results = <String, BatchResult>{};

    if (parallel) {
      final futures = operations.map((op) => op.execute());
      final batchResults = await Future.wait(futures);

      for (var i = 0; i < operations.length; i++) {
        results[operations[i].name] = batchResults[i];
      }
    } else {
      for (final op in operations) {
        results[op.name] = await op.execute();
      }
    }

    return results;
  }
}

/// عملية Batch
abstract class BatchOperation {
  String get name;
  Future<BatchResult> execute();
}

/// عملية حذف Batch
class BatchDeleteOperation extends BatchOperation {

  BatchDeleteOperation({
    required this.databaseId,
    required this.collectionId,
    required this.documentIds,
  });
  final String databaseId;
  final String collectionId;
  final List<String> documentIds;

  @override
  String get name => 'delete_${collectionId}_${documentIds.length}';

  @override
  Future<BatchResult> execute() {
    return BatchOperationsService().deleteDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      documentIds: documentIds,
    );
  }
}

/// عملية إنشاء Batch
class BatchCreateOperation extends BatchOperation {

  BatchCreateOperation({
    required this.databaseId,
    required this.collectionId,
    required this.documents,
  });
  final String databaseId;
  final String collectionId;
  final List<Map<String, dynamic>> documents;

  @override
  String get name => 'create_${collectionId}_${documents.length}';

  @override
  Future<BatchResult> execute() {
    return BatchOperationsService().createDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      documents: documents,
    );
  }
}
