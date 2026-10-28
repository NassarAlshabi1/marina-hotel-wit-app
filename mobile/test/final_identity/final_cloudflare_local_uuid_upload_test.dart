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
      return http.Response(jsonEncode({'success': true, 'result': []}), 200);
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
}
