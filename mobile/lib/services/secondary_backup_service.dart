// ignore_for_file: prefer_final_locals

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'appwrite_sync_utils.dart';
import 'local_db.dart';
import 'secondary_appwrite_service.dart';

/// إعادة تصدير FullBackupStats من الخدمة الأصلية
export 'secondary_appwrite_service.dart' show FullBackupStats, FullBackupFailure;

/// مراحل النسخة الشاملة
enum BackupPhase {
  preparing('تحضير البيانات...'),
  uploadingRooms('رفع الغرف...'),
  uploadingBookings('رفع الحجوزات...'),
  uploadingPayments('رفع الدفعات...'),
  uploadingExpenses('رفع المصروفات...'),
  uploadingDebts('رفع الديون...'),
  uploadingEmployees('رفع الموظفين...'),
  uploadingBookingNotes('رفع ملاحظات الحجز...'),
  uploadingBookingNights('رفع ليالي الحجز...'),
  uploadingCashTransactions('رفع المعاملات النقدية...'),
  uploadingSalaryCycles('رفع دورات الرواتب...'),
  uploadingSalaryPayments('رفع دفعات الرواتب...'),
  uploadingSalaryWithdrawals('رفع سحوبات الرواتب...'),
  uploadingSalaryCarryOverLogs('رفع ترحيل الرواتب...'),
  uploadingShiftNotes('رفع ملاحظات النوبة...'),
  uploadingPriceAdjustments('رفع تعديلات الأسعار...'),
  uploadingBookingPriceAdjustments('رفع تعديلات الحجوزات...'),
  uploadingAuditLogs('رفع سجلات التدقيق...'),
  uploadingPaymentVoids('رفع إلغاء الدفعات...'),
  uploadingAppSettings('رفع إعدادات التطبيق...'),
  uploadingGuestInfos('رفع معلومات النزلاء...'),
  uploadingBlacklist('رفع القائمة السوداء...'),
  completed('اكتمل!');

  final String label;
  const BackupPhase(this.label);
}

/// حالة التقدم في النسخة الشاملة
class BackupProgress {
  const BackupProgress({
    this.phase = BackupPhase.preparing,
    this.currentCollection = '',
    this.currentRecord = 0,
    this.totalRecords = 0,
    this.collectionProgress = 0,
    this.totalCollections = 0,
    this.completedCollections = 0,
    this.successCount = 0,
    this.failureCount = 0,
    this.isBookingNightsPhase = false,
    this.error,
    this.currentCollectionFailures = 0,
  });

  final BackupPhase phase;
  final String currentCollection;
  final int currentRecord;
  final int totalRecords;
  final int collectionProgress;
  final int totalCollections;
  final int completedCollections;
  final int successCount;
  final int failureCount;
  final bool isBookingNightsPhase;
  final String? error;

  /// عدد الإخفاقات في المجموعة الحالية
  final int currentCollectionFailures;

  double get percentage {
    if (totalRecords == 0) return 0;
    return (collectionProgress / totalRecords).clamp(0.0, 1.0);
  }

  double get overallPercentage {
    if (totalCollections == 0) return 0;
    return (completedCollections / totalCollections).clamp(0.0, 1.0);
  }

  BackupProgress copyWith({
    BackupPhase? phase,
    String? currentCollection,
    int? currentRecord,
    int? totalRecords,
    int? collectionProgress,
    int? totalCollections,
    int? completedCollections,
    int? successCount,
    int? failureCount,
    bool? isBookingNightsPhase,
    String? error,
    int? currentCollectionFailures,
  }) {
    return BackupProgress(
      phase: phase ?? this.phase,
      currentCollection: currentCollection ?? this.currentCollection,
      currentRecord: currentRecord ?? this.currentRecord,
      totalRecords: totalRecords ?? this.totalRecords,
      collectionProgress: collectionProgress ?? this.collectionProgress,
      totalCollections: totalCollections ?? this.totalCollections,
      completedCollections: completedCollections ?? this.completedCollections,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
      isBookingNightsPhase: isBookingNightsPhase ?? this.isBookingNightsPhase,
      error: error,
      currentCollectionFailures: currentCollectionFailures ?? this.currentCollectionFailures,
    );
  }
}

