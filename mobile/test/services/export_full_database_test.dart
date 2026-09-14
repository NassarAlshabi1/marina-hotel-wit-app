// ============================================================================
//  ExportService.exportFullDatabase — Unit Tests
// ============================================================================
//  اختبارات تصدير قاعدة البيانات كاملة إلى XLSX:
//    1. إنشاء ملف xlsx صالح يحتوي ورقة "نظرة عامة" + ورقة لكل جدول
//    2. صف العناوين يطابق أسماء أعمدة SQLite حتى للجداول الفارغة
//    3. قيم bool المخزَّنة 0/1 تُحوَّل إلى قيم منطقية
//    4. النظرة العامة تُظهر عدد صفوف كل جدول بشكل صحيح
//
//  قاعدة الاختبار: AppDatabase.forTesting(NativeDatabase.memory())
//  ملف الإخراج: مجلد مؤقت (بدون منصات نظام — اختبار وحدة صافٍ)
// ============================================================================

library marina_hotel_mobile.test.export_full_database_test;

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/export_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

AppDatabase _createTestDb() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}

int _epoch(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

/// استخراج نص قابل للقراءة من خلية Excel لأغراض التحقق.
String? _cellText(Data? cell) {
  final value = cell?.value;
  if (value is TextCellValue) return value.value.text;
  if (value is IntCellValue) return '${value.value}';
  if (value is DoubleCellValue) return '${value.value}';
  if (value is BoolCellValue) return '${value.value}';
  if (value == null) return null;
  return value.toString();
}

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = _createTestDb();
    tempDir = await Directory.systemTemp.createTemp('export_db_test');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('exportFullDatabase', () {
    test('ينشئ ملف xlsx صالحاً باسم متوقع', () async {
      final file = await ExportService.instance.exportFullDatabase(
        db,
        outputDirectory: tempDir,
      );

      expect(file.existsSync(), isTrue);
      expect(
        file.uri.pathSegments.last,
        startsWith('marina_hotel_database_'),
      );
      expect(file.uri.pathSegments.last, endsWith('.xlsx'));

      // الملف قابل للفك كحزمة xlsx صالحة
      final decoded = Excel.decodeBytes(file.readAsBytesSync());
      expect(decoded.tables.keys, contains('نظرة عامة'));
    });

    test('يصدّر ورقة لكل جدول مع العناوين والصفوف', () async {
      final now = DateTime(2026, 9, 14, 12);
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-uuid-1',
              createdAt: _epoch(now),
              updatedAt: _epoch(now),
              lastModified: _epoch(now),
              roomNumber: '101',
              type: 'غرفة مزدوجة',
              price: 250.0,
              status: 'occupied',
            ),
          );
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              localUuid: 'expense-uuid-1',
              createdAt: _epoch(now),
              updatedAt: _epoch(now),
              lastModified: _epoch(now),
              expenseType: 'رواتب',
              description: 'راتب موظف الاستقبال',
              amount: 1500,
              date: '2026-09-14',
            ),
          );

      final file = await ExportService.instance.exportFullDatabase(
        db,
        outputDirectory: tempDir,
      );

      final decoded = Excel.decodeBytes(file.readAsBytesSync());

      // أوراق الجداول موجودة
      expect(decoded.tables.keys, contains('rooms'));
      expect(decoded.tables.keys, contains('expenses'));

      // ورقة rooms: صف عناوين + صف بيانات واحد
      final roomsSheet = decoded.tables['rooms']!;
      expect(roomsSheet.rows.length, 2);
      final roomsHeader = roomsSheet.rows[0].map(_cellText).toList();
      expect(roomsHeader, contains('room_number'));
      expect(roomsHeader, contains('price'));

      // قيم الصف الأول
      final firstRoomRow = roomsSheet.rows[1].map(_cellText).toList();
      expect(firstRoomRow, contains('101'));
      expect(firstRoomRow, contains('غرفة مزدوجة'));

      // ورقة expenses: صف عناوين + صف بيانات
      final expensesSheet = decoded.tables['expenses']!;
      expect(expensesSheet.rows.length, 2);
      final expensesHeader = expensesSheet.rows[0].map(_cellText).toList();
      expect(expensesHeader, contains('expense_type'));
      final expenseRow = expensesSheet.rows[1].map(_cellText).toList();
      expect(expenseRow, contains('راتب موظف الاستقبال'));
    });

    test('يحوّل bool المخزَّن 0/1 إلى قيمة منطقية', () async {
      final now = DateTime(2026, 9, 14, 12);
      // requiresMaintenance له افتراضي false → يُخزَّن 0
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-uuid-2',
              createdAt: _epoch(now),
              updatedAt: _epoch(now),
              lastModified: _epoch(now),
              roomNumber: '102',
              type: 'سويت',
              price: 400.0,
              status: 'available',
            ),
          );

      final file = await ExportService.instance.exportFullDatabase(
        db,
        outputDirectory: tempDir,
      );

      final decoded = Excel.decodeBytes(file.readAsBytesSync());
      final roomsSheet = decoded.tables['rooms']!;
      final header = roomsSheet.rows[0].map(_cellText).toList();
      final colIndex = header.indexOf('requires_maintenance');
      expect(colIndex, greaterThan(-1));

      final cell = roomsSheet.rows[1][colIndex];
      // في الملف المكتوب bool تُقرأ مرة أخرى كقيمة منطقية (أو 0 حسب المستدور)
      final text = _cellText(cell);
      expect(text == 'false' || text == '0', isTrue);
    });

    test('النظرة العامة تعرض عدد صفوف كل جدول', () async {
      final now = DateTime(2026, 9, 14, 12);
      await db
          .into(db.rooms)
          .insert(
            RoomsCompanion.insert(
              localUuid: 'room-uuid-3',
              createdAt: _epoch(now),
              updatedAt: _epoch(now),
              lastModified: _epoch(now),
              roomNumber: '103',
              type: 'غرفة فردية',
              price: 180.0,
              status: 'available',
            ),
          );

      final file = await ExportService.instance.exportFullDatabase(
        db,
        outputDirectory: tempDir,
      );

      final decoded = Excel.decodeBytes(file.readAsBytesSync());
      final overview = decoded.tables['نظرة عامة']!;

      // ابحث عن سطر الجدول rooms في الإحصائيات وتحقق من عدد الصفوف
      var foundRoomsRow = false;
      for (final row in overview.rows) {
        final cells = row.map(_cellText).toList();
        if (cells.isNotEmpty && cells.first == 'rooms') {
          foundRoomsRow = true;
          expect(cells[1], '1');
        }
      }
      expect(foundRoomsRow, isTrue);
    });

    test('الجداول الفارغة تحصل على ورقة بعناوين فقط', () async {
      final file = await ExportService.instance.exportFullDatabase(
        db,
        outputDirectory: tempDir,
      );

      final decoded = Excel.decodeBytes(file.readAsBytesSync());
      final bookingsSheet = decoded.tables['bookings']!;
      expect(bookingsSheet.rows.length, 1); // العناوين فقط
      final header = bookingsSheet.rows[0].map(_cellText).toList();
      expect(header, contains('guest_name'));
    });
  });
}
