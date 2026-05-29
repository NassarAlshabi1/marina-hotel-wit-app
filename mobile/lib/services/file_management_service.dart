import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'local_backup_service.dart';

class FileManagementService {
  static const String _exportFolderName = 'MarinaHotelExports';

  /// تصدير البيانات بتنسيقات متعددة
  Future<String> exportToCSV() async {
    try {
      debugPrint('📊 بدء تصدير البيانات إلى CSV...');

      // الحصول على مجلد التصدير
      final exportDir = await _getExportDirectory();

      // تصدير كل جدول إلى CSV منفصل
      final timestamp = DateTime.now();
      final folderName =
          'marina_hotel_csv_export_${timestamp.millisecondsSinceEpoch}';
      final csvFolder = Directory('${exportDir.path}/$folderName');
      await csvFolder.create(recursive: true);

      // تصدير الجداول
      await _exportTableToCSV(csvFolder, 'rooms', 'rooms');
      await _exportTableToCSV(csvFolder, 'bookings', 'bookings');
      await _exportTableToCSV(csvFolder, 'booking_notes', 'booking_notes');
      await _exportTableToCSV(csvFolder, 'employees', 'employees');
      await _exportTableToCSV(csvFolder, 'expenses', 'expenses');
      await _exportTableToCSV(
        csvFolder,
        'cash_transactions',
        'cash_transactions',
      );
      await _exportTableToCSV(csvFolder, 'payments', 'payments');

      debugPrint('✅ تم تصدير البيانات إلى: ${csvFolder.path}');
      return csvFolder.path;
    } catch (e) {
      debugPrint('❌ خطأ في تصدير البيانات إلى CSV: $e');
      rethrow;
    }
  }

  /// تصدير تقرير شامل بتنسيق JSON قابل للقراءة
  Future<String> exportReadableReport() async {
    try {
      debugPrint('📋 بدء تصدير التقرير الشامل...');

      final exportDir = await _getExportDirectory();
      final timestamp = DateTime.now();

      // إنشاء البيانات الخلاصة من قاعدة البيانات المحلية
      final db = LocalBackupService();
      final backupData = await db.exportDatabaseToJson();

      // إنشاء تقرير قابل للقراءة
      final report = {
        'تقرير_مارينا_هوتيل': {
          'معلومات_عامة': {
            'تاريخ_التقرير': timestamp.toIso8601String(),
            'إجمالي_السجلات': backupData['metadata']['total_records'],
          },
          'ملخص_البيانات': {
            'عدد_الغرف': (backupData['rooms'] as List).length,
            'عدد_الحجوزات': (backupData['bookings'] as List).length,
            'عدد_الموظفين': (backupData['employees'] as List).length,
            'عدد_المصروفات': (backupData['expenses'] as List).length,
            'عدد_المدفوعات': (backupData['payments'] as List).length,
            'عدد_المعاملات_النقدية':
                (backupData['cash_transactions'] as List).length,
          },
          'بيانات_مفصلة': backupData,
        },
      };

      final fileName =
          'marina_hotel_report_${timestamp.toIso8601String().split('T')[0]}.json';
      final filePath = '${exportDir.path}/$fileName';

      final file = File(filePath);
      final jsonString = const JsonEncoder.withIndent('  ').convert(report);
      await file.writeAsString(jsonString);

      debugPrint('✅ تم إنشاء التقرير الشامل: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء التقرير الشامل: $e');
      rethrow;
    }
  }

  /// مشاركة متعددة الملفات
  Future<void> shareMultipleFiles(
    List<String> filePaths, {
    String? customMessage,
  }) async {
    try {
      if (filePaths.isEmpty) {
        throw Exception('لا توجد ملفات للمشاركة');
      }

      final xFiles = filePaths.map(XFile.new).toList();

      await Share.shareXFiles(
        xFiles,
        subject: 'ملفات مارينا هوتيل',
        text:
            customMessage ??
            'ملفات مُصدرة من تطبيق مارينا هوتيل لإدارة الفنادق',
      );

      debugPrint('✅ تم مشاركة ${filePaths.length} ملف');
    } catch (e) {
      debugPrint('❌ خطأ في مشاركة الملفات: $e');
      rethrow;
    }
  }