/// خدمة النسخة الشاملة في الخلفية
///
/// تعمل بشكل مستقل عن دورة حياة الـ Widget.
/// تستخدم Stream<BackupProgress> لإرسال التحديثات.
/// يمكن الاشتراك من أي شاشة والغاء الاشتراك عند التنقل.
class SecondaryBackupService {
  factory SecondaryBackupService() =>
      _instance ??= SecondaryBackupService._();

  SecondaryBackupService._();
  static SecondaryBackupService? _instance;

  // ignore: prefer_constructors_over_static_methods
  static SecondaryBackupService get instance => SecondaryBackupService();

  final _progressController = StreamController<BackupProgress>.broadcast();
  final _service = SecondaryAppwriteService();

  bool _isRunning = false;
  bool _cancelled = false;

  /// Stream للتقدم — يظل متاحاً حتى بعد التنقل بين الشاشات
  Stream<BackupProgress> get progressStream => _progressController.stream;

  /// هل النسخة قيد التشغيل حالياً؟
  bool get isRunning => _isRunning;

  /// إلغاء النسخة الحالية
  void cancel() {
    _cancelled = true;
  }

  /// بدء النسخة الشاملة في الخلفية
  ///
  /// تعمل بشكل مستقل — يمكن للمستخدم التنقل بين الشاشات بحرية.
  /// progressStream سيستمر في إرسال التحديثات.
  Future<FullBackupStats> startFullBackup() async {
    if (_isRunning) {
      throw StateError('النسخة الشاملة قيد التشغيل بالفعل');
    }

    _isRunning = true;
    _cancelled = false;
    _progressController.add(const BackupProgress(phase: BackupPhase.preparing));

    try {
      await _service.ensureInitialized();
      final db = DatabaseManager.instance;
      final stats = FullBackupStats();
      final collectionList = await _service.getAllCollections(db);

      stats.totalCollections = collectionList.length;

      final totalCollections = collectionList.length;
      var completedCollections = 0;

      // ─── المرحلة 1: جميع الجداول ما عدا booking_nights ───
      for (final coll in collectionList) {
        if (_cancelled) break;
        if (coll.name == 'booking_nights') continue; // المرحلة الثانية

        final phase = _phaseForCollection(coll.name);
        _progressController.add(BackupProgress(
          phase: phase,
          currentCollection: _collectionLabel(coll.name),
          totalRecords: coll.records.length,
          totalCollections: totalCollections,
          completedCollections: completedCollections,
          isBookingNightsPhase: false,
        ));

        await _uploadCollection(coll, stats, (record, current) {
          if (_cancelled) return;
          _progressController.add(BackupProgress(
            phase: phase,
            currentCollection: _collectionLabel(coll.name),
            currentRecord: current + 1,
            totalRecords: coll.records.length,
            collectionProgress: current + 1,
            totalCollections: totalCollections,
            completedCollections: completedCollections,
            successCount: stats.successCount,
            failureCount: stats.failureCount,
            isBookingNightsPhase: false,
          ));
        });

        completedCollections++;
        stats.collectionNames.add(coll.name);
        if (!_cancelled) {
          _progressController.add(BackupProgress(
            phase: phase,
            currentCollection: _collectionLabel(coll.name),
            totalRecords: coll.records.length,
            collectionProgress: coll.records.length,
            totalCollections: totalCollections,
            completedCollections: completedCollections,
            successCount: stats.successCount,
            failureCount: stats.failureCount,
            isBookingNightsPhase: false,
          ));
        }
      }

      // ─── المرحلة 2: booking_nights منفصلة ───
      if (!_cancelled) {
        final bookingNightsColl = collectionList
            .where((c) => c.name == 'booking_nights')
            .firstOrNull;
        if (bookingNightsColl != null) {
          _progressController.add(BackupProgress(
            phase: BackupPhase.uploadingBookingNights,
            currentCollection: 'ليالي الحجز',
            totalRecords: bookingNightsColl.records.length,
            totalCollections: totalCollections,
            completedCollections: completedCollections,
            isBookingNightsPhase: true,
          ));

          await _uploadCollection(bookingNightsColl, stats, (record, current) {
            if (_cancelled) return;
            _progressController.add(BackupProgress(
              phase: BackupPhase.uploadingBookingNights,
              currentCollection: 'ليالي الحجز',
              currentRecord: current + 1,
              totalRecords: bookingNightsColl.records.length,
              collectionProgress: current + 1,
              totalCollections: totalCollections,
              completedCollections: completedCollections,
              successCount: stats.successCount,
              failureCount: stats.failureCount,
              isBookingNightsPhase: true,
            ));
          });

          completedCollections++;
          stats.collectionNames.add('booking_nights');
          _progressController.add(BackupProgress(
            phase: BackupPhase.uploadingBookingNights,
            currentCollection: 'ليالي الحجز',
            totalRecords: bookingNightsColl.records.length,
            collectionProgress: bookingNightsColl.records.length,
            totalCollections: totalCollections,
            completedCollections: completedCollections,
            successCount: stats.successCount,
            failureCount: stats.failureCount,
            isBookingNightsPhase: true,
          ));
        }
      }

      if (_cancelled) {
        stats.error = 'تم إلغاء النسخة من قبل المستخدم';
      }

      _lastStats = stats;
      _progressController.add(BackupProgress(
        phase: BackupPhase.completed,
        totalCollections: totalCollections,
        completedCollections: completedCollections,
        successCount: stats.successCount,
        failureCount: stats.failureCount,
        error: stats.error,
      ));

      return stats;
    } catch (e) {
      _progressController.add(BackupProgress(
        phase: BackupPhase.completed,
        error: 'فشل: $e',
      ));
      rethrow;
    } finally {
      _isRunning = false;
      _cancelled = false;
    }
  }

