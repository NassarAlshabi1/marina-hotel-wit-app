import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_pull_service.dart';

void main() {
  group('Full sync tombstone filter', () {
    test(
      'excludes documents carrying deletedAt at the Appwrite query level',
      () {
        final queries = SyncPullService.buildFullSyncQueries();

        expect(queries, hasLength(1));
        expect(
          jsonDecode(queries.single),
          equals(<String, dynamic>{
            'method': 'or',
            'values': <Map<String, dynamic>>[
              <String, dynamic>{'method': 'isNull', 'attribute': 'deletedAt'},
              <String, dynamic>{
                'method': 'equal',
                'attribute': 'deletedAt',
                'values': <int>[0],
              },
            ],
          }),
        );
      },
    );
  });
}
