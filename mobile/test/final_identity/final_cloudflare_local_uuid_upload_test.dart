import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cloudflare upload ignores an existing local_uuid identity', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body)['sql'] as String);
      return http.Response(
        jsonEncode({'success': true, 'result': <dynamic>[]}),
        200,
      );
    });

    final service = CloudflareD1Service(
      const CloudflareD1Config(accountId: 'a', databaseId: 'd', apiToken: 't'),
      client: client,
    );

    final source = CloudflareD1SourceTable(
      name: 'employees',
      rowCount: 1,
      createSqlList: const [
        'CREATE TABLE employees ('
            '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
            '"local_uuid" TEXT NOT NULL UNIQUE, "name" TEXT NOT NULL)',
      ],
      readChunk: (limit, offset) async => [
        {'local_uuid': 'EMP-A', 'name': 'A'},
      ],
    );
    final result = await service.uploadData(tables: [source]);
    expect(result.errors, isEmpty);
    // ✅ عقد الهوية (من e1083c15): عبارات INSERT ترفع local_uuid فقط
    // بلا id المحلي. أوامر DDL (CREATE TABLE) تنقل مخطط الجدول المحلي
    // كما هو — وتعريف عمود id جزء مشروع من المخطط، لذلك نحصر
    // التحقق على عبارات INSERT وحدها دون أوامر إنشاء المخطط.
    final insertSql = requests
        .where((s) => s.toUpperCase().contains('INSERT INTO'))
        .join('\n');
    expect(insertSql, contains('INSERT INTO "employees"'));
    expect(insertSql, contains('ON CONFLICT DO NOTHING'));
    expect(insertSql, isNot(contains('INSERT OR REPLACE INTO "employees"')));
    expect(insertSql, isNot(contains('"id"')));
  });

  test(
    'Cloudflare upload with overwrite updates matching rows in place',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body)['sql'] as String);
        return http.Response(
          jsonEncode({'success': true, 'result': <dynamic>[]}),
          200,
        );
      });

      final service = CloudflareD1Service(
        const CloudflareD1Config(
          accountId: 'a',
          databaseId: 'd',
          apiToken: 't',
        ),
        client: client,
      );

      final source = CloudflareD1SourceTable(
        name: 'employees',
        rowCount: 1,
        createSqlList: const [
          'CREATE TABLE employees ('
              '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
              '"local_uuid" TEXT NOT NULL UNIQUE, "name" TEXT NOT NULL)',
        ],
        readChunk: (limit, offset) async => [
          {'local_uuid': 'EMP-A', 'name': 'A'},
        ],
      );

      // ✅ overwrite: التعارض على local_uuid يكتب فوق السجل القديم
      // في D1 بأحدث القيم بدلاً من تخطيه.
      final result = await service.uploadData(
        tables: [source],
        overwrite: true,
      );
      expect(result.errors, isEmpty);

      final insertSql = requests
          .where((s) => s.toUpperCase().contains('INSERT INTO'))
          .join('\n');
      expect(insertSql, contains('ON CONFLICT DO UPDATE'));
      expect(
        insertSql,
        contains('"local_uuid"=excluded."local_uuid"'),
        reason: 'SET يجب أن يشمل كل عمود مُرسل (باستثناء مفاتيح الهوية)',
      );
      expect(insertSql, contains('"name"=excluded."name"'));
      expect(insertSql, isNot(contains('"id"=excluded')));
      expect(insertSql, isNot(contains('ON CONFLICT DO NOTHING')));
    },
  );

  test(
    'Cloudflare overwrite also updates rows of tables that upload id',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add(jsonDecode(request.body)['sql'] as String);
        return http.Response(
          jsonEncode({'success': true, 'result': <dynamic>[]}),
          200,
        );
      });

      final service = CloudflareD1Service(
        const CloudflareD1Config(
          accountId: 'a',
          databaseId: 'd',
          apiToken: 't',
        ),
        client: client,
      );

      // جدول محلي/مساعد بلا local_uuid فريد: يُرفع مع عمود id نفسه،
      // والتعارض يقع عليه (PRIMARY KEY) — نفس السجل المرفوع مسبقاً.
      final source = CloudflareD1SourceTable(
        name: 'app_config',
        rowCount: 1,
        createSqlList: const [
          'CREATE TABLE app_config ('
              '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
              '"key" TEXT NOT NULL, "value" TEXT)',
        ],
        readChunk: (limit, offset) async => [
          {'id': 1, 'key': 'theme', 'value': 'dark'},
        ],
      );

      // ✅ overwrite: حتى الجداول التي ترفع id تُحدَّث فوق الصف القديم
      // المتطابق (نفس id) ببقية الأعمدة — id يبقى خارج SET.
      final result = await service.uploadData(
        tables: [source],
        overwrite: true,
      );
      expect(result.errors, isEmpty);

      final insertSql = requests
          .where((s) => s.toUpperCase().contains('INSERT INTO'))
          .join('\n');
      expect(insertSql, contains('INSERT INTO "app_config"'));
      expect(insertSql, contains('("id","key","value")'));
      expect(insertSql, contains('ON CONFLICT DO UPDATE'));
      expect(insertSql, contains('"key"=excluded."key"'));
      expect(insertSql, contains('"value"=excluded."value"'));
      expect(insertSql, isNot(contains('"id"=excluded')));
      expect(insertSql, isNot(contains('ON CONFLICT DO NOTHING')));
    },
  );
}
