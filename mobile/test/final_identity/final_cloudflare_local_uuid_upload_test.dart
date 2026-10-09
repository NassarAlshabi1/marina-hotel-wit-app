import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Cloudflare upload uses local_uuid conflict identity', () async {
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
      name: 'employees', rowCount: 1,
      readChunk: (limit, offset) async => [
        {'local_uuid': 'EMP-A', 'name': 'A'},
      ],
    );
    final result = await service.uploadData(tables: [source]);
    expect(result.errors, isEmpty);
    final sql = requests.join('\n');
    expect(sql, contains('ON CONFLICT("local_uuid") DO UPDATE'));
    expect(sql, isNot(contains('INSERT OR REPLACE INTO "employees"')));
  });
}
