import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';


import 'appwrite_backup_endpoint.dart';
import 'appwrite_backup_endpoints_manager.dart';
import 'appwrite_backup_history_manager.dart';
import 'appwrite_backup_operation_log.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'local_db.dart';

/// تقدم عملية الرفع/السحب
class BackupProgress {
  final String tableName;
  final int current;
  final int total;
  final String endpointName;
  final String operationType; // push / pull

  BackupProgress({
    required this.tableName,
    required this.current,
    required this.total,
    required this.endpointName,
    required this.operationType,
  });

  double get percentage => total > 0 ? current / total : 0.0;
}

/// خدمة المزامنة الاحتياطية (Slave Push/Pull)
class AppwriteBackupSyncService {
  AppwriteBackupSyncService._internal();
  static final AppwriteBackupSyncService _instance =
      AppwriteBackupSyncService._internal();
  factory AppwriteBackupSyncService() => _instance;

  final _logger = AppwriteLogger();

  bool _isPushing = false;
  bool _isPulling = false;

  bool get isPushing => _isPushing;
  bool get isPulling => _isPulling;
  bool get isBusy => _isPushing || _isPulling;

  static const List<String> _allCollectionIds = [
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
    AppwriteConfig.shiftNotesCollectionId,
    AppwriteConfig.priceAdjustmentsCollectionId,
    AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    AppwriteConfig.auditLogsCollectionId,
    AppwriteConfig.paymentVoidsCollectionId,
    AppwriteConfig.devicesCollectionId,
    AppwriteConfig.syncLogsCollectionId,
    AppwriteConfig.guestInfosCollectionId,
    AppwriteConfig.salaryWithdrawalsCollectionId,
    AppwriteConfig.blacklistCollectionId,
    AppwriteConfig.appSettingsCollectionId,
  ];

  // ─── Push: رفع البيانات المحلية إلى نقطة نهاية ─────────────────

  /// إنشاء عميل Appwrite من نقطة نهاية
  Client _createClient(BackupEndpoint endpoint) {
    final client = Client()
        .setEndpoint(endpoint.endpoint)
        .setProject(endpoint.projectId);
    if (endpoint.apiKey.isNotEmpty) {
      client.addHeader('X-Appwrite-Key', endpoint.apiKey);
    }
    return client;
  }

