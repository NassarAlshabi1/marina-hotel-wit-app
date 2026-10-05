import 'dart:async';

import 'package:drift/drift.dart' as d;

import '../../utils/expense_reason_matcher.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../appwrite_sync_manager.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../telegram/telegram_notification_service.dart';
import '../telegram/whatsapp_notification_service.dart';

class SalaryWithdrawalsRepository {
  SalaryWithdrawalsRepository(this._db) : _outboxDao = OutboxDao(_db);
  final AppDatabase _db;
  final OutboxDao _outboxDao;

  /// ✅ كتابة expense_id في عمود SQL خام بعد كل إدراج/تحديث
  /// العمود أُضيف عبر Migration 40 ولا يوجد في الـ data class المُولّد
  Future<void> _setExpenseIdRaw(int salaryWithdrawalId, int expenseId) async {
    try {
      await _db.customStatement(
        'UPDATE salary_withdrawals SET expense_id = ? WHERE id = ?',
        [expenseId, salaryWithdrawalId],
      );
    } catch (_) {
      // العمود قد لا يكون موجوداً في الإصدارات القديمة — نتخطى بصمت
    }
  }

  /// ✅ (2026-09-19) جلب UUID الموظف من قاعدة البيانات المحلية.
  ///
  /// الربط الرقمي (employeeId) صالح داخل الجهاز فقط؛ UUID هو المفتاح
  /// الدائم عبر الأجهزة (فجوة employee_uuid).
  Future<d.Value<String>> _employeeUuidFor(int employeeId) async {
    final employee =
        await (_db.select(_db.employees)
              ..where((e) => e.id.equals(employeeId))
              ..limit(1))
            .getSingleOrNull();
    if (employee == null || employee.localUuid.isEmpty) {
      return const d.Value.absent();
    }
    return d.Value(employee.localUuid);
  }

  /// ✅ (migration 68) جلب UUID المصروف من قاعدة البيانات المحلية —
  /// الرابط الدائم سحبة→مصروف الذي ينجو من إعادة ترقيم المعرفات.
  Future<d.Value<String>> _expenseUuidFor(int expenseId) async {
    final expense =
        await (_db.select(_db.expenses)
              ..where((e) => e.id.equals(expenseId))
              ..limit(1))
            .getSingleOrNull();
    if (expense == null || expense.localUuid.isEmpty) {
      return const d.Value.absent();
    }
    return d.Value(expense.localUuid);
  }

  /// ✅ (migration 68) ختم الرابط العكسي على المصروف: withdrawal_uuid =
  /// local_uuid للسحبة المرآة. يُحدّث الصف المحلي + يدمج عنصر outbox
  /// (op:update) ليت propagate للسحابة — دفع المصروفات يعيد بناء الحزمة
  /// من الصف الكامل (expenseToRemote) الذي يضمّن withdrawalUuid.
  Future<void> _stampExpenseMirrorLink(
    int expenseId,
    String withdrawalUuid,
    int now, {
    String? expenseLocalUuid,
    int? expenseServerId,
    bool originIsServer = false,
  }) async {
    try {
      await _db.customStatement(
        'UPDATE expenses SET withdrawal_uuid = ? '
        'WHERE id = ? AND (withdrawal_uuid IS NULL OR withdrawal_uuid != ?)',
        [withdrawalUuid, expenseId, withdrawalUuid],
      );
      // ✅ بيانات واردة من الخادم: الختم المحلي مطلوب (تصحيح الروابط)
      // لكن بلا إعادة دفع للسحابة (منع حلقات الرفع).
      if (!originIsServer &&
          expenseLocalUuid != null &&
          expenseLocalUuid.isNotEmpty) {
        await _outboxDao.merge(
          entity: 'expenses',
          op: 'update',
          localUuid: expenseLocalUuid,
          serverId: expenseServerId,
          payload: {'lastModified': now},
          clientTs: now,
        );
      }
    } catch (_) {
      // العمود قد لا يكون موجوداً في إصدارات قديمة جداً — لا نعطل الإنشاء
    }
  }