  /// استيراد ملفات متعددة
  Future<List<String>> importMultipleFiles({
    FileType fileType = FileType.custom,
    List<String>? allowedExtensions,
  }) async {
    try {
      debugPrint('📁 بدء استيراد ملفات متعددة...');

      final result = await FilePicker.platform.pickFiles(
        type: fileType,
        allowedExtensions: allowedExtensions ?? ['json', 'csv'],
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        return [];
      }

      final importedPaths = <String>[];
      final importDir = await _getImportDirectory();

      for (final pickedFile in result.files) {
        if (pickedFile.path != null) {
          final sourceFile = File(pickedFile.path!);
          final targetPath = '${importDir.path}/${pickedFile.name}';

          await sourceFile.copy(targetPath);
          importedPaths.add(targetPath);
        }
      }

      debugPrint('✅ تم استيراد ${importedPaths.length} ملف');
      return importedPaths;
    } catch (e) {
      debugPrint('❌ خطأ في استيراد الملفات: $e');
      rethrow;
    }
  }

  /// تنظيم الملفات بحسب التاريخ
  Future<Map<String, List<String>>> organizeBackupsByDate(
    List<String> backupPaths,
  ) async {
    final organized = <String, List<String>>{};

    for (final path in backupPaths) {
      try {
        final file = File(path);
        if (!file.existsSync()) {
          continue;
        }

        final stat = await file.stat();
        final dateKey =
            '${stat.modified.year}-${stat.modified.month.toString().padLeft(2, '0')}-${stat.modified.day.toString().padLeft(2, '0')}';

        organized.putIfAbsent(dateKey, () => []).add(path);
      } catch (e) {
        debugPrint('⚠️ خطأ في معالجة ملف $path: $e');
      }
    }

    return organized;
  }

  /// ضغط ملفات متعددة (محاكاة ZIP)
  Future<String> createArchive(
    List<String> filePaths,
    String archiveName,
  ) async {
    try {
      debugPrint('📦 إنشاء أرشيف: $archiveName');

      final exportDir = await _getExportDirectory();
      final archiveFolder = Directory('${exportDir.path}/$archiveName');
      await archiveFolder.create(recursive: true);

      for (int i = 0; i < filePaths.length; i++) {
        final sourcePath = filePaths[i];
        final sourceFile = File(sourcePath);

        if (sourceFile.existsSync()) {
          final fileName = sourceFile.path.split('/').last;
          final targetPath = '${archiveFolder.path}/${i + 1}_$fileName';
          await sourceFile.copy(targetPath);
        }
      }

      // إنشاء ملف index للأرشيف
      final indexFile = File('${archiveFolder.path}/index.txt');
      final indexContent = filePaths
          .asMap()
          .entries
          .map((entry) => '${entry.key + 1}. ${entry.value.split('/').last}')
          .join('\n');
      await indexFile.writeAsString(
        'محتويات أرشيف مارينا هوتيل\n\n$indexContent',
      );

      debugPrint('✅ تم إنشاء الأرشيف: ${archiveFolder.path}');
      return archiveFolder.path;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الأرشيف: $e');
      rethrow;
    }
  }

  /// تحليل وإحصائيات الملفات
  Future<Map<String, dynamic>> analyzeBackupFiles() async {
    try {
      final localService = LocalBackupService();
      final localBackups = await localService.listLocalBackups();

      if (localBackups.isEmpty) {
        return {
          'total_files': 0,
          'total_size_bytes': 0,
          'oldest_backup': null,
          'newest_backup': null,
          'average_size': 0,
        };
      }

      final totalSize = localBackups.fold<int>(
        0,
        (sum, backup) => sum + backup.sizeBytes,
      );
      final averageSize = totalSize / localBackups.length;

      localBackups.sort((a, b) => a.createdTime.compareTo(b.createdTime));

      return {
        'total_files': localBackups.length,
        'total_size_bytes': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'oldest_backup': localBackups.first.createdTime.toIso8601String(),
        'newest_backup': localBackups.last.createdTime.toIso8601String(),
        'average_size_mb': (averageSize / (1024 * 1024)).toStringAsFixed(2),
        'files_by_month': _groupFilesByMonth(localBackups),
      };
    } catch (e) {
      debugPrint('❌ خطأ في تحليل الملفات: $e');
      return {};
    }
  }

