// lib/services/backup_data_service.dart
//
// ✅ (2026-09-17) خدمة تصدير/تحقق بيانات النسخ الاحتياطي المحلية المشتركة.
//
// وُلدت هذه الخدمة من إزالة نظام Google Drive كاملاً بطلب المستخدم
// («مزامنة appwrite و sync google drive لا احتاجها نهائياً»): كانت أدوات
// التصدير والتحقق (BackupFormat/BackupMetadata/checksum/exportDatabaseToJson)
// تعيش داخل GoogleDriveBackupService رغم أنها لا تمسّ Drive إطلاقاً —
// يستخدمها النسخ المحلي والتصدير CSV والتقارير. نُقلت هنا كما هي
// (نفس المنطق حرفياً) لتخدم النسخ المحلي دون أي اعتماد سحابي.
//
// المستهلكون: local_backup_service.dart / file_management_service.dart /
// backup_provider.dart / test/unit/backup_restore_test.dart.

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import 'backup_serializers.dart';
import 'local_db.dart';

/// صيغة النسخة الاحتياطية (نفس القيم التاريخية — توافق بيانات التركيبات).
enum BackupFormat { json, sqlite }

/// البيانات الوصفية للنسخة الاحتياطية (نفس الحقول التاريخية).
class BackupMetadata {
  BackupMetadata({
    required this.appVersion,
    required this.databaseVersion,
    required this.backupTimestamp,
    required this.totalRecords,
    required this.deviceInfo,
    this.format = BackupFormat.json,
    this.dataHash,
  });

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    final rawFormat = json['format'] as String?;
    // Handle 'db' format as sqlite
    final formatName = rawFormat == 'db' ? 'sqlite' : rawFormat;
    final format = BackupFormat.values.firstWhere(
      (value) => value.name == formatName,
      orElse: () => BackupFormat.json,
    );
    return BackupMetadata(
      appVersion: (json['app_version'] as String?) ?? '',
      databaseVersion: (json['database_version'] as num?)?.toInt() ?? 1,
      backupTimestamp: DateTime.parse(json['backup_timestamp'] as String),
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      deviceInfo: (json['device_info'] as String?) ?? '',
      format: format,
      dataHash: json['data_hash'] as String?,
    );
  }
  final String appVersion;
  final int databaseVersion;
  final DateTime backupTimestamp;
  final int totalRecords;
  final String deviceInfo;
  final BackupFormat format;

  /// تجزئة SHA-256 للتحقق من سلامة بيانات النسخة الاحتياطية
  final String? dataHash;

  Map<String, dynamic> toJson() => {
    'app_version': appVersion,
    'database_version': databaseVersion,
    'backup_timestamp': backupTimestamp.toIso8601String(),
    'total_records': totalRecords,
    'device_info': deviceInfo,
    'format': format.name,
    if (dataHash != null) 'data_hash': dataHash,
  };
}

/// خدمة تصدير بيانات قاعدة البيانات المحلية وتقدير حجمها والتحقق من
/// سلامة النسخ — بلا أي اعتماد على أي سحابة.
class BackupDataService {
  BackupDataService._();
  static final BackupDataService instance = BackupDataService._();

  /// بادئة اسم ملف النسخة الكاملة (تُستخدم من النسخ المحلي sqlite).
  static const String fullBackupPrefix = 'marina_backup_full_';