  /// إنشاء سجل سحب راتب مرتبط بمصروف
  ///
  /// ✅ (2026-09-14) إسناد السحبة لمسجّلها:
  /// - [recorderName] اسم المستخدم المسجّل (من جلسة الدخول) — يُخزّن محلياً
  ///   ويُرفع للسحابة في حقل name ليظهر في التقارير على كل الأجهزة.
  /// - deviceId يُملأ تلقائياً من هوية الجهاز الحالية (إن وُجدت).
  Future<int> createFromExpense({
    required int expenseId,
    required int employeeId,
    required String reason,
    required double amount,
    required String date,
    String? hotelDayKey,
    String? withdrawalType,
    String? description,
    String? recorderName,
    bool originIsServer = false,
  }) async {
    final now = Time.nowEpoch();
    final uuid = IdGen.uuid();
    // ✅ وسم الجهاز — عمود deviceId موجود في SyncFields وكان يُرسل فارغاً دائماً
    final deviceId = AppwriteSyncManager.currentDeviceIdStatic ?? '';
    // ✅ (2026-09-19) UUID الموظف عند الإنشاء — الربط الدائم عبر الأجهزة
    final employeeUuid = await _employeeUuidFor(employeeId);
    // ✅ (migration 68) UUID المصروف عند الإنشاء — الرابط الدائم سحبة→مصروف
    final expenseUuid = expenseId > 0
        ? await _expenseUuidFor(expenseId)
        : const d.Value<String>.absent();

    final id = await _db.transaction(() async {
      final companion = SalaryWithdrawalsCompanion(
        localUuid: d.Value(uuid),
        serverId: const d.Value(null),
        employeeId: d.Value(employeeId),
        // ✅ (2026-09-19) توليد employee_uuid عند الإنشاء — الربط الدائم
        employeeUuid: employeeUuid,
        // ✅ (migration 68) expense_uuid عند الإنشاء — الرابط الدائم
        expenseUuid: expenseUuid,
        amount: d.Value(amount),
        withdrawDate: d.Value(date),
        reason: d.Value(reason),
        hotelDayKey: d.Value(hotelDayKey ?? _computeHotelDayKey(date)),
        withdrawalType: d.Value(withdrawalType),
        description: d.Value(description),
        recorderName: recorderName != null && recorderName.isNotEmpty
            ? d.Value(recorderName)
            : const d.Value.absent(),
        deviceId: d.Value(deviceId),
        createdAt: d.Value(now),
        updatedAt: d.Value(now),
        deletedAt: const d.Value(null),
        lastModified: d.Value(now),
        createdAtEpoch: d.Value(now),
        lastModifiedEpoch: d.Value(now),
        version: const d.Value(1),
        origin: d.Value(originIsServer ? 'server' : 'local'),
        vectorClock: const d.Value('{}'),
      );
      final id = await _db.into(_db.salaryWithdrawals).insert(companion);

      if (expenseId > 0) {
        await _setExpenseIdRaw(id, expenseId);
        // ✅ (migration 68) ختم الرابط العكسي على المصروف (withdrawal_uuid)
        // + عنصر outbox للمصروف ليُنشر للسحابة والأجهزة الأخرى.
        try {
          final expenseRow =
              await (_db.select(_db.expenses)
                    ..where((e) => e.id.equals(expenseId))
                    ..limit(1))
                  .getSingleOrNull();
          if (expenseRow != null) {
            await _stampExpenseMirrorLink(
              expenseId,
              uuid,
              now,
              expenseLocalUuid: expenseRow.localUuid,
              expenseServerId: expenseRow.serverId,
            );
          }
        } catch (_) {
          // لا نعطل الإنشاء إن فشل ختم الرابط العكسي
        }
      }

      if (!originIsServer) {
        final payload = <String, dynamic>{
          'employeeId': employeeId,
          'amount': amount,
          'withdrawDate': date,
          'reason': reason,
          'hotelDayKey': hotelDayKey ?? _computeHotelDayKey(date),
          'withdrawalType': withdrawalType,
          'description': description,
          'deviceId': deviceId,
          if (recorderName != null && recorderName.isNotEmpty)
            'recorderName': recorderName,
        };
        if (expenseId > 0) {
          payload['expenseId'] = expenseId;
          // ✅ (migration 68) uuid المرآة في الحمولة أيضاً (الدفع يعيد
          // البناء من الصف الكامل — هذا احتياط لمسارات delta/Drive).
          final eu = await _expenseUuidFor(expenseId);
          if (eu.present && eu.value.isNotEmpty) {
            payload['expenseUuid'] = eu.value;
          }
        }
        await _outboxDao.merge(
          entity: 'salary_withdrawals',
          op: 'create',
          localUuid: uuid,
          payload: payload,
          clientTs: now,
        );
      }

      return id;
    });

    // الإشعارات لا تدخل في المعاملة حتى لا تطيل قفل SQLite أو تُرسل قبل
    // نجاح حفظ السجل وoutbox. لا نرسلها للبيانات المسحوبة من الخادم.
    if (!originIsServer) {
      unawaited(
        WhatsAppNotificationService.instance.notifyNewExpense(
          category: 'سحب راتب',
          amount: amount,
          description: reason,
        ),
      );
      unawaited(
        TelegramNotificationService.instance.notifyNewExpense(
          category: 'سحب راتب',
          amount: amount,
          description: reason,
        ),
      );
    }

    return id;
  }

