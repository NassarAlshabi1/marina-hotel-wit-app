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

/// خدمة النسخ الاحتياطي والاستعادة الشاملة لـ Appwrite
/// تتيح هذه الخدمة تصدير جميع البيانات من قاعدة البيانات المحلية إلى ملف JSON
/// واستيرادها إلى Appwrite (Overwrite أو Merge)
class ComprehensiveAppwriteBackupService {
  static final ComprehensiveAppwriteBackupService _instance =
      ComprehensiveAppwriteBackupService._internal();

  factory ComprehensiveAppwriteBackupService() => _instance;

  ComprehensiveAppwriteBackupService._internal();

  final AppwriteService _appwriteService = AppwriteService();
  final AppwriteLogger _logger = AppwriteLogger();

  // قائمة المجموعات التي سيتم نسخها احتياطياً
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
      
      int totalCollections = _collectionIds.length;
      int processedCollections = 0;

      // 1. Rooms
      if (onProgress != null) onProgress('تصدير الغرف...', 0.1);
      final rooms = await db.select(db.rooms).get();
      collectionsData[AppwriteConfig.roomsCollectionId] = rooms.map((e) {
        final map = e.toJson();
        // تحويل JSON Drift إلى Map مناسب لـ Appwrite
        // إزالة الحقول المحلية البحتة إذا لزم الأمر
        return map;
      }).toList();
      
      // 2. Bookings
      if (onProgress != null) onProgress('تصدير الحجوزات...', 0.2);
      final bookings = await db.select(db.bookings).get();
      collectionsData[AppwriteConfig.bookingsCollectionId] = bookings.map((e) => e.toJson() as Map<String, dynamic>).toList();
      
      // 3. Payments
      if (onProgress != null) onProgress('تصدير المدفوعات...', 0.3);
      final payments = await db.select(db.payments).get();
      collectionsData[AppwriteConfig.paymentsCollectionId] = payments.map((e) => e.toJson() as Map<String, dynamic>).toList();
      
      // 4. Expenses
      if (onProgress != null) onProgress('تصدير المصروفات...', 0.4);
      final expenses = await db.select(db.expenses).get();
      collectionsData[AppwriteConfig.expensesCollectionId] = expenses.map((e) => e.toJson() as Map<String, dynamic>).toList();

      // 5. Employees
      if (onProgress != null) onProgress('تصدير الموظفين...', 0.5);
      final employees = await db.select(db.employees).get();
      collectionsData[AppwriteConfig.employeesCollectionId] = employees.map((e) => e.toJson() as Map<String, dynamic>).toList();
      
      // 6. Others
      final debts = await db.select(db.debts).get();
      collectionsData[AppwriteConfig.debtsCollectionId] = debts.map((e) => e.toJson() as Map<String, dynamic>).toList();
      
      final bookingNotes = await db.select(db.bookingNotes).get();
      collectionsData[AppwriteConfig.bookingNotesCollectionId] = bookingNotes.map((e) => e.toJson() as Map<String, dynamic>).toList();
      
      final cashTransactions = await db.select(db.cashTransactions).get();
      collectionsData[AppwriteConfig.cashTransactionsCollectionId] = cashTransactions.map((e) => e.toJson() as Map<String, dynamic>).toList();
      
      final shiftNotes = await db.select(db.shiftNotes).get();
      collectionsData[AppwriteConfig.shiftNotesCollectionId] = shiftNotes.map((e) => e.toJson() as Map<String, dynamic>).toList();

      final bookingNights = await db.select(db.bookingNights).get();
      collectionsData[AppwriteConfig.bookingNightsCollectionId] = bookingNights.map((e) => e.toJson() as Map<String, dynamic>).toList();

      final salaryCycles = await db.select(db.salaryCycles).get();
      collectionsData[AppwriteConfig.salaryCyclesCollectionId] = salaryCycles.map((e) => e.toJson() as Map<String, dynamic>).toList();

