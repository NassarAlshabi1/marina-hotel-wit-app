import 'dart:convert';
import 'dart:io';

import 'package:appwrite/models.dart' as models;

import 'appwrite_service.dart';
import 'appwrite_xlsx_export_service.dart';

/// نتيجة تصدير جدول واحد من Appwrite إلى CSV.
class CsvExportResult {
  const CsvExportResult({
    required this.file,
    required this.collectionId,
    required this.collectionLabel,
    required this.recordCount,
  });

  final File file;
  final String collectionId;
  final String collectionLabel;
  final int recordCount;
}

/// تصدير مجموعة واحدة يحددها المستخدم من Appwrite Cloud إلى ملف CSV.
/// القراءة من السحابة فقط؛ لا تُنشأ أو تُعدّل أي بيانات عن بُعد.
class AppwriteCsvExportService {
  AppwriteCsvExportService({required CollectionFetcher fetcher})
    : _fetcher = fetcher;

  final CollectionFetcher _fetcher;

  static CollectionFetcher fetcherOf(AppwriteService service) =>
      (collectionId) =>
          service.listAllDocuments(collectionId: collectionId, useCache: false);

  Future<CsvExportResult> exportCollection({
    required String collectionId,
    required String targetPath,
  }) async {
    final label = kExportableCollections[collectionId];
    if (label == null) {
      throw ArgumentError.value(
        collectionId,
        'collectionId',
        'المجموعة غير متاحة للتصدير',
      );
    }

    final List<models.Document> documents = await _fetcher(collectionId);
    final table = AppwriteXlsxExportService.buildTable(documents);
    final contents = encodeTable(table);
    final file = File(targetPath);
    await file.writeAsBytes(utf8.encode('\uFEFF$contents'), flush: true);

    return CsvExportResult(
      file: file,
      collectionId: collectionId,
      collectionLabel: label,
      recordCount: documents.length,
    );
  }

  /// ينتج CSV قياسيًا بفواصل وأسطر CRLF، مع اقتباس كل خلية وهروب علامات
  /// الاقتباس. تُسلسَل الخرائط والقوائم إلى JSON عبر buildTable.
  static String encodeTable(ExportTable table) {
    final output = StringBuffer();
    void writeRow(List<Object?> row) {
      output
        ..write(row.map(_encodeCell).join(','))
        ..write('\r\n');
    }

    writeRow(table.columns);
    for (final row in table.rows) {
      writeRow(row);
    }
    return output.toString();
  }

  static String _encodeCell(Object? value) {
    var text = value?.toString() ?? '';
    // حماية عند فتح CSV في Excel من تفسير مدخلات المستخدم كصيغ.
    if (value is String && RegExp(r'^[\t\r\n ]*[=+\-@]').hasMatch(text)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