  /// تصدير قاعدة البيانات المحلية إلى خريطة JSON قابلة للنسخ/الاستعادة.
  ///
  /// نفس منطق GoogleDriveBackupService.exportDatabaseToJson التاريخي
  /// (التحميل على دفعات + الإثراء بـ UUID للFK + SHA-256 داخل isolate واحد).
  Future<Map<String, dynamic>> exportDatabaseToJson() async {
    try {
      final db = DatabaseManager.instance;

      // تحميل البيانات على دفعات لتجنب استهلاك الذاكرة في قواعد كبيرة
      final roomsData = await _loadTableBatched<Room>(db.rooms);
      final bookingsData = await _loadTableBatched<Booking>(db.bookings);
      final bookingNotesData = await _loadTableBatched<BookingNote>(
        db.bookingNotes,
      );
      final bookingNightsData = await _loadTableBatched<BookingNight>(
        db.bookingNights,
      );
      final ledgerData = await _loadTableBatched<HotelDayLedgerEntry>(
        db.hotelDayLedger,
      );
      final shiftNotesData = await _loadTableBatched<ShiftNote>(db.shiftNotes);
      final employeesData = await _loadTableBatched<Employee>(db.employees);
      final expensesData = await _loadTableBatched<Expense>(db.expenses);
      final cashTransactionsData = await _loadTableBatched<CashTransaction>(
        db.cashTransactions,
      );
      final paymentsData = await _loadTableBatched<Payment>(db.payments);
      final debtsData = await _loadTableBatched<Debt>(db.debts);
      final salaryCyclesData = await _loadTableBatched<SalaryCycle>(
        db.salaryCycles,
      );
      final salaryPaymentsData = await _loadTableBatched<SalaryPayment>(
        db.salaryPayments,
      );
      final priceAdjustmentsData = await _loadTableBatched<PriceAdjustment>(
        db.priceAdjustments,
      );
      final bookingPriceAdjData =
          await _loadTableBatched<BookingPriceAdjustment>(
            db.bookingPriceAdjustments,
          );
      final auditLogsData = await _loadTableBatched<AuditLog>(db.auditLogs);
      final paymentVoidsData = await _loadTableBatched<PaymentVoid>(
        db.paymentVoids,
      );
      final guestInfosData = await _loadTableBatched<GuestInfo>(db.guestInfos);
      final salaryWithdrawalsData = await _loadTableBatched<SalaryWithdrawal>(
        db.salaryWithdrawals,
      );
      final salaryCarryOverLogsData =
          await _loadTableBatched<SalaryCarryOverLog>(
            db.salaryCarryOverLogs,
          );
      final inventoryItemsData = await _loadTableBatched<InventoryItem>(
        db.inventoryItems,
      );
      final inventoryTransactionsData =
          await _loadTableBatched<InventoryTransaction>(
            db.inventoryTransactions,
          );

      // استخراج عناصر القائمة السوداء بشكل منفصل (createdBy = 'blacklist')
      final blacklistQuery = db.select(db.shiftNotes)
        ..where((t) => t.createdBy.equals('blacklist'));
      final blacklistData = await blacklistQuery.get();

      final tableData = BackupTableData(
        roomsData: roomsData,
        bookingsData: bookingsData,
        bookingNotesData: bookingNotesData,
        bookingNightsData: bookingNightsData,
        ledgerData: ledgerData,
        shiftNotesData: shiftNotesData,
        employeesData: employeesData,
        expensesData: expensesData,
        cashTransactionsData: cashTransactionsData,
        paymentsData: paymentsData,
        debtsData: debtsData,
        salaryCyclesData: salaryCyclesData,
        salaryPaymentsData: salaryPaymentsData,
        priceAdjustmentsData: priceAdjustmentsData,
        bookingPriceAdjData: bookingPriceAdjData,
        auditLogsData: auditLogsData,
        paymentVoidsData: paymentVoidsData,
        guestInfosData: guestInfosData,
        salaryWithdrawalsData: salaryWithdrawalsData,
        salaryCarryOverLogsData: salaryCarryOverLogsData,
        inventoryItemsData: inventoryItemsData,
        inventoryTransactionsData: inventoryTransactionsData,
      );

      final totalRecords = tableData.totalRecords + blacklistData.length;

      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: DatabaseManager.instance.schemaVersion,
        backupTimestamp: DateTime.now(),
        totalRecords: totalRecords,
        deviceInfo: Platform.isAndroid ? 'Android' : 'iOS',
      );

      // إعدادات الواتساب من SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final whatsappSettings = <String, dynamic>{};
      const waKeys = [
        'wa_api_type',
        'wa_api_base_url',
        'wa_api_instance_id',
        'wa_api_token',
        'wa_custom_url_template',
      ];
      for (final key in waKeys) {
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) {
          whatsappSettings[key] = value;
        }
      }

