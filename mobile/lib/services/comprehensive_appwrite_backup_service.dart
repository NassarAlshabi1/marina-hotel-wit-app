// ignore_for_file: unused_import

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:intl/intl.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';
import 'local_db.dart';
import 'appwrite_logger.dart';
import '../utils/id.dart';

/// خدمة النسخ الاحتياطي والاستعادة الشاملة لـ Appwrite
class ComprehensiveAppwriteBackupService {
  factory ComprehensiveAppwriteBackupService() => _instance;

  ComprehensiveAppwriteBackupService._internal();
  static final ComprehensiveAppwriteBackupService _instance =
      ComprehensiveAppwriteBackupService._internal();

  final AppwriteService _appwriteService = AppwriteService();
  final AppwriteLogger _logger = AppwriteLogger();

  Future<File?> exportFullBackup(
    AppDatabase db,
    {String? deviceId,
    Function(String, double)? onProgress,}
  ) async {
    try {
      final timestamp = DateTime.now().toUtc();
      final collectionsData = <String, List<Map<String, dynamic>>>{};

      final entities = [
        {'table': db.rooms, 'id': AppwriteConfig.roomsCollectionId, 'name': 'الغرف'},
        {'table': db.bookings, 'id': AppwriteConfig.bookingsCollectionId, 'name': 'الحجوزات'},
        {'table': db.payments, 'id': AppwriteConfig.paymentsCollectionId, 'name': 'المدفوعات'},
        {'table': db.expenses, 'id': AppwriteConfig.expensesCollectionId, 'name': 'المصروفات'},
        {'table': db.employees, 'id': AppwriteConfig.employeesCollectionId, 'name': 'الموظفين'},
        {'table': db.debts, 'id': AppwriteConfig.debtsCollectionId, 'name': 'الديون'},
        {'table': db.bookingNotes, 'id': AppwriteConfig.bookingNotesCollectionId, 'name': 'ملاحظات الحجوزات'},
        {'table': db.cashTransactions, 'id': AppwriteConfig.cashTransactionsCollectionId, 'name': 'المعاملات النقدية'},
        {'table': db.shiftNotes, 'id': AppwriteConfig.shiftNotesCollectionId, 'name': 'ملاحظات النوبة'},
        {'table': db.bookingNights, 'id': AppwriteConfig.bookingNightsCollectionId, 'name': 'ليالي الحجز'},
        {'table': db.salaryCycles, 'id': AppwriteConfig.salaryCyclesCollectionId, 'name': 'دورات الرواتب'},
        {'table': db.salaryPayments, 'id': AppwriteConfig.salaryPaymentsCollectionId, 'name': 'دفعات الرواتب'},
        {'table': db.hotelDayLedger, 'id': AppwriteConfig.hotelDayLedgerCollectionId, 'name': 'دفتر اليومية'},
        {'table': db.priceAdjustments, 'id': AppwriteConfig.priceAdjustmentsCollectionId, 'name': 'تعديلات الأسعار'},
        {'table': db.bookingPriceAdjustments, 'id': AppwriteConfig.bookingPriceAdjustmentsCollectionId, 'name': 'تعديلات أسعار الحجوزات'},
        {'table': db.auditLogs, 'id': AppwriteConfig.auditLogsCollectionId, 'name': 'سجلات التدقيق'},
        {'table': db.paymentVoids, 'id': AppwriteConfig.paymentVoidsCollectionId, 'name': 'إلغاءات الدفع'},
      ];

      for (int i = 0; i < entities.length; i++) {
        final entity = entities[i];
        if (onProgress != null) onProgress('تصدير ${entity['name']}...', (i + 1) / entities.length);
        final rows = await db.select(entity['table'] as dynamic).get();
        collectionsData[entity['id'] as String] = rows.map((e) => (e as dynamic).toJson() as Map<String, dynamic>).toList();
      }

      final payload = {
        'metadata': {
          'version': '1.0',
          'timestamp': timestamp.toIso8601String(),
          'projectId': AppwriteConfig.projectId,
          'databaseId': AppwriteConfig.databaseId,
          'deviceId': deviceId ?? 'unknown',
          'source': 'local_db_export',
        },
        'collections': collectionsData,
      };

      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/full_backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final fileName = 'marina_full_backup_${DateFormat("yyyyMMdd_HHmmss").format(DateTime.now())}.json';
      final file = File('${backupDir.path}/$fileName');

      await file.writeAsString(jsonEncode(payload));
      if (onProgress != null) onProgress('تم إنشاء ملف النسخة الاحتياطية', 1.0);

      return file;
    } catch (e, stack) {
      _logger.error('Error exporting full backup', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<File?> exportFullCloudBackup({
    String? deviceId,
    Function(String, double)? onProgress,
  }) async {
    try {
      final timestamp = DateTime.now().toUtc();
      final collectionsData = <String, List<Map<String, dynamic>>>{};

      await _appwriteService.initialize();

      final collectionsToFetch = [
        {'id': AppwriteConfig.roomsCollectionId, 'name': 'الغرف'},
        {'id': AppwriteConfig.bookingsCollectionId, 'name': 'الحجوزات'},
        {'id': AppwriteConfig.paymentsCollectionId, 'name': 'المدفوعات'},
        {'id': AppwriteConfig.expensesCollectionId, 'name': 'المصروفات'},
        {'id': AppwriteConfig.employeesCollectionId, 'name': 'الموظفين'},
        {'id': AppwriteConfig.debtsCollectionId, 'name': 'الديون'},
        {'id': AppwriteConfig.bookingNotesCollectionId, 'name': 'ملاحظات الحجوزات'},
        {'id': AppwriteConfig.cashTransactionsCollectionId, 'name': 'المعاملات النقدية'},
        {'id': AppwriteConfig.shiftNotesCollectionId, 'name': 'ملاحظات النوبة'},
        {'id': AppwriteConfig.bookingNightsCollectionId, 'name': 'ليالي الحجز'},
        {'id': AppwriteConfig.salaryCyclesCollectionId, 'name': 'دورات الرواتب'},
        {'id': AppwriteConfig.salaryPaymentsCollectionId, 'name': 'دفعات الرواتب'},
        {'id': AppwriteConfig.hotelDayLedgerCollectionId, 'name': 'دفتر اليومية'},
        {'id': AppwriteConfig.priceAdjustmentsCollectionId, 'name': 'تعديلات الأسعار'},
        {'id': AppwriteConfig.bookingPriceAdjustmentsCollectionId, 'name': 'تعديلات أسعار الحجوزات'},
        {'id': AppwriteConfig.auditLogsCollectionId, 'name': 'سجلات التدقيق'},
        {'id': AppwriteConfig.paymentVoidsCollectionId, 'name': 'إلغاءات الدفع'},
      ];

      for (int i = 0; i < collectionsToFetch.length; i++) {
        final coll = collectionsToFetch[i];
        final progress = (i + 1) / collectionsToFetch.length;
        if (onProgress != null) onProgress('جلب ${coll['name']} من السحابة...', progress);

        final docs = await _appwriteService.databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: coll['id']!,
          queries: [Query.limit(5000)],
        );
        collectionsData[coll['id']!] = docs.documents.map((d) => d.data).toList();
      }

      final payload = {
        'metadata': {
          'version': '1.0_cloud_dump',
          'timestamp': timestamp.toIso8601String(),
          'projectId': AppwriteConfig.projectId,
          'databaseId': AppwriteConfig.databaseId,
          'deviceId': deviceId ?? 'unknown',
          'source': 'appwrite_cloud_export',
        },
        'collections': collectionsData,
      };

      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/cloud_exports');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final fileName = 'marina_cloud_export_${DateFormat("yyyyMMdd_HHmmss").format(DateTime.now())}.json';
      final file = File('${backupDir.path}/$fileName');

      await file.writeAsString(jsonEncode(payload));
      if (onProgress != null) onProgress('تم تصدير كافة بيانات السحابة بنجاح', 1.0);
      return file;
    } catch (e, stack) {
      _logger.error('Error exporting full cloud backup', error: e, stackTrace: stack);
      rethrow;
    }
  }

  Future<void> restoreToAppwrite(
    File backupFile, {
    bool clearExisting = false,
    Function(String, double)? onProgress,
  }) async {
    try {
      if (onProgress != null) onProgress('قراءة ملف النسخة الاحتياطية...', 0.0);
      final fileContent = await backupFile.readAsString();
      final data = jsonDecode(fileContent) as Map<String, dynamic>;

      final collections = data['collections'] as Map<String, dynamic>;

      await _appwriteService.initialize();

      final totalCollections = collections.keys.length;
      int collectionsProcessed = 0;
      final totalDocs = collections.values.fold(0, (sum, val) => sum + (val is List ? val.length : 0));
      int docsProcessed = 0;

      for (final collectionId in collections.keys) {
        final items = collections[collectionId] as List;
        collectionsProcessed++;
        final collectionOverallProgress = collectionsProcessed / totalCollections;

        if (onProgress != null) {
          onProgress('جاري معالجة مجموعة $collectionId (${items.length} عنصر)...', collectionOverallProgress * 0.5);
        }

        if (clearExisting) {
          await _appwriteService.deleteAllDocumentsInCollection(AppwriteConfig.databaseId, collectionId);
        }

        for (final item in items) {
          try {
            final docData = Map<String, dynamic>.from(item as Map);
            final String? documentId = (docData['localUuid'] ?? docData['$id'] ?? ID.unique()) as String?;
            final cleanData = _cleanDataForAppwrite(docData);

            try {
              await _appwriteService.databases.createDocument(
                databaseId: AppwriteConfig.databaseId,
                collectionId: collectionId,
                documentId: documentId!,
                data: cleanData,
              );
            } on AppwriteException catch (e) {
              if (e.code == 409) {
                await _appwriteService.databases.updateDocument(
                  databaseId: AppwriteConfig.databaseId,
                  collectionId: collectionId,
                  documentId: documentId!,
                  data: cleanData,
                );
              } else {
                rethrow;
              }
            }
            docsProcessed++;
            if (onProgress != null && docsProcessed % 10 == 0) {
              onProgress('جاري رفع $collectionId ($docsProcessed / $totalDocs)...', 0.5 + (docsProcessed / totalDocs) * 0.5);
            }
          } catch (e) {
            _logger.warning('Failed to restore item in $collectionId: $e', tag: 'RESTORE_APPWRITE');
          }
        }
      }
      if (onProgress != null) onProgress('تمت عملية الرفع بنجاح', 1.0);
    } catch (e, stack) {
      _logger.error('Error restoring backup to Appwrite', error: e, stackTrace: stack, tag: 'RESTORE_APPWRITE');
      rethrow;
    }
  }

  Map<String, dynamic> _cleanDataForAppwrite(Map<String, dynamic> data) {
    final clean = Map<String, dynamic>.from(data);
    clean.remove('$id');
    clean.remove('$createdAt');
    clean.remove('$updatedAt');
    clean.remove('$permissions');
    clean.remove('$collectionId');
    clean.remove('$databaseId');
    clean.remove('id');
    return clean;
  }

  Future<File?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null && result.files.single.path != null) {
      return File(result.files.single.path!);
    }
    return null;
  }
}