  /// رفع مجموعة واحدة مع تتبع التقدم
  Future<void> _uploadCollection(
    CollectionData coll,
    FullBackupStats stats,
    void Function(Map<String, dynamic> record, int index) onProgress,
  ) async {
    int successCount = 0;
    int failureCount = 0;

    int runningFailureCount = 0;

    for (int i = 0; i < coll.records.length; i++) {
      if (_cancelled) return;

      final record = coll.records[i];

      final documentId = (record['localUuid'] as String?)?.trim();
      if (documentId == null || documentId.isEmpty) {
        failureCount++;
        const reason = 'تخطّي سجل بلا localUuid صالح';
        stats.failuresByCollection.putIfAbsent(coll.name, () => []).add(
          FullBackupFailure(reason: reason, collectionName: coll.name),
        );
        stats.errorsByReason[reason] = (stats.errorsByReason[reason] ?? 0) + 1;
        onProgress(record, i);
        continue;
      }

      try {
        final sanitized = AppwriteSyncUtils.sanitizePayload(
          coll.name,
          record,
          collectionId: coll.collectionId,
        );
        final enhancedData = Map<String, dynamic>.from(sanitized);
        final now = DateTime.now().millisecondsSinceEpoch;
        enhancedData['syncTimestamp'] ??= now;
        enhancedData['idempotencyKey'] ??=
            'backup_${coll.name}_${documentId}_$now';
        enhancedData['sync_origin'] ??= 'secondary_backup';
        await _service.upsertDocument(
          collectionId: coll.collectionId,
          documentId: documentId,
          data: enhancedData,
        );
        successCount++;
      } catch (e) {
        runningFailureCount++;
        failureCount++;
        final reason = e.toString();
        final failure = FullBackupFailure(
          documentId: documentId,
          reason: reason,
          collectionName: coll.name,
          timestamp: DateTime.now(),
        );
        stats.failuresByCollection.putIfAbsent(coll.name, () => []).add(failure);
        stats.failedRecords.add(failure);
        final reasonShort = reason.length > 500 ? reason.substring(0, 500) : reason;
        stats.errorsByReason[reasonShort] = (stats.errorsByReason[reasonShort] ?? 0) + 1;
      }

      onProgress(record, i);
    }

    stats.collectionDetails.add({
      'name': coll.name,
      'total': coll.records.length,
      'success': successCount,
      'failure': failureCount,
      'isFullySuccessful': failureCount == 0,
    });
    stats.successCount += successCount;
    stats.failureCount += failureCount;
    if (failureCount == 0) {
      stats.fullySuccessfulCollections++;
    } else {
      stats.failedCollections++;
    }
  }