      final salaryPayments = await db.select(db.salaryPayments).get();
      collectionsData[AppwriteConfig.salaryPaymentsCollectionId] = salaryPayments.map((e) => e.toJson() as Map<String, dynamic>).toList();

      final ledger = await db.select(db.hotelDayLedger).get();
      collectionsData[AppwriteConfig.hotelDayLedgerCollectionId] = ledger.map((e) => e.toJson() as Map<String, dynamic>).toList();
      
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

      final fileName = 'marina_full_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
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
  Future<void> restoreToAppwrite(
      File backupFile, {
      bool clearExisting = false,
      Function(String, double)? onProgress,
      }) async {
    
    try {
      // قراءة الملف
      if (onProgress != null) onProgress('قراءة ملف النسخة الاحتياطية...', 0.0);
      final content = await backupFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      
      final collections = data['collections'] as Map<String, dynamic>;
      
      // تهيئة الخدمة
      await _appwriteService.initialize();
      
      int totalItems = 0;
      collections.forEach((key, value) {
        if (value is List) totalItems += value.length;
      });
      
      int processedItems = 0;
      
      // معالجة كل مجموعة
      for (final collectionId in collections.keys) {
        final items = collections[collectionId] as List;
        
        if (onProgress != null) {
          onProgress('جاري رفع $collectionId (${items.length} عنصر)...', processedItems / totalItems);
        }
        
        // إذا تم طلب مسح البيانات القديمة (حذر جداً!)
        if (clearExisting) {
          // TODO: Implement deletion logic if strictly needed
          // هذه خطوة خطيرة، نفضل التحديث أو الإنشاء فقط
        }
        
        for (final item in items) {
          try {
            // تحضير البيانات
            final docData = Map<String, dynamic>.from(item as Map);
            
            // استخراج المعرفات
            String? documentId;
            if (docData.containsKey('localUuid')) {
              documentId = docData['localUuid'];
            } else if (docData.containsKey('\$id')) {
              documentId = docData['\$id'];
            } else {
              documentId = ID.unique();
            }
            
            // تنظيف البيانات من الحقول الخاصة بـ Appwrite أو Drift التي لا يجب إرسالها
            final cleanData = _cleanDataForAppwrite(docData);
            
            // محاولة إنشاء أو تحديث المستند
            try {
              await _appwriteService.databases.createDocument(
                databaseId: AppwriteConfig.databaseId,
                collectionId: collectionId,
                documentId: documentId!,
                data: cleanData,
              );
            } on AppwriteException catch (e) {
              // إذا كان موجوداً بالفعل، نقوم بالتحديث
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
            
            processedItems++;
            if (onProgress != null && processedItems % 5 == 0) {
              onProgress('جاري الرفع... ($processedItems / $totalItems)', processedItems / totalItems);
            }
            
          } catch (e) {
            _logger.warning('Failed to restore item in $collectionId: $e');
            // نستمر في العمل مع باقي العناصر
          }
        }
      }
      
      if (onProgress != null) onProgress('تمت عملية الرفع بنجاح', 1.0);
      
    } catch (e, stack) {
      _logger.error('Error restoring backup to Appwrite', error: e, stackTrace: stack);
      rethrow;
    }
  }
  
  // تنظيف البيانات لتتوافق مع Appwrite
  Map<String, dynamic> _cleanDataForAppwrite(Map<String, dynamic> data) {
    final clean = Map<String, dynamic>.from(data);
    
    // إزالة الحقول التي يضيفها Appwrite تلقائياً
    clean.remove('\$id');
    clean.remove('\$createdAt');
    clean.remove('\$updatedAt');
    clean.remove('\$permissions');
    clean.remove('\$collectionId');
    clean.remove('\$databaseId');
    
    // تحويل التواريخ إلى صيغة ISO 8601 إذا كانت timestamps
    // (هنا يعتمد على بنية جداولك في drift مقابل appwrite)
    
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
