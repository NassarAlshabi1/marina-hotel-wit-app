// lib/services/appwrite_xlsx_export_service.dart
// خدمة تصدير قاعدة بيانات Appwrite إلى ملف Excel (XLSX) على ذاكرة الهاتف.
//
// تسحب كل الجداول التجارية من Appwrite Cloud (قراءة فقط) وتُنشئ ملف XLSX
// بورقة عربية (RTL) لكل جدول + ورقة «الملخص» بعدد سجلات كل جدول.
//
// الاستخدام:
// ```dart
// final service = AppwriteXlsxExportService(
//   fetcher: AppwriteXlsxExportService.fetcherOf(appwriteService),
// );
// final result = await service.export(
//   targetPath: '/storage/emulated/0/Download/marina.xlsx',
//   onProgress: (p) => ...,
// );
// ```
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'appwrite_service.dart';

/// الجداول القابلة للتصدير: معرّف المجموعة على Appwrite → اسم الورقة بالعربية.
///
/// تستثني الجداول التقنية (devices وsync_logs) لأنها بيانات تشغيل مزامنة
/// وليست بيانات عمل — إضافتها مستقبلية عبر توسيع هذه الخريطة فقط.
const Map<String, String> kExportableCollections = {
  'rooms': 'الغرف',
  'bookings': 'الحجوزات',
  'booking_nights': 'ليالي الحجوزات',
  'payments': 'المدفوعات',
  'expenses': 'المصروفات',
  'employees': 'الموظفون',
  'salary_withdrawals': 'سحوبات الرواتب',
  'salary_cycles': 'دورات الرواتب',
  'salary_payments': 'دفعات الرواتب',
  'salary_carry_over_logs': 'سجلات ترحيل الرواتب',
  'debts': 'الديون',
  'guest_infos': 'معلومات النزلاء',
  'blacklist': 'القائمة السوداء',
  'booking_notes': 'ملاحظات الحجوزات',
  'shift_notes': 'ملاحظات الورديات',
  'cash_transactions': 'المعاملات النقدية',
  'price_adjustments': 'تعديلات الأسعار',
  'booking_price_adjustments': 'تعديلات أسعار الحجوزات',
  'payment_voids': 'إلغاءات الدفع',
  'audit_logs': 'سجلات التدقيق',
  'app_settings': 'إعدادات التطبيق',
  'app_users': 'مستخدمو التطبيق',
  'inventory_items': 'أصناف المخزون',
  'inventory_transactions': 'حركات المخزون',
};

/// دالة سحب كل مستندات مجموعة واحدة — نقطة الحقن للاختبارات.
typedef CollectionFetcher =
    Future<List<models.Document>> Function(String collectionId);

/// حالة تقدم التصدير: كم جدولاً اكتمل من الإجمالي، وما اسم الجدول الجاري.
class XlsxExportProgress {
  const XlsxExportProgress(this.done, this.total, this.currentLabel);

  /// عدد الجداول المكتملة.
  final int done;

  /// إجمالي الجداول المطلوبة.
  final int total;

  /// وسم الجدول الجاري سحبه.
  final String currentLabel;

  /// نسبة الإنجاز 0..1 أو null إذا كان الإجمالي صفراً.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

/// نتيجة التصدير: الملف الناتج + عدد السجلات لكل ورقة.
class XlsxExportResult {
  const XlsxExportResult({
    required this.file,
    required this.counts,
    required this.totalRecords,
  });

  /// ملف XLSX المكتوب فعلياً على القرص.
  final File file;

  /// اسم الورقة بالعربية → عدد السجلات المصدرية.
  final Map<String, int> counts;

  /// إجمالي السجلات في كل الجداول.
  final int totalRecords;
}

/// جدول مُسطَّح جاهز للكتابة في ورقة Excel.
class ExportTable {
  const ExportTable({required this.columns, required this.rows});

  /// أسماء الأعمدة (ترتيب مستقر).
  final List<String> columns;

  /// صفوف البيانات بنفس ترتيب الأعمدة، والقيمة null تعني خلية فارغة.
  final List<List<Object?>> rows;
}

/// خدمة تصدير قاعدة بيانات Appwrite إلى XLSX — قراءة فقط من السحابة.
class AppwriteXlsxExportService {
  /// إنشاء الخدمة بدالة سحب مخصصة (يسمح بحقن بديل في الاختبارات).
  AppwriteXlsxExportService({required CollectionFetcher fetcher})
    : _fetcher = fetcher;

