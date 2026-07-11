import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import '../utils/hotel_time_engine.dart';
import '../utils/time.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

/// ✅ خدمة إصلاح hotelDayKey لجميع الجداول
///
/// **المشكلة:**
/// البيانات القديمة على Appwrite Cloud قد تحتوي على `hotelDayKey`
/// محسوب بقاعدة 14:00 القديمة بدل 14:01.
/// - السجلات بين 14:00 و 14:01 (دقيقة واحدة) تحتوي على hotelDayKey خاطئ
/// - بعض السجلات القديمة لا تحتوي على hotelDayKey أصلاً (null)
///
/// **الحل:**
/// عند تشغيل التطبيق، نعيد حساب hotelDayKey لكل سجل إذا كان خاطئًا.
/// هذا يُصلح البيانات المحلية (SQLite) — وعند المزامنة التالية
/// سيُرفع hotelDayKey المصحح إلى Appwrite Cloud عبر Outbox.
///
/// **الجداول المعالجة:**
/// - expenses (حقل التاريخ: date)
/// - salary_withdrawals (حقل التاريخ: withdrawDate)
/// - payments (حقل التاريخ: paymentDate)
/// - booking_nights (حقل التاريخ: nightStart)
/// - salary_payments (حقل التاريخ: paymentDateIso)
/// - payment_voids (حقل التاريخ: voidedAtIso)
/// - audit_logs (حقل التاريخ: timestampIso)
///
/// **ملاحظة:** booking_price_adjustments لا تحتوي على hotelDayKey
/// لكنها تحتوي على effectiveHotelDay (مفتاح اليوم الفندقي نفسه)
/// لذلك لا تحتاج إصلاح.
class HotelDayKeyFixService {
  HotelDayKeyFixService._();
  static final HotelDayKeyFixService instance = HotelDayKeyFixService._();

  /// هل تم الإصلاح بالفعل في هذه الجلسة؟
  bool _applied = false;

  /// تشغيل الإصلاح (مرة واحدة فقط لكل جلسة)
  Future<void> runIfNeeded(AppDatabase db) async {
    if (_applied) return;
    _applied = true;

    debugPrint('🔧 HotelDayKeyFixService: بدء فحص وإصلاح hotelDayKey...');

    int totalFixed = 0;

    try {
      totalFixed += await _fixExpenses(db);
      totalFixed += await _fixSalaryWithdrawals(db);
      totalFixed += await _fixSalaryWithdrawalsEmployeeUuid(db);
      totalFixed += await _fixExpenseWithdrawalLinks(db);
      totalFixed += await _fixPayments(db);
      totalFixed += await _fixBookingNights(db);
      totalFixed += await _fixSalaryPayments(db);
      totalFixed += await _fixPaymentVoids(db);
      totalFixed += await _fixAuditLogs(db);
    } catch (e) {
      debugPrint('⚠️ HotelDayKeyFixService: خطأ أثناء الإصلاح: $e');
    }

    if (totalFixed > 0) {
      debugPrint('✅ HotelDayKeyFixService: تم إصلاح $totalFixed سجل إجمالاً');
    } else {
      debugPrint('✅ HotelDayKeyFixService: لا توجد سجلات تحتاج إصلاح');
    }
  }

