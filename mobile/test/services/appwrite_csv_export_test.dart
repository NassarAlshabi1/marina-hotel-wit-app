import 'dart:convert';
import 'dart:io';

import 'package:appwrite/models.dart' as models;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_csv_export_service.dart';
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

void main() {
  group('AppwriteCsvExportService.encodeTable', () {
    test(
      'escapes commas, quotes, and newlines while preserving Arabic text',
      () {
        final csv = AppwriteCsvExportService.encodeTable(
          const ExportTable(
            columns: ['name', 'notes'],
            rows: [
              ['أحمد, "علي"', 'سطر 1\nسطر 2'],
            ],
          ),
        );

        expect(csv, '"name","notes"\r\n"أحمد, ""علي""","سطر 1\nسطر 2"\r\n');
      },
    );

    test('neutralizes formula-like text when opened in spreadsheet apps', () {
      final csv = AppwriteCsvExportService.encodeTable(
        const ExportTable(
          columns: ['note'],
          rows: [
            ['=1+1'],
          ],
        ),
      );

      expect(csv, '"note"\r\n"\'=1+1"\r\n');
    });
  });

  group('AppwriteCsvExportService.exportCollection', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('csv_export_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exports only the selected table with a UTF-8 BOM', () async {
      final fetchCalls = <String>[];
      final service = AppwriteCsvExportService(
        fetcher: (collectionId) async {
          fetchCalls.add(collectionId);
          return [
            _doc('b1', data: {'guestName': 'أحمد', 'amount': 150.5}),
          ];
        },
      );

      final result = await service.exportCollection(
        collectionId: 'bookings',
        targetPath: '${tempDir.path}/bookings.csv',
      );
      final bytes = await result.file.readAsBytes();
      final contents = utf8.decode(bytes);

      expect(fetchCalls, ['bookings']);
      expect(result.collectionLabel, 'الحجوزات');
      expect(result.recordCount, 1);
      expect(result.file.existsSync(), isTrue);
      // ✅ التحقق من UTF-8 BOM على مستوى البايتات (EF BB BF):
      // utf8.decode في Dart الحديثة تزيل الـ BOM أثناء فك الترميز،
      // لذا لا يمكن التحقق منه من النص المفكوك.
      expect(bytes.take(3).toList(), const [0xEF, 0xBB, 0xBF]);
      expect(contents, contains('guestName'));
      expect(contents, contains('أحمد'));
      expect(contents, contains('150.5'));
    });

    test('rejects collections outside the user-facing export list', () async {
      var fetchCalled = false;
      final service = AppwriteCsvExportService(
        fetcher: (_) async {
          fetchCalled = true;
          return const [];
        },
      );

      await expectLater(
        service.exportCollection(
          collectionId: 'devices',
          targetPath: '${tempDir.path}/devices.csv',
        ),
        throwsArgumentError,
      );
      expect(fetchCalled, isFalse);
    });
  });
}
