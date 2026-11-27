// test/services/appwrite_xlsx_export_test.dart
//
// اختبارات خدمة تصدير قاعدة بيانات Appwrite إلى XLSX — بلا شبكة:
// حقن دالة سحب وهمية ثم توليد ملف حقيقي وقراءته والتحقق من محتواه.
import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_xlsx_export_service.dart';

models.Document _doc(String id, {Map<String, dynamic> data = const {}}) {
  return models.Document(
    $id: id,
    $sequence: 1,
    $collectionId: 'test_collection',
    $databaseId: 'test_db',
    $createdAt: '2026-09-14T00:00:00.000Z',
    $updatedAt: '2026-09-14T00:00:00.000Z',
    $permissions: const <String>[],
    data: data,
  );
}

String _cellText(Data? cell) {
  final v = cell?.value;
  if (v == null) {
    return '';
  }
  if (v is TextCellValue) {
    return v.value.text ?? '';
  }
  return v.toString();
}

num _cellNumber(Data? cell) {
  final v = cell?.value;
  if (v is IntCellValue) {
    return v.value;
  }
  if (v is DoubleCellValue) {
    return v.value;
  }
  fail('الخلية ليست رقمية: $v');
}

void main() {
  group('AppwriteXlsxExportService.buildTable', () {
    test('أعمدة النظام أولاً ثم اتحاد حقول البيانات بترتيب الثبات', () {
      final docs = [
        _doc(
          'a',
          data: {
            'name': 'غرفة 1',
            'price': 100,
            'meta': {'x': 1},
            'tags': ['a', 'b'],
          },
        ),
        _doc('b', data: {'name': 'غرفة 2', 'extra': true}),
      ];

      final table = AppwriteXlsxExportService.buildTable(docs);

      expect(table.columns, const [
        '\$id',
        '\$createdAt',
        '\$updatedAt',
        'name',
        'price',
        'meta',
        'tags',
        'extra',
      ]);
      expect(table.rows, hasLength(2));
      expect(table.rows[0][0], 'a');
      expect(table.rows[1][7], true);
    });

    test('convertValue يحوّل الأنواع بشكل صحيح', () {
      final dt = DateTime.parse('2026-09-14T10:30:00');
      expect(AppwriteXlsxExportService.convertValue(dt), '2026-09-14 10:30:00');
      expect(AppwriteXlsxExportService.convertValue({'x': 1}), '{"x":1}');
      expect(AppwriteXlsxExportService.convertValue(null), isNull);
      expect(AppwriteXlsxExportService.convertValue(42), 42);
      expect(AppwriteXlsxExportService.convertValue(1.5), 1.5);
      expect(AppwriteXlsxExportService.convertValue('نص'), 'نص');
    });

    test('جدول فارغ يعطي صفوفاً صفرية', () {
      final table = AppwriteXlsxExportService.buildTable(const []);
      expect(table.rows, isEmpty);
    });
  });

  group('AppwriteXlsxExportService.export', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('xlsx_export_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('ينتج ملف XLSX صالحاً بأوراق عربية RTL وورقة ملخص', () async {
      final fetchCalls = <String>[];
      final service = AppwriteXlsxExportService(
        fetcher: (collectionId) async {
          fetchCalls.add(collectionId);
          if (collectionId == 'rooms') {
            return [
              _doc('r1', data: {'number': 101, 'guest': 'أحمد'}),
            ];
          }
          if (collectionId == 'bookings') {
            return [
              _doc('b1', data: {'total': 1500.5}),
            ];
          }
          return const [];
        },
      );

      final progressLog = <XlsxExportProgress>[];
      final result = await service.export(
        targetPath: '${tempDir.path}/out.xlsx',
        onProgress: progressLog.add,
      );

      // سحب كل الجداول القابلة للتصدير مرة واحدة لكل منها
      expect(fetchCalls.length, kExportableCollections.length);
      expect(fetchCalls.toSet().length, kExportableCollections.length);

      expect(result.file.existsSync(), isTrue);
      expect(result.totalRecords, 2);
      expect(result.counts['الغرف'], 1);
      expect(result.counts['الحجوزات'], 1);
      expect(result.counts['الموظفون'], 0);
      expect(progressLog, isNotEmpty);

      final bytes = File('${tempDir.path}/out.xlsx').readAsBytesSync();
      final book = Excel.decodeBytes(bytes);

      expect(book.tables.keys, containsAll(['الغرف', 'الحجوزات', 'الملخص']));
      expect(book.tables.keys, isNot(contains('Sheet1')));

      // ورقة الغرف: RTL + رأس أعمدة + صف بيانات
      final rooms = book.tables['الغرف']!;
      expect(rooms.isRTL, isTrue);
      expect(_cellText(rooms.rows[0][0]), '\$id');
      expect(_cellText(rooms.rows[0][3]), 'number');
      expect(_cellText(rooms.rows[0][4]), 'guest');
      expect(_cellText(rooms.rows[1][0]), 'r1');
      expect(_cellNumber(rooms.rows[1][3]), 101);

      // ورقة جدول فارغ: رسالة «لا توجد سجلات»
      final employees = book.tables['الموظفون']!;
      expect(_cellText(employees.rows[0][0]), 'لا توجد سجلات');

      // ورقة الملخص: عنوان + رأس + صف إجمالي بعدد سجلين
      final summary = book.tables['الملخص']!;
      expect(
        _cellText(summary.rows[0][0]),
        'فندق مارينا — تصدير قاعدة بيانات Appwrite',
      );
      expect(_cellText(summary.rows[3][0]), 'الجدول');
      expect(_cellText(summary.rows.last[0]), 'الإجمالي');
      expect(_cellNumber(summary.rows.last[1]), 2);
    });
  });
}
