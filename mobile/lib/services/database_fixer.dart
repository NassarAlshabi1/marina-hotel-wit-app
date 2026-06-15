import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'local_db.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// خدمة لإصلاح البيانات الفاسدة في قاعدة البيانات
class DatabaseFixer {

  DatabaseFixer(this.db);
  final AppDatabase db;

  /// إصلاح جميع المشاكل المعروفة في قاعدة البيانات
  Future<FixResult> fixAllIssues() async {
    final result = FixResult();

    try {
      // 1. إصلاح serverId التي تحتوي على UUID بدلاً من أرقام
      result.serverIdFixed = await _fixInvalidServerIds();

      // 2. إصلاح المدفوعات التي تشير لحجوزات غير موجودة
      result.orphanPaymentsFixed = await _fixOrphanPayments();

      // 3. إصلاح المصروفات التي تشير لبيانات غير موجودة
      result.orphanExpensesFixed = await _fixOrphanExpenses();

      result.success = true;
    } catch (e) {
      result.error = e.toString();
      result.success = false;
    }

    return result;
  }

  /// إصلاح serverId التي تحتوي على UUID
  Future<int> _fixInvalidServerIds() async {
    int fixed = 0;

    try {
      // إصلاح serverId في جدول Rooms
      final roomsQuery = await db
          .customSelect(
            'SELECT id, server_id FROM rooms WHERE server_id IS NOT NULL',
          )
          .get();

      for (final row in roomsQuery) {
        final serverId = row.data['server_id'];
        if (serverId != null && serverId is String) {
          // إذا كان serverId يحتوي على UUID (يحتوي على -)
          if (serverId.contains('-')) {
            await db.customUpdate(
              'UPDATE rooms SET server_id = NULL WHERE id = ?',
              variables: [Variable.withInt(row.data['id'] as int)],
              updates: {db.rooms},
            );
            fixed++;
          }
        }
      }

      // إصلاح serverId في جدول Payments
      final paymentsQuery = await db
          .customSelect(
            'SELECT id, server_id FROM payments WHERE server_id IS NOT NULL',
          )
          .get();

      for (final row in paymentsQuery) {
        final serverId = row.data['server_id'];
        if (serverId != null && serverId is String) {
          if (serverId.contains('-')) {
            await db.customUpdate(
              'UPDATE payments SET server_id = NULL WHERE id = ?',
              variables: [Variable.withInt(row.data['id'] as int)],
              updates: {db.payments},
            );
            fixed++;
          }
        }
      }

      // إصلاح serverId في جدول Expenses
      final expensesQuery = await db
          .customSelect(
            'SELECT id, server_id FROM expenses WHERE server_id IS NOT NULL',
          )
          .get();

      for (final row in expensesQuery) {
        final serverId = row.data['server_id'];
        if (serverId != null && serverId is String) {
          if (serverId.contains('-')) {
            await db.customUpdate(
              'UPDATE expenses SET server_id = NULL WHERE id = ?',
              variables: [Variable.withInt(row.data['id'] as int)],
              updates: {db.expenses},
            );
            fixed++;
          }
        }
      }

      AppLogger.info('Fixed $fixed invalid serverId records', tag: 'APP');
    } catch (e) {
      AppLogger.info('Error fixing serverId: $e', tag: 'APP');
    }

    return fixed;
  }

  /// إصلاح المدفوعات اليتيمة (التي تشير لحجوزات غير موجودة)
  Future<int> _fixOrphanPayments() async {
    int fixed = 0;

    try {
      // البحث عن المدفوعات التي تشير لحجوزات غير موجودة
      final orphanPayments = await db.customSelect('''
        SELECT p.id, p.booking_local_id, p.room_number
        FROM payments p
        LEFT JOIN bookings b ON p.booking_local_id = b.id
        WHERE p.booking_local_id IS NOT NULL 
          AND b.id IS NULL
          AND p.deleted_at IS NULL
        ''').get();

      for (final payment in orphanPayments) {
        final paymentId = payment.data['id'] as int;
        // إزالة الربط بالحجز غير الموجود
        await db.customUpdate(
          'UPDATE payments SET booking_local_id = NULL WHERE id = ?',
          variables: [Variable.withInt(paymentId)],
          updates: {db.payments},
        );
        fixed++;
        AppLogger.info('Fixed orphan payment: $paymentId', tag: 'APP');
      }

      AppLogger.info('Fixed $fixed orphan payments', tag: 'APP');
    } catch (e) {
      AppLogger.info('Error fixing orphan payments: $e', tag: 'APP');
    }

    return fixed;
  }