  final CollectionFetcher _fetcher;

  /// غلاف جاهز يستخدم [AppwriteService.listAllDocuments] بلا ذاكرة مؤقتة
  /// حتى تكون النسخة المصدرية طازجة من السحابة.
  static CollectionFetcher fetcherOf(AppwriteService service) =>
      (collectionId) =>
          service.listAllDocuments(collectionId: collectionId, useCache: false);

  /// تصدير كل الجداول القابلة للتصدير إلى ملف XLSX في [targetPath].
  ///
  /// يرمي الاستثناء عند فشل أي سحب أو كتابة — والمستدعي يقرر عرض الخطأ.
  Future<XlsxExportResult> export({
    required String targetPath,
    void Function(XlsxExportProgress progress)? onProgress,
  }) async {
    final total = kExportableCollections.length;
    final counts = <String, int>{};
    final excel = Excel.createExcel();
    var done = 0;
    var totalRecords = 0;

    for (final entry in kExportableCollections.entries) {
      onProgress?.call(XlsxExportProgress(done, total, 'سحب: ${entry.value}'));
      final docs = await _fetcher(entry.key);
      _addSheet(excel, entry.value, buildTable(docs));
      counts[entry.value] = docs.length;
      totalRecords += docs.length;
      done++;
    }

    onProgress?.call(XlsxExportProgress(done, total, 'إنشاء ورقة الملخص...'));
    _addSummarySheet(excel, counts, totalRecords);

    // حذف الورقة الافتراضية التي ينشئها excel package.
    excel.delete('Sheet1');

    final bytes = excel.save();
    if (bytes == null) {
      throw const FormatException('فشل توليد ملف Excel (save أعاد null)');
    }
    // excel 4.0.6 لا يكتب خاصية isRTL في XML الملف المحفوظ (تم التحقق
    // تجريبياً) — فنحقنها يدوياً في كل أوراق العمل قبل الكتابة.
    final fixedBytes = enforceRightToLeft(bytes);
    final file = File(targetPath);
    await file.writeAsBytes(fixedBytes, flush: true);

    onProgress?.call(
      XlsxExportProgress(total, total, 'تم الحفظ: ${file.path}'),
    );
    return XlsxExportResult(
      file: file,
      counts: counts,
      totalRecords: totalRecords,
    );
  }

  /// يحوّل مستندات Appwrite إلى جدول مسطَّح: أعمدة النظام أولاً
  /// ($id، $createdAt، $updatedAt) ثم اتحاد حقول البيانات بترتيب الثبات.
  static ExportTable buildTable(List<models.Document> docs) {
    final dataColumns = <String>[];
    final seen = <String>{};
    for (final doc in docs) {
      for (final key in doc.data.keys) {
        if (seen.add(key)) {
          dataColumns.add(key);
        }
      }
    }
    final columns = <String>[
      '\$id',
      '\$createdAt',
      '\$updatedAt',
      ...dataColumns,
    ];
    final rows = docs
        .map(
          (doc) => columns
              .map(
                (c) => switch (c) {
                  '\$id' => doc.$id,
                  '\$createdAt' => doc.$createdAt,
                  '\$updatedAt' => doc.$updatedAt,
                  _ => convertValue(doc.data[c]),
                },
              )
              .toList(),
        )
        .toList();
    return ExportTable(columns: columns, rows: rows);
  }

  /// تحويل قيمة خام من Appwrite إلى قيمة صالحة لخلية Excel:
  /// أرقام/قيم منطقية كما هي، خرائط وقوائم JSON، والتواريخ نصاً منسقاً.
  static Object? convertValue(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd HH:mm:ss').format(value);
    }
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    if (value is num || value is bool || value is String) {
      return value;
    }
    return value.toString();
  }

  void _addSheet(Excel excel, String arabicName, ExportTable table) {
    final sheet = excel[_sanitizeSheetName(arabicName)];
    sheet.isRTL = true;

    if (table.rows.isEmpty) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        ..value = TextCellValue('لا توجد سجلات')
        ..cellStyle = CellStyle(
          fontSize: 11,
          fontColorHex: ExcelColor.fromHexString('FF666666'),
          horizontalAlign: HorizontalAlign.Center,
        );
      return;
    }

