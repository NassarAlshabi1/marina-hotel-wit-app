import 'package:appwrite/appwrite.dart';
import 'package:drift/drift.dart' as drift;
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_service.dart';
import 'local_db.dart';
import 'repositories/rooms_repository.dart';

/// ✅ خدمة السحب الشامل من Appwrite
/// تجلب جميع البيانات بدون أي فلترة - كل الجداول وكل الحقول
class AppwriteFullPull {
  factory AppwriteFullPull() => _instance;
  AppwriteFullPull._internal();
  static final AppwriteFullPull _instance = AppwriteFullPull._internal();

  AppwriteService? _appwriteService;
  AppDatabase? _database;
  final AdapterRegistry _adapterRegistry = AdapterRegistry.instance;
  final _logger = AppwriteLogger();

  /// حجم الدفعة الواحدة
  static const int _batchSize = 100;

  /// هل تم التهيئة
  bool get isInitialized => _appwriteService != null && _database != null;

  /// تهيئة الخدمة
  Future<void> initialize(AppwriteService service, AppDatabase db) async {
    _appwriteService = service;
    _database = db;
    _logger.info('تم تهيئة خدمة السحب الشامل', tag: 'FULL_PULL');
  }

  /// سحب جميع البيانات من Appwrite
  Future<FullPullResult> pullAll() async {
    if (!isInitialized) {
      return FullPullResult(success: false, message: 'الخدمة غير مهيأة');
    }

    _logger.info('🚀 بدء السحب الشامل من Appwrite...', tag: 'FULL_PULL');

    final result = FullPullResult(success: true, message: 'تم السحب بنجاح');

    // ✅ لا نعطل FK - بل نرتب السحب بشكل صحيح ونتخطى السجلات اليتيمة
    // PRAGMA foreign_keys=OFF كان يسمح بإدراج بيانات فاسدة (يتيمة)
    // الآن نحافظ على قيود FK ونتخطى السجلات التي تشير لآباء غير موجودين

    try {
      // ترتيب السحب حسب العلاقات
      final entities = _getEntitiesInOrder();

      for (final entity in entities) {
        try {
          final count = await _pullEntity(entity, result);
          result.counts[entity.name] = count;
          _logger.info(
            '✅ تم سحب $count سجل من ${entity.name}',
            tag: 'FULL_PULL',
          );
        } catch (e) {
          _logger.error('❌ فشل سحب ${entity.name}: $e', tag: 'FULL_PULL');
          result.failedEntities.add(entity.name);
        }
      }

      // تحديث حالة الإشغال للغرف
      if (result.totalPulled > 0) {
        await _refreshRoomOccupancy();
      }

      result.success = result.failedEntities.isEmpty;
      result.message = result.failedEntities.isEmpty
          ? 'تم سحب ${result.totalPulled} سجل من ${result.counts.length} جدول'
          : 'تم سحب ${result.totalPulled} سجل، فشل في: ${result.failedEntities.join(', ')}';

      _logger.info('✅ ${result.message}', tag: 'FULL_PULL');
    } finally {
      // ✅ فحص سلامة FK بعد السحب
      try {
        final violations = await _database!
            .customSelect(
              'PRAGMA foreign_key_check',
              readsFrom: Set.unmodifiable({}),
            )
            .get();
        if (violations.isNotEmpty) {
          _logger.warning(
            '⚠️ ${violations.length} انتهاك FK بعد السحب الشامل',
            tag: 'FULL_PULL',
          );
          // حذف السجلات اليتيمة تلقائياً
          for (final row in violations) {
            final table = row.data['table']?.toString() ?? '';
            final rowId = row.data['rowid']?.toString() ?? '';
            try {
              await _database!.customStatement(
                'DELETE FROM $table WHERE rowid = ?',
                [int.tryParse(rowId)],
              );
              _logger.info(
                '🧹 تم حذف سجل يتيم من $table (rowid=$rowId)',
                tag: 'FULL_PULL',
              );
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    return result;
  }

  /// ترتيب الكيانات للسحب (حسب العلاقات)
  List<_PullEntity> _getEntitiesInOrder() {
    final reg = _adapterRegistry;

    return [
      // 1. الغرف أولاً (Bookings.roomNumber → Rooms.roomNumber)
      _PullEntity(
        name: 'rooms',
        collectionId: AppwriteConfig.roomsCollectionId,
        repo: reg.rooms,
      ),
      // 2. الموظفين (SalaryCycles.employeeId, SalaryWithdrawals.employeeId → Employees.id)
      _PullEntity(
        name: 'employees',
        collectionId: AppwriteConfig.employeesCollectionId,
        repo: reg.employees,
      ),
      // 3. أصناف المخزون ثم حركاتها (الحركات تعتمد على الصنف عبر UUID)
      _PullEntity(
        name: 'inventory_items',
        collectionId: AppwriteConfig.inventoryItemsCollectionId,
        repo: reg.inventoryItems,
      ),
      _PullEntity(
        name: 'inventory_transactions',
        collectionId: AppwriteConfig.inventoryTransactionsCollectionId,
        repo: reg.inventoryTransactions,
      ),
      // 4. الحجوزات (تعتمد على الغرف)
      _PullEntity(
        name: 'bookings',
        collectionId: AppwriteConfig.bookingsCollectionId,
        repo: reg.bookings,
      ),
      // 4. المعاملات النقدية (يجب أن تسبق المدفوعات - FK: payments.cashTransactionLocalId)
      _PullEntity(
        name: 'cash_transactions',
        collectionId: AppwriteConfig.cashTransactionsCollectionId,
        repo: reg.cashTransactions,
      ),
      // 5. ليالي الحجز (تعتمد على الحجوزات)
      _PullEntity(
        name: 'booking_nights',
        collectionId: AppwriteConfig.bookingNightsCollectionId,
        repo: reg.nights,
        maxRecords: 1000,
      ),
      // 6. ملاحظات الحجز (تعتمد على الحجوزات)
      _PullEntity(
        name: 'booking_notes',
        collectionId: AppwriteConfig.bookingNotesCollectionId,
        repo: reg.bookingNotes,
      ),
      // 7. المدفوعات (تعتمد على الحجوزات والمعاملات النقدية)
      _PullEntity(
        name: 'payments',
        collectionId: AppwriteConfig.paymentsCollectionId,
        repo: reg.payments,
      ),
      // 8. المصروفات
      _PullEntity(
        name: 'expenses',
        collectionId: AppwriteConfig.expensesCollectionId,
        repo: reg.expenses,
      ),
      // 9. الديون (تعتمد على الحجوزات)
      _PullEntity(
        name: 'debts',
        collectionId: AppwriteConfig.debtsCollectionId,
        repo: reg.debts,
      ),
      // 10. دورات الرواتب (تعتمد على الموظفين)
      _PullEntity(
        name: 'salary_cycles',
        collectionId: AppwriteConfig.salaryCyclesCollectionId,
        repo: reg.salaryCycles,
      ),
      // 11. مدفوعات الرواتب (تعتمد على دورات الرواتب)
      _PullEntity(
        name: 'salary_payments',
        collectionId: AppwriteConfig.salaryPaymentsCollectionId,
        repo: reg.salaryPayments,
      ),
      // 12. سحوبات الرواتب (تعتمد على الموظفين)
      _PullEntity(
        name: 'salary_withdrawals',
        collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
        repo: reg.salaryWithdrawals,
      ),
      // 13. ملاحظات الورديات (لا FK)
      _PullEntity(
        name: 'shift_notes',
        collectionId: AppwriteConfig.shiftNotesCollectionId,
        repo: reg.shiftNotes,
      ),
      // 14. تعديلات الأسعار (لا FK)
      _PullEntity(
        name: 'price_adjustments',
        collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
        repo: reg.priceAdjustments,
      ),
      // 15. تعديلات أسعار الحجوزات (bookingLocalId → Bookings.id)
      _PullEntity(
        name: 'booking_price_adjustments',
        collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
        repo: reg.bookingPriceAdjustments,
      ),
      // 16. سجلات التدقيق (لا FK)
      _PullEntity(
        name: 'audit_logs',
        collectionId: AppwriteConfig.auditLogsCollectionId,
        repo: reg.auditLogs,
      ),
      // 17. إلغاءات الدفع (لا FK — يستخدم UUID فقط)
      _PullEntity(
        name: 'payment_voids',
        collectionId: AppwriteConfig.paymentVoidsCollectionId,
        repo: reg.paymentVoids,
      ),
      // 18. معلومات الضيوف (لا FK)
      _PullEntity(
        name: 'guest_infos',
        collectionId: AppwriteConfig.guestInfosCollectionId,
        repo: reg.guestInfos,
      ),
      // 19. سجلات ترحيل الرواتب (تعتمد على الموظفين)
      // ✅ إصلاح (2026-08-07): كان يُدفع (outbox/delta/secondary) لكنه لم يكن
      // يُسحب أبداً → مزامنة أحادية الاتجاه وفقدان صامت للبيانات على أجهزة أخرى.
      _PullEntity(
        name: 'salary_carry_over_logs',
        collectionId: AppwriteConfig.salaryCarryOverLogsCollectionId,
        repo: reg.salaryCarryOverLogs,
      ),
    ];
  }

  /// سحب كيان واحد - جميع السجلات بدون فلترة
  Future<int> _pullEntity(_PullEntity entity, FullPullResult result) async {
    if (entity.collectionId == null) {
      _logger.warning(
        '⚠️ لا يوجد collectionId لـ ${entity.name}',
        tag: 'FULL_PULL',
      );
      return 0;
    }

    int totalCount = 0;
    int offset = 0;
    int errorCount = 0;
    int skippedCount = 0;

    _logger.info(
      '📥 بدء سحب ${entity.name} من collection: ${entity.collectionId}',
      tag: 'FULL_PULL',
    );

    // حلقة لجلب جميع السجلات على دفعات
    _pullLoop:
    while (true) {
      try {
        // ✅ استعلام بسيط - بدون أي فلترة بالوقت
        // ignore: deprecated_member_use
        final response = await _appwriteService!.databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: entity.collectionId!,
          queries: [Query.limit(_batchSize), Query.offset(offset)],
        );

        final documents = response.documents;
        final totalAvailable = response.total;

        if (documents.isEmpty) {
          _logger.info(
            '📭 لا مزيد من السجلات في ${entity.name}',
            tag: 'FULL_PULL',
          );
          break; // لا مزيد من السجلات
        }

        _logger.info(
          '📦 جلب ${documents.length} سجل من ${entity.name} (offset: $offset, total: $totalAvailable)',
          tag: 'FULL_PULL',
        );

        // معالجة كل سجل
        for (final doc in documents) {
          try {
            // نسخ جميع البيانات كما هي
            final remoteData = Map<String, dynamic>.from(doc.data);

            // ✅ تنظيف البيانات من حقول Appwrite الخاصة
            _cleanDataFromAppwrite(remoteData, doc.$id);

            // ✅ logging للبيانات المستلمة (أول 3 سجلات فقط)
            if (totalCount < 3) {
              _logger.debug(
                '📄 نموذج سجل ${entity.name} #${totalCount + 1}: ${remoteData.keys.take(10).join(', ')}...',
                tag: 'FULL_PULL',
              );
            }

            // استخدام document ID كـ localUuid إذا لم يكن موجوداً
            remoteData['localUuid'] =
                remoteData['localUuid']?.toString() ??
                remoteData['local_uuid']?.toString() ??
                doc.$id;

            // ✅ إصلاح دقيق: فحص FK قبل الإدراج للجداول ذات القيود
            // هذا يمنع انتهاكات FK عند سحب سجلات يتيمة (تشير لآباء محذوفين)
            if (!await _fkPreCheck(entity.name, remoteData)) {
              continue; // تخطي السجل اليتيم
            }

            // ✅ تخزين remote id كـ serverId للموظفين — يسمح بحل FK عبر الأجهزة
            // salary_withdrawals و salary_cycles يستخدمان employeeId البعيد
            // الذي يساوي id الموظف على جهاز المصدر
            if (entity.name == 'employees') {
              final remoteId = _asIntSafe(remoteData, 'id');
              if (remoteId != null && remoteData['serverId'] == null) {
                remoteData['serverId'] = remoteId;
              }
            }

            // ✅ LWW: حل التعارضات تلقائياً - المحلي الأحدث يفوز للمبالغ المالية
            // يمنع طمس مبلغ محلي أحدث بمبلغ بعيد أقدم عند السحب الشامل
            final localUuid =
                remoteData['localUuid']?.toString() ??
                remoteData['local_uuid']?.toString();
            if (localUuid != null &&
                localUuid.isNotEmpty &&
                _isFinancialEntity(entity.name)) {
              final localTs = await _getLocalLastModified(
                entity.name,
                localUuid,
              );
              final remoteTs = _extractRemoteLastModified(remoteData);
              if (localTs != null && remoteTs != null && localTs >= remoteTs) {
                skippedCount++;
                totalCount++;
                continue;
              }
            }

            // ✅ Full Pull: الحد الأقصى للسجلات المسحوبة (مثل booking_nights)
            if (entity.maxRecords != null && totalCount >= entity.maxRecords!) {
              _logger.info(
                '⏹️ تم الوصول للحد الأقصى (${entity.maxRecords}) لـ ${entity.name}',
                tag: 'FULL_PULL',
              );
              break _pullLoop;
            }

            // حفظ السجل (upsert)
            await entity.repo!.upsertFromJson(remoteData, src: Source.appwrite);
            totalCount++;
          } on SqliteException catch (e) {
            // ✅ انتهاك FK — تخطي السجل بدلاً من إيقاف السحب
            if (e.resultCode == 787) {
              _logger.warning(
                '⏭️ تخطي سجل يتيم من ${entity.name}: FK constraint failed - $e',
                tag: 'FULL_PULL',
              );
            } else {
              errorCount++;
              _logger.warning(
                '⚠️ فشل حفظ سجل من ${entity.name}: $e',
                tag: 'FULL_PULL',
              );
            }
          } catch (e) {
            errorCount++;
            _logger.warning(
              '⚠️ فشل حفظ سجل من ${entity.name}: $e',
              tag: 'FULL_PULL',
            );
            // الاستمرار في معالجة باقي السجلات
          }
        }

        offset += documents.length;

        // إذا كانت الدفعة أقل من الحجم المحدد، انتهت البيانات
        if (documents.length < _batchSize) {
          break;
        }
      } catch (e) {
        _logger.error(
          '❌ خطأ في جلب دفعة من ${entity.name}: $e',
          tag: 'FULL_PULL',
        );
        break;
      }
    }

    _logger.info(
      '✅ انتهى سحب ${entity.name}: $totalCount سجل (أخطاء: $errorCount، تم تجاوز: $skippedCount)',
      tag: 'FULL_PULL',
    );

    result.totalPulled += totalCount;
    return totalCount;
  }

  /// ✅ فحص FK قبل الإدراج — يتحقق من وجود الآباء قبل إدراج الأبناء
  /// يمنع انتهاكات FK عند سحب سجلات يتيمة (تشير لآباء محذوفين من Appwrite)
  Future<bool> _fkPreCheck(String entityName, Map<String, dynamic> data) async {
    try {
      final db = _database!;

      switch (entityName) {
        // ✅ salary_withdrawals: Employees ← SalaryWithdrawals.employeeId (NOT NULL)
        // حل FK بثلاث مستويات: UUID → id → serverId
        case 'salary_withdrawals':
          {
            final remoteEmployeeId =
                _asIntSafe(data, 'employeeId') ??
                _asIntSafe(data, 'employee_id');
            final employeeUuid =
                (data['employeeUuid'] as String?) ??
                (data['employee_uuid'] as String?) ??
                (data['employeeLocalUuid'] as String?) ??
                (data['employee_local_uuid'] as String?);

            if (remoteEmployeeId != null ||
                (employeeUuid != null && employeeUuid.isNotEmpty)) {
              Employee? employee;

              // الطريقة 1: البحث بالـ UUID (الأكثر موثوقية عبر الأجهزة)
              if (employeeUuid != null && employeeUuid.isNotEmpty) {
                employee =
                    await (db.select(db.employees)
                          ..where((e) => e.localUuid.equals(employeeUuid))
                          ..limit(1))
                        .getSingleOrNull();
              }

              // الطريقة 2: البحث بالـ id البعيد كـ id محلي
              if (employee == null && remoteEmployeeId != null) {
                employee =
                    await (db.select(db.employees)
                          ..where((e) => e.id.equals(remoteEmployeeId))
                          ..limit(1))
                        .getSingleOrNull();
              }

              // الطريقة 3: البحث بالـ serverId (id الأصلي من جهاز المصدر)
              if (employee == null && remoteEmployeeId != null) {
                employee =
                    await (db.select(db.employees)
                          ..where((e) => e.serverId.equals(remoteEmployeeId))
                          ..limit(1))
                        .getSingleOrNull();
              }

              if (employee == null) {
                _logger.warning(
                  '⏭️ تخطي salary_withdrawal يتيم: الموظف $remoteEmployeeId (uuid=$employeeUuid) غير موجود محلياً',
                  tag: 'FULL_PULL',
                );
                return false;
              }

              // ✅ استبدال employeeId البعيد بالمعرف المحلي الصحيح
              data['employeeId'] = employee.id;
            }
            break;
          }

        // ✅ salary_cycles: Employees ← SalaryCycles.employeeId (NOT NULL)
        // حل FK بثلاث مستويات: UUID → id → serverId
        case 'salary_cycles':
          {
            final remoteEmployeeId =
                _asIntSafe(data, 'employeeId') ??
                _asIntSafe(data, 'employee_id');
            final employeeUuid =
                (data['employeeUuid'] as String?) ??
                (data['employee_uuid'] as String?) ??
                (data['employeeLocalUuid'] as String?) ??
                (data['employee_local_uuid'] as String?);

            if (remoteEmployeeId != null ||
                (employeeUuid != null && employeeUuid.isNotEmpty)) {
              Employee? employee;

              // الطريقة 1: البحث بالـ UUID
              if (employeeUuid != null && employeeUuid.isNotEmpty) {
                employee =
                    await (db.select(db.employees)
                          ..where((e) => e.localUuid.equals(employeeUuid))
                          ..limit(1))
                        .getSingleOrNull();
              }

              // الطريقة 2: البحث بالـ id البعيد
              if (employee == null && remoteEmployeeId != null) {
                employee =
                    await (db.select(db.employees)
                          ..where((e) => e.id.equals(remoteEmployeeId))
                          ..limit(1))
                        .getSingleOrNull();
              }

              // الطريقة 3: البحث بالـ serverId
              if (employee == null && remoteEmployeeId != null) {
                employee =
                    await (db.select(db.employees)
                          ..where((e) => e.serverId.equals(remoteEmployeeId))
                          ..limit(1))
                        .getSingleOrNull();
              }

              if (employee == null) {
                _logger.warning(
                  '⏭️ تخطي salary_cycle يتيم: الموظف $remoteEmployeeId (uuid=$employeeUuid) غير موجود محلياً',
                  tag: 'FULL_PULL',
                );
                return false;
              }

              // ✅ استبدال employeeId البعيد بالمعرف المحلي الصحيح
              data['employeeId'] = employee.id;
            }
            break;
          }

        // ✅ salary_payments: SalaryCycles ← SalaryPayments.cycleId (NOT NULL)
        case 'salary_payments':
          final remoteCycleId =
              _asIntSafe(data, 'cycleId') ?? _asIntSafe(data, 'cycle_id');
          if (remoteCycleId != null) {
            var cycle =
                await (db.select(db.salaryCycles)
                      ..where((c) => c.id.equals(remoteCycleId))
                      ..limit(1))
                    .getSingleOrNull();
            cycle ??=
                await (db.select(db.salaryCycles)
                      ..where((c) => c.serverId.equals(remoteCycleId))
                      ..limit(1))
                    .getSingleOrNull();
            if (cycle == null) {
              _logger.warning(
                '⏭️ تخطي salary_payment يتيم: الدورة $remoteCycleId غير موجودة محلياً',
                tag: 'FULL_PULL',
              );
              return false;
            }
          }

        // باقي الجداول: FK nullable أو يُعالجها adapter بـ drift.Value.absent()
      }
    } catch (e) {
      _logger.warning(
        '⚠️ فشل فحص FK المسبق لـ $entityName: $e',
        tag: 'FULL_PULL',
      );
    }
    return true; // افتراض النجاح
  }

  /// تحويل آمن للقيمة الرقمية من Map
  int? _asIntSafe(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// ✅ تنظيف البيانات من حقول Appwrite الخاصة قبل الحفظ
  /// هذه الحقول يضيفها Appwrite تلقائياً ولا يجب تخزينها محلياً
  void _cleanDataFromAppwrite(Map<String, dynamic> data, String docId) {
    // إزالة حقول Appwrite الخاصة
    data.remove(r'$id');
    data.remove(r'$createdAt');
    data.remove(r'$updatedAt');
    data.remove(r'$permissions');
    data.remove(r'$collectionId');
    data.remove(r'$databaseId');

    // أيضاً إزالة الحقول بأسماء بديلة
    data.remove(r'createdAt_$');
    data.remove(r'updatedAt_$');

    // الاحتفاظ بـ document ID كـ reference إذا لزم الأمر
    // يمكن استخدامه لاحقاً للتحديثات
    if (!data.containsKey('serverDocId')) {
      data['serverDocId'] = docId;
    }
  }

  /// هل هذا الكيان يحتوي على بيانات مالية تحتاج حماية LWW؟
  bool _isFinancialEntity(String entityName) {
    return switch (entityName) {
      'payments' ||
      'expenses' ||
      'debts' ||
      'salary_cycles' ||
      'salary_payments' ||
      'salary_withdrawals' ||
      'cash_transactions' ||
      'booking_price_adjustments' ||
      'price_adjustments' ||
      'booking_nights' => true,
      _ => false,
    };
  }

  /// جلب آخر تعديل محلي لكي المقارنة مع البعيد (LWW)
  Future<int?> _getLocalLastModified(String tableName, String localUuid) async {
    try {
      final db = _database!;
      final sanitized = tableName.replaceAll("'", "''");
      final result = await db
          .customSelect(
            "SELECT last_modified FROM '$sanitized' WHERE local_uuid = ? LIMIT 1",
            variables: [drift.Variable.withString(localUuid)],
            readsFrom: Set.unmodifiable({}),
          )
          .getSingleOrNull();
      final raw = result?.data['last_modified'];
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// استخراج طابع زمني من البيانات البعيدة
  int? _extractRemoteLastModified(Map<String, dynamic> data) {
    final v =
        data['lastModified'] ??
        data['last_modified'] ??
        data['lastModifiedEpoch'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// تحديث حالة إشغال الغرف
  /// ✅ يستخدم RoomsRepository.refreshAllRoomOccupancy() لضمان:
  /// - تحديث version و lastModified مع كل تغيير
  /// - التحقق من الحالة الحالية قبل التحديث (تجنب التحديثات غير الضرورية)
  /// - دعم جميع حالات الغرف (شاغرة، محجوزة، صيانة، إلخ) عبر StatusUtils
  Future<void> _refreshRoomOccupancy() async {
    try {
      final roomsRepo = RoomsRepository(_database!);
      await roomsRepo.refreshAllRoomOccupancy(originIsServer: true);
      _logger.info('🔄 تم تحديث حالة إشغال الغرف', tag: 'FULL_PULL');
    } catch (e) {
      _logger.warning('⚠️ فشل تحديث حالة الإشغال: $e', tag: 'FULL_PULL');
    }
  }
}

/// كيان للسحب
class _PullEntity {
  // BaseRepository<dynamic, dynamic>

  _PullEntity({
    required this.name,
    this.collectionId,
    this.repo,
    this.maxRecords,
  });
  final String name;
  final String? collectionId;
  final dynamic repo;

  /// الحد الأقصى للسجلات المسحوبة (null = غير محدود)
  final int? maxRecords;
}

/// نتيجة السحب الشامل
class FullPullResult {
  FullPullResult({required this.success, required this.message});

  bool success;
  String message;
  int totalPulled = 0;

  /// عدد السجلات لكل جدول
  Map<String, int> counts = {};

  /// الجداول التي فشل سحبها
  List<String> failedEntities = [];

  /// ملخص النتيجة
  Map<String, dynamic> toMap() {
    return {
      'success': success,
      'message': message,
      'totalPulled': totalPulled,
      'counts': counts,
      'failedEntities': failedEntities,
    };
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('FullPullResult:');
    buffer.writeln('  success: $success');
    buffer.writeln('  totalPulled: $totalPulled');
    buffer.writeln('  counts:');
    for (final entry in counts.entries) {
      buffer.writeln('    ${entry.key}: ${entry.value}');
    }
    if (failedEntities.isNotEmpty) {
      buffer.writeln('  failedEntities: ${failedEntities.join(', ')}');
    }
    return buffer.toString();
  }
}
