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

    final id = await _db.transaction(() async {
      final companion = SalaryWithdrawalsCompanion(
        localUuid: d.Value(uuid),
        serverId: const d.Value(null),
        employeeId: d.Value(employeeId),
        // ✅ (2026-09-19) توليد employee_uuid عند الإنشاء — الربط الدائم
        employeeUuid: employeeUuid,
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

  /// حفظ أو تحديث سجل سحب راتب مرتبط بمصروف (UPSERT via expense_id)
  /// ✅ إصلاح خبير: البحث أولاً عبر عمود expense_id ثم عبر reason
  /// تغليف العملية في معاملة لضمان اتساق البيانات
  ///
  /// [previousAmount] — المبلغ الموقّع القديم للمرآة قبل التعديل
  /// (سالب للخصوم، موجب للنقدي). يُستخدم في الطريقة 3 (تبنّي المرآة
  /// اليتيمة) عندما يفشل الربط المباشر لأن رابط المرآة يحمل معرّف
  /// جهاز المصدر (autoincrement محلي غير محمول عبر الأجهزة).
  /// مرِّره من شاشة التعديل كي لا تُنشأ مرآة ثانية تكرر المبلغ في
  /// التقارير. null = توافق خلفي (يُستخدم المبلغ الجديد في البحث).
  Future<void> saveFromExpense({
    required int expenseId,
    required int employeeId,
    required String action,
    required double amount,
    required String date,
    String? note,
    String? hotelDayKey,
    double? previousAmount,
    bool originIsServer = false,
  }) async {
    // ✅ (2026-09-19) UUID الموظف — يُخزن مع السجل الجديد عند الإنشاء
    final employeeUuid = await _employeeUuidFor(employeeId);

    // ✅ البحث عن سجل موجود — محاولة عبر عمود expense_id أولاً
    SalaryWithdrawal? matched;

    // الطريقة 1: بحث عبر عمود expense_id (الأكثر موثوقية)
    try {
      final rows = await _db
          .customSelect(
            'SELECT * FROM salary_withdrawals WHERE expense_id = ? AND deleted_at IS NULL LIMIT 1',
            variables: [d.Variable.withInt(expenseId)],
          )
          .get();
      if (rows.isNotEmpty) {
        // نقرأ بيانات السجل من جدول salary_withdrawals عبر Drift
        final byId =
            await (_db.select(_db.salaryWithdrawals)
                  ..where((t) => t.id.equals(rows.first.read<int>('id')))
                  ..limit(1))
                .getSingleOrNull();
        if (byId != null) {
          matched = byId;
        }
      }
    } catch (_) {
      // العمود قد لا يكون موجوداً
    }

    // الطريقة 2: بحث عبر reason (الطريقة القديمة)
    if (matched == null) {
      final existing =
          await (_db.select(_db.salaryWithdrawals)..where(
                (t) => t.reason.like('%exp_$expenseId%') & t.deletedAt.isNull(),
              ))
              .get();
      matched = existing
          .where((w) => matchesExpenseRef(w.reason, expenseId))
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
        if (matchesExpenseRef(w.reason, expenseId)) {
          staleRecords.add(w);
        }
      }
    }

    await _db.transaction(() async {
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
        // إنشاء سجل جديد
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
            },
            clientTs: now,
          );
        }
      }
    });
  }

  /// البحث عن مرآة يتيمة قابلة للتبنّي (الطريقة 3 في [saveFromExpense]).
  ///
  /// شروط التبنّي (كلها معاً):
  /// - سحبة نشطة (غير محذوفة) لنفس الموظف.
  /// - المبلغ يطابق المبلغ الموقّع القديم للمرآة (تسامح فروق التقريب).
  /// - نفس اليوم الفندقي (أو التاريخ التقويمي عند غياب المفتاح).
  /// - ليست سحبة مباشرة (reason لا يبدأ بـ direct_withdrawal_).
  /// - رابطها لا يشير لمصروف محلي قائم غير المصروف الحالي
  ///   (expense_id وreason/exp_N كلاهما) — وإلا فهي مرآة مصروف آخر.
  Future<SalaryWithdrawal?> _findOrphanMirrorForAdoption({
    required int expenseId,
    required int employeeId,
    required double expectedAmount,
    required String date,
    String? hotelDayKey,
  }) async {
    final candidates =
        await (_db.select(_db.salaryWithdrawals)..where(
              (t) => t.deletedAt.isNull() & t.employeeId.equals(employeeId),
            ))
            .get();
    if (candidates.isEmpty) return null;

    final effectiveHotelDayKey = hotelDayKey ?? _computeHotelDayKey(date);

    for (final w in candidates) {
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

  /// ✅ إصلاح: حذف ناعم (soft delete) بدلاً من الحذف الفعلي
  /// لتوافق مع آلية المزامنة التي تعتمد على deletedAt
  /// ✅ إصلاح خبير: البحث أولاً عبر عمود expense_id ثم عبر reason
  Future<void> deleteByExpenseId(
    int expenseId, {
    bool originIsServer = false,
  }) async {
    // الطريقة 1: بحث عبر عمود expense_id
    List<SalaryWithdrawal> toDelete = [];
    try {
      final rows = await _db
          .customSelect(
            'SELECT id FROM salary_withdrawals WHERE expense_id = ? AND deleted_at IS NULL',
            variables: [d.Variable.withInt(expenseId)],
          )
          .get();
      if (rows.isNotEmpty) {
        final ids = rows.map((r) => r.read<int>('id')).toList();
        toDelete = await (_db.select(
          _db.salaryWithdrawals,
        )..where((t) => t.id.isIn(ids))).get();
      }
    } catch (_) {
      // العمود قد لا يكون موجوداً
    }

    // الطريقة 2: بحث عبر reason (الطريقة القديمة) إذا لم نجد عبر expense_id
    if (toDelete.isEmpty) {
      final candidates =
          await (_db.select(_db.salaryWithdrawals)..where(
                (t) => t.reason.like('%exp_$expenseId%') & t.deletedAt.isNull(),
              ))
              .get();
      toDelete = candidates
          .where((w) => matchesExpenseRef(w.reason, expenseId))
          .toList();
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