  /// حفظ أو تحديث سجل سحب راتب مرتبط بمصروف.
  ///
  /// ✅ القاعدة الحاكمة (هجرة 68): **التمييز بهوية العملية نفسها**
  /// (سحبة.expenseUuid ↔ مصروف.localUuid)، وليس باسم الموظف أو اليوم أو
  /// المبلغ:
  /// - الإضافة الجديدة عملية مستقلة بهوية جديدة حتى لو تشابهت بياناتها
  ///   تماماً مع عمليات أخرى (سحبتان بنفس الموظف/اليوم/المبلغ = عمليتان).
  /// - التعديل يحدّث المرآة نفسها ويحافظ على هويتها — يظهر المبلغ الأخير
  ///   مرة واحدة فقط، دون إبقاء القديم ودون إنشاء نسخة إضافية.
  /// - إن وُجدت أكثر من مرآة تعلن نفس الهوية (تصادم إنشاء مزدوج) تُعتمد
  ///   الأحدث وتُحذف البقية حذفًا ناعماً.
  ///
  /// ترتيب المطابقة: الطريقة 0 (هوية UUID، اتجاهان) ← الطريقة 1
  /// (عمود expense_id الرقمي) ← الطريقة 2 (نمط reason=exp_N) ← الطريقة 3
  /// (تبنّي مرآة يتيمة تراثية بلا رابط هوية). أي طريقة نجحت تُختم بعدها
  /// روابط الهوية الدائمة في الاتجاهين لتُحسم التعديلات اللاحقة بالطريقة 0.
  /// تغليف العملية في معاملة لضمان اتساق البيانات.
  ///
  /// [previousAmount] — المبلغ الموقّع القديم للمرآة قبل التعديل
  /// (سالب للخصوم، موجب للنقدي). يُستخدم في الطريقة 3 (تبنّي المرآة
  /// اليتيمة) عندما يفشل الربط المباشر لأن رابط المرآة يحمل معرّف
  /// جهاز المصدر (autoincrement محلي غير محمول عبر الأجهزة).
  /// مرِّره من شاشة التعديل كي لا تُنشأ مرآة ثانية تكرر المبلغ في
  /// التقارير. null = توافق خلفي (يُستخدم المبلغ الجديد في البحث).
  ///
  /// [previousEmployeeId] — موظف المصروف السابق عند إعادة التعيين (تعديل
  /// مصروف راتب وتغيير موظفه). يُمرَّره من الشاشة كي لا تُنشأ مرآة ثانية
  /// عند تغيير الموظف (الطريقة 1 تجد المرآة القديمة لموظفه السابق).
  ///
  /// ✅ (المرحلة 0 — P0.3 / R3) كل مطابقة بـ expense_id/reason تمرّ عبر
  /// [_ownedByDeviceOrEmployee]: مرآة جهاز آخر تحمل نفس الرقم لا تُمسَّ
  /// ولا تُحدَّث (كان يتعديل مسحوب موظف/جهاز آخر وينتشر للسحابة).
  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
    String? hotelDayKey,
    double? previousAmount,
    int? previousEmployeeId,
    bool originIsServer = false,
  }) async {
    // ✅ (2026-09-19) UUID الموظف — يُخزن مع السجل الجديد عند الإنشاء
    final employeeUuid = await _employeeUuidFor(employeeId);

    // ✅ (هجرة 68) صف المصروف نفسه — مصدر حقول الهوية للمطابقة والختم.
    // التمييز هنا بهوية العملية نفسها (UUID)، وليس باسم الموظف أو اليوم
    // أو المبلغ: سحبتان متطابقتا البيانات تبقى كل منهما عملية مستقلة.
    final expenseRow =
        await (_db.select(_db.expenses)
              ..where((e) => e.id.equals(expenseId))
              ..limit(1))
            .getSingleOrNull();
    final expenseLocalUuid = (expenseRow?.localUuid ?? '').trim();

    // البحث عن سجل موجود
    SalaryWithdrawal? matched;

    // ✅ نسخ مكررة لنفس الهوية: أكثر من مرآة تعلن ارتباطها بنفس المصروف
    // (تصادم إنشاء مزدوج عبر الأجهزة لنفس العملية). تُعالج في المعاملة:
    // تُعتمد الأحدث كممثل وحيد للعملية وتُحذف البقية حذفًا ناعماً —
    // العملية الواحدة تُحتسب مرة واحدة فقط في التقارير والمزامنة.
    final identityDuplicates = <SalaryWithdrawal>[];

    // الطريقة 0 (هوية العملية): الرابط الدائم سحبة↔مصروف بالـ UUID —
    // حتمي وعابر للأجهزة، يُرجّح على كل الطرق الرقمية/البيانية الأقدم.
    if (expenseLocalUuid.isNotEmpty) {
      // 0-أ: المرآة التي تعلن ارتباطها بهذا المصروف بهويته (سحبة → مصروف)
      final byExpenseUuid =
          await (_db.select(_db.salaryWithdrawals)..where(
                (t) =>
                    t.expenseUuid.equals(expenseLocalUuid) &
                    t.deletedAt.isNull(),
              ))
              .get();
      if (byExpenseUuid.isNotEmpty) {
        if (byExpenseUuid.length == 1) {
          matched = byExpenseUuid.first;
        } else {
          // أكثر من نسخة لنفس العملية — اعتمد الأحدث تحديثاً (وبالتعادل
          // الأعلى معرفاً) وأزل البقية كيلا يُحتسب المبلغ مرتين.
          final sorted = [...byExpenseUuid]
            ..sort((a, b) {
              if (a.updatedAt != b.updatedAt) {
                return b.updatedAt.compareTo(a.updatedAt);
              }
              return b.id.compareTo(a.id);
            });
          matched = sorted.first;
          identityDuplicates.addAll(sorted.skip(1));
        }
      }

      // 0-ب: الختم العكسي على المصروف (مصروف → سحبة). يُتجاهل الختم
      // الذاتي الفاسد (خطأ تاريخي كان يختم المصروف بهويته هو).
      if (matched == null) {
        final stampedUuid = (expenseRow?.withdrawalUuid ?? '').trim();
        if (stampedUuid.isNotEmpty && stampedUuid != expenseLocalUuid) {
          final stamped =
              await (_db.select(_db.salaryWithdrawals)..where(
                    (t) =>
                        t.localUuid.equals(stampedUuid) & t.deletedAt.isNull(),
                  )..limit(1))
                  .getSingleOrNull();
          if (stamped != null) {
            // ✅ حارس الاختطاف: إن كانت المرآة المختومة تعلن بهويتها
            // انتماءها لمصروف آخر قائم فهي تخصّه — الختم الفاسد على
            // هذا المصروف لا يخوّل اختطافها.
            final declared = (stamped.expenseUuid ?? '').trim();
            final belongsToOther =
                declared.isNotEmpty &&
                declared != expenseLocalUuid &&
                await _activeExpenseExistsByUuid(declared);
            if (!belongsToOther) {
              matched = stamped;
            }
          }
        }
      }
    }

    // الطريقة 1: بحث عبر عمود expense_id (روابط رقمية محلية — تراثية)
    // ✅ (المرحلة 0 — P0.3) تُفحص كل المرشحات عبر _ownedByDeviceOrEmployee
    // بدل LIMIT 1 أعمى — المرآة الأجنبية المتصادمة تُتجاوز لا تُختار.
    if (matched == null) {
      try {
        final rows = await _db
            .customSelect(
              'SELECT id FROM salary_withdrawals WHERE expense_id = ? AND deleted_at IS NULL',
              variables: [d.Variable.withInt(expenseId)],
            )
            .get();
        for (final row in rows) {
          // نقرأ بيانات السجل من جدول salary_withdrawals عبر Drift
          final byId =
              await (_db.select(_db.salaryWithdrawals)
                    ..where((t) => t.id.equals(row.read<int>('id')))
                    ..limit(1))
                  .getSingleOrNull();
          if (byId != null &&
              _ownedByDeviceOrEmployee(
                byId,
                employeeId: employeeId,
                previousEmployeeId: previousEmployeeId,
                employeeUuid: employeeUuid.value,
              )) {
            matched = byId;
            break;
          }
        }
      } catch (_) {
        // العمود قد لا يكون موجوداً
      }
    }

    // الطريقة 2: بحث عبر reason (الطريقة القديمة)
    if (matched == null) {
      final existing =
          await (_db.select(_db.salaryWithdrawals)..where(
                (t) => t.reason.like('%exp_$expenseId%') & t.deletedAt.isNull(),
              ))
              .get();
      matched = existing
          .where(
            (w) =>
                matchesExpenseRef(w.reason, expenseId) &&
                _ownedByDeviceOrEmployee(
                  w,
                  employeeId: employeeId,
                  previousEmployeeId: previousEmployeeId,
                  employeeUuid: employeeUuid.value,
                ),
          )
          .firstOrNull;
    }

    // الطريقة 3: تبنّي مرآة يتيمة عبر بيانات المطابقة (موظف + مبلغ قديم + يوم)
    // ✅ إصلاح تكرار التقارير عند تعديل المبلغ (2026-09-25):
    // المرآة القديمة رابطها أجنبي (expense_id/reason يحملان معرّف
    // autoincrement لجهاز المصدر) فلا يجدها البحث أعلاه على الجهاز
    // الثاني → يُنشأ مرآة جديدة وتبقى القديمة نشطة → المبلغ يظهر
    // مرتين في التقرير. هنا نتبنّى القديمة: نفس الموظف + نفس اليوم +
    // المبلغ القديم (قبل التعديل) + رابطها لا يشير لمصروف محلي قائم.
    matched ??= await _findOrphanMirrorForAdoption(
      expenseId: expenseId,
      employeeId: employeeId,
      expectedAmount: previousAmount ?? amount,
      date: date,
      hotelDayKey: hotelDayKey,
      expenseLocalUuid: expenseLocalUuid,
    );

    final now = Time.nowEpoch();
    // reason يحتوي فقط على علامة الربط بالمصروف
    final reasonText = 'exp_$expenseId';
    // ✅ وسم الجهاز على سجلات المرايا أيضاً (مصروف → سحبة مطابقة)
    final deviceId = AppwriteSyncManager.currentDeviceIdStatic ?? '';

    // جمع السجلات القديمة غير المطابقة لمنع التكرار عند التعديل
    final staleRecords = <SalaryWithdrawal>[];
    if (matched != null) {
      final matchedId = matched.id; // ✅ متغير محلي non-null
      // البحث عن سجلات أخرى بنفس expense_id أو exp_XX
      final allExisting =
          await (_db.select(_db.salaryWithdrawals)..where(
                (t) => t.deletedAt.isNull() & t.id.equals(matchedId).not(),
              ))
              .get();
      for (final w in allExisting) {
        // ✅ النسخ المكررة بالهوية (identityDuplicates) تُعالج في بداية
        // المعاملة — لا نعيد معالجتها هنا منعاً للازدواج.
        if (identityDuplicates.any((dup) => dup.id == w.id)) continue;
        // ✅ (المرحلة 0 — P0.3) حتى تنظيف "السجلات القديمة" لا يلمس
        // مرآة أجنبية متصادمة الرقماً مع expense/reason المحلي.
        if (matchesExpenseRef(w.reason, expenseId) &&
            _ownedByDeviceOrEmployee(
              w,
              employeeId: employeeId,
              previousEmployeeId: previousEmployeeId,
              employeeUuid: employeeUuid.value,
            )) {
          staleRecords.add(w);
        }
      }
    }

    await _db.transaction(() async {
      // ─── حذف النسخ المكررة لنفس الهوية (الطريقة 0) داخل المعاملة ───
      // نفس معاملة السجلات القديمة: حذف ناعم + مزامنة كتحديث للعملية نفسها.
      for (final duplicate in identityDuplicates) {
        await (_db.update(
          _db.salaryWithdrawals,
        )..where((t) => t.id.equals(duplicate.id))).write(
          SalaryWithdrawalsCompanion(
            deletedAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(duplicate.version + 1),
          ),
        );
        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: duplicate.localUuid,
            serverId: duplicate.serverId,
            payload: {
              'employeeId': duplicate.employeeId,
              'deletedAt': now,
              'lastModified': now,
            },
            clientTs: now,
          );
        }
      }

      // ─── حذف السجلات القديمة داخل المعاملة لضمان اتساق المزامنة ───
      for (final stale in staleRecords) {
        await (_db.update(
          _db.salaryWithdrawals,
        )..where((t) => t.id.equals(stale.id))).write(
          SalaryWithdrawalsCompanion(
            deletedAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(stale.version + 1),
          ),
        );

        if (!originIsServer) {
          // ✅ إصلاح حرج: استخدام op:'update' بدلاً من op:'delete'
          // الحذف الناعم (soft-delete) يجب أن يستخدم 'update' لكي يُحدث سجل Appwrite
          // بدلاً من حذفه نهائياً — هذا يضمن رؤية deletedAt على الأجهزة الأخرى
          // ✅ إصلاح: إضافة employeeId للحمولة لضمان مزامنة relatedId/employeeId بشكل صحيح
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: stale.localUuid,
            serverId: stale.serverId,
            payload: {
              'employeeId': stale.employeeId,
              'deletedAt': now,
              'lastModified': now,
            },
            clientTs: now,
          );
        }
      }

      // ─── إنشاء أو تحديث السجل الرئيسي ───
      if (matched != null) {
        final matchedId = matched.id; // ✅ متغير محلي non-null
        final matchedLocalUuid = matched.localUuid;
        final matchedServerId = matched.serverId;
        final matchedVersion = matched.version;
        // تحديث السجل الموجود
        await (_db.update(
          _db.salaryWithdrawals,
        )..where((t) => t.id.equals(matchedId))).write(
          SalaryWithdrawalsCompanion(
            employeeId: d.Value(employeeId),
            // ✅ (R12) تحديث employeeUuid مع employeeId — بدونه يبقى قديم
            // الموظف السابق ويُرفع للسحابة (ربط خاطئ ينتشر لكل الأجهزة).
            employeeUuid: employeeUuid,
            amount: d.Value(amount),
            withdrawDate: d.Value(date),
            reason: d.Value(reasonText),
            withdrawalType: d.Value(action),
            description: d.Value(note),
            hotelDayKey: d.Value(hotelDayKey ?? _computeHotelDayKey(date)),
            deviceId: deviceId.isEmpty
                ? const d.Value.absent()
                : d.Value(deviceId),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(matchedVersion + 1),
          ),
        );

        // ✅ تحديث expense_id في العمود الخام
        await _setExpenseIdRaw(matchedId, expenseId);
        // ✅ (هجرة 68) ختم الهوية على المرآة: expense_uuid = هوية هذا
        // المصروف — الرابط الدائم الذي ينجو من إعادة ترقيم المعرفات.
        if (expenseLocalUuid.isNotEmpty) {
          await (_db.update(_db.salaryWithdrawals)
                ..where((t) => t.id.equals(matchedId)))
              .write(
                SalaryWithdrawalsCompanion(
                  expenseUuid: d.Value(expenseLocalUuid),
                ),
              );
        }
        // ✅ الختم العكسي على المصروف: withdrawal_uuid = هوية المرآة
        // نفسها (matchedLocalUuid) — وليس هوية المصروف. (الخطأ التاريخي
        // كان يختم المصروف بهويته هو فيكسر حلّ الهوية ويُسقط النظام
        // على المطابقات البيانية/الرقمية.) التعديل يحدّث العملية نفسها
        // ويحافظ على هويتها، ويُعمَّم الختم الجديد للسحابة عبر outbox.
        await _stampExpenseMirrorLink(
          expenseId,
          matchedLocalUuid,
          now,
          expenseLocalUuid: expenseRow?.localUuid,
          expenseServerId: expenseRow?.serverId,
          originIsServer: originIsServer,
        );

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: matchedLocalUuid,
            serverId: matchedServerId,
            payload: {
              'employeeId': employeeId,
              'amount': amount,
              'withdrawDate': date,
              'reason': reasonText,
              'withdrawalType': action,
              'description': note,
              'hotelDayKey': hotelDayKey ?? _computeHotelDayKey(date),
              'lastModified': now,
              'expenseId': expenseId,
              // ✅ (هجرة 68) هوية المصروف على المرآة — الرابط الدائم
              if (expenseLocalUuid.isNotEmpty)
                'expenseUuid': expenseLocalUuid,
            },
            clientTs: now,
          );
        }
        // إشعارات فورية (fire-and-forget) عند التحديث
        unawaited(
          WhatsAppNotificationService.instance.notifyNewExpense(
            category: 'سحب راتب',
            amount: amount,
            description: note ?? reasonText,
          ),
        );
        unawaited(
          TelegramNotificationService.instance.notifyNewExpense(
            category: 'سحب راتب',
            amount: amount,
            description: note ?? reasonText,
          ),
        );
      } else {
        // إنشاء سجل جديد — إضافة جديدة = عملية مستقلة بهوية جديدة، حتى لو
        // تشابهت بياناتها (موظف/يوم/مبلغ) مع عملية أخرى قائمة.
        final uuid = IdGen.uuid();
        final newId = await _db
            .into(_db.salaryWithdrawals)
            .insert(
              SalaryWithdrawalsCompanion(
                localUuid: d.Value(uuid),
                serverId: const d.Value(null),
                employeeId: d.Value(employeeId),
                // ✅ (2026-09-19) employee_uuid عند الإنشاء
                employeeUuid: employeeUuid,
                // ✅ (هجرة 68) هوية المصروف عند الإنشاء — الرابط الدائم
                expenseUuid: expenseLocalUuid.isNotEmpty
                    ? d.Value(expenseLocalUuid)
                    : const d.Value.absent(),
                amount: d.Value(amount),
                withdrawDate: d.Value(date),
                reason: d.Value(reasonText),
                withdrawalType: d.Value(action),
                description: d.Value(note),
                hotelDayKey: d.Value(hotelDayKey ?? _computeHotelDayKey(date)),
                deviceId: d.Value(deviceId),
                createdAt: d.Value(now),
                updatedAt: d.Value(now),
                deletedAt: const d.Value(null),
                lastModified: d.Value(now),
                createdAtEpoch: d.Value(now),
                lastModifiedEpoch: d.Value(now),
                version: const d.Value(1),
                origin: d.Value(originIsServer ? 'server' : 'local'),
                vectorClock: const d.Value('{}'),
              ),
            );

        // ✅ كتابة expense_id في العمود الخام
        await _setExpenseIdRaw(newId, expenseId);
        // ✅ (هجرة 68) الختم العكسي على المصروف: withdrawal_uuid = هوية
        // المرآة الجديدة نفسها (uuid) — وليس هوية المصروف — مع تعميمه
        // للسحابة عبر outbox.
        await _stampExpenseMirrorLink(
          expenseId,
          uuid,
          now,
          expenseLocalUuid: expenseRow?.localUuid,
          expenseServerId: expenseRow?.serverId,
          originIsServer: originIsServer,
        );
        unawaited(
          WhatsAppNotificationService.instance.notifyNewExpense(
            category: 'سحب راتب',
            amount: amount,
            description: note,
          ),
        );
        unawaited(
          TelegramNotificationService.instance.notifyNewExpense(
            category: 'سحب راتب',
            amount: amount,
            description: note,
          ),
        );

        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'create',
            localUuid: uuid,
            payload: {
              'employeeId': employeeId,
              'amount': amount,
              'withdrawDate': date,
              'reason': reasonText,
              'withdrawalType': action,
              'description': note,
              'hotelDayKey': hotelDayKey ?? _computeHotelDayKey(date),
              'expenseId': expenseId,
              // ✅ (هجرة 68) هوية المصروف على المرآة — الرابط الدائم
              if (expenseLocalUuid.isNotEmpty)
                'expenseUuid': expenseLocalUuid,
            },
            clientTs: now,
          );
        }
      }
    });
  }

  /// البحث عن مرآة يتيمة قابلة للتبنّي (الطريقة 3 في [saveFromExpense]).
  ///
  /// ⚠️ مسار تراثي للسجلات القديمة التي لا تحمل رابط هوية (هجرة 68) فقط:
  /// البيانات الجديدة تُحسم دائماً بالطريقة 0 (سحبة.expenseUuid ==
  /// مصروف.localUuid). عند التبنّي هنا يُختم الرابط الدائم فوراً في مسار
  /// التحديث (expense_uuid + withdrawal_uuid) فتُحسم التعديلات اللاحقة
  /// بالهوية مباشرة. التبنّي يحافظ على عدد العمليات والمجموع: مرآة واحدة
  /// تُحدَّث بدل إنشاء نسخة إضافية.
  ///
  /// شروط التبنّي (كلها معاً):
  /// - سحبة نشطة (غير محذوفة) لنفس الموظف.
  /// - المبلغ يطابق المبلغ الموقّع القديم للمرآة (تسامح فروق التقريب).
  /// - نفس اليوم الفندقي (أو التاريخ التقويمي عند غياب المفتاح).
  /// - ليست سحبة مباشرة (reason لا يبدأ بـ direct_withdrawal_).
  /// - لا تحمل رابط هوية لمصروف آخر (سحبة مرتبطة بهوية مصروف آخر
  ///   تخصّه هو ولا تُختطف).
  /// - رابطها لا يشير لمصروف محلي قائم غير المصروف الحالي
  ///   (expense_id وreason/exp_N كلاهما) — وإلا فهي مرآة مصروف آخر.
  Future<SalaryWithdrawal?> _findOrphanMirrorForAdoption({
    required int expenseId,
    required int employeeId,
    required double expectedAmount,
    required String date,
    String? hotelDayKey,
    String? expenseLocalUuid,
  }) async {
    final candidates =
        await (_db.select(_db.salaryWithdrawals)..where(
              (t) => t.deletedAt.isNull() & t.employeeId.equals(employeeId),
            ))
            .get();
    if (candidates.isEmpty) return null;

    final effectiveHotelDayKey = hotelDayKey ?? _computeHotelDayKey(date);
    final currentUuid = (expenseLocalUuid ?? '').trim();

    for (final w in candidates) {
      // ✅ رابط هوية (سحبة → مصروف) يشير لمصروف آخر قائم → مرآة ذلك
      // المصروف قطعاً ولا تُختطف مهما تشابهت البيانات.
      final wEu = (w.expenseUuid ?? '').trim();
      if (wEu.isNotEmpty && wEu != currentUuid) {
        if (await _activeExpenseExistsByUuid(wEu)) continue;
      }

      // المبلغ الموقّع القديم — بتسامح فروق التقريب العائمة.
      if ((w.amount - expectedAmount).abs() >= 0.005) continue;

      // لا نتبنى السحوبات المباشرة الحقيقية أبداً — نقد بلا مصروف مقابل.
      final r = (w.reason ?? '').trim();
      if (r.startsWith('direct_withdrawal_')) continue;

      // نتبنى فقط ما يحمل علامة مرآة (expense_id أو exp_N) — السحوبات
      // اليدوية القديمة بلا علامة مصدرها غامض ولا تُختطف.
      final wExpId = w.expenseId;
      final hasMirrorMarker =
          (wExpId != null && wExpId > 0) || RegExp(r'exp_\d+').hasMatch(r);
      if (!hasMirrorMarker) continue;

      // رابط expense_id يشير لمصروف محلي قائم آخر → مرآة ذلك المصروف.
      if (wExpId != null && wExpId > 0 && wExpId != expenseId) {
        if (await _activeExpenseExists(wExpId)) continue;
      }

      // reason=exp_M يشير لمصروف محلي قائم آخر → مرآة ذلك المصروف.
      final m = RegExp(r'exp_(\d+)').firstMatch(r);
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n != expenseId && await _activeExpenseExists(n)) {
          continue;
        }
      }

      // نفس اليوم: hotelDayKey عند توفرهما، وإلا التاريخ التقويمي.
      final wDay = (w.hotelDayKey ?? '').trim();
      final dayMatch = wDay.isNotEmpty
          ? wDay == effectiveHotelDayKey
          : w.withdrawDate.trim() == date.trim();
      if (!dayMatch) continue;

      return w;
    }
    return null;
  }

  /// هل يوجد مصروف نشط (غير محذوف) بهذا المعرف المحلي؟
  Future<bool> _activeExpenseExists(int id) async {
    final row =
        await (_db.select(_db.expenses)
              ..where((t) => t.id.equals(id) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// هل يوجد مصروف نشط (غير محذوف) بهذه الهوية (local_uuid)؟
  Future<bool> _activeExpenseExistsByUuid(String localUuid) async {
    final row =
        await (_db.select(_db.expenses)
              ..where((t) => t.localUuid.equals(localUuid) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  /// ✅ (المرحلة 0 — P0.3 / R3) حارس مطابقة المرآة بـ expense_id/reason.
  ///
  /// لا يُطابَق سجل برابط محلي إلا إذا اجتاز شرطين:
  /// 1) **ملكية الجهاز**: `origin != 'server'` (أُنشئ هنا) أو `deviceId`
  ///    يساوي الجهاز الحالي (أُنشئ أو تُبنّي على هذا الجهاز). المرآة
  ///    القادمة من جهاز آخر تحمل `expense_id`/`exp_N` ذلك الجهاز، وتصادم
  ///    autoincrement بين جهازين شائع → حذف/تعديل مسحوب موظف آخر.
  /// 2) **نطاق الموظف** (إن وُفّر): الموظف الحالي للمصروف أو السابق
  ///    (إعادة التعيين عبر [previousEmployeeId])، بـ uuid أو id.
  ///
  /// بدون نطاق موظف يكتفي بالحارس 1 (المالك المحلي وحده كفيل: الرابط
  /// المحلي لا يُنتَج إلا من هذا الجهاز).
  bool _ownedByDeviceOrEmployee(
    SalaryWithdrawal w, {
    required int? employeeId,
    String? employeeUuid,
    int? previousEmployeeId,
  }) {
    final currentDeviceId = AppwriteSyncManager.currentDeviceIdStatic ?? '';

    // 1) ملكية الجهاز: منشأ محلي ('local') أو مرور فعلي بهذا الجهاز.
    //    'server'/'mobile' = بيانات مسحوبة تحمل رابط جهاز آخر → تُرفض ما لم
    //    يُتبنَّها هذا الجهاز فعلياً (device_id يُعاد كتابته عند التبنّي).
    final createdByThisDevice =
        (w.origin != 'server' && w.origin != 'mobile') ||
        (currentDeviceId.isNotEmpty && w.deviceId == currentDeviceId);
    if (!createdByThisDevice) return false;

    // 2) نطاق الموظف (يُطبَّق دائماً عند توفيره — حتى للسجلات المحلية):
    //    يحمي من روابط قديمة خاطئة (رقم موظف سابق/مستعادة) ومن مستقبل
    //    إعادة الترقيم بعد الاستعادة (المرحلة 5).
    final hasScope =
        employeeId != null ||
        previousEmployeeId != null ||
        (employeeUuid != null && employeeUuid.isNotEmpty);
    if (!hasScope) return true;
    if (employeeId != null && w.employeeId == employeeId) return true;
    if (previousEmployeeId != null && w.employeeId == previousEmployeeId) {
      return true;
    }
    if (employeeUuid != null &&
        employeeUuid.isNotEmpty &&
        w.employeeUuid == employeeUuid) {
      return true;
    }
    return false;
  }

  /// ✅ إصلاح: حذف ناعم (soft delete) بدلاً من الحذف الفعلي
  /// لتوافق مع آلية المزامنة التي تعتمد على deletedAt
  /// ✅ إصلاح خبير: البحث أولاً عبر عمود expense_id ثم عبر reason
  ///
  /// [employeeId] / [employeeUuid] — موظف المصروف عند حذفه (تُمرَّر من
  /// الشاشة). بدونهما يكتفي الحارس بالملكية المحلية؛ معهما يمنع أيضاً
  /// حذف مرآة موظف آخر تصادم رقم الربط (المرحلة 0 — P0.3 / R3).
  Future<void> deleteByExpenseId(
    int expenseId, {
    bool originIsServer = false,
    int? employeeId,
    String? employeeUuid,
  }) async {
    List<SalaryWithdrawal> toDelete = [];
    bool containsId(int id) => toDelete.any((x) => x.id == id);

    // الطريقة 0 (هوية العملية): الرابط الدائم سحبة↔مصروف (هجرة 68).
    // الهوية حاسمة ولا تصطدم — لا تحتاج حارس الجهاز/الموظف: مرآة مرتبطة
    // بهوية هذا المصروف تخصّه حصراً، وحذف المصروف يحذف مرآته أينما كانت
    // حقول الموظف فيها (إعادة تعيين/استعادة لا تغيّر انتماء العملية).
    final expenseRow =
        await (_db.select(_db.expenses)
              ..where((e) => e.id.equals(expenseId))
              ..limit(1))
            .getSingleOrNull();
    final expenseLocalUuid = (expenseRow?.localUuid ?? '').trim();
    if (expenseLocalUuid.isNotEmpty) {
      // 0-أ: سحبات تعلن ارتباطها بهذا المصروف بهويته (سحبة → مصروف)
      final byUuid =
          await (_db.select(_db.salaryWithdrawals)..where(
                (t) =>
                    t.expenseUuid.equals(expenseLocalUuid) &
                    t.deletedAt.isNull(),
              ))
              .get();
      for (final w in byUuid) {
        if (!containsId(w.id)) toDelete.add(w);
      }
      // 0-ب: المرآة المختومة على المصروف (مصروف → سحبة). يُتجاهل الختم
      // الذاتي الفاسد (خطأ تاريخي كان يختم المصروف بهويته هو).
      final stampedUuid = (expenseRow?.withdrawalUuid ?? '').trim();
      if (stampedUuid.isNotEmpty && stampedUuid != expenseLocalUuid) {
        final stamped =
            await (_db.select(_db.salaryWithdrawals)..where(
                  (t) =>
                      t.localUuid.equals(stampedUuid) & t.deletedAt.isNull(),
                )..limit(1))
                .getSingleOrNull();
        // ✅ حارس الاختطاف: مرآة تعلن انتماءها لمصروف آخر قائم لا تُحذف
        // بسبب ختم فاسد على هذا المصروف.
        final declared = (stamped?.expenseUuid ?? '').trim();
        final belongsToOther =
            stamped != null &&
            declared.isNotEmpty &&
            declared != expenseLocalUuid &&
            await _activeExpenseExistsByUuid(declared);
        if (stamped != null && !belongsToOther && !containsId(stamped.id)) {
          toDelete.add(stamped);
        }
      }
    }

    // الطريقة 1: بحث عبر عمود expense_id (روابط رقمية تراثية)
    List<SalaryWithdrawal> legacyMatches = [];
    try {
      final rows = await _db
          .customSelect(
            'SELECT id FROM salary_withdrawals WHERE expense_id = ? AND deleted_at IS NULL',
            variables: [d.Variable.withInt(expenseId)],
          )
          .get();
      if (rows.isNotEmpty) {
        final ids = rows.map((r) => r.read<int>('id')).toList();
        legacyMatches = await (_db.select(
          _db.salaryWithdrawals,
        )..where((t) => t.id.isIn(ids))).get();
      }
    } catch (_) {
      // العمود قد لا يكون موجوداً
    }

    // ✅ (مراجعة kilo 2026-10-04) الحارس يُطبَّق على نتائج الطريقة 1 **قبل**
    // قرار استدعاء الطريقة 2: إن عثرت الطريقة 1 على مرايا أجنبية فقط
    // (تصادم expense_id رقمي) فلا ينبغي أن يُلغي ذلك بحث reason — صف
    // قديم مرتبط بالـ reason وحده كان يبقى حياً خطأً.
    // ✅ الحارس يخص الروابط الرقمية/البيانية فقط — نتائج الطريقة 0
    // محسومة بالهوية ولا تخضع له.
    bool guard(SalaryWithdrawal w) => _ownedByDeviceOrEmployee(
      w,
      employeeId: employeeId,
      employeeUuid: employeeUuid,
    );
    legacyMatches = legacyMatches.where(guard).toList();

    // الطريقة 2: بحث عبر reason (الطريقة القديمة) إذا لم نجد عبر expense_id
    if (legacyMatches.isEmpty) {
      final candidates =
          await (_db.select(_db.salaryWithdrawals)..where(
                (t) => t.reason.like('%exp_$expenseId%') & t.deletedAt.isNull(),
              ))
              .get();
      legacyMatches = candidates
          .where((w) => matchesExpenseRef(w.reason, expenseId))
          .toList();
    }

    // ✅ (المرحلة 0 — P0.3 / R3) تطبيق الحارس على المرشحات من المسارين:
    // لا يُحذف سجل لا يخص هذا الجهاز/هذا الموظف حتى لو تصادم الرقم.
    // (إعادة التطبيق على نتائج الطريقة 2 — عملية idempotent).
    legacyMatches = legacyMatches.where(guard).toList();

    // دمج نتائج الهوية مع النتائج التراثية (بلا تكرار)
    for (final w in legacyMatches) {
      if (!containsId(w.id)) toDelete.add(w);
    }

    final now = Time.nowEpoch();

    // ✅ حذف ناعم في معاملة واحدة لضمان الاتساق
    await _db.transaction(() async {
      for (final item in toDelete) {
        await (_db.update(
          _db.salaryWithdrawals,
        )..where((t) => t.id.equals(item.id))).write(
          SalaryWithdrawalsCompanion(
            deletedAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
            version: d.Value(item.version + 1),
          ),
        );

        // ✅ إصلاح حرج: استخدام op:'update' بدلاً من op:'delete'
        // الحذف الناعم (soft-delete) يجب أن يستخدم 'update' لكي يُحدث سجل Appwrite
        // بدلاً من حذفه نهائياً — هذا يضمن رؤية deletedAt على الأجهزة الأخرى
        // ✅ إصلاح: إضافة employeeId للحمولة لضمان مزامنة relatedId/employeeId بشكل صحيح
        if (!originIsServer) {
          await _outboxDao.merge(
            entity: 'salary_withdrawals',
            op: 'update',
            localUuid: item.localUuid,
            serverId: item.serverId,
            payload: {
              'employeeId': item.employeeId,
              'deletedAt': now,
              'lastModified': now,
            },
            clientTs: now,
          );
        }
      }
    });
  }

  /// جلب كل سحوبات الرواتب (غير المحذوفة فقط)
  Future<List<SalaryWithdrawal>> listAll() async {
    // Returns ALL records including soft-deleted ones (for audit/recovery)
    return _db.select(_db.salaryWithdrawals).get();
  }

  /// جلب سحوبات موظف معين
  Future<List<SalaryWithdrawal>> listByEmployeeId(int employeeId) async {
    return (_db.select(
          _db.salaryWithdrawals,
        )..where((t) => t.employeeId.equals(employeeId) & t.deletedAt.isNull()))
        .get();
  }

  /// جلب السحوبات النشطة (غير المحذوفة) مع حد اختياري للقوائم منخفضة الذاكرة.
  Future<List<SalaryWithdrawal>> listActive({
    int? limit,
    int offset = 0,
  }) async {
    final query = _db.select(_db.salaryWithdrawals)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => d.OrderingTerm(
          expression: t.withdrawDate,
          mode: d.OrderingMode.desc,
        ),
        (t) => d.OrderingTerm(expression: t.id, mode: d.OrderingMode.desc),
      ]);
    if (limit != null) {
      query.limit(limit, offset: offset);
    }
    return query.get();
  }

  /// حساب مفتاح اليوم الفندقي من تاريخ السحب
  /// إذا كان التاريخ يحتوي على وقت (yyyy-MM-dd HH:mm)، يستخدمه مباشرة
  /// إذا كان تاريخاً تقويمياً فقط (yyyy-MM-dd)، يمرّر 14:01 لضمان اليوم الصحيح
  static String _computeHotelDayKey(String date) {
    try {
      final trimmed = date.trim();
      final hasTime = trimmed.length > 10;
      if (hasTime) {
        return HotelTimeEngine.getHotelDayKeyFromIso(trimmed);
      }
      // تاريخ تقويمي بدون وقت — نمرّر 14:01:00 لضمان اليوم الفندقي الصحيح
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
}