  Map<String, int> _groupFilesByMonth(List<LocalBackupFile> backups) {
    final byMonth = <String, int>{};

    for (final backup in backups) {
      final monthKey =
          '${backup.createdTime.year}-${backup.createdTime.month.toString().padLeft(2, '0')}';
      byMonth[monthKey] = (byMonth[monthKey] ?? 0) + 1;
    }

    return byMonth;
  }

  /// الحصول على مجلد التصدير
  Future<Directory> _getExportDirectory() async {
    Directory baseDir;

    if (Platform.isAndroid) {
      final externalDirs = await getExternalStorageDirectories();
      if (externalDirs != null && externalDirs.isNotEmpty) {
        baseDir = externalDirs.first;
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final exportDir = Directory('${baseDir.path}/$_exportFolderName');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }

    return exportDir;
  }

  /// الحصول على مجلد الاستيراد
  Future<Directory> _getImportDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final importDir = Directory('${baseDir.path}/imports');

    if (!importDir.existsSync()) {
      await importDir.create(recursive: true);
    }

    return importDir;
  }

  /// تصدير جدول واحد إلى CSV
  Future<void> _exportTableToCSV(
    Directory csvFolder,
    String tableName,
    String tableKey,
  ) async {
    try {
      // الحصول على البيانات من قاعدة البيانات المحلية
      final db = LocalBackupService();
      final backupData = await db.exportDatabaseToJson();

      if (!backupData.containsKey(tableKey) || backupData[tableKey] is! List) {
        debugPrint('⚠️ لا توجد بيانات للجدول: $tableName');
        return;
      }

      final tableData = backupData[tableKey] as List<dynamic>;
      if (tableData.isEmpty) {
        debugPrint('⚠️ الجدول $tableName فارغ');
        return;
      }

      // إنشاء CSV
      final csvFile = File('${csvFolder.path}/$tableName.csv');
      final csvContent = StringBuffer();

      // إضافة العناوين
      final firstRow = tableData.first as Map<String, dynamic>;
      final headers = firstRow.keys
          .map(_translateColumnName)
          .join(',');
      csvContent.writeln(headers);

      // إضافة البيانات
      for (final row in tableData) {
        final values = (row as Map<String, dynamic>).values
            .map((value) => _escapeCsvValue(value?.toString() ?? ''))
            .join(',');
        csvContent.writeln(values);
      }

      await csvFile.writeAsString(csvContent.toString());
      debugPrint('✅ تم تصدير جدول $tableName إلى CSV');
    } catch (e) {
      debugPrint('❌ خطأ في تصدير الجدول $tableName: $e');
    }
  }

  /// ترجمة أسماء الأعمدة للعربية
  String _translateColumnName(String columnName) {
    final translations = {
      'id': 'المعرف',
      'roomNumber': 'رقم_الغرفة',
      'type': 'النوع',
      'price': 'السعر',
      'status': 'الحالة',
      'guestName': 'اسم_الضيف',
      'guestPhone': 'هاتف_الضيف',
      'checkinDate': 'تاريخ_الوصول',
      'checkoutDate': 'تاريخ_المغادرة',
      'name': 'الاسم',
      'basicSalary': 'الراتب_الأساسي',
      'position': 'المنصب',
      'amount': 'المبلغ',
      'description': 'الوصف',
      'date': 'التاريخ',
      'paymentMethod': 'طريقة_الدفع',
      'transactionType': 'نوع_المعاملة',
      'createdAt': 'تاريخ_الإنشاء',
      'updatedAt': 'تاريخ_التحديث',
    };

    return translations[columnName] ?? columnName;
  }

