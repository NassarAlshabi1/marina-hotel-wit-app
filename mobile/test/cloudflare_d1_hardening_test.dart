import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_d1_service.dart';
import 'package:marina_hotel_mobile/services/local_backup_service.dart';

class _RecordingClient extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  final List<String> bodies = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (request is http.Request) bodies.add(request.body);

    final path = request.url.path;
    Object result;
    if (path.endsWith('/tokens/verify')) {
      result = <String, Object>{'status': 'active'};
    } else if (request.method == 'GET' && path.endsWith('/d1/database')) {
      result = <String, Object>{
        'results': <Object>[
          <String, Object>{
            'uuid': 'database',
            'name': 'marina',
            'file_size': 1,
          },
        ],
      };
    } else {
      result = <Object>[
        <String, Object>{
          'results': <Object>[
            <String, Object>{'ok': 1},
          ],
        },
      ];
    }
    final bytes = utf8.encode(jsonEncode(<String, Object>{
      'success': true,
      'result': result,
    }));
    return http.StreamedResponse(Stream.value(bytes), 200);
  }
}

void main() {
  const config = CloudflareD1Config(
    accountId: 'account',
    databaseId: 'database',
    apiToken: 'token',
  );

  test('direct upload fails before reading rows or making HTTP requests', () {
    final client = _RecordingClient();
    final service = CloudflareD1Service(config, client: client);
    var reads = 0;
    final source = CloudflareD1SourceTable(
      name: 'expenses',
      rowCount: 1,
      readChunk: (limit, offset) async {
        reads++;
        return <Map<String, Object?>>[
          <String, Object?>{'id': 1},
        ];
      },
    );

    expect(
      () => service.uploadData(tables: <CloudflareD1SourceTable>[source]),
      throwsUnsupportedError,
    );
    expect(reads, 0);
    expect(client.requests, isEmpty);
  });

  test('raw SQLite restore is rejected before opening the file', () async {
    await expectLater(
      LocalBackupService().restoreFromLocalBackup('/missing/backup.db'),
      throwsUnsupportedError,
    );
  });

  test('probe is read-only and does not claim DML or DDL permission', () async {
    final client = _RecordingClient();
    final result = await CloudflareD1Service(config, client: client).probe();

    expect(result.databaseReachable, isTrue);
    expect(result.dmlAllowed, isFalse);
    expect(result.ddlAllowed, isFalse);
    final sqlBodies = client.bodies.join('\n').toUpperCase();
    expect(sqlBodies, contains('SELECT 1 AS OK'));
    expect(sqlBodies, isNot(contains('INSERT')));
    expect(sqlBodies, isNot(contains('CREATE TABLE')));
    expect(sqlBodies, isNot(contains('DROP TABLE')));
  });
}
