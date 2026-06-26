import 'package:appwrite/appwrite.dart';
import '../appwrite_logger.dart';

/// Helper class for logging Appwrite errors with table and field information
class AppwriteErrorHelper {
  AppwriteErrorHelper._();
  static final AppwriteErrorHelper instance = AppwriteErrorHelper._();

  final _logger = AppwriteLogger();

  /// Log error for document operations
  void logDocumentError({
    required String collectionName,
    required String operation,
    required String errorMessage,
    String? documentId,
    Map<String, dynamic>? documentData,
    dynamic appwriteException,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('📄 خطأ في المستند');
    buffer.writeln('   الجدول: $collectionName');
    buffer.writeln('   العملية: $operation');
    if (documentId != null) {
      buffer.writeln('   معرف المستند: $documentId');
    }
    if (documentData != null) {
      buffer.writeln('   البيانات: ${_truncateData(documentData)}');
    }
    buffer.write('   الخطأ: $errorMessage');

    _logger.log(
      buffer.toString(),
      level: LogLevel.error,
      tag: 'DOCUMENT_ERROR',
      error: appwriteException ?? errorMessage,
      stackTrace: stackTrace,
    );
  }

  /// Log error for attribute/field operations
  void logAttributeError({
    required String collectionName,
    required String attributeName,
    required String errorMessage,
    dynamic attributeValue,
    dynamic appwriteException,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🔷 خطأ في الحقل');
    buffer.writeln('   الجدول: $collectionName');
    buffer.writeln('   الحقل: $attributeName');
    if (attributeValue != null) {
      buffer.writeln('   القيمة: $attributeValue');
    }
    buffer.write('   الخطأ: $errorMessage');

    _logger.log(
      buffer.toString(),
      level: LogLevel.error,
      tag: 'ATTRIBUTE_ERROR',
      error: appwriteException ?? errorMessage,
      stackTrace: stackTrace,
    );
  }

  /// Log schema mismatch between local and cloud
  void logSchemaMismatch({
    required String collectionName,
    required List<String> missingInCloud,
    required List<String> missingInLocal,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🔍 عدم تطابق المخطط');
    buffer.writeln('   الجدول: $collectionName');
    if (missingInCloud.isNotEmpty) {
      buffer.writeln('   مفقود في Cloud: ${missingInCloud.join(', ')}');
    }
    if (missingInLocal.isNotEmpty) {
      buffer.writeln('   مفقود محلياً: ${missingInLocal.join(', ')}');
    }

    _logger.log(
      buffer.toString(),
      level: LogLevel.warning,
      tag: 'SCHEMA_MISMATCH',
      error: 'Missing in cloud: ${missingInCloud.length}, Missing local: ${missingInLocal.length}',
      stackTrace: stackTrace,
    );
  }

  /// Log sync error with full context
  void logSyncError({
    required String collectionName,
    required String operation,
    required String errorMessage,
    String? localUuid,
    int? localId,
    int? serverId,
    dynamic appwriteException,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🔄 خطأ مزامنة');
    buffer.writeln('   الجدول: $collectionName');
    buffer.writeln('   العملية: $operation');
    if (localUuid != null) buffer.writeln('   Local UUID: $localUuid');
    if (localId != null) buffer.writeln('   Local ID: $localId');
    if (serverId != null) buffer.writeln('   Server ID: $serverId');
    buffer.write('   الخطأ: $errorMessage');

    _logger.log(
      buffer.toString(),
      level: LogLevel.error,
      tag: 'SYNC_ERROR',
      error: appwriteException ?? errorMessage,
      stackTrace: stackTrace,
    );
  }

  /// Log permission error
  void logPermissionError({
    required String collectionName,
    required String operation,
    required String errorMessage,
    String? documentId,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('🔒 خطأ في الصلاحيات');
    buffer.writeln('   الجدول: $collectionName');
    buffer.writeln('   العملية: $operation');
    if (documentId != null) buffer.writeln('   المستند: $documentId');
    buffer.write('   الخطأ: $errorMessage');

    _logger.log(
      buffer.toString(),
      level: LogLevel.warning,
      tag: 'PERMISSION_ERROR',
      error: errorMessage,
      stackTrace: stackTrace,
    );
  }

  /// Parse AppwriteException and log with details
  void parseAndLogAppwriteException({
    required AppwriteException e,
    required String collectionName,
    String? operation,
    String? documentId,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('⚠️ خطأ Appwrite');
    buffer.writeln('   الجدول: $collectionName');
    if (operation != null) buffer.writeln('   العملية: $operation');
    if (documentId != null) buffer.writeln('   المستند: $documentId');
    buffer.writeln('   الكود: ${e.code}');
    buffer.writeln('   النوع: ${e.type ?? 'غير معروف'}');
    buffer.write('   الرسالة: ${e.message}');

    final level = _getLevelFromCode(e.code);
    _logger.log(
      buffer.toString(),
      level: level,
      tag: 'APPWRITE_EXCEPTION',
      error: e,
      stackTrace: stackTrace,
    );
  }

  LogLevel _getLevelFromCode(dynamic code) {
    if (code == 401 || code == 403) return LogLevel.warning;
    if (code == 404) return LogLevel.info;
    if (code == 500 || code == 502 || code == 503) return LogLevel.critical;
    return LogLevel.error;
  }

  String _truncateData(Map<String, dynamic> data, {int maxLength = 200}) {
    final str = data.toString();
    if (str.length <= maxLength) return str;
    return '${str.substring(0, maxLength)}...';
  }
}