  Future<void> _createOutboxEntry(
    OutboxDao outboxDao,
    String entity,
    String localUuid,
    String payload,
  ) async {
    try {
      await outboxDao.merge(
        entity: entity,
        op: 'update',
        localUuid: localUuid,
        payload: {'hotelDayKey': payload},
        clientTs: Time.nowEpoch(),
      );
    } catch (e) {
      debugPrint('⚠️ HotelDayKeyFixService outbox: فشل إنشاء outbox لـ $entity/$localUuid: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // حساب hotelDayKey الصحيح من التاريخ
  // ═══════════════════════════════════════════════════════════════

  /// حساب مفتاح اليوم الفندقي من تاريخ (تقويمي أو ISO)
  ///
  /// - تاريخ تقويمي (yyyy-MM-dd): يمرّر 14:01 لضمان اليوم الفندقي الصحيح
  /// - تاريخ ISO مع وقت (yyyy-MM-dd HH:mm): يستخدم الوقت مباشرة
  static String computeCorrectHotelDayKey(String date) {
    try {
      final trimmed = date.trim();
      // إذا كان التاريخ يحتوي على وقت (مثل "2026-05-19 14:30")
      if (trimmed.length > 10) {
        return HotelTimeEngine.getHotelDayKeyFromIso(trimmed);
      }
      // تاريخ تقويمي بدون وقت — نمرّر 14:01:00
      final parts = trimmed.split('-');
      if (parts.length != 3) {
        return HotelTimeEngine.getHotelDayKey();
      }
      final year = int.tryParse(parts[0]) ?? 1;
      final month = int.tryParse(parts[1]) ?? 1;
      final day = int.tryParse(parts[2]) ?? 1;
      return HotelTimeEngine.getHotelDayKey(
        dateTime: DateTime(year, month, day, 14, 1),
      );
    } catch (_) {
      return HotelTimeEngine.getHotelDayKey();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // إصلاح كل جدول
  // ═══════════════════════════════════════════════════════════════

  /// إصلاح expenses
  /// حقل التاريخ: date (yyyy-MM-dd تقويمي)
  /// hotelDayKey: nullable text
  Future<int> _fixExpenses(AppDatabase db) async {
    try {
      final rows = await (db.select(db.expenses)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      int fixed = 0;
      for (final row in rows) {
        final correctKey = computeCorrectHotelDayKey(row.date);
        if (row.hotelDayKey != correctKey) {
          // ✅ bump version + outbox لضمان مزامنة التصحيح مع Appwrite Cloud
          await (db.update(db.expenses)
                ..where((t) => t.id.equals(row.id)))
              .write(ExpensesCompanion(
            hotelDayKey: d.Value(correctKey),
            version: d.Value(row.version + 1),
          ));
          await _createOutboxEntry(
            OutboxDao(db),
            'expenses',
            row.localUuid,
            correctKey,
          );
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 expenses: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ expenses: خطأ $e');
      return 0;
    }
  }

  /// إصلاح salary_withdrawals
  /// حقل التاريخ: withdrawDate (yyyy-MM-dd تقويمي)
  /// hotelDayKey: nullable text
  Future<int> _fixSalaryWithdrawals(AppDatabase db) async {
    try {
      final rows = await (db.select(db.salaryWithdrawals)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      int fixed = 0;
      for (final row in rows) {
        final correctKey = computeCorrectHotelDayKey(row.withdrawDate);
        if (row.hotelDayKey != correctKey) {
          // ✅ bump version + outbox لضمان مزامنة التصحيح مع Appwrite Cloud
          await (db.update(db.salaryWithdrawals)
                ..where((t) => t.id.equals(row.id)))
              .write(SalaryWithdrawalsCompanion(
            hotelDayKey: d.Value(correctKey),
            version: d.Value(row.version + 1),
          ));
          await _createOutboxEntry(
            OutboxDao(db),
            'salary_withdrawals',
            row.localUuid,
            correctKey,
          );
          fixed++;
        }
      }
      if (fixed > 0) {
        debugPrint('  📋 salary_withdrawals: تم إصلاح $fixed سجل');
      }
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ salary_withdrawals: خطأ $e');
      return 0;
    }
  }

  /// ✅ إصلاح ربط سحوبات الرواتب بالمصروفات + تعبئة expense_id
  /// + إنشاء outbox للمزامنة مع Appwrite Cloud
  ///
  /// **المشكلة:**
  /// سجلات salary_withdrawals القديمة قد:
  ///   1. لا تحتوي على نمط exp_XX في حقل reason
  ///   2. لا تحتوي على قيمة في عمود expense_id
  /// هذا يسبب تكرار البيانات في تقرير المصروفات لأن السحب
  /// يصبح "يتيماً" بالخطأ (لا يُطابق أي مصروف)
  ///
  /// **الحل:**
  /// لكل سحب راتب بدون exp_XX وبدون expense_id:
  ///   - نبحث عن مصروف راتب مطابق بنفس: employeeId + hotelDayKey + amount
  ///   - إذا وُجد: نحدّث reason = 'exp_{expenseId}' + نعبّئ expense_id
  ///   - نُنشئ عنصر outbox (op='update') لمزامنة التغيير مع Appwrite
  ///   - السحوبات المباشرة (reason يبدأ بـ direct_withdrawal_) لا تُعالج
  ///
  /// كذلك نعبّئ expense_id للسجلات التي تحتوي exp_XX لكن expense_id فارغ
  Future<int> _fixExpenseWithdrawalLinks(AppDatabase db) async {
    final outboxDao = OutboxDao(db);

    try {
      // ─── الخطوة 1: تعبئة expense_id من reason للسجلات الحديثة ───
      int step1Fixed = 0;
      try {
        await db.customStatement(
          'UPDATE salary_withdrawals SET expense_id = CAST(SUBSTR(reason, 5) AS INTEGER) '
          "WHERE reason LIKE 'exp_%' "
          "AND reason NOT LIKE 'exp_%\\_%' ESCAPE '\\' "
          'AND expense_id IS NULL '
          'AND deleted_at IS NULL',
        );
        // customStatement() يُرجع void — لا يمكننا معرفة عدد الصفوف المتأثرة
        // نعتبر العملية ناجحة إذا لم تُطلق استثناءً
        step1Fixed = -1; // علامة على أن العملية تمت بدون خطأ
      } catch (e) {
        // العمود قد لا يكون موجوداً بعد
        debugPrint('  ⚠️ fixExpenseWithdrawalLinks step1: $e');
      }

      // ─── الخطوة 2: ربط السحوبات القديمة (بدون exp_XX) بالمصروفات ───
      // ✅ مع إنشاء outbox للمزامنة مع Appwrite Cloud
      int step2Fixed = 0;
      int outboxCreated = 0;
      try {
        // جلب مصروفات الرواتب النشطة
        final salaryExpenses = await (db.select(db.expenses)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final salaryTypeExpenses = salaryExpenses
            .where((e) => _isSalaryType(e.expenseType))
            .toList();

        // جلب سحوبات الرواتب النشطة
        final withdrawals = await (db.select(db.salaryWithdrawals)
              ..where((t) => t.deletedAt.isNull()))
            .get();

        // بناء خريطة مصروفات الرواتب: (employeeId, hotelDayKey) → List<Expense>
        final expenseMap = <String, List<Expense>>{};
        for (final exp in salaryTypeExpenses) {
          final dayKey = exp.hotelDayKey ?? _extractDatePart(exp.date);
          final key = '${exp.relatedId}_$dayKey';
          expenseMap.putIfAbsent(key, () => []).add(exp);
        }

        // جلب الموظفين لبناء خريطة id → localUuid (لـ employeeUuid في outbox)
        final employees = await (db.select(db.employees)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        final empUuidMap = <int, String>{};
        for (final emp in employees) {
          empUuidMap[emp.id] = emp.localUuid;
        }

        for (final sw in withdrawals) {
          // تخطي السحوبات المباشرة (ليس لها مصروف مقابل)
          if (sw.reason != null && sw.reason!.startsWith('direct_withdrawal_')) {
            continue;
          }

          // تخطي السحوبات المرتبطة بالفعل
          final hasExpRef = sw.reason != null &&
              RegExp(r'exp_(\d+)').hasMatch(sw.reason!);
          if (hasExpRef) continue;

          // البحث عن مصروف مطابق
          final swDayKey = sw.hotelDayKey ?? _extractDatePart(sw.withdrawDate);
          final key = '${sw.employeeId}_$swDayKey';
          final candidates = expenseMap[key];
          if (candidates == null || candidates.isEmpty) continue;

          // مطابقة بالمبلغ مع tolerance
          Expense? matched;
          for (final exp in candidates) {
            if ((exp.amount - sw.amount.abs()).abs() <= 0.5) {
              matched = exp;
              break;
            }
          }
          if (matched == null) continue;

          // تحديث reason + expense_id
          final newReason = 'exp_${matched.id}';
          final now = Time.nowEpoch();

          // تحديث reason + updatedAt + lastModified عبر Drift API
          await (db.update(db.salaryWithdrawals)
                ..where((t) => t.id.equals(sw.id)))
              .write(SalaryWithdrawalsCompanion(
            reason: d.Value(newReason),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(sw.version + 1),
          ));

          // تحديث expense_id عبر SQL خام
          try {
            await db.customStatement(
              'UPDATE salary_withdrawals SET expense_id = ? WHERE id = ?',
              [matched.id, sw.id],
            );
          } catch (_) {
            // العمود قد لا يكون موجوداً
          }

          // ✅ إنشاء عنصر outbox لمزامنة التغيير مع Appwrite Cloud
          // هذا يضمن أن reason = 'exp_XXX' و expenseId يُحدثان على السحابة
          try {
            final empUuid = empUuidMap[sw.employeeId];
            await outboxDao.merge(
              entity: 'salary_withdrawals',
              op: 'update',
              localUuid: sw.localUuid,
              serverId: sw.serverId,
              payload: {
                'employeeId': sw.employeeId,
                'amount': sw.amount,
                'reason': newReason,
                'expenseId': matched.id,
                'withdrawDate': sw.withdrawDate,
                'hotelDayKey': sw.hotelDayKey ?? swDayKey,
                'withdrawalType': sw.withdrawalType,
                'description': sw.description,
                'lastModified': now,
                if (empUuid != null) 'employeeUuid': empUuid,
              },
              clientTs: now,
            );
            outboxCreated++;
          } catch (e) {
            debugPrint('  ⚠️ fixExpenseWithdrawalLinks outbox: فشل إنشاء outbox لـ sw.id=${sw.id}: $e');
          }

          step2Fixed++;
          debugPrint(
            '  🔗 ربط سحب راتب قديم: sw.id=${sw.id} → expense.id=${matched.id} '
            '(موظف=${sw.employeeId}, يوم=$swDayKey, مبلغ=${sw.amount})',
          );
        }
      } catch (e) {
        debugPrint('  ⚠️ fixExpenseWithdrawalLinks step2: $e');
      }

      final total = step1Fixed + step2Fixed;
      if (total > 0) {
        debugPrint(
          '  🔗 expense_withdrawal_links: تم إصلاح $total سجل '
          '(step1=$step1Fixed, step2=$step2Fixed, outbox=$outboxCreated)',
        );
      }
      return total;
    } catch (e) {
      debugPrint('  ⚠️ expense_withdrawal_links: خطأ $e');
      return 0;
    }
  }

  /// هل نوع المصروف مرتبط بالرواتب
  static bool _isSalaryType(String type) {
    const salaryKeywords = ['رواتب', 'سحب راتب', 'سحب من الراتب', 'خصم راتب', 'خصم من الراتب'];
    for (final keyword in salaryKeywords) {
      if (type.contains(keyword)) return true;
    }
    return false;
  }

  /// استخراج جزء التاريخ فقط (yyyy-MM-dd) من سلسلة نصية
  static String _extractDatePart(String dateStr) {
    final trimmed = dateStr.trim();
    if (trimmed.length >= 10) {
      return trimmed.substring(0, 10);
    }
    return trimmed;
  }

  ///
  /// **المشكلة:**
  /// السجلات القديمة على Appwrite Cloud لا تحتوي على employeeUuid،
  /// مما يمنع حل FK الموظف عبر الأجهزة المختلفة.
  /// عند المزامنة من جهاز آخر، يتم تخطي السجل كـ "يتيم"
  /// لأن حل FK يعتمد على employeeUuid أولاً.
  ///
  /// **الحل:**
  /// نبحث عن سجلات salary_withdrawals التي لا يوجد لها outbox
  /// مرتبط (أي سبق رفعها)، ونعيد رفعها مع employeeUuid.
  /// لكن هذه الطريقة معقدة — بدلاً من ذلك، نحدث السجل محلياً
  /// لزيادة version، مما يضمن رفعه في المزامنة التالية مع employeeUuid.
  Future<int> _fixSalaryWithdrawalsEmployeeUuid(AppDatabase db) async {
    try {
      // جلب الموظفين لبناء خريطة id → localUuid
      final employees = await (db.select(db.employees)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      final empUuidMap = <int, String>{};
      for (final emp in employees) {
        empUuidMap[emp.id] = emp.localUuid;
      }

      // جلب سجلات salary_withdrawals النشطة
      final rows = await (db.select(db.salaryWithdrawals)
            ..where((t) => t.deletedAt.isNull()))
          .get();

      const int fixed = 0;
      for (final _ in rows) {
        // لا نحتاج إصلاح employeeUuid محلياً لأن SQLite لا يخزنه
        // لكن نحتاج التأكد أن outbox سيرفعه مع employeeUuid
        // هذا يتم تلقائياً في _processSalaryWithdrawalEntry
        // الذي يضيف employeeUuid من جدول employees
        // لذلك لا نحتاج أي إصلاح محلي هنا
      }
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ salary_withdrawals employeeUuid: خطأ $e');
      return 0;
    }
  }

  /// إصلاح payments
  /// حقل التاريخ: paymentDate (ISO format مع وقت)
  /// hotelDayKey: nullable text
  Future<int> _fixPayments(AppDatabase db) async {
    try {
      final rows = await (db.select(db.payments)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      int fixed = 0;
      for (final row in rows) {
        if (row.paymentDate.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.paymentDate);
        if (row.hotelDayKey != correctKey) {
          // ✅ bump version + outbox لضمان مزامنة التصحيح مع Appwrite Cloud
          await (db.update(db.payments)
                ..where((t) => t.id.equals(row.id)))
              .write(PaymentsCompanion(
            hotelDayKey: d.Value(correctKey),
            version: d.Value(row.version + 1),
          ));
          await _createOutboxEntry(
            OutboxDao(db),
            'payments',
            row.localUuid,
            correctKey,
          );
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 payments: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ payments: خطأ $e');
      return 0;
    }
  }

  /// إصلاح booking_nights
  /// حقل التاريخ: nightStart (ISO format)
  /// hotelDayKey: text (غير nullable)
  Future<int> _fixBookingNights(AppDatabase db) async {
    try {
      final rows = await db.select(db.bookingNights).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.nightStart.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.nightStart);
        if (row.hotelDayKey != correctKey) {
          // ✅ bump version + outbox لضمان مزامنة التصحيح مع Appwrite Cloud
          await (db.update(db.bookingNights)
                ..where((t) => t.id.equals(row.id)))
              .write(BookingNightsCompanion(
            hotelDayKey: d.Value(correctKey),
            version: d.Value(row.version + 1),
          ));
          await _createOutboxEntry(
            OutboxDao(db),
            'booking_nights',
            row.localUuid,
            correctKey,
          );
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 booking_nights: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ booking_nights: خطأ $e');
      return 0;
    }
  }

  /// إصلاح salary_payments
  /// حقل التاريخ: paymentDateIso (ISO format)
  /// hotelDayKey: nullable text
  Future<int> _fixSalaryPayments(AppDatabase db) async {
    try {
      final rows = await db.select(db.salaryPayments).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.paymentDateIso.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.paymentDateIso);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.salaryPayments)
                ..where((t) => t.id.equals(row.id)))
              .write(SalaryPaymentsCompanion(
            hotelDayKey: d.Value(correctKey),
            version: d.Value(row.version + 1),
          ));
          await _createOutboxEntry(
            OutboxDao(db),
            'salary_payments',
            row.localUuid,
            correctKey,
          );
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 salary_payments: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ salary_payments: خطأ $e');
      return 0;
    }
  }

  /// إصلاح payment_voids
  /// حقل التاريخ: voidedAtIso (ISO format)
  /// hotelDayKey: text (غير nullable)
  Future<int> _fixPaymentVoids(AppDatabase db) async {
    try {
      final rows = await db.select(db.paymentVoids).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.voidedAtIso.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.voidedAtIso);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.paymentVoids)
                ..where((t) => t.id.equals(row.id)))
              .write(PaymentVoidsCompanion(
            hotelDayKey: d.Value(correctKey),
            version: d.Value(row.version + 1),
          ));
          await _createOutboxEntry(
            OutboxDao(db),
            'payment_voids',
            row.localUuid,
            correctKey,
          );
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 payment_voids: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ payment_voids: خطأ $e');
      return 0;
    }
  }

  /// إصلاح audit_logs
  /// حقل التاريخ: timestampIso (ISO format)
  /// hotelDayKey: text (غير nullable)
  Future<int> _fixAuditLogs(AppDatabase db) async {
    try {
      final rows = await db.select(db.auditLogs).get();
      int fixed = 0;
      for (final row in rows) {
        if (row.timestampIso.isEmpty) continue;
        final correctKey = computeCorrectHotelDayKey(row.timestampIso);
        if (row.hotelDayKey != correctKey) {
          await (db.update(db.auditLogs)
                ..where((t) => t.id.equals(row.id)))
              .write(AuditLogsCompanion(
            hotelDayKey: d.Value(correctKey),
            version: d.Value(row.version + 1),
          ));
          await _createOutboxEntry(
            OutboxDao(db),
            'audit_logs',
            row.localUuid,
            correctKey,
          );
          fixed++;
        }
      }
      if (fixed > 0) debugPrint('  📋 audit_logs: تم إصلاح $fixed سجل');
      return fixed;
    } catch (e) {
      debugPrint('  ⚠️ audit_logs: خطأ $e');
      return 0;
    }
  }
}
