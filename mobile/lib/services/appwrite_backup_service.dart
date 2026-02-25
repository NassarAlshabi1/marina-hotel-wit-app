import 'dart:convert';
import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'appwrite_config.dart';
import 'appwrite_config_manager.dart';
import 'appwrite_service.dart';

class AppwriteBackupResult {
  const AppwriteBackupResult({
    required this.file,
    required this.counts,
    required this.totalRecords,
    required this.timestamp,
  });
  final File file;
  final Map<String, int> counts;
  final int totalRecords;
  final DateTime timestamp;
}

class AppwriteBackupService {
  AppwriteBackupService({AppwriteService? appwriteService})
      : _appwriteService = appwriteService ?? AppwriteService();

  final AppwriteService _appwriteService;

  static const List<String> _defaultCollectionIds = [
    AppwriteConfig.roomsCollectionId,
    AppwriteConfig.bookingsCollectionId,
    AppwriteConfig.bookingNotesCollectionId,
    AppwriteConfig.bookingNightsCollectionId,
    AppwriteConfig.paymentsCollectionId,
    AppwriteConfig.expensesCollectionId,
    AppwriteConfig.cashTransactionsCollectionId,
    AppwriteConfig.debtsCollectionId,
    AppwriteConfig.employeesCollectionId,
    AppwriteConfig.salaryCyclesCollectionId,
    AppwriteConfig.salaryPaymentsCollectionId,
    AppwriteConfig.hotelDayLedgerCollectionId,
    AppwriteConfig.shiftNotesCollectionId,
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
    AppwriteConfig.devicesCollectionId,
    AppwriteConfig.syncLogsCollectionId,
  ];

  Future<List<models.Collection>> _listAllCollections() async {
    final allCollections = <models.Collection>[];
    const limit = AppwriteConfig.maxPageSize;
    var offset = 0;
    var usedFallback = false;

    while (true) {
      try {
        final result =
            await _appwriteService.databases.listCollections(
          databaseId: AppwriteConfigManager.databaseId,
          queries: [Query.limit(limit), Query.offset(offset)],
        );
        final batch = result.collections;
        if (batch.isEmpty) {
          break;
        }
        allCollections.addAll(batch);
        if (batch.length < limit) {
          break;
        }
        offset += limit;
      } catch (_) {
        usedFallback = true;
        break;
      }
    }

    if (allCollections.isEmpty && usedFallback) {
      for (final id in _defaultCollectionIds) {
        try {
          final collection =
              await _appwriteService.databases.getCollection(
            databaseId: AppwriteConfigManager.databaseId,
            collectionId: id,
          );
          allCollections.add(collection);
        } catch (_) { /* Log error or handle gracefully */ }
      }
    }

    return allCollections;
  }

  Map<String, dynamic> _serializeCollection(models.Collection collection) {
    return collection.toMap();
  }

  Future<AppwriteBackupResult> exportBackup({
    String? deviceId,
    bool includeSchema = false,
  }) async {
    await _appwriteService.initialize();

    final timestamp = DateTime.now().toUtc();
    final collections = <String, dynamic>{};
    final counts = <String, int>{};
    final schemaCollections = <Map<String, dynamic>>[];
    final collectionIds = <String>[];

    if (includeSchema) {
      final cloudCollections = await _listAllCollections();
      for (final collection in cloudCollections) {
          final id = collection.$id;
          collectionIds.add(id);
        schemaCollections.add(_serializeCollection(collection));
      }
    } else {
      collectionIds.addAll(_defaultCollectionIds);
    }

    for (final id in collectionIds) {
      final docs = await _appwriteService.listAllDocuments(
        collectionId: id,
        useCache: false,
      );
      collections[id] =
          docs.map((doc) => {r'$id': doc.$id, ...doc.data}).toList();
      counts[id] = docs.length;
    }

    final totalRecords = counts.values.fold<int>(0, (sum, v) => sum + v);

    final payload = {
      'metadata': {
        'timestamp': timestamp.toIso8601String(),
        'projectId': AppwriteConfigManager.projectId,
        'databaseId': AppwriteConfigManager.databaseId,
        'deviceId': deviceId,
        'totalRecords': totalRecords,
        'counts': counts,
        'includesSchema': includeSchema,
      },
      if (includeSchema)
        'schema': {
          'collections': schemaCollections,
        },
      'collections': collections,
    };

    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/appwrite_backups');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final prefix = includeSchema ? 'appwrite_full_backup' : 'appwrite_backup';
    final fileName =
        '${prefix}_${DateFormat('yyyyMMdd_HHmmss').format(timestamp)}.json';
    final file = File('${targetDir.path}/$fileName');
    await file.writeAsString(jsonEncode(payload));

    return AppwriteBackupResult(
      file: file,
      counts: counts,
      totalRecords: totalRecords,
      timestamp: timestamp,
    );
  }
}