    final headerBg = ExcelColor.fromHexString('FF1B3A5C');
    for (var c = 0; c < table.columns.length; c++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
        ..value = TextCellValue(table.columns[c])
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
          backgroundColorHex: headerBg,
          horizontalAlign: HorizontalAlign.Center,
        );
    }

    for (var r = 0; r < table.rows.length; r++) {
      for (var c = 0; c < table.columns.length; c++) {
        final v = table.rows[r][c];
        if (v == null) {
          continue;
        }
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
        );
        cell.value = switch (v) {
          final int x => IntCellValue(x),
          final double x => DoubleCellValue(x),
          final bool x => BoolCellValue(x),
          final String x => TextCellValue(x),
          _ => TextCellValue(v.toString()),
        };
      }
    }
  }

  void _addSummarySheet(Excel excel, Map<String, int> counts, int total) {
    final sheet = excel['الملخص'];
    sheet.isRTL = true;

    final exportedAt = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    sheet.cell(CellIndex.indexByString('A1'))
      ..value = TextCellValue('فندق مارينا — تصدير قاعدة بيانات Appwrite')
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        horizontalAlign: HorizontalAlign.Center,
      );
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('C1'));

    sheet.cell(CellIndex.indexByString('A2'))
      ..value = TextCellValue('تاريخ التصدير: $exportedAt')
      ..cellStyle = CellStyle(
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('FF666666'),
      );

    final headerBg = ExcelColor.fromHexString('FF1B3A5C');
    final headers = ['الجدول', 'عدد السجلات'];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3))
        ..value = TextCellValue(headers[i])
        ..cellStyle = CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
          backgroundColorHex: headerBg,
          horizontalAlign: HorizontalAlign.Center,
        );
    }

    var rowIndex = 4;
    counts.forEach((name, count) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
        ..value = TextCellValue(name)
        ..cellStyle = CellStyle(fontSize: 10);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
        ..value = IntCellValue(count)
        ..cellStyle = CellStyle(fontSize: 10);
      rowIndex++;
    });

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
      ..value = TextCellValue('الإجمالي')
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        backgroundColorHex: ExcelColor.fromHexString('FFF0F0F0'),
      );
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
      ..value = IntCellValue(total)
      ..cellStyle = CellStyle(
        bold: true,
        fontSize: 11,
        fontColorHex: ExcelColor.fromHexString('FFB46B00'),
        backgroundColorHex: ExcelColor.fromHexString('FFF0F0F0'),
      );
  }

  /// يضمن أن كل أوراق العمل في ملف XLSX تُفتح من اليمين لليسار (RTL).
  ///
  /// excel 4.0.6 لا يُضمّن سمة `rightToLeft="1"` في XML أوراق العمل المحفوظة
  /// حتى لو ضُبطت `sheet.isRTL = true` — لذا نفك ضغط الملف ونحقن السمة في
  /// عنصر `<sheetView>` لكل ورقة ثم نعيد ضغطه. تصلح هذه الدالة أي ملف XLSX
  /// ناتج عن الحزمة (قابلة لإعادة الاستخدام من ExportService أيضاً).
  static List<int> enforceRightToLeft(List<int> xlsxBytes) {
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final patched = Archive();
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      var content = List<int>.from(file.content as List<int>);
      final isWorksheetXml =
          file.name.startsWith('xl/worksheets/sheet') &&
          file.name.endsWith('.xml');
      if (isWorksheetXml && !utf8.decode(content).contains('rightToLeft=')) {
        final xml = utf8
            .decode(content)
            .replaceAll('<sheetView>', '<sheetView rightToLeft="1">')
            .replaceAll('<sheetView ', '<sheetView rightToLeft="1" ');
        content = utf8.encode(xml);
      }
      patched.addFile(ArchiveFile(file.name, content.length, content));
    }
    return ZipEncoder().encode(patched)!;
  }

  String _sanitizeSheetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\[\]\:\*\?\/\\]'), ' ').trim();
    if (cleaned.length <= 31) {
      return cleaned;
    }
    return cleaned.substring(0, 31);
  }
}