      // JSON serialization + FK enrichment + SHA-256 hash داخل isolate واحد
      // (نفس إصلاح P3-15 التاريخي — يمنع jank الـ UI أثناء النسخ).
      final metadataJson = metadata.toJson();
      final backupData = await Isolate.run(() {
        // 1. بناء خريطة النسخة الاحتياطية (يشمل .toJson() لكل صف)
        final data = buildBackupDataMap(
          metadata: metadataJson,
          roomsData: roomsData,
          bookingsData: bookingsData,
          bookingNotesData: bookingNotesData,
          bookingNightsData: bookingNightsData,
          ledgerData: ledgerData,
          shiftNotesData: shiftNotesData,
          employeesData: employeesData,
          expensesData: expensesData,
          cashTransactionsData: cashTransactionsData,
          paymentsData: paymentsData,
          debtsData: debtsData,
          salaryCyclesData: salaryCyclesData,
          salaryPaymentsData: salaryPaymentsData,
          priceAdjustmentsData: priceAdjustmentsData,
          bookingPriceAdjData: bookingPriceAdjData,
          auditLogsData: auditLogsData,
          paymentVoidsData: paymentVoidsData,
          guestInfosData: guestInfosData,
          salaryWithdrawalsData: salaryWithdrawalsData,
          salaryCarryOverLogsData: salaryCarryOverLogsData,
          inventoryItemsData: inventoryItemsData,
          inventoryTransactionsData: inventoryTransactionsData,
          blacklistData: blacklistData,
          whatsappSettings: whatsappSettings,
        );

        // 2. إثراء بـ UUID للكيانات المرجعية (FK resolution at restore time)
        _enrichBackupWithFKUuidsInIsolate(
          data,
          employeesData,
          salaryCyclesData,
        );

        // 3. حساب SHA-256 hash (باستثناء حقل data_hash نفسه)
        final metadataForHash = Map<String, dynamic>.from(
          data['metadata'] as Map,
        )..remove('data_hash');
        final dataForHash = <String, dynamic>{
          ...data,
          'metadata': metadataForHash,
        };
        final jsonBytes = utf8.encode(jsonEncode(dataForHash));
        final digest = sha256.convert(jsonBytes);
        (data['metadata'] as Map<String, dynamic>)['data_hash'] = digest
            .toString();

        return data;
      });

