import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';

class AppwriteBackupService {
  AppwriteBackupService({AppwriteService? appwriteService})
      : _appwriteService = appwriteService ?? AppwriteService();

  final AppwriteService _appwriteService;

  Future<File> exportBackup({String? deviceId}) async {
    await _appwriteService.initialize();

    final timestamp = DateTime.now().toUtc();
    final collections = <String, dynamic>{};
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
      collections[id] = docs
          .map((doc) => {
                r'$id': doc.$id,
                ...doc.data,
              })
          .toList();
    }

    final payload = {
      'metadata': {
        'timestamp': timestamp.toIso8601String(),
        'projectId': AppwriteConfig.projectId,
        'databaseId': AppwriteConfig.databaseId,
        'deviceId': deviceId,
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
    return file;
  }
}
