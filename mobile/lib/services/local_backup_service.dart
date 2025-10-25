import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';
import 'providers.dart';
import 'google_drive_backup_service.dart';

class LocalBackupFile {
  final String fileName;
  final String filePath;
  final DateTime createdTime;
  final int sizeBytes;
  final BackupMetadata? metadata;

  LocalBackupFile({
    required this.fileName,
    required this.filePath,
    required this.createdTime,
    required this.sizeBytes,
    this.metadata,
  });

  factory LocalBackupFile.fromFile(File file) {
    final stat = file.statSync();
    return LocalBackupFile(
      fileName: file.path.split('/').last,
      filePath: file.path,
      createdTime: stat.modified,
      sizeBytes: stat.size,
    );
  }
}

class LocalBackupService {
  static const String _backupFolderName = 'MarinaHotelBackups';
  static const String _backupFilePrefix = 'marina_hotel_backup_';
  static const String _prefsLastLocalBackupKey = 'last_local_backup_timestamp';
  static const String _prefsAutoLocalBackupKey = 'auto_local_backup_enabled';
  static const String _prefsAutoLocalBackupFrequencyKey = 'auto_local_backup_frequency';
  static const String _prefsLocalBackupPathKey = 'local_backup_path';

  Directory? _backupDirectory;