      dlog('✅ [BackupDataService] تم تصدير البيانات: $totalRecords سجل');
      return backupData;
    } catch (e) {
      dlog('❌ [BackupDataService] خطأ في تصدير البيانات: $e');
      rethrow;
    }
  }

  /// تقدير حجم قاعدة البيانات بالبايت (حجم JSON المكافئ).
  Future<int> estimateDatabaseSize() async {
    try {
      final backupData = await exportDatabaseToJson();
      final jsonString = const JsonEncoder().convert(backupData);
      return utf8.encode(jsonString).length;
    } catch (e) {
      dlog('❌ [BackupDataService] خطأ في تقدير حجم قاعدة البيانات: $e');
      return 0;
    }
  }

  /// تحميل بيانات جدول على دفعات لتجنب استهلاك الذاكرة.
  Future<List<T>> _loadTableBatched<T>(
    dynamic table, {
    int batchSize = 500,
  }) async {
    final db = DatabaseManager.instance;
    final allData = <T>[];
    int offset = 0;

    while (true) {
      // تحويل الجدول إلى TableInfo لاستخدامه مع select
      final tableInfo = table as TableInfo;
      final query = db.select(tableInfo)..limit(batchSize, offset: offset);
      final batch = await query.get();
      if (batch.isEmpty) {
        break;
      }
      allData.addAll(batch.cast<T>());
      offset += batchSize;
      // إذا كانت الدفعة الأخيرة أقل من الحجم المطلوب، فقد وصلنا للنهاية
      if (batch.length < batchSize) {
        break;
      }
    }

    return allData;
  }

  /// حساب تجزئة SHA-256 لبيانات النسخة الاحتياطية (باستثناء حقل data_hash
  /// نفسه) — نفس الدالة التاريخية حرفياً (توافق تجزئات النسخ القائمة).
  static String computeBackupChecksum(Map<String, dynamic> backupData) {
    // إزالة data_hash مؤقتاً من البيانات الوصفية قبل الحساب
    final metadata = Map<String, dynamic>.from(backupData['metadata'] as Map);
    metadata.remove('data_hash');

    final dataForHash = <String, dynamic>{...backupData, 'metadata': metadata};

    final jsonBytes = utf8.encode(jsonEncode(dataForHash));
    final digest = sha256.convert(jsonBytes);
    return digest.toString();
  }

  /// التحقق من تجزئة النسخة الاحتياطية عند الاستعادة.
  static bool verifyBackupChecksum(Map<String, dynamic> backupData) {
    final metadata = backupData['metadata'];
    if (metadata is! Map) {
      return true; // لا يوجد بيانات وصفية = تجاوز التحقق
    }
    final storedHash = metadata['data_hash'] as String?;
    if (storedHash == null) {
      return true; // نسخ قديمة بدون تجزئة = تجاوز التحقق
    }

    final computedHash = computeBackupChecksum(backupData);
    return storedHash == computedHash;
  }
}

/// إثراء بيانات النسخة الاحتياطية بمعرفات UUID للكيانات المرجعية (FK) —
/// نفس الدالة التاريخية حرفياً، top-level لقابلية الاستدعاء من Isolate.run.
void _enrichBackupWithFKUuidsInIsolate(
  Map<String, dynamic> backupData,
  List<dynamic> employeesData,
  List<dynamic> salaryCyclesData,
) {
  // بناء خريطة: معرّف الموظف المحلي → UUID
  final employeeUuidMap = <int, String>{};
  for (final emp in employeesData) {
    final empMap = (emp as dynamic).toJson() as Map<String, dynamic>;
    final empId = empMap['id'] as int?;
    final empUuid = empMap['localUuid'] as String?;
    if (empId != null && empUuid != null) {
      employeeUuidMap[empId] = empUuid;
    }
  }

  // إثراء سحوبات الرواتب بـ UUID الموظف
  final withdrawalsList = backupData['salary_withdrawals'] as List<dynamic>?;
  if (withdrawalsList != null) {
    for (int i = 0; i < withdrawalsList.length; i++) {
      final wMap = withdrawalsList[i] as Map<String, dynamic>;
      final empId = wMap['employeeId'] as int?;
      if (empId != null && employeeUuidMap.containsKey(empId)) {
        wMap['employee_uuid'] = employeeUuidMap[empId];
      }
    }
  }

  // بناء خريطة: معرّف دورة الراتب المحلي → UUID
  final cycleUuidMap = <int, String>{};
  for (final cycle in salaryCyclesData) {
    final cycleMap = (cycle as dynamic).toJson() as Map<String, dynamic>;
    final cycleId = cycleMap['id'] as int?;
    final cycleUuid = cycleMap['localUuid'] as String?;
    if (cycleId != null && cycleUuid != null) {
      cycleUuidMap[cycleId] = cycleUuid;
    }
  }

  // إثراء مدفوعات الرواتب بـ UUID دورة الراتب
  final salaryPaymentsList = backupData['salary_payments'] as List<dynamic>?;
  if (salaryPaymentsList != null) {
    for (int i = 0; i < salaryPaymentsList.length; i++) {
      final pMap = salaryPaymentsList[i] as Map<String, dynamic>;
      final cycleId = pMap['cycleId'] as int?;
      if (cycleId != null && cycleUuidMap.containsKey(cycleId)) {
        pMap['cycle_local_uuid'] = cycleUuidMap[cycleId];
      }
    }
  }
}