  BackupPhase _phaseForCollection(String name) {
    switch (name) {
      case 'rooms': return BackupPhase.uploadingRooms;
      case 'bookings': return BackupPhase.uploadingBookings;
      case 'payments': return BackupPhase.uploadingPayments;
      case 'expenses': return BackupPhase.uploadingExpenses;
      case 'debts': return BackupPhase.uploadingDebts;
      case 'employees': return BackupPhase.uploadingEmployees;
      case 'booking_notes': return BackupPhase.uploadingBookingNotes;
      case 'cash_transactions': return BackupPhase.uploadingCashTransactions;
      case 'salary_cycles': return BackupPhase.uploadingSalaryCycles;
      case 'salary_payments': return BackupPhase.uploadingSalaryPayments;
      case 'salary_withdrawals': return BackupPhase.uploadingSalaryWithdrawals;
      case 'salary_carry_over_logs': return BackupPhase.uploadingSalaryCarryOverLogs;
      case 'shift_notes': return BackupPhase.uploadingShiftNotes;
      case 'price_adjustments': return BackupPhase.uploadingPriceAdjustments;
      case 'booking_price_adjustments': return BackupPhase.uploadingBookingPriceAdjustments;
      case 'audit_logs': return BackupPhase.uploadingAuditLogs;
      case 'payment_voids': return BackupPhase.uploadingPaymentVoids;
      case 'app_settings': return BackupPhase.uploadingAppSettings;
      case 'guest_infos': return BackupPhase.uploadingGuestInfos;
      default: return BackupPhase.uploadingRooms;
    }
  }

  String _collectionLabel(String name) {
    switch (name) {
      case 'rooms': return 'الغرف';
      case 'bookings': return 'الحجوزات';
      case 'payments': return 'الدفعات';
      case 'expenses': return 'المصروفات';
      case 'debts': return 'الديون';
      case 'employees': return 'الموظفين';
      case 'booking_notes': return 'ملاحظات الحجز';
      case 'booking_nights': return 'ليالي الحجز';
      case 'cash_transactions': return 'المعاملات النقدية';
      case 'salary_cycles': return 'دورات الرواتب';
      case 'salary_payments': return 'دفعات الرواتب';
      case 'salary_withdrawals': return 'سحوبات الرواتب';
      case 'salary_carry_over_logs': return 'ترحيل الرواتب';
      case 'shift_notes': return 'ملاحظات النوبة';
      case 'price_adjustments': return 'تعديلات الأسعار';
      case 'booking_price_adjustments': return 'تعديلات الحجوزات';
      case 'audit_logs': return 'سجلات التدقيق';
      case 'payment_voids': return 'إلغاء الدفعات';
      case 'app_settings': return 'إعدادات التطبيق';
      case 'guest_infos': return 'معلومات النزلاء';
      default: return name;
    }
  }

  /// آخر نسخة شاملة مكتملة (للوصول إلى الأخطاء بعد الانتهاء)
  FullBackupStats? _lastStats;

  /// الحصول على آخر إحصائيات النسخة
  FullBackupStats? get lastStats => _lastStats;

  /// نص الأخطاء المنسق جاهز للنسخ إلى الحافظة
  String get errorReportText {
    if (_lastStats == null) return 'لا توجد نسخة سابقة';
    return _lastStats!.textSummary;
  }

  /// أخطاء مجموعة محددة كـ String للنسخ
  String errorsForCollection(String collectionName) {
    if (_lastStats == null) return '';
    final failures = _lastStats!.failuresByCollection[collectionName];
    if (failures == null || failures.isEmpty) return '✅ لا توجد أخطاء في $collectionName';

    final buf = StringBuffer();
    buf.writeln('❌ أخطاء $collectionName (${failures.length}):');
    for (final f in failures) {
      buf.writeln('  · $f');
    }
    return buf.toString();
  }

  /// تنظيف الموارد
  void dispose() {
    _progressController.close();
  }
}
