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
/// تتيح هذه الخدمة تصدير جميع البيانات من قاعدة البيانات المحلية إلى ملف JSON
/// واستيرادها إلى Appwrite (Overwrite أو Merge)
class ComprehensiveAppwriteBackupService {
  factory ComprehensiveAppwriteBackupService() => _instance;

  ComprehensiveAppwriteBackupService._internal();
  static final ComprehensiveAppwriteBackupService _instance =
      ComprehensiveAppwriteBackupService._internal();

  final AppwriteService _appwriteService = AppwriteService();
  final AppwriteLogger _logger = AppwriteLogger();

  // قائمة المجموعات التي سيتم نسخها احتياطياً
  // ignore: unused_field
  final List<String> _collectionIds = [
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
  ];

  // تصدير النسخة الاحتياطية من قاعدة البيانات المحلية
  Future<File?> exportFullBackup(
    AppDatabase db, {
    String? deviceId,
    Function(String, double)? onProgress,
  }) async {
    try {
      final timestamp = DateTime.now().toUtc();
      final collectionsData = <String, List<Map<String, dynamic>>>{};

      // 1. Rooms
      if (onProgress != null) onProgress('تصدير الغرف...', 0.1);
      final rooms = await db.select(db.rooms).get();
      collectionsData[AppwriteConfig.roomsCollectionId] =
          rooms.map((e) => e.toJson()).toList();

      // 2. Bookings
      if (onProgress != null) onProgress('تصدير الحجوزات...', 0.2);
      final bookings = await db.select(db.bookings).get();
      collectionsData[AppwriteConfig.bookingsCollectionId] =
          bookings.map((e) => e.toJson()).toList();

      // 3. Payments
      if (onProgress != null) onProgress('تصدير المدفوعات...', 0.3);
      final payments = await db.select(db.payments).get();
      collectionsData[AppwriteConfig.paymentsCollectionId] =
          payments.map((e) => e.toJson()).toList();

      // 4. Expenses
      if (onProgress != null) onProgress('تصدير المصروفات...', 0.4);
      final expenses = await db.select(db.expenses).get();
      collectionsData[AppwriteConfig.expensesCollectionId] =
          expenses.map((e) => e.toJson()).toList();

      // 5. Employees
      if (onProgress != null) onProgress('تصدير الموظفين...', 0.5);
      final employees = await db.select(db.employees).get();
      collectionsData[AppwriteConfig.employeesCollectionId] =
          employees.map((e) => e.toJson()).toList();

      // 6. Debts
      if (onProgress != null) onProgress('تصدير الديون...', 0.6);
      final debts = await db.select(db.debts).get();
      collectionsData[AppwriteConfig.debtsCollectionId] =
          debts.map((e) => e.toJson()).toList();

      // 7. Booking Notes
      if (onProgress != null) onProgress('تصدير ملاحظات الحجوزات...', 0.7);
      final bookingNotes = await db.select(db.bookingNotes).get();
      collectionsData[AppwriteConfig.bookingNotesCollectionId] =
          bookingNotes.map((e) => e.toJson()).toList();

      // 8. Cash Transactions
      if (onProgress != null) onProgress('تصدير المعاملات النقدية...', 0.75);
      final cashTransactions = await db.select(db.cashTransactions).get();
      collectionsData[AppwriteConfig.cashTransactionsCollectionId] =
          cashTransactions.map((e) => e.toJson()).toList();

      // 9. Shift Notes
      if (onProgress != null) onProgress('تصدير ملاحظات النوبة...', 0.8);
      final shiftNotes = await db.select(db.shiftNotes).get();
      collectionsData[AppwriteConfig.shiftNotesCollectionId] =
          shiftNotes.map((e) => e.toJson()).toList();

      // 10. Booking Nights
      if (onProgress != null) onProgress('تصدير ليالي الحجوزات...', 0.85);
      final bookingNights = await db.select(db.bookingNights).get();
      collectionsData[AppwriteConfig.bookingNightsCollectionId] =
          bookingNights.map((e) => e.toJson()).toList();

      // 11. Salary Cycles
      if (onProgress != null) onProgress('تصدير دورات الرواتب...', 0.9);
      final salaryCycles = await db.select(db.salaryCycles).get();
      collectionsData[AppwriteConfig.salaryCyclesCollectionId] =
          salaryCycles.map((e) => e.toJson()).toList();

      // 12. Salary Payments
      if (onProgress != null) onProgress('تصدير دفعات الرواتب...', 0.95);
      final salaryPayments = await db.select(db.salaryPayments).get();
      collectionsData[AppwriteConfig.salaryPaymentsCollectionId] =
          salaryPayments.map((e) => e.toJson()).toList();

      // 13. Hotel Day Ledger
      if (onProgress != null) onProgress('تصدير دفتر اليومية...', 0.88);
      final ledger = await db.select(db.hotelDayLedger).get();
      collectionsData[AppwriteConfig.hotelDayLedgerCollectionId] =
          ledger.map((e) => e.toJson()).toList();

      // 14. Price Adjustments
      if (onProgress != null) onProgress('تصدير تعديلات الأسعار...', 0.91);
      final priceAdjustments = await db.select(db.priceAdjustments).get();
      collectionsData[AppwriteConfig.priceAdjustmentsCollectionId] =
          priceAdjustments.map((e) => e.toJson()).toList();

      // 15. Booking Price Adjustments
      if (onProgress != null)
        onProgress('تصدير تعديلات أسعار الحجوزات...', 0.93);
      final bookingPriceAdj = await db.select(db.bookingPriceAdjustments).get();
      collectionsData[AppwriteConfig.bookingPriceAdjustmentsCollectionId] =
          bookingPriceAdj.map((e) => e.toJson()).toList();

      // 16. Audit Logs
      if (onProgress != null) onProgress('تصدير سجلات التدقيق...', 0.95);
      final auditLogs = await db.select(db.auditLogs).get();
      collectionsData[AppwriteConfig.auditLogsCollectionId] =
          auditLogs.map((e) => e.toJson()).toList();

      // 17. Payment Voids
      if (onProgress != null) onProgress('تصدير إلغاءات الدفع...', 0.98);
      final paymentVoids = await db.select(db.paymentVoids).get();
      collectionsData[AppwriteConfig.paymentVoidsCollectionId] =
          paymentVoids.map((e) => e.toJson()).toList();

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

      // حفظ الملف
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/full_backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final fileName =
          'marina_full_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final file = File('${backupDir.path}/$fileName');

      await file.writeAsString(jsonEncode(payload));

      if (onProgress != null) onProgress('تم إنشاء ملف النسخة الاحتياطية', 1.0);

      return file;
    } catch (e, stack) {
      _logger.error('Error exporting full backup', error: e, stackTrace: stack);
      rethrow;
    }
  }

