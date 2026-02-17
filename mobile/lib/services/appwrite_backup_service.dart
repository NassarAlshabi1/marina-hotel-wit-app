import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';

class AppwriteBackupResult {
  final File file;
  final Map<String, int> counts;
  final int totalRecords;
  final DateTime timestamp;

  const AppwriteBackupResult({
    required this.file,
    required this.counts,
    required this.totalRecords,
    required this.timestamp,
  });
}

class AppwriteBackupService {
  AppwriteBackupService({AppwriteService? appwriteService})
      : _appwriteService = appwriteService ?? AppwriteService();

  final AppwriteService _appwriteService;

  Future<AppwriteBackupResult> exportBackup({String? deviceId}) async {
    await _appwriteService.initialize();

    final timestamp = DateTime.now().toUtc();
    final collections = <String, dynamic>{};
    final counts = <String, int>{};
    final collectionIds = <String>[
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
      AppwriteConfig.devicesCollectionId,
      AppwriteConfig.syncLogsCollectionId,
    ];

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
        'projectId': AppwriteConfig.projectId,
        'databaseId': AppwriteConfig.databaseId,
        'deviceId': deviceId,
        'totalRecords': totalRecords,
        'counts': counts,
      },
      'collections': collections,
    };

    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/appwrite_backups');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final fileName =
        'appwrite_backup_${DateFormat('yyyyMMdd_HHmmss').format(timestamp)}.json';
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
