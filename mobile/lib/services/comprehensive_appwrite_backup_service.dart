// ignore_for_file: unused_import

import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart' hide Permission;
import 'package:appwrite/models.dart' as models;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/debug_log.dart';
import '../utils/json_isolate.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_service.dart';
import 'local_db.dart';

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

  /// اسم مجلد النسخ الخارجي (مشترك مع LocalBackupService للاتساق).
  static const String _externalBackupFolderName = 'MarinaHotelBackups';

  /// المجلد الفرعي الخاص بنسخ Appwrite داخل مجلد النسخ الخارجي.
  static const String _appwriteSubfolder = 'Appwrite';

  /// مسار مجلد النسخ الخارجي على أندرويد:
  /// /storage/emulated/0/Documents/MarinaHotelBackups/Appwrite
  static String get _androidExternalPath =>
      '/storage/emulated/0/Documents/$_externalBackupFolderName/$_appwriteSubfolder';

  Directory? _cachedBackupDirectory;
  bool _cachedIsExternal = false;

  /// التحقق من أذونات التخزين الخارجي وطلبها عند الحاجة.
  ///
  /// ✅ على Android 11+ نطلب MANAGE_EXTERNAL_STORAGE (معلنة في Manifest)،
  /// وعلى الأقدم نطلب WRITE/READ_EXTERNAL_STORAGE.
  /// عند الرفض لا نفشل العملية — نرجع false ويتولى المُستدعي
  /// استخدام المجلد الخاص بالتطبيق كبديل (نفس سياسة LocalBackupService).
  Future<bool> _checkExternalStoragePermission() async {
    try {
      if (!Platform.isAndroid) {
        return true; // iOS/سطح المكتب: نستخدم مجلد التطبيق
      }
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 30) {
        final granted = await Permission.manageExternalStorage
            .request()
            .isGranted;
        if (granted) {
          dlog('✅ MANAGE_EXTERNAL_STORAGE granted (Appwrite backup)');
          return true;
        }
        dlog(
          '⚠️ MANAGE_EXTERNAL_STORAGE denied (Appwrite backup) — '
          'falling back to app-private directory',
        );
        return false;
      }

      // Android < 11
      final storagePermission = await Permission.storage.request();
      return storagePermission.isGranted;
    } catch (e) {
      dlog(() => '❌ خطأ في التحقق من أذونات التخزين: $e');
      return false;
    }
  }

  /// مجلد حفظ نسخة Appwrite الاحتياطية.
  ///
  /// الأولوية للتخزين الخارجي المشترك على أندرويد حتى تبقى النسخة
  /// محفوظة حتى لو أُلغي تثبيت التطبيق، ويستطيع المستخدم نسخها يدوياً.
  /// عند رفض الإذن أو فشل الإنشاء نتراجع إلى مجلد التطبيق الخاص
  /// (بنفس المسار القديم full_backups للتوافق مع النسخ السابقة).
  ///
  /// يُرجع (المجلد، هل هو تخزين خارجي مشترك؟)
  Future<(Directory, bool)> getBackupDirectory() async {
    if (_cachedBackupDirectory != null &&
        _cachedBackupDirectory!.existsSync()) {
      return (_cachedBackupDirectory!, _cachedIsExternal);
    }

    Directory backupDir;
    bool isExternal = false;

    if (Platform.isAndroid) {
      final hasPermission = await _checkExternalStoragePermission();
      if (hasPermission) {
        final externalDir = Directory(_androidExternalPath);
        try {
          if (!externalDir.existsSync()) {
            await externalDir.create(recursive: true);
          }
          // تأكيد قابلية الكتابة فعلياً (إذن ممنوح لا يعني دائماً كتابة ناجحة)
          final probe = File('${externalDir.path}/.write_probe');
          await probe.writeAsString('ok', flush: true);
          if (probe.existsSync()) {
            await probe.delete();
          }
          backupDir = externalDir;
          isExternal = true;
          dlog(() => '✅ مجلد نسخ Appwrite الخارجي: ${backupDir.path}');
        } catch (e) {
          dlog(
            () =>
                '⚠️ فشل الوصول للتخزين الخارجي ($e) — '
                'الانتقال إلى مجلد التطبيق',
          );
          backupDir = await _appPrivateBackupDir();
        }
      } else {
        backupDir = await _appPrivateBackupDir();
      }
    } else {
      // iOS / سطح المكتب: مجلد مستندات التطبيق (الوصول لنظام الملفات
      // المشترك يتطلب مسارات مختلفة لكل منصة)
      backupDir = await _appPrivateBackupDir();
    }

    _cachedBackupDirectory = backupDir;
    _cachedIsExternal = isExternal;

    return (backupDir, isExternal);
  }

  /// مجلد النسخ داخل مساحة التطبيق الخاصة (السلوك القديم).
  Future<Directory> _appPrivateBackupDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${dir.path}/full_backups');
    if (!backupDir.existsSync()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

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
    // ❌ hotelDayLedgerCollectionId — جدول محلي فقط، لا يتم مزامنته
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
    void Function(String, double)? onProgress,
  }) async {
    try {
      final timestamp = DateTime.now().toUtc();
      final collectionsData = <String, List<Map<String, dynamic>>>{};

      // 1. Rooms
      if (onProgress != null) {
        onProgress('تصدير الغرف...', 0.1);
      }
      final rooms = await db.select(db.rooms).get();
      collectionsData[AppwriteConfig.roomsCollectionId] = rooms
          .map((e) => e.toJson())
          .toList();

      // 2. Bookings
      if (onProgress != null) {
        onProgress('تصدير الحجوزات...', 0.2);
      }
      final bookings = await db.select(db.bookings).get();
      collectionsData[AppwriteConfig.bookingsCollectionId] = bookings
          .map((e) => e.toJson())
          .toList();

      // 3. Payments
      if (onProgress != null) {
        onProgress('تصدير المدفوعات...', 0.3);
      }
      final payments = await db.select(db.payments).get();
      collectionsData[AppwriteConfig.paymentsCollectionId] = payments
          .map((e) => e.toJson())
          .toList();

      // 4. Expenses
      if (onProgress != null) {
        onProgress('تصدير المصروفات...', 0.4);
      }
      final expenses = await db.select(db.expenses).get();
      collectionsData[AppwriteConfig.expensesCollectionId] = expenses
          .map((e) => e.toJson())
          .toList();

      // 5. Employees
      if (onProgress != null) {
        onProgress('تصدير الموظفين...', 0.5);
      }
      final employees = await db.select(db.employees).get();
      collectionsData[AppwriteConfig.employeesCollectionId] = employees
          .map((e) => e.toJson())
          .toList();

      // 6. Debts
      if (onProgress != null) {
        onProgress('تصدير الديون...', 0.6);
      }
      final debts = await db.select(db.debts).get();
      collectionsData[AppwriteConfig.debtsCollectionId] = debts
          .map((e) => e.toJson())
          .toList();

      // 7. Booking Notes
      if (onProgress != null) {
        onProgress('تصدير ملاحظات الحجوزات...', 0.7);
      }
      final bookingNotes = await db.select(db.bookingNotes).get();
      collectionsData[AppwriteConfig.bookingNotesCollectionId] = bookingNotes
          .map((e) => e.toJson())
          .toList();

      // 8. Cash Transactions
      if (onProgress != null) {
        onProgress('تصدير المعاملات النقدية...', 0.75);
      }
      final cashTransactions = await db.select(db.cashTransactions).get();
      collectionsData[AppwriteConfig.cashTransactionsCollectionId] =
          cashTransactions.map((e) => e.toJson()).toList();

      // 9. Shift Notes
      if (onProgress != null) {
        onProgress('تصدير ملاحظات النوبة...', 0.8);
      }
      final shiftNotes = await db.select(db.shiftNotes).get();
      collectionsData[AppwriteConfig.shiftNotesCollectionId] = shiftNotes
          .map((e) => e.toJson())
          .toList();

      // 10. Booking Nights
      if (onProgress != null) {
        onProgress('تصدير ليالي الحجوزات...', 0.85);
      }
      final bookingNights = await db.select(db.bookingNights).get();
      collectionsData[AppwriteConfig.bookingNightsCollectionId] = bookingNights
          .map((e) => e.toJson())
          .toList();

      // 11. Salary Cycles
      if (onProgress != null) {
        onProgress('تصدير دورات الرواتب...', 0.9);
      }
      final salaryCycles = await db.select(db.salaryCycles).get();
      collectionsData[AppwriteConfig.salaryCyclesCollectionId] = salaryCycles
          .map((e) => e.toJson())
          .toList();

      // 12. Salary Payments
      if (onProgress != null) {
        onProgress('تصدير دفعات الرواتب...', 0.95);
      }
      final salaryPayments = await db.select(db.salaryPayments).get();
      collectionsData[AppwriteConfig.salaryPaymentsCollectionId] =
          salaryPayments.map((e) => e.toJson()).toList();

      // ❌ 13. Hotel Day Ledger — جدول محلي فقط، لا يتم تصديره إلى Appwrite
      // البيانات تُحسب محلياً من خلال restore_fix_service.dart
      // لا يوجد collection على Appwrite Cloud

      // 14. Price Adjustments
      if (onProgress != null) {
        onProgress('تصدير تعديلات الأسعار...', 0.91);
      }
      final priceAdjustments = await db.select(db.priceAdjustments).get();
      collectionsData[AppwriteConfig.priceAdjustmentsCollectionId] =
          priceAdjustments.map((e) => e.toJson()).toList();

      // 15. Booking Price Adjustments
      if (onProgress != null) {
        onProgress('تصدير تعديلات أسعار الحجوزات...', 0.93);
      }
      final bookingPriceAdj = await db.select(db.bookingPriceAdjustments).get();
      collectionsData[AppwriteConfig.bookingPriceAdjustmentsCollectionId] =
          bookingPriceAdj.map((e) => e.toJson()).toList();

      // 16. Audit Logs
      if (onProgress != null) {
        onProgress('تصدير سجلات التدقيق...', 0.95);
      }
      final auditLogs = await db.select(db.auditLogs).get();
      collectionsData[AppwriteConfig.auditLogsCollectionId] = auditLogs
          .map((e) => e.toJson())
          .toList();

      // 17. Payment Voids
      if (onProgress != null) {
        onProgress('تصدير إلغاءات الدفع...', 0.98);
      }
      final paymentVoids = await db.select(db.paymentVoids).get();
      collectionsData[AppwriteConfig.paymentVoidsCollectionId] = paymentVoids
          .map((e) => e.toJson())
          .toList();

      final payload = {
        'metadata': {
          'version': '1.1',
          'timestamp': timestamp.toIso8601String(),
          'projectId': AppwriteConfig.projectId,
          'databaseId': AppwriteConfig.databaseId,
          'deviceId': deviceId ?? 'unknown',
          'source': 'local_db_export',
        },
        'collections': collectionsData,
      };

      // حفظ الملف
      // ✅ (2026-10-31) الأولوية للتخزين الخارجي المشترك على أندرويد حتى تبقى
      // النسخة محفوظة بعد إلغاء تثبيت التطبيق ويمكن للمستخدم نسخها يدوياً.
      final (backupDir, isExternal) = await getBackupDirectory();

      final fileName =
          'marina_full_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final file = File('${backupDir.path}/$fileName');

      await file.writeAsString(jsonEncode(payload));

      dlog(
        () =>
            '✅ حُفظت نسخة Appwrite الاحتياطية '
            '${isExternal ? 'في التخزين الخارجي' : 'في مجلد التطبيق'}: '
            '${file.path}',
      );

      if (onProgress != null) {
        onProgress(
          isExternal
              ? 'تم إنشاء ملف النسخة في الذاكرة الخارجية'
              : 'تم إنشاء ملف النسخة (مجلد التطبيق — لم تُمنح صلاحية التخزين الخارجي)',
          1.0,
        );
      }

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
    void Function(String, double)? onProgress,
  }) async {
    try {
      // قراءة الملف
      if (onProgress != null) {
        onProgress('قراءة ملف النسخة الاحتياطية...', 0.0);
      }
      final content = await backupFile.readAsString();
      // ✅ Performance: استخدم Isolate لـ JSON parsing (backup files كبيرة)
      final data = await JsonIsolate.decodeAsMap(content);

      final collections = data['collections'] as Map<String, dynamic>;

      // تهيئة الخدمة
      await _appwriteService.initialize();

      int totalItems = 0;
      collections.forEach((key, value) {
        if (value is List) {
          totalItems += value.length;
        }
      });

      int processedItems = 0;

      // معالجة كل مجموعة
      for (final collectionId in collections.keys) {
        final items = collections[collectionId] as List;

        if (onProgress != null) {
          onProgress(
            'جاري رفع $collectionId (${items.length} عنصر)...',
            processedItems / totalItems,
          );
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
              documentId = docData['localUuid'] as String?;
            } else if (docData.containsKey(r'$id')) {
              documentId = docData[r'$id'] as String?;
            } else {
              documentId = ID.unique();
            }

            // تنظيف البيانات من الحقول الخاصة بـ Appwrite أو Drift التي لا يجب إرسالها
            final cleanData = _cleanDataForAppwrite(docData);

            // محاولة إنشاء أو تحديث المستند
            try {
              // ignore: deprecated_member_use
              await _appwriteService.databases.createDocument(
                databaseId: AppwriteConfig.databaseId,
                collectionId: collectionId,
                documentId: documentId!,
                data: cleanData,
              );
            } on AppwriteException catch (e) {
              // إذا كان موجوداً بالفعل، نقوم بالتحديث
              if (e.code == 409) {
                // ignore: deprecated_member_use
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
              onProgress(
                'جاري الرفع... ($processedItems / $totalItems)',
                processedItems / totalItems,
              );
            }
          } catch (e) {
            _logger.warning('Failed to restore item in $collectionId: $e');
            // نستمر في العمل مع باقي العناصر
          }
        }
      }

      if (onProgress != null) {
        onProgress('تمت عملية الرفع بنجاح', 1.0);
      }
    } catch (e, stack) {
      _logger.error(
        'Error restoring backup to Appwrite',
        error: e,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  // تنظيف البيانات لتتوافق مع Appwrite
  Map<String, dynamic> _cleanDataForAppwrite(Map<String, dynamic> data) {
    final clean = Map<String, dynamic>.from(data);

    // إزالة الحقول التي يضيفها Appwrite تلقائياً
    clean.remove(r'$id');
    clean.remove(r'$createdAt');
    clean.remove(r'$updatedAt');
    clean.remove(r'$permissions');
    clean.remove(r'$collectionId');
    clean.remove(r'$databaseId');

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