  // استيراد ورفع النسخة الشاملة إلى Appwrite
  
  // fetch data from Appwrite and export to JSON
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
       Future<void> restoreToAppwrite(
    File backupFile, {
    bool clearExisting = false,
    Function(String, double)? onProgress,
  }) async {
    try {
      if (onProgress != null) onProgress('قراءة ملف النسخة الاحتياطية...', 0.0);
      final content = await backupFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      final metadata = data['metadata'] as Map<String, dynamic>?;
      final collections = data['collections'] as Map<String, dynamic>;

      if (metadata == null) {
        _logger.error('Backup file missing metadata.', tag: 'RESTORE_APPWRITE');
        throw Exception('Backup file missing metadata.');
      }

      await _appwriteService.initialize();

      int totalCollections = collections.keys.length;
      int collectionsProcessed = 0;
      int totalDocuments = 0;
      collections.forEach((key, value) {
        if (value is List) totalDocuments += value.length;
      });

      int documentsProcessed = 0;

      // Process each collection
      for (final collectionId in collections.keys) {
        final items = collections[collectionId] as List;

        collectionsProcessed++;
        double collectionOverallProgress = collectionsProcessed / totalCollections;

        try {
          if (onProgress != null) {
            onProgress(
              'جاري معالجة مجموعة $collectionId (${items.length} عنصر)...',
              collectionOverallProgress * 0.5, // Half of progress for deletion/preparation
            );
          }

          // If clearExisting is true, first delete all documents in this collection
          if (clearExisting) {
            _logger.info('Clearing existing documents in collection $collectionId...', tag: 'RESTORE_APPWRITE');
            // Assuming AppwriteService has a method to delete all documents in a collection
            await _appwriteService.deleteAllDocumentsInCollection(
                AppwriteConfig.databaseId, collectionId);
            _logger.info('Finished clearing existing documents in collection $collectionId.', tag: 'RESTORE_APPWRITE');
          }

          int failedDocumentsInCollection = 0;
          for (final item in items) {
            try {
              final docData = Map<String, dynamic>.from(item as Map);

              String? documentId;
              if (docData.containsKey('localUuid')) {
                documentId = docData['localUuid'];
              } else if (docData.containsKey('\$id')) {
                documentId = docData['\$id'];
              } else {
                documentId = ID.unique();
              }

              final cleanData = _cleanDataForAppwrite(docData);

              // Attempt to create or update the document
              try {
                await _appwriteService.databases.createDocument(
                  databaseId: AppwriteConfig.databaseId,
                  collectionId: collectionId,
                  documentId: documentId!,
                  data: cleanData,
                );
              } on AppwriteException catch (e) {
                if (e.code == 409) { // Document already exists, update it
                  await _appwriteService.databases.updateDocument(
                    databaseId: AppwriteConfig.databaseId,
                    collectionId: collectionId,
                    documentId: documentId!,
                    data: cleanData,
                  );
                } else {
                  rethrow; // Re-throw other AppwriteExceptions
                }
              }

              documentsProcessed++;
              if (onProgress != null && documentsProcessed % 10 == 0) {
                onProgress(
                  'جاري رفع $collectionId (${documentsProcessed} / $totalDocuments)...',
                  collectionOverallProgress * 0.5 + (documentsProcessed / totalDocuments) * 0.5,
                );
              }
            } catch (e, stack) {
              failedDocumentsInCollection++;
              _logger.warning('Failed to restore item in $collectionId: $e', error: e, stackTrace: stack, tag: 'RESTORE_APPWRITE');
            }
          }

          if (failedDocumentsInCollection > 0) {
            _logger.error('Failed to restore $failedDocumentsInCollection documents in collection $collectionId.', tag: 'RESTORE_APPWRITE');
            throw Exception('Partial restoration in collection $collectionId.'); // Fail the collection if any doc failed
          } else {
            _logger.info('Successfully restored collection $collectionId.', tag: 'RESTORE_APPWRITE');
          }

        } catch (e, stack) {
          _logger.error(
            'Error processing collection $collectionId: $e',
            error: e,
            stackTrace: stack,
            tag: 'RESTORE_APPWRITE',
          );
          rethrow; // Re-throw to fail the entire restore if one collection fails
        }
      }

      if (onProgress != null) onProgress('تمت عملية الرفع بنجاح', 1.0);
      _logger.info('Appwrite backup restored successfully.', tag: 'RESTORE_APPWRITE');
    } catch (e, stack) {
      _logger.error(
        'Error restoring backup to Appwrite',
        error: e,
        stackTrace: stack,
        tag: 'RESTORE_APPWRITE',
      );
      rethrow;
    }
  }


  Map<String, dynamic> _cleanDataForAppwrite(Map<String, dynamic> data) {
    final clean = Map<String, dynamic>.from(data);

    // إزالة الحقول التي يضيفها Appwrite تلقائياً
    clean.remove('\$id');
    clean.remove('\$createdAt');
    clean.remove('\$updatedAt');
    clean.remove('\$permissions');
    clean.remove('\$collectionId');
    clean.remove('\$databaseId');

    // إزالة الحقول الخاصة بـ Drift/SQLite
    clean.remove('id');

    return clean;
  }

  // اختيار ملف من الجهاز
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
}
}