  /// تنظيف قيم CSV من المحارف الخاصة
  String _escapeCsvValue(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// دمج نسخ متعددة
  Future<String> mergeBackupFiles(
    List<String> backupPaths,
    String mergedFileName,
  ) async {
    try {
      debugPrint('🔗 بدء دمج ${backupPaths.length} نسخة احتياطية...');

      final mergedData = <String, List<dynamic>>{
        'rooms': [],
        'bookings': [],
        'booking_notes': [],
        'employees': [],
        'expenses': [],
        'cash_transactions': [],
        'payments': [],
      };

      BackupMetadata? latestMetadata;
      int totalRecords = 0;

      for (final backupPath in backupPaths) {
        try {
          final file = File(backupPath);
          final content = await file.readAsString();
          final backupData = jsonDecode(content) as Map<String, dynamic>;

          // دمج البيانات
          for (final key in mergedData.keys) {
            if (backupData.containsKey(key) && backupData[key] is List) {
              final tableData = backupData[key] as List<dynamic>;
              for (final record in tableData) {
                // تجنب التكرار باستخدام localUuid
                final recordMap = record as Map<String, dynamic>;
                final uuid = recordMap['localUuid'];

                if (uuid != null) {
                  final exists = mergedData[key]!.any(
                    (existing) =>
                        existing is Map && existing['localUuid'] == uuid,
                  );

                  if (!exists) {
                    mergedData[key]!.add(record);
                    totalRecords++;
                  }
                }
              }
            }
          }

          // تحديث metadata
          if (backupData.containsKey('metadata')) {
            final metadataSource = backupData['metadata'];
            if (metadataSource is Map) {
              final metadata = BackupMetadata.fromJson(
                Map<String, dynamic>.from(metadataSource),
              );
              if (latestMetadata == null ||
                  metadata.backupTimestamp.isAfter(
                    latestMetadata.backupTimestamp,
                  )) {
                latestMetadata = metadata;
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ خطأ في معالجة الملف $backupPath: $e');
        }
      }

      // إنشاء البيانات المدمجة
      final mergedBackup = {
        'metadata': {
          'app_version': latestMetadata?.appVersion ?? '1.2.0+3',
          'database_version': latestMetadata?.databaseVersion ?? 3,
          'backup_timestamp': DateTime.now().toIso8601String(),
          'total_records': totalRecords,
          'device_info': 'Merged Backup',
          'source_files': backupPaths.length,
        },
        ...mergedData,
      };

      // حفظ الملف المدمج
      final exportDir = await _getExportDirectory();
      final mergedPath = '${exportDir.path}/$mergedFileName';
      final mergedFile = File(mergedPath);

      final jsonString = const JsonEncoder.withIndent(
        '  ',
      ).convert(mergedBackup);
      await mergedFile.writeAsString(jsonString);

      debugPrint('✅ تم دمج النسخ بنجاح: $mergedPath');
      debugPrint('📊 إجمالي السجلات المدمجة: $totalRecords');

      return mergedPath;
    } catch (e) {
      debugPrint('❌ خطأ في دمج النسخ الاحتياطية: $e');
      rethrow;
    }
  }

  /// تحويل النسخة الاحتياطية إلى تنسيق قابل للقراءة البشرية
  Future<String> convertToHumanReadable(String backupPath) async {
    try {
      final file = File(backupPath);
      final content = await file.readAsString();
      final backupData = jsonDecode(content) as Map<String, dynamic>;

      final readableContent = StringBuffer();

      // معلومات عامة
      readableContent.writeln('=== تقرير مارينا هوتيل ===\n');

      if (backupData.containsKey('metadata')) {
        final metadata = backupData['metadata'];
        readableContent.writeln('📋 معلومات النسخة الاحتياطية:');
        readableContent.writeln('   إصدار التطبيق: ${metadata['app_version']}');
        readableContent.writeln(
          '   تاريخ النسخة: ${metadata['backup_timestamp']}',
        );
        readableContent.writeln(
          '   إجمالي السجلات: ${metadata['total_records']}',
        );
        readableContent.writeln(
          '   معلومات الجهاز: ${metadata['device_info']}\n',
        );
      }

      // تفاصيل كل جدول
      final tables = {
        'rooms': '🏨 الغرف',
        'bookings': '📅 الحجوزات',
        'employees': '👥 الموظفين',
        'expenses': '💰 المصروفات',
        'payments': '💳 المدفوعات',
        'cash_transactions': '💵 المعاملات النقدية',
      };

      for (final entry in tables.entries) {
        final key = entry.key;
        final title = entry.value;

        if (backupData.containsKey(key) && backupData[key] is List) {
          final data = backupData[key] as List<dynamic>;
          readableContent.writeln('$title (${data.length} سجل):');

          if (data.isNotEmpty) {
            for (int i = 0; i < data.length && i < 5; i++) {
              final record = data[i] as Map<String, dynamic>;
              readableContent.writeln(
                '   ${i + 1}. ${_formatRecordForDisplay(record, key)}',
              );
            }

            if (data.length > 5) {
              readableContent.writeln(
                '   ... وسجلات أخرى (${data.length - 5})',
              );
            }
          }

          readableContent.writeln();
        }
      }

      // حفظ التقرير القابل للقراءة
      final exportDir = await _getExportDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final readablePath =
          '${exportDir.path}/marina_hotel_readable_$timestamp.txt';

      final readableFile = File(readablePath);
      await readableFile.writeAsString(readableContent.toString());

      debugPrint('✅ تم تحويل النسخة إلى تنسيق قابل للقراءة: $readablePath');
      return readablePath;
    } catch (e) {
      debugPrint('❌ خطأ في تحويل النسخة إلى تنسيق قابل للقراءة: $e');
      rethrow;
    }
  }

  String _formatRecordForDisplay(
    Map<String, dynamic> record,
    String tableType,
  ) {
    switch (tableType) {
      case 'rooms':
        return 'غرفة ${record['roomNumber'] ?? 'N/A'} - ${record['type'] ?? 'N/A'} - ${record['price'] ?? 'N/A'}';
      case 'bookings':
        return '${record['guestName'] ?? 'N/A'} - غرفة ${record['roomNumber'] ?? 'N/A'} - ${record['checkinDate'] ?? 'N/A'}';
      case 'employees':
        return '${record['name'] ?? 'N/A'} - ${record['position'] ?? 'N/A'} - ${record['basicSalary'] ?? 'N/A'}';
      case 'expenses':
        return '${record['description'] ?? 'N/A'} - ${record['amount'] ?? 'N/A'} - ${record['date'] ?? 'N/A'}';
      case 'payments':
        return 'دفعة ${record['amount'] ?? 'N/A'} - ${record['paymentMethod'] ?? 'N/A'} - ${record['paymentDate'] ?? 'N/A'}';
      case 'cash_transactions':
        return '${record['transactionType'] ?? 'N/A'} - ${record['amount'] ?? 'N/A'} - ${record['description'] ?? 'N/A'}';
      default:
        return record.toString();
    }
  }

  /// تنظيف الملفات المؤقتة
  Future<void> cleanupTempFiles() async {
    try {
      final importDir = await _getImportDirectory();
      final exportDir = await _getExportDirectory();

      // حذف ملفات الاستيراد الأقدم من 7 أيام
      await _cleanDirectoryOlderThan(importDir, const Duration(days: 7));

      // حذف ملفات التصدير الأقدم من 3 أيام
      await _cleanDirectoryOlderThan(exportDir, const Duration(days: 3));

      debugPrint('✅ تم تنظيف الملفات المؤقتة');
    } catch (e) {
      debugPrint('❌ خطأ في تنظيف الملفات المؤقتة: $e');
    }
  }

  Future<void> _cleanDirectoryOlderThan(
    Directory dir,
    Duration duration,
  ) async {
    if (!dir.existsSync()) {
      return;
    }

    final cutoffTime = DateTime.now().subtract(duration);

    final entities = dir.listSync();
    for (final entity in entities) {
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoffTime)) {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        }
      } catch (e) {
        debugPrint('⚠️ خطأ في حذف ${entity.path}: $e');
      }
    }
  }
}