  /// رفع جميع البيانات المحلية إلى نقطة نهاية محددة (Full Push)
  Future<Map<String, int>> fullPushAllToEndpoint({
    required AppDatabase db,
    required BackupEndpoint endpoint,
    void Function(BackupProgress progress)? onProgress,
  }) async {
    final stats = <String, int>{
      'rooms': 0,
      'employees': 0,
      'bookings': 0,
      'payments': 0,
      'expenses': 0,
      'debts': 0,
      'booking_notes': 0,
      'booking_nights': 0,
      'shift_notes': 0,
      'cash_transactions': 0,
      'guest_infos': 0,
      'salary_cycles': 0,
      'salary_payments': 0,
      'salary_withdrawals': 0,
      'price_adjustments': 0,
      'booking_price_adjustments': 0,
      'audit_logs': 0,
      'payment_voids': 0,
      'errors': 0,
    };

    final client = _createClient(endpoint);
    final databases = Databases(client);
    final dbId = endpoint.databaseId;

    Future<bool> upsert(
        String collection, String docId, Map<String, dynamic> data) async {
      try {
        await databases.createDocument(
          databaseId: dbId,
          collectionId: collection,
          documentId: docId,
          data: data,
        );
        return true;
      } catch (_) {
        try {
          await databases.updateDocument(
            databaseId: dbId,
            collectionId: collection,
            documentId: docId,
            data: data,
          );
          return true;
        } catch (e) {
          _logger.warning('⚠️ فشل رفع $docId إلى $collection: $e',
              tag: 'BACKUP_SYNC');
          return false;
        }
      }
    }

    _logger.info('🚀 بدء الرفع الشامل إلى ${endpoint.name}...',
        tag: 'BACKUP_SYNC');

    // ─── 1. rooms ───
    final rooms = await db.select(db.rooms).get();
    for (var i = 0; i < rooms.length; i++) {
      final room = rooms[i];
      if (room.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'rooms',
          current: i + 1,
          total: rooms.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildRoomData(room);
      if (await upsert('rooms', room.localUuid, data)) {
        stats['rooms'] = stats['rooms']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 2. employees ───
    final employees = await db.select(db.employees).get();
    for (var i = 0; i < employees.length; i++) {
      final emp = employees[i];
      if (emp.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'employees',
          current: i + 1,
          total: employees.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildEmployeeData(emp);
      if (await upsert('employees', emp.localUuid, data)) {
        stats['employees'] = stats['employees']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 3. bookings ───
    final bookings = await db.select(db.bookings).get();
    for (var i = 0; i < bookings.length; i++) {
      final b = bookings[i];
      if (b.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'bookings',
          current: i + 1,
          total: bookings.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildBookingData(b);
      if (await upsert('bookings', b.localUuid, data)) {
        stats['bookings'] = stats['bookings']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 4. payments ───
    final payments = await db.select(db.payments).get();
    for (var i = 0; i < payments.length; i++) {
      final p = payments[i];
      if (p.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'payments',
          current: i + 1,
          total: payments.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildPaymentData(p);
      if (await upsert('payments', p.localUuid, data)) {
        stats['payments'] = stats['payments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 5. expenses ───
    final expenses = await db.select(db.expenses).get();
    final employeesById = {for (final e in employees) e.id: e};
    for (var i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      if (e.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'expenses',
          current: i + 1,
          total: expenses.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildExpenseData(e);
      if (e.relatedId != null) {
        final emp = employeesById[e.relatedId];
        if (emp != null) {
          data['employeeUuid'] = emp.localUuid;
        }
      }
      if (await upsert('expenses', e.localUuid, data)) {
        stats['expenses'] = stats['expenses']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 6. debts ───
    final debts = await db.select(db.debts).get();
    for (var i = 0; i < debts.length; i++) {
      final d = debts[i];
      if (d.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'debts',
          current: i + 1,
          total: debts.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildDebtData(d);
      if (await upsert('debts', d.localUuid, data)) {
        stats['debts'] = stats['debts']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 7. booking_notes ───
    final bookingNotes = await db.select(db.bookingNotes).get();
    for (var i = 0; i < bookingNotes.length; i++) {
      final bn = bookingNotes[i];
      if (bn.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'booking_notes',
          current: i + 1,
          total: bookingNotes.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildBookingNoteData(bn);
      if (await upsert('booking_notes', bn.localUuid, data)) {
        stats['booking_notes'] = stats['booking_notes']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 8. booking_nights ───
    final bookingNights = await db.select(db.bookingNights).get();
    for (var i = 0; i < bookingNights.length; i++) {
      final bn = bookingNights[i];
      if (bn.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'booking_nights',
          current: i + 1,
          total: bookingNights.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildBookingNightData(bn);
      if (await upsert('booking_nights', bn.localUuid, data)) {
        stats['booking_nights'] = stats['booking_nights']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 9. shift_notes ───
    final shiftNotes = await db.select(db.shiftNotes).get();
    for (var i = 0; i < shiftNotes.length; i++) {
      final sn = shiftNotes[i];
      if (sn.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'shift_notes',
          current: i + 1,
          total: shiftNotes.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildShiftNoteData(sn);
      if (await upsert('shift_notes', sn.localUuid, data)) {
        stats['shift_notes'] = stats['shift_notes']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 10. cash_transactions ───
    final cashTransactions = await db.select(db.cashTransactions).get();
    for (var i = 0; i < cashTransactions.length; i++) {
      final ct = cashTransactions[i];
      if (ct.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'cash_transactions',
          current: i + 1,
          total: cashTransactions.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildCashTransactionData(ct);
      if (await upsert('cash_transactions', ct.localUuid, data)) {
        stats['cash_transactions'] = stats['cash_transactions']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 11. guest_infos ───
    final guestInfos = await db.select(db.guestInfos).get();
    for (var i = 0; i < guestInfos.length; i++) {
      final gi = guestInfos[i];
      if (gi.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'guest_infos',
          current: i + 1,
          total: guestInfos.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildGuestInfoData(gi);
      if (await upsert('guest_infos', gi.localUuid, data)) {
        stats['guest_infos'] = stats['guest_infos']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 12. salary_cycles ───
    final salaryCycles = await db.select(db.salaryCycles).get();
    for (var i = 0; i < salaryCycles.length; i++) {
      final sc = salaryCycles[i];
      if (sc.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'salary_cycles',
          current: i + 1,
          total: salaryCycles.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildSalaryCycleData(sc);
      if (await upsert('salary_cycles', sc.localUuid, data)) {
        stats['salary_cycles'] = stats['salary_cycles']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 13. salary_payments ───
    final salaryPayments = await db.select(db.salaryPayments).get();
    for (var i = 0; i < salaryPayments.length; i++) {
      final sp = salaryPayments[i];
      if (sp.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'salary_payments',
          current: i + 1,
          total: salaryPayments.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildSalaryPaymentData(sp);
      if (await upsert('salary_payments', sp.localUuid, data)) {
        stats['salary_payments'] = stats['salary_payments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 14. salary_withdrawals ───
    final salaryWithdrawals = await db.select(db.salaryWithdrawals).get();
    final empById = {for (final e in employees) e.id: e};
    for (var i = 0; i < salaryWithdrawals.length; i++) {
      final sw = salaryWithdrawals[i];
      if (sw.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'salary_withdrawals',
          current: i + 1,
          total: salaryWithdrawals.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildSalaryWithdrawalData(sw);
      final employee = empById[sw.employeeId];
      if (employee != null) {
        data['employeeUuid'] = employee.localUuid;
        data['name'] = employee.name;
      }
      if (await upsert('salary_withdrawals', sw.localUuid, data)) {
        stats['salary_withdrawals'] = stats['salary_withdrawals']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 15. price_adjustments ───
    final priceAdjustments = await db.select(db.priceAdjustments).get();
    for (var i = 0; i < priceAdjustments.length; i++) {
      final pa = priceAdjustments[i];
      if (pa.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'price_adjustments',
          current: i + 1,
          total: priceAdjustments.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildPriceAdjustmentData(pa);
      if (await upsert('price_adjustments', pa.localUuid, data)) {
        stats['price_adjustments'] = stats['price_adjustments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 16. booking_price_adjustments ───
    final bookingPriceAdj = await db.select(db.bookingPriceAdjustments).get();
    for (var i = 0; i < bookingPriceAdj.length; i++) {
      final bpa = bookingPriceAdj[i];
      if (bpa.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'booking_price_adjustments',
          current: i + 1,
          total: bookingPriceAdj.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildBookingPriceAdjustmentData(bpa);
      if (await upsert('booking_price_adjustments', bpa.localUuid, data)) {
        stats['booking_price_adjustments'] =
            stats['booking_price_adjustments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 17. audit_logs ───
    final auditLogs = await db.select(db.auditLogs).get();
    for (var i = 0; i < auditLogs.length; i++) {
      final al = auditLogs[i];
      onProgress?.call(BackupProgress(
          tableName: 'audit_logs',
          current: i + 1,
          total: auditLogs.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildAuditLogData(al);
      if (await upsert('audit_logs', al.localUuid, data)) {
        stats['audit_logs'] = stats['audit_logs']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 18. payment_voids ───
    final paymentVoids = await db.select(db.paymentVoids).get();
    final allPayments = await db.select(db.payments).get();
    final paymentsByLocalUuid = {for (final p in allPayments) p.localUuid: p};
    for (var i = 0; i < paymentVoids.length; i++) {
      final pv = paymentVoids[i];
      if (pv.deletedAt != null) continue;
      onProgress?.call(BackupProgress(
          tableName: 'payment_voids',
          current: i + 1,
          total: paymentVoids.length,
          endpointName: endpoint.name,
          operationType: 'push'));
      final data = _buildPaymentVoidData(pv);
      data['note'] = pv.voidReason;
      if (pv.originalPaymentUuid.isNotEmpty) {
        final payment = paymentsByLocalUuid[pv.originalPaymentUuid];
        if (payment != null) {
          data['paymentUuid'] = payment.localUuid;
          data['originalAmount'] = payment.amount.round();
        }
      }
      if (await upsert('payment_voids', pv.localUuid, data)) {
        stats['payment_voids'] = stats['payment_voids']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // حفظ سجل العملية
    await BackupHistoryManager.addLog(BackupOperationLog(
      id: BackupHistoryManager.generateId(),
      endpointId: endpoint.id,
      endpointName: endpoint.name,
      operationType: 'push',
      timestamp: DateTime.now(),
      stats: Map.from(stats),
      success: (stats['errors'] ?? 0) == 0,
    ));

    // تحديث آخر وقت رفع
    final updated = endpoint.copyWith(lastPushAt: DateTime.now());
    await BackupEndpointsManager.updateEndpoint(updated);

    _logger.info(
        '✅ اكتمل الرفع الشامل إلى ${endpoint.name}: $stats',
        tag: 'BACKUP_SYNC');
    return stats;
  }

  /// رفع جميع البيانات إلى جميع نقاط النهاية النشطة
  Future<Map<String, Map<String, int>>> fullPushAllToAllEndpoints({
    required AppDatabase db,
    void Function(BackupProgress progress)? onProgress,
  }) async {
    final endpoints = await BackupEndpointsManager.loadEndpoints();
    if (endpoints.isEmpty) return {};

    final allStats = <String, Map<String, int>>{};

    for (final endpoint in endpoints) {
      if (!endpoint.pushEnabled) continue;
      final stats = await fullPushAllToEndpoint(
        db: db,
        endpoint: endpoint,
        onProgress: onProgress,
      );
      allStats[endpoint.name] = stats;
    }

    return allStats;
  }

  // ─── Pull: سحب البيانات من نقطة نهاية إلى ملف JSON ────────────

  /// سحب جميع البيانات من نقطة نهاية محددة وحفظها في ملف JSON
  Future<File?> pullAllFromEndpoint({
    required BackupEndpoint endpoint,
    void Function(BackupProgress progress)? onProgress,
  }) async {
    _isPulling = true;
    try {
      final client = _createClient(endpoint);
      final databases = Databases(client);
      final dbId = endpoint.databaseId;

      final collections = <String, List<Map<String, dynamic>>>{};
      final stats = <String, int>{};

      var totalCollections = _allCollectionIds.length;
      for (var ci = 0; ci < totalCollections; ci++) {
        final collectionId = _allCollectionIds[ci];
        onProgress?.call(BackupProgress(
          tableName: collectionId,
          current: 0,
          total: 1,
          endpointName: endpoint.name,
          operationType: 'pull',
        ));

        final docs = <Map<String, dynamic>>[];
        var offset = 0;
        const limit = 100;
        var hasMore = true;

        while (hasMore) {
          try {
            final result = await databases.listDocuments(
              databaseId: dbId,
              collectionId: collectionId,
              queries: [Query.limit(limit), Query.offset(offset)],
            );

            for (final doc in result.documents) {
              docs.add({r'$id': doc.$id, ...doc.data});
            }

            if (result.documents.length < limit) {
              hasMore = false;
            }
            offset += limit;

            onProgress?.call(BackupProgress(
              tableName: collectionId,
              current: docs.length,
              total: docs.length + 1,
              endpointName: endpoint.name,
              operationType: 'pull',
            ));
          } catch (e) {
            _logger.warning(
                '⚠️ فشل سحب $collectionId: $e', tag: 'BACKUP_SYNC');
            hasMore = false;
          }
        }

        collections[collectionId] = docs;
        stats[collectionId] = docs.length;
      }

      final totalRecords = stats.values.fold<int>(0, (sum, v) => sum + v);

      final payload = {
        'metadata': {
          'version': '1.0',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'source': endpoint.name,
          'endpoint': endpoint.endpoint,
          'projectId': endpoint.projectId,
          'databaseId': endpoint.databaseId,
          'totalRecords': totalRecords,
          'operation': 'pull_from_backup',
        },
        'collections': collections,
      };

      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/backup_pulls');
      if (!backupDir.existsSync()) {
        await backupDir.create(recursive: true);
      }

      final dateStr =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeName = endpoint.name.replaceAll(RegExp(r'[^\w]'), '_');
      final fileName = '${safeName}_${dateStr}.json';
      final file = File('${backupDir.path}/$fileName');
      await file.writeAsString(jsonEncode(payload));

      // حفظ سجل العملية
      await BackupHistoryManager.addLog(BackupOperationLog(
        id: BackupHistoryManager.generateId(),
        endpointId: endpoint.id,
        endpointName: endpoint.name,
        operationType: 'pull',
        timestamp: DateTime.now(),
        stats: stats,
        success: true,
      ));

      // تحديث آخر وقت سحب
      final updated = endpoint.copyWith(lastPullAt: DateTime.now());
      await BackupEndpointsManager.updateEndpoint(updated);

      _logger.info(
          '✅ اكتمل السحب من ${endpoint.name}: $totalRecords سجل',
          tag: 'BACKUP_SYNC');

      return file;
    } catch (e, st) {
      _logger.error('❌ فشل السحب من ${endpoint.name}',
          error: e, stackTrace: st, tag: 'BACKUP_SYNC');

      await BackupHistoryManager.addLog(BackupOperationLog(
        id: BackupHistoryManager.generateId(),
        endpointId: endpoint.id,
        endpointName: endpoint.name,
        operationType: 'pull',
        timestamp: DateTime.now(),
        stats: {'errors': 1},
        success: false,
        errorMessage: e.toString(),
      ));

      return null;
    } finally {
      _isPulling = false;
    }
  }

  /// سحب البيانات من جميع نقاط النهاية التي لديها pull مفعّل
  Future<Map<String, File?>> pullAllFromAllEndpoints({
    void Function(BackupProgress progress)? onProgress,
  }) async {
    final endpoints = await BackupEndpointsManager.loadEndpoints();
    if (endpoints.isEmpty) return {};

    final results = <String, File?>{};

    for (final endpoint in endpoints) {
      if (!endpoint.pullEnabled) continue;
      final file = await pullAllFromEndpoint(
        endpoint: endpoint,
        onProgress: onProgress,
      );
      results[endpoint.name] = file;
    }

    return results;
  }

  // ─── دفع عملية واحدة (للمزامنة التلقائية) ────────────────────

  /// دفع عملية واحدة إلى جميع نقاط النهاية النشطة
  Future<void> pushToBackups({
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
    required String operation,
  }) async {
    if (_isPushing) return;

    final endpoints = await BackupEndpointsManager.loadEndpoints();
    if (endpoints.isEmpty) return;

    _isPushing = true;
    int successCount = 0;
    int failCount = 0;

    for (final endpoint in endpoints) {
      if (!endpoint.pushEnabled) continue;
      try {
        await _pushToEndpoint(
          endpoint: endpoint,
          tableName: tableName,
          documentId: documentId,
          data: data,
          operation: operation,
        );
        successCount++;
      } catch (e) {
        failCount++;
        _logger.warning(
            '⚠️ فشل دفع احتياطي إلى ${endpoint.name}: $e',
            tag: 'BACKUP_SYNC');
      }
    }

    _isPushing = false;
  }

  /// دفع دفعة عمليات إلى جميع نقاط النهاية
  Future<void> pushBatchToBackups({
    required List<BackupOperation> operations,
  }) async {
    if (_isPushing || operations.isEmpty) return;

    final endpoints = await BackupEndpointsManager.loadEndpoints();
    if (endpoints.isEmpty) return;

    _isPushing = true;

    for (final endpoint in endpoints) {
      if (!endpoint.pushEnabled) continue;
      int successCount = 0;
      int failCount = 0;

      for (final op in operations) {
        try {
          await _pushToEndpoint(
            endpoint: endpoint,
            tableName: op.tableName,
            documentId: op.documentId,
            data: op.data,
            operation: op.operation,
          );
          successCount++;
        } catch (e) {
          failCount++;
        }
      }
    }

    _isPushing = false;
  }

  Future<void> _pushToEndpoint({
    required BackupEndpoint endpoint,
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
    required String operation,
  }) async {
    final client = _createClient(endpoint);
    final databases = Databases(client);
    final dbId = endpoint.databaseId;

    switch (operation) {
      case 'create':
        await databases.createDocument(
          databaseId: dbId,
          collectionId: tableName,
          documentId: documentId,
          data: data,
        );
        break;
      case 'update':
        try {
          await databases.updateDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
            data: data,
          );
        } catch (_) {
          await databases.createDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
            data: data,
          );
        }
        break;
      case 'delete':
        try {
          await databases.deleteDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
          );
        } catch (_) {}
        break;
    }
  }

  // ─── اختبار الاتصال ──────────────────────────────────────

  static Future<bool> testConnection(BackupEndpoint endpoint) async {
    try {
      final client = Client()
          .setEndpoint(endpoint.endpoint)
          .setProject(endpoint.projectId);
      if (endpoint.apiKey.isNotEmpty) {
        client.addHeader('X-Appwrite-Key', endpoint.apiKey);
      }
      final databases = Databases(client);
      await databases.listDocuments(
        databaseId: endpoint.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      return true;
    } catch (e) {
      debugPrint('❌ Backup endpoint test failed: $e');
      return false;
    }
  }

  // ─── دوال بناء البيانات ──────────────────────────────────

  Map<String, dynamic> _buildRoomData(dynamic room) => {
        'id': room.id,
        'localUuid': room.localUuid,
        'serverId': room.serverId,
        'roomNumber': room.roomNumber,
        'type': room.type,
        'price': room.price,
        'status': room.status,
        'imageUrl': room.imageUrl,
        'cleaningStatus': room.cleaningStatus,
        'lastCleanedHotelDay': room.lastCleanedHotelDay,
        'lastOccupiedHotelDay': room.lastOccupiedHotelDay,
        'requiresMaintenance': room.requiresMaintenance,
        'createdAt': room.createdAt,
        'updatedAt': room.updatedAt,
        'deletedAt': room.deletedAt,
        'lastModified': room.lastModified,
        'createdAtIso': room.createdAtIso,
        'updatedAtIso': room.updatedAtIso,
        'deletedAtIso': room.deletedAtIso,
        'createdAtEpoch': room.createdAtEpoch,
        'lastModifiedEpoch': room.lastModifiedEpoch,
        'version': room.version,
        'origin': room.origin,
        'vectorClock': room.vectorClock,
        'deviceId': room.deviceId,
      };

  Map<String, dynamic> _buildEmployeeData(dynamic emp) => {
        'id': emp.id,
        'localUuid': emp.localUuid,
        'serverId': emp.serverId,
        'name': emp.name,
        'basicSalary': emp.basicSalary,
        'position': emp.position,
        'phone': emp.phone,
        'hireDate': emp.hireDate,
        'status': emp.status,
        'terminationDate': emp.terminationDate,
        'terminationReason': emp.terminationReason,
        'createdAt': emp.createdAt,
        'updatedAt': emp.updatedAt,
        'deletedAt': emp.deletedAt,
        'lastModified': emp.lastModified,
        'createdAtIso': emp.createdAtIso,
        'updatedAtIso': emp.updatedAtIso,
        'deletedAtIso': emp.deletedAtIso,
        'createdAtEpoch': emp.createdAtEpoch,
        'lastModifiedEpoch': emp.lastModifiedEpoch,
        'version': emp.version,
        'origin': emp.origin,
        'vectorClock': emp.vectorClock,
        'deviceId': emp.deviceId,
      };

  Map<String, dynamic> _buildBookingData(dynamic b) => {
        'id': b.id,
        'localUuid': b.localUuid,
        'serverId': b.serverId,
        'serverBookingId': b.serverBookingId,
        'roomNumber': b.roomNumber,
        'guestName': b.guestName,
        'guestPhone': b.guestPhone,
        'guestIdType': b.guestIdType,
        'guestIdNumber': b.guestIdNumber,
        'guestIdIssueDate': b.guestIdIssueDate,
        'guestIdIssuePlace': b.guestIdIssuePlace,
        'guestNationality': b.guestNationality,
        'guestEmail': b.guestEmail,
        'guestAddress': b.guestAddress,
        'checkinDate': b.checkinDate,
        'checkoutDate': b.checkoutDate,
        'actualCheckout': b.actualCheckout,
        'status': b.status,
        'notes': b.notes,
        'discount': b.discount,
        'discountType': b.discountType,
        'discountStartDate': b.discountStartDate,
        'expectedNights': b.expectedNights,
        'calculatedNights': b.calculatedNights,
        'totalNightsCached': b.totalNightsCached,
        'stayDurationIso': b.stayDurationIso,
        'lastNightEpoch': b.lastNightEpoch,
        'isOverdue': b.isOverdue,
        'needsCheckoutReview': b.needsCheckoutReview,
        'totalDueCached': b.totalDueCached,
        'totalPaidCached': b.totalPaidCached,
        'remainingBalanceCached': b.remainingBalanceCached,
        'isFullyPaid': b.isFullyPaid,
        'hotelDayCheckin': b.hotelDayCheckin,
        'hotelDayCheckout': b.hotelDayCheckout,
        'createdAt': b.createdAt,
        'updatedAt': b.updatedAt,
        'deletedAt': b.deletedAt,
        'lastModified': b.lastModified,
        'version': b.version,
        'origin': b.origin,
        'vectorClock': b.vectorClock,
        'deviceId': b.deviceId,
      };

  Map<String, dynamic> _buildPaymentData(dynamic p) => {
        'id': p.id,
        'localUuid': p.localUuid,
        'serverId': p.serverId,
        'serverPaymentId': p.serverPaymentId,
        'bookingLocalId': p.bookingLocalId,
        'serverBookingId': p.serverBookingId,
        'roomNumber': p.roomNumber,
        'amount': p.amount,
        'paymentDate': p.paymentDate,
        'notes': p.notes,
        'paymentMethod': p.paymentMethod,
        'revenueType': p.revenueType,
        'cashTransactionLocalId': p.cashTransactionLocalId,
        'cashTransactionServerId': p.cashTransactionServerId,
        'referenceNumber': p.referenceNumber,
        'hotelDayKey': p.hotelDayKey,
        'isPendingBalance': p.isPendingBalance,
        'linkedDebtUuid': p.linkedDebtUuid,
        'bookingUuidCache': p.bookingUuidCache,
        'discountAmount': p.discountAmount,
        'discountStartDate': p.discountStartDate,
        'isVoided': p.isVoided,
        'voidedAt': p.voidedAt,
        'voidedBy': p.voidedBy,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'deletedAt': p.deletedAt,
        'lastModified': p.lastModified,
        'version': p.version,
        'origin': p.origin,
        'vectorClock': p.vectorClock,
        'deviceId': p.deviceId,
      };

  Map<String, dynamic> _buildExpenseData(dynamic e) => {
        'id': e.id,
        'localUuid': e.localUuid,
        'serverId': e.serverId,
        'expenseType': e.expenseType,
        'relatedId': e.relatedId,
        'description': e.description,
        'amount': e.amount,
        'date': e.date,
        'cashTransactionId': e.cashTransactionId,
        'hotelDayKey': e.hotelDayKey,
        'categoryUuid': e.categoryUuid,
        'cashFlowUuid': e.cashFlowUuid,
        'isAutoGenerated': e.isAutoGenerated,
        'createdAt': e.createdAt,
        'updatedAt': e.updatedAt,
        'deletedAt': e.deletedAt,
        'lastModified': e.lastModified,
        'createdAtIso': e.createdAtIso,
        'updatedAtIso': e.updatedAtIso,
        'deletedAtIso': e.deletedAtIso,
        'createdAtEpoch': e.createdAtEpoch,
        'lastModifiedEpoch': e.lastModifiedEpoch,
        'version': e.version,
        'origin': e.origin,
        'vectorClock': e.vectorClock,
        'deviceId': e.deviceId,
      };

  Map<String, dynamic> _buildDebtData(dynamic d) => {
        'id': d.id,
        'localUuid': d.localUuid,
        'serverId': d.serverId,
        'bookingLocalId': d.bookingLocalId,
        'guestName': d.guestName,
        'checkinDate': d.checkinDate,
        'checkoutDate': d.checkoutDate,
        'dateRecorded': d.dateRecorded,
        'debtReason': d.debtReason,
        'totalAmount': d.totalAmount,
        'paidAmount': d.paidAmount,
        'remainingAmount': d.remainingAmount,
        'paymentDate': d.paymentDate,
        'isSettled': d.isSettled,
        'pledge': d.pledge,
        'pledgeType': d.pledgeType,
        'note': d.note,
        'debtUuid': d.debtUuid,
        'hotelDayOpened': d.hotelDayOpened,
        'hotelDayClosed': d.hotelDayClosed,
        'isFromAutoFix': d.isFromAutoFix,
        'settlementConfirmed': d.settlementConfirmed,
        'createdAt': d.createdAt,
        'updatedAt': d.updatedAt,
        'deletedAt': d.deletedAt,
        'lastModified': d.lastModified,
        'version': d.version,
        'origin': d.origin,
        'vectorClock': d.vectorClock,
        'deviceId': d.deviceId,
      };

  Map<String, dynamic> _buildBookingNoteData(dynamic bn) => {
        'id': bn.id,
        'localUuid': bn.localUuid,
        'serverId': bn.serverId,
        'bookingId': bn.bookingId,
        'noteText': bn.noteText,
        'alertType': bn.alertType,
        'alertUntil': bn.alertUntil,
        'isActive': bn.isActive,
        'createdAt': bn.createdAt,
        'updatedAt': bn.updatedAt,
        'deletedAt': bn.deletedAt,
        'lastModified': bn.lastModified,
        'createdAtIso': bn.createdAtIso,
        'updatedAtIso': bn.updatedAtIso,
        'deletedAtIso': bn.deletedAtIso,
        'createdAtEpoch': bn.createdAtEpoch,
        'lastModifiedEpoch': bn.lastModifiedEpoch,
        'version': bn.version,
        'origin': bn.origin,
        'vectorClock': bn.vectorClock,
        'deviceId': bn.deviceId,
      };

  Map<String, dynamic> _buildBookingNightData(dynamic bn) => {
        'id': bn.id,
        'localUuid': bn.localUuid,
        'serverId': bn.serverId,
        'bookingLocalId': bn.bookingLocalId,
        'hotelDayKey': bn.hotelDayKey,
        'nightStart': bn.nightStart,
        'nightEnd': bn.nightEnd,
        'nightlyRate': bn.nightlyRate,
        'sequence': bn.sequence,
        'isProcessedByAutoFix': bn.isProcessedByAutoFix,
        'baseRate': bn.baseRate,
        'adjustment': bn.adjustment,
        'finalRate': bn.finalRate,
        'appliedAdjustmentUuid': bn.appliedAdjustmentUuid,
        'createdAt': bn.createdAt,
        'updatedAt': bn.updatedAt,
        'deletedAt': bn.deletedAt,
        'lastModified': bn.lastModified,
        'createdAtIso': bn.createdAtIso,
        'updatedAtIso': bn.updatedAtIso,
        'deletedAtIso': bn.deletedAtIso,
        'createdAtEpoch': bn.createdAtEpoch,
        'lastModifiedEpoch': bn.lastModifiedEpoch,
        'version': bn.version,
        'origin': bn.origin,
        'vectorClock': bn.vectorClock,
        'deviceId': bn.deviceId,
      };

  Map<String, dynamic> _buildShiftNoteData(dynamic sn) {
    final createdDate = DateTime.fromMillisecondsSinceEpoch(sn.createdAt * 1000);
    final shiftDate = createdDate.toIso8601String().substring(0, 10);
    return {
        'id': sn.id,
        'localUuid': sn.localUuid,
        'serverId': sn.serverId,
        'title': sn.title,
        'content': sn.content,
        'priority': sn.priority,
        'shiftType': sn.shiftType,
        'isRead': sn.isRead,
        'createdBy': sn.createdBy,
        'expiresAt': sn.expiresAt,
        'createdAt': sn.createdAt,
        'updatedAt': sn.updatedAt,
        'deletedAt': sn.deletedAt,
        'lastModified': sn.lastModified,
        'createdAtIso': sn.createdAtIso,
        'updatedAtIso': sn.updatedAtIso,
        'deletedAtIso': sn.deletedAtIso,
        'createdAtEpoch': sn.createdAtEpoch,
        'lastModifiedEpoch': sn.lastModifiedEpoch,
        'version': sn.version,
        'origin': sn.origin,
        'vectorClock': sn.vectorClock,
        'deviceId': sn.deviceId,
        'shiftDate': shiftDate,
        'note': sn.content,
      };
  }

  Map<String, dynamic> _buildCashTransactionData(dynamic ct) => {
        'id': ct.id,
        'localUuid': ct.localUuid,
        'serverId': ct.serverId,
        'registerId': ct.registerId,
        'transactionType': ct.transactionType,
        'amount': ct.amount,
        'referenceType': ct.referenceType,
        'referenceId': ct.referenceId,
        'description': ct.description,
        'transactionTime': ct.transactionTime,
        'createdBy': ct.createdBy,
        'createdAt': ct.createdAt,
        'updatedAt': ct.updatedAt,
        'deletedAt': ct.deletedAt,
        'lastModified': ct.lastModified,
        'createdAtIso': ct.createdAtIso,
        'updatedAtIso': ct.updatedAtIso,
        'deletedAtIso': ct.deletedAtIso,
        'createdAtEpoch': ct.createdAtEpoch,
        'lastModifiedEpoch': ct.lastModifiedEpoch,
        'version': ct.version,
        'origin': ct.origin,
        'vectorClock': ct.vectorClock,
        'deviceId': ct.deviceId,
      };

  Map<String, dynamic> _buildGuestInfoData(dynamic gi) => {
        'id': gi.id,
        'localUuid': gi.localUuid,
        'serverId': gi.serverId,
        'roomNumber': gi.roomNumber,
        'guestName': gi.guestName,
        'nationality': gi.nationality,
        'idNumber': gi.idNumber,
        'idType': gi.idType,
        'issueDate': gi.issueDate,
        'issuePlace': gi.issuePlace,
        'governorate': gi.governorate,
        'notes': gi.notes,
        'createdAt': gi.createdAt,
        'updatedAt': gi.updatedAt,
        'deletedAt': gi.deletedAt,
        'lastModified': gi.lastModified,
        'createdAtIso': gi.createdAtIso,
        'updatedAtIso': gi.updatedAtIso,
        'deletedAtIso': gi.deletedAtIso,
        'createdAtEpoch': gi.createdAtEpoch,
        'lastModifiedEpoch': gi.lastModifiedEpoch,
        'version': gi.version,
        'origin': gi.origin,
        'vectorClock': gi.vectorClock,
        'deviceId': gi.deviceId,
      };

  Map<String, dynamic> _buildSalaryCycleData(dynamic sc) => {
        'id': sc.id,
        'localUuid': sc.localUuid,
        'serverId': sc.serverId,
        'employeeId': sc.employeeId,
        'cycleKey': sc.cycleKey,
        'hotelDayStart': sc.hotelDayStart,
        'hotelDayEnd': sc.hotelDayEnd,
        'expectedAmount': sc.expectedAmount,
        'actualPaid': sc.actualPaid,
        'remainingAmount': sc.remainingAmount,
        'status': sc.status,
        'createdAt': sc.createdAt,
        'updatedAt': sc.updatedAt,
        'deletedAt': sc.deletedAt,
        'lastModified': sc.lastModified,
        'createdAtIso': sc.createdAtIso,
        'updatedAtIso': sc.updatedAtIso,
        'deletedAtIso': sc.deletedAtIso,
        'createdAtEpoch': sc.createdAtEpoch,
        'lastModifiedEpoch': sc.lastModifiedEpoch,
        'version': sc.version,
        'origin': sc.origin,
        'vectorClock': sc.vectorClock,
        'deviceId': sc.deviceId,
      };

  Map<String, dynamic> _buildSalaryPaymentData(dynamic sp) => {
        'id': sp.id,
        'localUuid': sp.localUuid,
        'serverId': sp.serverId,
        'cycleId': sp.cycleId,
        'amount': sp.amount,
        'hotelDayKey': sp.hotelDayKey,
        'paymentDateIso': sp.paymentDateIso,
        'method': sp.method,
        'isAutoGenerated': sp.isAutoGenerated,
        'createdAt': sp.createdAt,
        'updatedAt': sp.updatedAt,
        'deletedAt': sp.deletedAt,
        'lastModified': sp.lastModified,
        'createdAtIso': sp.createdAtIso,
        'updatedAtIso': sp.updatedAtIso,
        'deletedAtIso': sp.deletedAtIso,
        'createdAtEpoch': sp.createdAtEpoch,
        'lastModifiedEpoch': sp.lastModifiedEpoch,
        'version': sp.version,
        'origin': sp.origin,
        'vectorClock': sp.vectorClock,
        'deviceId': sp.deviceId,
      };

  Map<String, dynamic> _buildSalaryWithdrawalData(dynamic sw) {
    // استخراج expenseId من حقل reason (الصيغة: "exp_123")
    int? expenseId;
    if (sw.reason != null && sw.reason!.startsWith('exp_')) {
      expenseId = int.tryParse(sw.reason!.substring(4));
    }
    return {
        'id': sw.id,
        'localUuid': sw.localUuid,
        'serverId': sw.serverId,
        'employeeId': sw.employeeId,
        'amount': sw.amount,
        'withdrawDate': sw.withdrawDate,
        'reason': sw.reason,
        'hotelDayKey': sw.hotelDayKey,
        'withdrawalType': sw.withdrawalType,
        'description': sw.description,
        'date': sw.withdrawDate,
        'action': sw.withdrawalType,
        'note': sw.description,
        'expenseId': expenseId,
        'createdAt': sw.createdAt,
        'updatedAt': sw.updatedAt,
        'deletedAt': sw.deletedAt,
        'lastModified': sw.lastModified,
        'createdAtIso': sw.createdAtIso,
        'updatedAtIso': sw.updatedAtIso,
        'deletedAtIso': sw.deletedAtIso,
        'createdAtEpoch': sw.createdAtEpoch,
        'lastModifiedEpoch': sw.lastModifiedEpoch,
        'version': sw.version,
        'origin': sw.origin,
        'vectorClock': sw.vectorClock,
        'deviceId': sw.deviceId,
      };

  Map<String, dynamic> _buildPriceAdjustmentData(dynamic pa) => {
        'id': pa.id,
        'localUuid': pa.localUuid,
        'serverId': pa.serverId,
        'targetType': pa.targetType,
        'targetUuid': pa.targetUuid,
        'adjustmentType': pa.adjustmentType,
        'previousValue': pa.previousValue,
        'newValue': pa.newValue,
        'reason': pa.reason,
        'effectiveDate': pa.effectiveDate,
        'appliedBy': pa.appliedBy,
        'hotelDayKey': pa.hotelDayKey,
        'isReversed': pa.isReversed,
        'reversedAt': pa.reversedAt,
        'reversedBy': pa.reversedBy,
        'createdAt': pa.createdAt,
        'updatedAt': pa.updatedAt,
        'deletedAt': pa.deletedAt,
        'lastModified': pa.lastModified,
        'createdAtIso': pa.createdAtIso,
        'updatedAtIso': pa.updatedAtIso,
        'deletedAtIso': pa.deletedAtIso,
        'createdAtEpoch': pa.createdAtEpoch,
        'lastModifiedEpoch': pa.lastModifiedEpoch,
        'version': pa.version,
        'origin': pa.origin,
        'vectorClock': pa.vectorClock,
        'deviceId': pa.deviceId,
      };

  Map<String, dynamic> _buildBookingPriceAdjustmentData(dynamic bpa) => {
        'id': bpa.id,
        'localUuid': bpa.localUuid,
        'serverId': bpa.serverId,
        'bookingLocalUuid': bpa.bookingLocalUuid,
        'bookingLocalId': bpa.bookingLocalId,
        'roomNumber': bpa.roomNumber,
        'adjustmentType': bpa.adjustmentType,
        'adjustmentMode': bpa.adjustmentMode,
        'amount': bpa.amount,
        'effectiveHotelDay': bpa.effectiveHotelDay,
        'endHotelDay': bpa.endHotelDay,
        'isActive': bpa.isActive,
        'reason': bpa.reason,
        'appliedBy': bpa.appliedBy,
        'cancelledAt': bpa.cancelledAt,
        'cancelledBy': bpa.cancelledBy,
        'createdAt': bpa.createdAt,
        'updatedAt': bpa.updatedAt,
        'deletedAt': bpa.deletedAt,
        'lastModified': bpa.lastModified,
        'createdAtIso': bpa.createdAtIso,
        'updatedAtIso': bpa.updatedAtIso,
        'deletedAtIso': bpa.deletedAtIso,
        'createdAtEpoch': bpa.createdAtEpoch,
        'lastModifiedEpoch': bpa.lastModifiedEpoch,
        'version': bpa.version,
        'origin': bpa.origin,
        'vectorClock': bpa.vectorClock,
        'deviceId': bpa.deviceId,
      };

  Map<String, dynamic> _buildAuditLogData(dynamic al) => {
        'id': al.id,
        'localUuid': al.localUuid,
        'operationType': al.operationType,
        'entityType': al.entityType,
        'entityUuid': al.entityUuid,
        'entityId': al.entityId,
        'previousState': al.previousState,
        'newState': al.newState,
        'changedFields': al.changedFields,
        'performedBy': al.performedBy,
        'deviceId': al.deviceId,
        'ipAddress': al.ipAddress,
        'hotelDayKey': al.hotelDayKey,
        'timestamp': al.timestamp,
        'timestampIso': al.timestampIso,
        'isFinancial': al.isFinancial,
        'amountImpact': al.amountImpact,
        'createdAt': al.createdAt,
      };

  Map<String, dynamic> _buildPaymentVoidData(dynamic pv) => {
        'id': pv.id,
        'localUuid': pv.localUuid,
        'serverId': pv.serverId,
        'originalPaymentUuid': pv.originalPaymentUuid,
        'originalPaymentId': pv.originalPaymentId,
        'bookingUuid': pv.bookingUuid,
        'voidedAmount': pv.voidedAmount,
        'voidReason': pv.voidReason,
        'voidedBy': pv.voidedBy,
        'voidedAt': pv.voidedAt,
        'voidedAtIso': pv.voidedAtIso,
        'hotelDayKey': pv.hotelDayKey,
        'reversalPaymentUuid': pv.reversalPaymentUuid,
        'approvedBy': pv.approvedBy,
        'createdAt': pv.createdAt,
        'updatedAt': pv.updatedAt,
        'deletedAt': pv.deletedAt,
        'lastModified': pv.lastModified,
        'createdAtIso': pv.createdAtIso,
        'updatedAtIso': pv.updatedAtIso,
        'deletedAtIso': pv.deletedAtIso,
        'createdAtEpoch': pv.createdAtEpoch,
        'lastModifiedEpoch': pv.lastModifiedEpoch,
        'version': pv.version,
        'origin': pv.origin,
        'vectorClock': pv.vectorClock,
        'deviceId': pv.deviceId,
      };
}

/// عملية احتياطية — تستخدم لإرسال دفعة
class BackupOperation {
  final String tableName;
  final String documentId;
  final Map<String, dynamic> data;
  final String operation;

  BackupOperation({
    required this.tableName,
    required this.documentId,
    required this.data,
    required this.operation,
  });
}