  /// التحقق من الأذونات المطلوبة
  Future<bool> checkPermissions() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        
        // Android 13+ يتطلب أذونات مختلفة
        if (androidInfo.version.sdkInt >= 33) {
          // للـ Android 13+، نستخدم MANAGE_EXTERNAL_STORAGE أو تطبيق scoped storage
          return await Permission.manageExternalStorage.request().isGranted;
        } else if (androidInfo.version.sdkInt >= 30) {
          // Android 11-12
          return await Permission.manageExternalStorage.request().isGranted;
        } else {
          // Android < 11
          final storagePermission = await Permission.storage.request();
          return storagePermission.isGranted;
        }
      }
      return true; // على iOS أو منصات أخرى
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من الأذونات: $e');
      return false;
    }
  }

  /// الحصول على مجلد النسخ الاحتياطي المحلي
  Future<Directory> getBackupDirectory() async {
    if (_backupDirectory != null) {
      return _backupDirectory!;
    }

    try {
      Directory baseDir;
      
      if (Platform.isAndroid) {
        // محاولة استخدام External Storage أولاً
        final externalDirs = await getExternalStorageDirectories();
        if (externalDirs != null && externalDirs.isNotEmpty) {
          baseDir = externalDirs.first;
        } else {
          // fallback إلى Application Documents Directory
          baseDir = await getApplicationDocumentsDirectory();
        }
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }

      _backupDirectory = Directory('${baseDir.path}/$_backupFolderName');
      
      if (!await _backupDirectory!.exists()) {
        await _backupDirectory!.create(recursive: true);
        debugPrint('✅ تم إنشاء مجلد النسخ الاحتياطي: ${_backupDirectory!.path}');
      }

      // حفظ مسار المجلد في التفضيلات
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLocalBackupPathKey, _backupDirectory!.path);

      return _backupDirectory!;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء مجلد النسخ الاحتياطي: $e');
      rethrow;
    }
  }

  /// إنشاء نسخة احتياطية محلية
  Future<String> createLocalBackup() async {
    try {
      debugPrint('🔄 بدء إنشاء نسخة احتياطية محلية...');

      // التحقق من الأذونات
      final hasPermission = await checkPermissions();
      if (!hasPermission) {
        throw Exception('لا توجد أذونات للوصول للتخزين المحلي');
      }

      // الحصول على مجلد النسخ
      final backupDir = await getBackupDirectory();

      // تصدير البيانات (نفس طريقة Google Drive)
      final db = getDatabase();
      
      final roomsData = await db.select(db.rooms).get();
      final bookingsData = await db.select(db.bookings).get();
      final bookingNotesData = await db.select(db.bookingNotes).get();
      final employeesData = await db.select(db.employees).get();
      final expensesData = await db.select(db.expenses).get();
      final cashTransactionsData = await db.select(db.cashTransactions).get();
      final paymentsData = await db.select(db.payments).get();
      final syncStateData = await db.select(db.syncState).get();

      final totalRecords = roomsData.length + 
                          bookingsData.length + 
                          bookingNotesData.length + 
                          employeesData.length + 
                          expensesData.length + 
                          cashTransactionsData.length + 
                          paymentsData.length;

      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: 3,
        backupTimestamp: DateTime.now(),
        totalRecords: totalRecords,
        deviceInfo: Platform.isAndroid ? 'Android Local' : 'iOS Local',
      );

      final backupData = {
        'metadata': metadata.toJson(),
        'rooms': roomsData.map((room) => room.toJson()).toList(),
        'bookings': bookingsData.map((booking) => booking.toJson()).toList(),
        'booking_notes': bookingNotesData.map((note) => note.toJson()).toList(),
        'employees': employeesData.map((employee) => employee.toJson()).toList(),
        'expenses': expensesData.map((expense) => expense.toJson()).toList(),
        'cash_transactions': cashTransactionsData.map((transaction) => transaction.toJson()).toList(),
        'payments': paymentsData.map((payment) => payment.toJson()).toList(),
        'sync_state': syncStateData.isNotEmpty ? syncStateData.first.toJson() : {},
      };

      // إنشاء اسم الملف
      final timestamp = DateTime.now();
      final fileName = '$_backupFilePrefix${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.json';
      final filePath = '${backupDir.path}/$fileName';

      // كتابة الملف
      final file = File(filePath);
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      await file.writeAsString(jsonString);

      // حفظ وقت آخر نسخة احتياطية
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLastLocalBackupKey, timestamp.toIso8601String());

      debugPrint('✅ تم إنشاء النسخة الاحتياطية المحلية: $filePath');
      debugPrint('📊 السجلات المحفوظة: $totalRecords');
      debugPrint('📁 حجم الملف: ${await file.length()} بايت');

      return filePath;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النسخة الاحتياطية المحلية: $e');
      rethrow;
    }
  }

  /// عرض قائمة النسخ الاحتياطية المحلية
  Future<List<LocalBackupFile>> listLocalBackups() async {
    try {
      final backupDir = await getBackupDirectory();
      
      if (!await backupDir.exists()) {
        return [];
      }

      final files = backupDir
          .listSync()
          .where((entity) => 
              entity is File && 
              entity.path.endsWith('.json') && 
              entity.path.contains(_backupFilePrefix))
          .map((entity) => entity as File)
          .toList();

      final backupFiles = <LocalBackupFile>[];

      for (final file in files) {
        try {
          final backupFile = LocalBackupFile.fromFile(file);
          
          // محاولة قراءة metadata من الملف
          final content = await file.readAsString();
          final jsonData = jsonDecode(content) as Map<String, dynamic>;
          
          if (jsonData.containsKey('metadata')) {
            final metadata = BackupMetadata.fromJson(jsonData['metadata']);
            backupFiles.add(LocalBackupFile(
              fileName: backupFile.fileName,
              filePath: backupFile.filePath,
              createdTime: backupFile.createdTime,
              sizeBytes: backupFile.sizeBytes,
              metadata: metadata,
            ));
          } else {
            backupFiles.add(backupFile);
          }
        } catch (e) {
          debugPrint('⚠️ خطأ في قراءة ملف النسخة الاحتياطية ${file.path}: $e');
          // إضافة الملف حتى لو فشلت قراءة metadata
          backupFiles.add(LocalBackupFile.fromFile(file));
        }
      }

      // ترتيب حسب تاريخ الإنشاء (الأحدث أولاً)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      debugPrint('✅ تم جلب ${backupFiles.length} نسخة احتياطية محلية');
      return backupFiles;
    } catch (e) {
      debugPrint('❌ خطأ في جلب قائمة النسخ الاحتياطية المحلية: $e');
      return [];
    }
  }

  /// استعادة من نسخة احتياطية محلية
  Future<void> restoreFromLocalBackup(String filePath) async {
    try {
      debugPrint('🔄 بدء استعادة النسخة الاحتياطية من: $filePath');

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('ملف النسخة الاحتياطية غير موجود');
      }

      // قراءة محتوى الملف
      final jsonString = await file.readAsString();
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      // التحقق من البيانات الوصفية
      if (!backupData.containsKey('metadata')) {
        throw Exception('النسخة الاحتياطية لا تحتوي على بيانات وصفية');
      }

      final metadata = BackupMetadata.fromJson(backupData['metadata']);
      
      // التحقق من توافق إصدار قاعدة البيانات
      if (metadata.databaseVersion > 3) {
        throw Exception('إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي');
      }

      debugPrint('🔄 بدء استعادة البيانات...');

      final db = getDatabase();

      // مسح البيانات الموجودة (عدا Outbox)
      await db.delete(db.rooms).go();
      await db.delete(db.bookings).go();
      await db.delete(db.bookingNotes).go();
      await db.delete(db.employees).go();
      await db.delete(db.expenses).go();
      await db.delete(db.cashTransactions).go();
      await db.delete(db.payments).go();
      await db.delete(db.syncState).go();

      // استعادة البيانات
      if (backupData.containsKey('rooms')) {
        final roomsData = backupData['rooms'] as List<dynamic>;
        for (final roomJson in roomsData) {
          await db.into(db.rooms).insert(Room.fromJson(roomJson));
        }
      }

      if (backupData.containsKey('bookings')) {
        final bookingsData = backupData['bookings'] as List<dynamic>;
        for (final bookingJson in bookingsData) {
          await db.into(db.bookings).insert(Booking.fromJson(bookingJson));
        }
      }

      if (backupData.containsKey('booking_notes')) {
        final notesData = backupData['booking_notes'] as List<dynamic>;
        for (final noteJson in notesData) {
          await db.into(db.bookingNotes).insert(BookingNote.fromJson(noteJson));
        }
      }

      if (backupData.containsKey('employees')) {
        final employeesData = backupData['employees'] as List<dynamic>;
        for (final employeeJson in employeesData) {
          await db.into(db.employees).insert(Employee.fromJson(employeeJson));
        }
      }

      if (backupData.containsKey('expenses')) {
        final expensesData = backupData['expenses'] as List<dynamic>;
        for (final expenseJson in expensesData) {
          await db.into(db.expenses).insert(Expense.fromJson(expenseJson));
        }
      }

      if (backupData.containsKey('cash_transactions')) {
        final transactionsData = backupData['cash_transactions'] as List<dynamic>;
        for (final transactionJson in transactionsData) {
          await db.into(db.cashTransactions).insert(CashTransaction.fromJson(transactionJson));
        }
      }

      if (backupData.containsKey('payments')) {
        final paymentsData = backupData['payments'] as List<dynamic>;
        for (final paymentJson in paymentsData) {
          await db.into(db.payments).insert(Payment.fromJson(paymentJson));
        }
      }

      if (backupData.containsKey('sync_state') && 
          backupData['sync_state'] is Map && 
          (backupData['sync_state'] as Map).isNotEmpty) {
        await db.into(db.syncState).insert(SyncStateData.fromJson(backupData['sync_state']));
      }

      debugPrint('✅ تم استعادة ${metadata.totalRecords} سجل بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في استعادة البيانات من النسخة المحلية: $e');
      rethrow;
    }
  }

  /// مشاركة نسخة احتياطية
  Future<void> shareBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('ملف النسخة الاحتياطية غير موجود');
      }

      final fileName = filePath.split('/').last;
      
      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'نسخة احتياطية - تطبيق مارينا هوتيل',
        text: 'نسخة احتياطية من بيانات تطبيق مارينا هوتيل\nاسم الملف: $fileName',
      );
      
      debugPrint('✅ تم مشاركة النسخة الاحتياطية: $fileName');
    } catch (e) {
      debugPrint('❌ خطأ في مشاركة النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// استيراد نسخة احتياطية من ملف خارجي
  Future<String> importBackupFromFile() async {
    try {
      debugPrint('🔄 بدء استيراد نسخة احتياطية من ملف خارجي...');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        throw Exception('لم يتم اختيار ملف');
      }

      final pickedFile = result.files.first;
      if (pickedFile.path == null) {
        throw Exception('مسار الملف غير صحيح');
      }

      final sourceFile = File(pickedFile.path!);
      
      // التحقق من أن الملف نسخة احتياطية صالحة
      final content = await sourceFile.readAsString();
      final jsonData = jsonDecode(content) as Map<String, dynamic>;
      
      if (!jsonData.containsKey('metadata')) {
        throw Exception('الملف المختار ليس نسخة احتياطية صالحة');
      }

      // نسخ الملف إلى مجلد النسخ الاحتياطية
      final backupDir = await getBackupDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newFileName = 'imported_backup_$timestamp.json';
      final newFilePath = '${backupDir.path}/$newFileName';
      
      await sourceFile.copy(newFilePath);

      debugPrint('✅ تم استيراد النسخة الاحتياطية: $newFilePath');
      return newFilePath;
    } catch (e) {
      debugPrint('❌ خطأ في استيراد النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// حذف نسخة احتياطية محلية
  Future<void> deleteLocalBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('✅ تم حذف النسخة الاحتياطية: $filePath');
      }
    } catch (e) {
      debugPrint('❌ خطأ في حذف النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// تصدير نسخة احتياطية إلى مجلد Downloads
  Future<String> exportToDownloads() async {
    try {
      debugPrint('🔄 تصدير نسخة احتياطية إلى مجلد Downloads...');

      // إنشاء النسخة الاحتياطية أولاً
      await createLocalBackup();

      // البحث عن أحدث نسخة
      final backups = await listLocalBackups();
      if (backups.isEmpty) {
        throw Exception('لا توجد نسخ احتياطية متاحة');
      }

      final latestBackup = backups.first;
      
      // محاولة الحصول على مجلد Downloads
      Directory? downloadsDir;
      
      if (Platform.isAndroid) {
        // محاولة الوصول لـ Downloads directory
        final externalDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (externalDirs != null && externalDirs.isNotEmpty) {
          downloadsDir = externalDirs.first;
        } else {
          // fallback إلى external storage
          final externalStorage = await getExternalStorageDirectories();
          if (externalStorage != null && externalStorage.isNotEmpty) {
            downloadsDir = Directory('${externalStorage.first.parent.parent.parent.parent.path}/Download');
          }
        }
      }
      
      if (downloadsDir == null) {
        // استخدام مجلد التطبيق كـ fallback
        downloadsDir = await getBackupDirectory();
      }

      // نسخ الملف
      final sourceFile = File(latestBackup.filePath);
      final timestamp = DateTime.now();
      final exportFileName = 'marina_hotel_export_${timestamp.toIso8601String().split('T')[0]}.json';
      final exportPath = '${downloadsDir.path}/$exportFileName';
      
      await sourceFile.copy(exportPath);
      
      debugPrint('✅ تم تصدير النسخة الاحتياطية إلى: $exportPath');
      return exportPath;
    } catch (e) {
      debugPrint('❌ خطأ في تصدير النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// إعدادات النسخ التلقائي المحلي
  Future<void> setAutoLocalBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoLocalBackupKey, enabled);
  }

  Future<bool> isAutoLocalBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsAutoLocalBackupKey) ?? false;
  }

  Future<void> setAutoLocalBackupFrequency(String frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAutoLocalBackupFrequencyKey, frequency);
  }

  Future<String> getAutoLocalBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsAutoLocalBackupFrequencyKey) ?? 'daily';
  }

  /// الحصول على وقت آخر نسخة احتياطية محلية
  Future<DateTime?> getLastLocalBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString(_prefsLastLocalBackupKey);
    return timeString != null ? DateTime.parse(timeString) : null;
  }

  /// تنظيف النسخ القديمة (الاحتفاظ بآخر 10 نسخ فقط)
  Future<void> cleanOldBackups({int keepCount = 10}) async {
    try {
      final backups = await listLocalBackups();
      
      if (backups.length <= keepCount) {
        return; // لا حاجة للتنظيف
      }

      // ترتيب حسب التاريخ (الأحدث أولاً) وحذف القديم
      backups.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      
      final backupsToDelete = backups.skip(keepCount).toList();
      
      for (final backup in backupsToDelete) {
        await deleteLocalBackup(backup.filePath);
      }
      
      debugPrint('✅ تم تنظيف ${backupsToDelete.length} نسخة احتياطية قديمة');
    } catch (e) {
      debugPrint('❌ خطأ في تنظيف النسخ القديمة: $e');
    }
  }

  /// تقدير حجم جميع النسخ المحلية
  Future<int> getTotalBackupsSize() async {
    try {
      final backups = await listLocalBackups();
      return backups.fold<int>(0, (total, backup) => total + backup.sizeBytes);
    } catch (e) {
      debugPrint('❌ خطأ في حساب حجم النسخ: $e');
      return 0;
    }
  }

  /// الحصول على معلومات مجلد النسخ الاحتياطي
  Future<Map<String, dynamic>> getBackupFolderInfo() async {
    try {
      final backupDir = await getBackupDirectory();
      final backups = await listLocalBackups();
      final totalSize = await getTotalBackupsSize();
      
      return {
        'path': backupDir.path,
        'exists': await backupDir.exists(),
        'backups_count': backups.length,
        'total_size_bytes': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      debugPrint('❌ خطأ في الحصول على معلومات مجلد النسخ: $e');
      return {};
    }
  }
}