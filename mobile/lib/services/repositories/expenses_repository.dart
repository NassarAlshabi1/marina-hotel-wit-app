import 'dart:async';

import 'package:drift/drift.dart' as d;

import '../../utils/hotel_time_engine.dart';
import '../../utils/time.dart';
import '../auto_backup_manager.dart';
import '../crashlytics_service.dart';
import '../daos/expenses_dao.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../telegram/telegram_notification_service.dart';
import '../telegram/whatsapp_notification_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class ExpensesRepository {
  ExpensesRepository(this.db) {
    outbox = OutboxDao(db);
    dao = ExpensesDao(db, outbox);
  }
  final AppDatabase db;
  late final OutboxDao outbox;
  late final ExpensesDao dao;

  Stream<List<Expense>> watchAll() => dao.watchList();
  Stream<List<Expense>> watchByHotelDayKey(String hotelDayKey) =>
      dao.watchByHotelDayKey(hotelDayKey);
  Stream<Expense?> watchOne(int id) => dao.watchById(id);
  Future<List<Expense>> listFiltered({
    String? from,
    String? to,
    String? expenseType,
  }) => dao.listFiltered(from: from, to: to, expenseType: expenseType);

  /// البحث المتقدم مع دعم البحث النصي في الوصف ونوع المصروف
  Future<List<Expense>> listWithSearch({
    String? search,
    String? from,
    String? to,
  }) => dao.list(search: search, from: from, to: to);

  /// فلترة بـ hotelDayKey مع دعم البحث النصي — الطريقة الدقيقة
  Future<List<Expense>> listFilteredByHotelDay({
    String? fromHotelDay,
    String? toHotelDay,
    String? expenseType,
    String? search,
    bool excludeAdvance = false,
  }) => dao.listFilteredByHotelDay(
    fromHotelDay: fromHotelDay,
    toHotelDay: toHotelDay,
    expenseType: expenseType,
    search: search,
    excludeAdvance: excludeAdvance,
  );

  Future<int> create({
    required String expenseType,
    required String description,
    required double amount,
    required String date,
    int? relatedId,
    String? hotelDayKey,
    // ✅ التوصية 1: اكتب employeeUuid وقت الإنشاء (وليس فقط وقت الرفع).
    // يجعل كل مصروف راتب جديد محمولاً فورًا حتى قبل المزامنة، ويُغلق خطر #1
    // (employeeUuid لا يُكتب إلا وقت الرفع). الحقن وقت الرفع يبقى كشبكة أمان
    // للسجلات القديمة التي أُنشئت قبل هذا الإصلاح.
    String? employeeUuid,
  }) async {
    try {
      final normalizedDate = Time.safeIsoToDateString(date);
      // ✅ إصلاح: استخدام hotelDayKey الممرّر إن وُجد، وإلا حسابه
      // - للمصروفات الجديدة: يُمرّر HotelTimeEngine.getHotelDayKey() (اليوم الفندقي الحالي)
      // - للمصروفات القديمة / الاستيراد: يُحسب من التاريخ التقويمي
      final effectiveHotelDayKey =
          hotelDayKey ?? _hotelDayKeyFromCalendarDate(normalizedDate);
      final result = await dao.insertOne(
        ExpensesCompanion(
          expenseType: d.Value(expenseType),
          relatedId: d.Value(relatedId),
          description: d.Value(description),
          amount: d.Value(amount),
          date: d.Value(normalizedDate),
          hotelDayKey: d.Value(effectiveHotelDayKey),
          employeeUuid: employeeUuid != null && employeeUuid.isNotEmpty
              ? d.Value(employeeUuid)
              : const d.Value.absent(),
        ),
      );
      unawaited(AutoBackupManager.instance.onDataChange(
          'expenses',
          'INSERT',
          recordData: {'amount': amount},
        ),
      );
      // إشعارات فورية — مع اسم الموظف إذا كان المصروف راتباً (له employeeUuid)
      unawaited(
        () async {
          String? empName;
          if (employeeUuid != null && employeeUuid.isNotEmpty) {
            try {
              final emp = await (db.select(db.employees)
                    ..where((e) => e.localUuid.equals(employeeUuid))
                    ..limit(1))
                  .getSingleOrNull();
              empName = emp?.name;
            } catch (e) {
      debugPrint('⚠️ Swallowed error in expenses_repository.dart: ');
              // الموظف قد لا يكون متزامناً بعد — نتخطى بصمت
            }
          }
          await WhatsAppNotificationService.instance.notifyNewExpense(
            category: expenseType,
            amount: amount,
            description: description,
            employeeName: empName,
          );
        }(),
      );
      unawaited(
        () async {
          String? empName;
          if (employeeUuid != null && employeeUuid.isNotEmpty) {
            try {
              final emp = await (db.select(db.employees)
                    ..where((e) => e.localUuid.equals(employeeUuid))
                    ..limit(1))
                  .getSingleOrNull();
              empName = emp?.name;
            } catch (e) {
      debugPrint('⚠️ Swallowed error in expenses_repository.dart: ');
              // الموظف قد لا يكون متزامناً بعد — نتخطى بصمت
            }
          }
          await TelegramNotificationService.instance.notifyNewExpense(
            category: expenseType,
            amount: amount,
            description: description,
            employeeName: empName,
          );
        }(),
      );
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ExpensesRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'expenseType': expenseType, 'amount': '$amount'},
      );
      rethrow;
    }
  }

  /// إنشاء مصروف مُولّد تلقائياً (سلفة مقسطة / خصم من الراتب)
  Future<int> createAutoGenerated({
    required String expenseType,
    required String description,
    required double amount,
    required String date,
    int? relatedId,
  }) async {
    try {
      final normalizedDate = Time.safeIsoToDateString(date);
      // ✅ إصلاح: استخدام _hotelDayKeyFromCalendarDate لضمان الاتساق مع create/update
      final hotelDayKey = _hotelDayKeyFromCalendarDate(normalizedDate);
      final result = await dao.insertOne(
        ExpensesCompanion(
          expenseType: d.Value(expenseType),
          relatedId: d.Value(relatedId),
          description: d.Value(description),
          amount: d.Value(amount),
          date: d.Value(normalizedDate),
          hotelDayKey: d.Value(hotelDayKey),
          isAutoGenerated: const d.Value(true),
        ),
      );
      unawaited(AutoBackupManager.instance.onDataChange(
          'expenses',
          'INSERT',
          recordData: {'amount': amount, 'isAutoGenerated': true},
        ),
      );
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ExpensesRepository',
        action: 'createAutoGenerated',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'expenseType': expenseType, 'amount': '$amount'},
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    String? expenseType,
    int? relatedId,
    String? description,
    double? amount,
    String? date,
    String? hotelDayKey,
    // ✅ التوصية 1: اكتب employeeUuid وقت التعديل أيضًا.
    // - مرّر قيمة (غير فارغة) لتعيين employeeUuid.
    // - مرّر سلسلة فارغة '' لمسح employeeUuid (عند التحويل من راتب إلى غير راتب).
    // - مرّر null لترك القيمة الحالية دون تغيير (سلوك التوافق للخلف).
    String? employeeUuid,
  }) async {
    try {
      final normalizedDate = date != null
          ? Time.safeIsoToDateString(date)
          : null;
      final result = await dao.updateById(
        id,
        ExpensesCompanion(
          expenseType: expenseType != null
              ? d.Value(expenseType)
              : const d.Value.absent(),
          relatedId: relatedId != null
              ? d.Value(relatedId)
              : const d.Value.absent(),
          description: description != null
              ? d.Value(description)
              : const d.Value.absent(),
          amount: amount != null ? d.Value(amount) : const d.Value.absent(),
          date: normalizedDate != null
              ? d.Value(normalizedDate)
              : const d.Value.absent(),
          // ✅ إصلاح: استخدام hotelDayKey الممرّر إن وُجد، وإلا حسابه من التاريخ
          hotelDayKey: hotelDayKey != null
              ? d.Value(hotelDayKey)
              : date != null
              ? d.Value(_hotelDayKeyFromCalendarDate(normalizedDate!))
              : const d.Value.absent(),
          // ✅ التوصية 1: employeeUuid — فارغ = مسح، null = لا تغيير.
          employeeUuid: employeeUuid == null
              ? const d.Value.absent()
              : employeeUuid.isEmpty
              ? const d.Value(null)
              : d.Value(employeeUuid),
        ),
      );
      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange(
            'expenses',
            'UPDATE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ExpensesRepository',
        action: 'update',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  Future<int> delete(int id) async {
    try {
      final result = await dao.softDelete(id);
      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange(
            'expenses',
            'DELETE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ExpensesRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المصروفات
  Future<Map<String, dynamic>> exportData() async {
    final expensesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': expensesData, 'count': recordCount, 'entity': 'expenses'};
  }

  /// استيراد بيانات المصروفات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data'] as List),
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return dao.getRecordCount();
  }

  /// الحصول على إجمالي المصروفات لتاريخ محدد
  Future<double> getTotalByDate(String date) async {
    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses WHERE date LIKE ? AND deleted_at IS NULL',
          variables: [d.Variable.withString('$date%')],
          readsFrom: {db.expenses},
        )
        .getSingle();
    return (result.data['total'] as num).toDouble();
  }

  Future<double> getTotalByHotelDayKey(String hotelDayKey) async {
    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses '
          'WHERE deleted_at IS NULL AND (hotel_day_key = ? OR (hotel_day_key IS NULL AND date LIKE ?))',
          variables: [
            d.Variable.withString(hotelDayKey),
            d.Variable.withString('$hotelDayKey%'),
          ],
          readsFrom: {db.expenses},
        )
        .getSingle();
    return (result.data['total'] as num).toDouble();
  }

  /// مراقبة إجمالي المصروفات ليوم فندقي محدد عبر SQL SUM() — أداء أفضل
  /// من تحميل جميع المصروفات ثم جمعها في Dart. يُحدَّث تلقائياً عند أي تغيير
  /// في جدول المصروفات بفضل Stream من Drift customSelectStream.
  Stream<double> watchTotalByHotelDayKey(String hotelDayKey) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses '
          'WHERE deleted_at IS NULL AND (hotel_day_key = ? OR (hotel_day_key IS NULL AND date LIKE ?))',
          variables: [
            d.Variable.withString(hotelDayKey),
            d.Variable.withString('$hotelDayKey%'),
          ],
          readsFrom: {db.expenses},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  /// إصلاح سجلات المصروفات القديمة التي تحتوي على hotelDayKey خاطئ
  /// (كان يُعيَّن بالتاريخ التقويمي بدلاً من مفتاح اليوم الفندقي)
  ///
  /// يُستدعى مرة واحدة عند تشغيل التطبيق لتصحيح البيانات التاريخية.
  Future<int> backfillHotelDayKeys() async {
    final allExpenses = await dao.list(includeDeleted: true);
    int fixed = 0;
    for (final expense in allExpenses) {
      if (expense.hotelDayKey == null || expense.hotelDayKey!.isEmpty) {
        continue;
      }
      // ✅ إصلاح: استخدام _hotelDayKeyFromCalendarDate بدلاً من getHotelDayKeyFromIso
      // لأن حقل date يخزن تاريخاً تقويمياً بدون وقت (yyyy-MM-dd)
      // وتمريره مباشرة لـ getHotelDayKeyFromIso يُنتج اليوم الفندقي السابق خطأً
      final correctKey = _hotelDayKeyFromCalendarDate(expense.date);
      if (expense.hotelDayKey != correctKey) {
        await (db.update(
          db.expenses,
        )..where((t) => t.id.equals(expense.id))).write(
          ExpensesCompanion(hotelDayKey: d.Value(correctKey)),
        );
        fixed++;
      }
    }
    return fixed;
  }

  /// حساب مفتاح اليوم الفندقي من تاريخ تقويمي (بدون وقت)
  ///
  /// المنتقي يعطي تاريخاً بدون وقت مثل "2026-05-19".
  /// إذا مررناه مباشرة لـ HotelTimeEngine.getHotelDayKeyFromIso،
  /// يُفسَّر كمنتصف الليل (00:00:00) وهو قبل 14:00، فيُعطي اليوم السابق خطأً.
  ///
  /// الحل: نمرّر 14:01:00 لضمان أن التاريخ التقويمي يُعطي نفس اليوم الفندقي.
  /// هذا يطابق منطق _hotelDayKeyFromDate في expenses_list.dart
  static String _hotelDayKeyFromCalendarDate(String calendarDate) {
    try {
      final parts = calendarDate.split('-');
      if (parts.length != 3) {
        return HotelTimeEngine.getHotelDayKey();
      }
      final year = int.tryParse(parts[0]) ?? 1;
      final month = int.tryParse(parts[1]) ?? 1;
      final day = int.tryParse(parts[2]) ?? 1;
      return HotelTimeEngine.getHotelDayKey(
        dateTime: DateTime(year, month, day, 14, 1),
      );
    } catch (e) {
      debugPrint('⚠️ Swallowed error in expenses_repository.dart: ');
      return HotelTimeEngine.getHotelDayKey();
    }
  }
}
