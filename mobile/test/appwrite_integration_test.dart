// ✅ Tag: integration — يُستثنى عبر --exclude-tags integration في CI
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:marina_hotel_mobile/services/appwrite_config.dart';

const String devKey = String.fromEnvironment(
  'APPWRITE_DEV_KEY',
  defaultValue: '',
);

void main() {
  final bool hasDevKey = devKey.isNotEmpty;
  final String skipReason =
      'APPWRITE_DEV_KEY not provided; skipping integration test.';

  test(
    'Appwrite integration: listDocuments with devKey',
    () async {
      final client = Client()
        ..setEndpoint(AppwriteConfig.endpoint)
        ..setProject(AppwriteConfig.projectId);

      if (hasDevKey) {
        client.setDevKey(devKey);
      }

      final db = Databases(client);

      final res = await db.listDocuments(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: ['limit(1)'],
      );

      // Just ensure we got a valid response structure
      expect(res.documents, isA<List<models.Document>>());
    },
    skip: hasDevKey ? false : skipReason,
  );
}