  /// إصلاح المصروفات اليتيمة
  Future<int> _fixOrphanExpenses() async {
    int fixed = 0;

    try {
      // البحث عن المصروفات التي تشير لبيانات غير موجودة
      final orphanExpenses = await db.customSelect('''
        SELECT e.id, e.related_id, e.expense_type
        FROM expenses e
        WHERE e.related_id IS NOT NULL 
          AND e.deleted_at IS NULL
        ''').get();

      for (final expense in orphanExpenses) {
        final expenseId = expense.data['id'] as int;
        final relatedId = expense.data['related_id'] as int?;
        final expenseType = expense.data['expense_type'] as String;

        bool shouldFix = false;

        // التحقق من وجود البيانات المرتبطة بناءً على نوع المصروف
        if (relatedId != null) {
          if (expenseType == 'employee') {
            final employee = await (db.select(
              db.employees,
            )..where((e) => e.id.equals(relatedId))).getSingleOrNull();
            if (employee == null) {
              shouldFix = true;
            }
          } else if (expenseType == 'booking') {
            final booking = await (db.select(
              db.bookings,
            )..where((b) => b.id.equals(relatedId))).getSingleOrNull();
            if (booking == null) {
              shouldFix = true;
            }
          }
        }

        if (shouldFix) {
          // إزالة الربط بالبيانات غير الموجودة
          await db.customUpdate(
            'UPDATE expenses SET related_id = NULL WHERE id = ?',
            variables: [Variable.withInt(expenseId)],
            updates: {db.expenses},
          );
          fixed++;
          AppLogger.info('Fixed orphan expense: $expenseId', tag: 'APP');
        }
      }

      AppLogger.info('Fixed $fixed orphan expenses', tag: 'APP');
    } catch (e) {
      AppLogger.info('Error fixing orphan expenses: $e', tag: 'APP');
    }

    return fixed;
  }

  /// التحقق من صحة قاعدة البيانات
  Future<ValidationReport> validate() async {
    final report = ValidationReport();

    try {
      // التحقق من serverId الفاسدة
      final invalidServerIds = await db.customSelect('''
        SELECT 'rooms' as table_name, COUNT(*) as count 
        FROM rooms 
        WHERE server_id IS NOT NULL AND typeof(server_id) = 'text' AND server_id LIKE '%-%'
        UNION ALL
        SELECT 'payments', COUNT(*) 
        FROM payments 
        WHERE server_id IS NOT NULL AND typeof(server_id) = 'text' AND server_id LIKE '%-%'
        UNION ALL
        SELECT 'expenses', COUNT(*) 
        FROM expenses 
        WHERE server_id IS NOT NULL AND typeof(server_id) = 'text' AND server_id LIKE '%-%'
        ''').get();

      int totalInvalidServerIds = 0;
      for (final row in invalidServerIds) {
        final count = row.data['count'] as int;
        totalInvalidServerIds += count;
      }
      report.invalidServerIds = totalInvalidServerIds;

      // التحقق من المدفوعات اليتيمة
      final orphanPaymentsResult = await db.customSelect('''
        SELECT COUNT(*) as count
        FROM payments p
        LEFT JOIN bookings b ON p.booking_local_id = b.id
        WHERE p.booking_local_id IS NOT NULL 
          AND b.id IS NULL
          AND p.deleted_at IS NULL
        ''').getSingle();

      report.orphanPayments = orphanPaymentsResult.data['count'] as int;

      // التحقق من المصروفات اليتيمة
      final orphanExpensesResult = await db.customSelect('''
        SELECT COUNT(*) as count
        FROM expenses e
        WHERE e.related_id IS NOT NULL 
          AND e.deleted_at IS NULL
        ''').getSingle();

      report.orphanExpenses = orphanExpensesResult.data['count'] as int;

      report.hasIssues =
          report.invalidServerIds > 0 ||
          report.orphanPayments > 0 ||
          report.orphanExpenses > 0;
    } catch (e) {
      report.error = e.toString();
    }

    return report;
  }
}

class FixResult {
  bool success = false;
  String? error;
  int serverIdFixed = 0;
  int orphanPaymentsFixed = 0;
  int orphanExpensesFixed = 0;

  int get totalFixed =>
      serverIdFixed + orphanPaymentsFixed + orphanExpensesFixed;

  @override
  String toString() {
    if (!success) {
      return 'فشل الإصلاح: $error';
    }
    return '''
تم الإصلاح بنجاح:
- serverId فاسدة: $serverIdFixed
- مدفوعات يتيمة: $orphanPaymentsFixed
- مصروفات يتيمة: $orphanExpensesFixed
الإجمالي: $totalFixed
    ''';
  }
}

class ValidationReport {
  bool hasIssues = false;
  String? error;
  int invalidServerIds = 0;
  int orphanPayments = 0;
  int orphanExpenses = 0;

  int get totalIssues => invalidServerIds + orphanPayments + orphanExpenses;

  @override
  String toString() {
    if (error != null) {
      return 'خطأ في التحقق: $error';
    }
    if (!hasIssues) {
      return 'قاعدة البيانات صحيحة ✓';
    }
    return '''
تم العثور على مشاكل:
- serverId فاسدة: $invalidServerIds
- مدفوعات يتيمة: $orphanPayments
- مصروفات يتيمة: $orphanExpenses
الإجمالي: $totalIssues
    ''';
  }
}
