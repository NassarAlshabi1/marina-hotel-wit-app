// test/unit/cloudflare_full_chain_contract_test.dart
//
// ✅ الاختبار العقدي الشامل للسلسلة الكاملة (2026-09-14) — طلب المستخدم:
// «اختبار عقدي Cloudflare يمر على كل الجداول»:
//   1. إنشاء سجل محلي عبر المنتجين الحقيقيين (DAOs/Repositories/Services).
//   2. تسجيله في Outbox (نفس ما يفعله الإنتاج).
//   3. بنية عملية الدفع عبر buildPushOperation (نقطة الدفع الوحيدة في
//      _pushBatch) + PayloadNormalizer (camelCase → snake_case).
//   4. حقول المزامنة العامة لكل كيان (الهوية/الساعة/ال Idempotency) +
//      الحقول الخاصة بكل جدول ضد مخطط D1 الفعلي (worker/schema.sql).
//   5. محاكاة أمينة لدلالات createRecord في الـ worker (database.ts):
//      فلترة الأعمدة بـ PRAGMA + ختم الخادم (updated_at الموزّع،
//      origin='cloud'، version=1، device_id) + ملء NOT NULL.
//   6. السحب العكسي عبر applyPulledRecords الحقيقي على قاعدة ناظرة
//      (جهاز آخر) — بدون فقدان أو تغيير نوع، مع ترجمة FK وظلّ server_id.
//
// يغطي أيضاً حدود النطاق المعماري: مطابقة ENTITY_TABLES بين الـ worker
// وCloudflareConfig، واستبعاد hotel_day_ledger (محلي محسوب)، ومسار
// blacklist الخاص (كيان سحابي بلا جدول Drift — يهبط في shift_notes).

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marina_hotel_mobile/services/auth_local_store.dart';
import 'package:marina_hotel_mobile/services/booking_price_adjustment_service.dart';
import 'package:marina_hotel_mobile/services/cloudflare_config.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/daos/bookings_dao.dart';
import 'package:marina_hotel_mobile/services/daos/booking_notes_dao.dart';
import 'package:marina_hotel_mobile/services/daos/cash_transactions_dao.dart';
import 'package:marina_hotel_mobile/services/daos/debts_dao.dart';
import 'package:marina_hotel_mobile/services/daos/employees_dao.dart';
import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/daos/payments_dao.dart';
import 'package:marina_hotel_mobile/services/daos/rooms_dao.dart';
import 'package:marina_hotel_mobile/services/daos/shift_notes_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_void_service.dart';
import 'package:marina_hotel_mobile/services/price_adjustment_service.dart';
import 'package:marina_hotel_mobile/services/repositories/blacklist_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/guest_infos_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/inventory_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/salary_withdrawals_repository.dart';
import 'package:marina_hotel_mobile/services/sync/payload_normalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════
//  قراءة مخطط D1 الفعلي من worker/schema.sql (الأعمدة + الأنواع +
//  قيود NOT NULL/DEFAULT) وخريطة ENTITY_TABLES من worker/src/database.ts
//  — لا قوائم مكرَّرة يدوياً: المرجع هو مصدر الـ worker نفسه.
// ═══════════════════════════════════════════════════════════════

class _Col {
  _Col(this.name, this.type, this.notNull, this.hasDefault);
  final String name;
  final String type;
  final bool notNull;
  final bool hasDefault;
}

Map<String, Map<String, _Col>>? _schema;

File _repoFile(String relative) {
  final candidates = [
    File('../$relative'),
    File(relative),
    File('../../$relative'),
  ];
  return candidates.firstWhere(
    (f) => f.existsSync(),
    orElse: () => throw StateError('$relative غير موجود — الاختبار يحتاجه'),
  );
}

Map<String, Map<String, _Col>> _loadSchema() {
  if (_schema != null) return _schema!;
  final tables = <String, Map<String, _Col>>{};
  String? current;
  for (final raw in _repoFile('worker/schema.sql').readAsLinesSync()) {
    final line = raw.trim();
    final create = RegExp(
      r'^CREATE TABLE (IF NOT EXISTS )?(\w+) \($',
    ).firstMatch(line);
    if (create != null) {
      current = create.group(2)!;
      tables.putIfAbsent(current, () => <String, _Col>{});
      continue;
    }
    if (current == null) continue;
    if (line.startsWith(')')) {
      current = null;
      continue;
    }
    if (line.isEmpty || line.startsWith('--')) continue;
    final m = RegExp(r'^"?(\w+)"?\s+(TEXT|INTEGER|REAL|BLOB)').firstMatch(
      line,
    );
    if (m == null) continue; // UNIQUE/FOREIGN/PRIMARY/CHECK/CONSTRAINT
    final name = m.group(1)!;
    if (const {
      'UNIQUE',
      'PRIMARY',
      'FOREIGN',
      'CHECK',
      'CONSTRAINT',
    }.contains(name)) {
      continue;
    }
    tables[current]![name] = _Col(
      name,
      m.group(2)!,
      line.contains('NOT NULL'),
      line.contains('DEFAULT'),
    );
  }
  return _schema = tables;
}

Set<String>? _workerEntities;

Set<String> _loadWorkerEntities() {
  if (_workerEntities != null) return _workerEntities!;
  final lines = _repoFile('worker/src/database.ts').readAsLinesSync();
  final entities = <String>{};
  var inside = false;
  for (final line in lines) {
    if (line.contains('const ENTITY_TABLES')) {
      inside = true;
      continue;
    }
    if (inside) {
      if (line.startsWith('};')) break;
      final m = RegExp(r"(\w+):\s*'(\w+)'").firstMatch(line);
      if (m != null) entities.add(m.group(1)!);
    }
  }
  expect(entities, isNotEmpty, reason: 'ENTITY_TABLES لم تُقرأ من database.ts');
  return _workerEntities = entities;
}

/// أعمدة جدول محلي (Drift) — قياس حقيقي بـ PRAGMA على قاعدة الاختبار.
Future<Set<String>> localColumns(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.data['name'] as String).toSet();
}

// مؤشرات FK الرقمية على السلك (مرآة _fkRules في cloudflare_sync_manager):
// {الكيان: {العمود: جدول الأب}} — الترجمة عند السحب تتم عبر uuid_cache
// أو ظلّ server_id للأب (اعتماداً على ترتيب السحب الخادمي).
const Map<String, Map<String, String>> _fkPointers = {
  'booking_nights': {'booking_local_id': 'bookings'},
  'booking_notes': {'booking_id': 'bookings'},
  'payments': {
    'booking_local_id': 'bookings',
    'cash_transaction_local_id': 'cash_transactions',
  },
  'booking_price_adjustments': {'booking_local_id': 'bookings'},
  'salary_cycles': {'employee_id': 'employees'},
  'salary_payments': {'cycle_id': 'salary_cycles'},
  'salary_withdrawals': {'employee_id': 'employees'},
  'salary_carry_over_logs': {'employee_id': 'employees'},
  'inventory_transactions': {'item_id': 'inventory_items'},
};

/// أعمدة يصدرها الإنتاج المعروف ولا تحملها جداول Drift المحلية
/// (يسقطها _filterToLocalColumns عمداً — إسقاط لا فقدان).
const Set<String> _droppableKeys = {'sync_timestamp'};

/// أعمدة سحابية فقط (في D1 لا في Drift) — تُسقط عند السحب بلا أثر:
/// مرتبطة بأسباب موثقة؛ أي عمود جديد خارج هذه القائمة = فشل صاخب
/// يطلب مراجعة (قائمة موجبة صريحة لا كتم صامت).
const Map<String, Set<String>> _serverOnlyColumns = {
  // مرجع ذاتي قديم في جدول employees على D1 بلا استخدام محلي
  'employees': {'employee_id'},
  // ✅ (2026-09-19) salary_withdrawals.employee_uuid لم يبقَ سحابياً فقط —
  // أُضيف عمود Drift محلي (migration 68) يُخزَّن من الحمولة ويُعاد
  // إرساله في toJson، فصار الاثنان متطابقين (نفس عقد expenses).
};

bool _sameValue(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a == b) return true;
  if (a is num && b is num) return a == b; // 500 == 500.0
  return false;
}

// ═══════════════════════════════════════════════════════════════
//  محاكاة أمينة لدلالات worker createRecord (worker/src/database.ts)
// ═══════════════════════════════════════════════════════════════

Map<String, dynamic> _simulateWorkerCreateRow({
  required String entity,
  required Map<String, dynamic> op,
  required int wireId,
  required int serverUpdatedAt,
  required String deviceId,
}) {
  final table = CloudflareConfig.tableNameFor(entity)!;
  final cols = _loadSchema()[table]!;
  final data = (op['data'] as Map).cast<String, dynamic>();

  // worker: ينسخ البيانات ثم يختم حقول الخادم المرجعية.
  final row = <String, dynamic>{};
  data.forEach((k, v) {
    if (k == 'id') return; // delete record.id — D1 autoincrement
    if (cols.containsKey(k)) row[k] = v; // فلترة PRAGMA table_info
  });
  row['id'] = wireId;
  row['local_uuid'] = data['local_uuid'];
  row['server_id'] = null;
  final createdAtNum = data['created_at'];
  row['created_at'] = createdAtNum is num && createdAtNum > 0
      ? createdAtNum
      : serverUpdatedAt;
  row['updated_at'] = serverUpdatedAt; // allocateUpdatedAt
  row['deleted_at'] = null;
  row['version'] = 1;
  row['origin'] = 'cloud';
  row['device_id'] = deviceId;
  final vc = data['vector_clock'];
  row['vector_clock'] = (vc is String && vc.isNotEmpty && vc != '{}')
      ? vc
      : jsonEncode({deviceId: 1});

  // worker createRecord: خطوات الملء الثلاث قبل فلترة PRAGMA
  // (worker/src/database.ts — createRecord).
  if (row['last_modified'] == null || (row['last_modified'] as num) == 0) {
    row['last_modified'] = serverUpdatedAt;
  }
  if (row['created_at_epoch'] == null ||
      (row['created_at_epoch'] as num) == 0) {
    row['created_at_epoch'] = 0;
  }
  if (row['last_modified_epoch'] == null ||
      (row['last_modified_epoch'] as num) == 0) {
    row['last_modified_epoch'] = 0;
  }

  // worker: ملء NOT NULL بلا DEFAULT بقيم فارغة حسب النوع.
  for (final col in cols.values) {
    if (!col.notNull || col.hasDefault) continue;
    if (col.name == 'id' || col.name == 'local_uuid') continue;
    if (row.containsKey(col.name) && row[col.name] != null) continue;
    row[col.name] =
        (col.type == 'INTEGER' || col.type == 'REAL' || col.type == 'BLOB')
        ? 0
        : '';
  }

  // الدلالة المادية: صف D1 حقيقي يُجسّد DEFAULT عند الإدراج، والسحب
  // يعيد SELECT * — كل الأعمدة حاضرة بقيمها الافتراضية إن لم تُرسل.
  for (final col in cols.values) {
    if (row.containsKey(col.name) && row[col.name] != null) continue;
    if (!col.hasDefault) continue;
    final raw = _defaultLiteral(col.name, table);
    row[col.name] = col.type == 'INTEGER'
        ? int.tryParse(raw) ?? 0
        : col.type == 'REAL'
        ? double.tryParse(raw) ?? 0.0
        : raw;
  }
  return row;
}

/// القيمة الافتراضية المعلنة في worker/schema.sql (داخل كتلة الجدول).
String? _declaredDefault(String table, String column) {
  String? current;
  for (final raw in _repoFile('worker/schema.sql').readAsLinesSync()) {
    final line = raw.trim();
    final create = RegExp(
      r'^CREATE TABLE (IF NOT EXISTS )?(\w+) \($',
    ).firstMatch(line);
    if (create != null) {
      current = create.group(2)!;
      continue;
    }
    if (current == null) continue;
    if (line.startsWith(')')) {
      current = null;
      continue;
    }
    if (current != table || line.isEmpty || line.startsWith('--')) continue;
    if (!line.startsWith('"$column"') && !line.startsWith('$column ')) {
      continue;
    }
    final m = RegExp(r'DEFAULT\s+([^,]+)').firstMatch(line);
    if (m == null) continue;
    return m.group(1)!.trim().replaceAll("'", '');
  }
  return null;
}

String _defaultLiteral(String column, String table) =>
    _declaredDefault(table, column) ?? '';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase dbA; // جهاز المنتِج
  late AppDatabase dbB; // جهاز المستقبِل (قاعدة ناظرة)
  late OutboxDao outboxDao;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
      'cf_device_id': 'contract-device-A',
    });
    dbA = AppDatabase.forTesting(NativeDatabase.memory());
    dbB = AppDatabase.forTesting(NativeDatabase.memory());
    outboxDao = OutboxDao(dbA);
  });

  tearDown(() async {
    await dbA.close();
    await dbB.close();
  });

  // ─── المنتجون الحقيقيون (نفس مسارات الإنتاج) ──────────────────

  Future<Map<String, List<OutboxData>>> _produceAll() async {
    // الترتيب = الترتيب الإنتاجي: الآباء قبل الأبناء.
    final roomsDao = RoomsDao(dbA, outboxDao);
    final bookingsDao = BookingsDao(dbA, outboxDao);
    final employeesDao = EmployeesDao(dbA, outboxDao);

    // غرفة وحجز نشط بليالٍ (للدفعات والملاحظات والديون والتسويات)
    await roomsDao.insertOne(
      RoomsCompanion(
        roomNumber: const d.Value('701'),
        type: const d.Value('standard'),
        price: const d.Value(150.0),
        status: const d.Value('شاغرة'),
      ),
    );
    final now = DateTime.now();
    final bookingId = await bookingsDao.insertOne(
      BookingsCompanion(
        roomNumber: const d.Value('701'),
        guestName: const d.Value('ضيف السلسلة'),
        guestPhone: const d.Value('0555555555'),
        guestIdType: const d.Value('هوية'),
        guestNationality: const d.Value('يمني'),
        checkinDate: d.Value(
          now.subtract(const Duration(days: 1)).toIso8601String(),
        ),
        checkoutDate: d.Value(
          now.add(const Duration(days: 1)).toIso8601String(),
        ),
        status: const d.Value('نشط'),
        discountType: const d.Value('none'),
        needsCheckoutReview: const d.Value(false),
        remainingBalanceCached: const d.Value(0),
      ),
    );
    for (final offset in [0, 1]) {
      final dayKey = now
          .add(Duration(days: offset))
          .toIso8601String()
          .substring(0, 10);
      await dbA
          .into(dbA.bookingNights)
          .insert(
            BookingNightsCompanion.insert(
              bookingLocalId: bookingId,
              hotelDayKey: dayKey,
              nightStart: now.toIso8601String(),
              nightEnd: now.add(const Duration(days: 1)).toIso8601String(),
              localUuid: 'night-$offset-uuid',
              createdAt: 1720000000,
              updatedAt: 1720000000,
              lastModified: 1720000000,
            ),
          );
    }

    // موظف
    await employeesDao.insertOne(
      EmployeesCompanion(
        name: const d.Value('موظف السلسلة'),
        basicSalary: const d.Value(3000.0),
        status: const d.Value('active'),
      ),
    );

    // دفعة
    await PaymentsDao(dbA, outboxDao).insertOne(
      PaymentsCompanion(
        bookingLocalId: d.Value(bookingId),
        amount: const d.Value(500.0),
        paymentDate: d.Value(now.toIso8601String()),
        paymentMethod: const d.Value('cash'),
        revenueType: const d.Value('room'),
        isPendingBalance: const d.Value(false),
      ),
    );

    // مصروف
    await ExpensesDao(dbA, outboxDao).insertOne(
      ExpensesCompanion(
        expenseType: const d.Value('صيانة'),
        description: const d.Value('اصلاح مكيف'),
        amount: const d.Value(120.0),
        date: d.Value(now.toIso8601String()),
        isAutoGenerated: const d.Value(false),
      ),
    );

    // دين
    await DebtsDao(dbA, outboxDao).insertOne(
      DebtsCompanion(
        bookingLocalId: d.Value(bookingId),
        guestName: const d.Value('مدين السلسلة'),
        checkinDate: d.Value(now.toIso8601String()),
        checkoutDate: d.Value(
          now.add(const Duration(days: 1)).toIso8601String(),
        ),
        totalAmount: const d.Value(1000.0),
        paidAmount: const d.Value(400.0),
        remainingAmount: const d.Value(600.0),
        paymentDate: d.Value(now.toIso8601String()),
        isFromAutoFix: const d.Value(false),
        settlementConfirmed: const d.Value(false),
      ),
    );

    // ملاحظة حجز
    await BookingNotesDao(dbA, outboxDao).insertOne(
      BookingNotesCompanion(
        bookingId: d.Value(bookingId),
        noteText: const d.Value('ملاحظة السلسلة'),
        alertType: const d.Value('info'),
      ),
    );

    // معاملة صندوق + ملاحظة وردية
    await CashTransactionsDao(dbA, outboxDao).insertOne(
      CashTransactionsCompanion(
        transactionType: const d.Value('income'),
        amount: const d.Value(300.0),
        transactionTime: d.Value(now.toIso8601String()),
      ),
    );
    await ShiftNotesDao(dbA, outboxDao).addNote(
      title: 'ملاحظة وردية السلسلة',
      content: 'تفاصيل الوردية',
    );

    // نزيل + مخزون (صنف + حركة افتتاحية)
    await GuestInfosRepository(dbA).create(
      roomNumber: '701',
      guestName: 'نزيل السلسلة',
      nationality: 'يمني',
      idNumber: '12345',
    );
    await InventoryRepository(dbA).createItem(
      name: 'منشفة',
      unit: 'قطعة',
      initialQuantity: 10,
      minimumQuantity: 2,
    );

    // سحب راتب (يتطلب موظفاً)
    await SalaryWithdrawalsRepository(dbA).createFromExpense(
      expenseId: 0,
      employeeId: 1,
      reason: 'سلفة',
      amount: 100.0,
      date: now.toIso8601String(),
    );

    // قائمة سوداء (كيان سحابي عبر مسار خاص)
    await BlacklistRepository(dbA).addEntry(
      name: 'محظور السلسلة',
      nationality: 'يمني',
      reason: 'تجربة السلسلة',
    );

    // تعديل سعر غرفة → price_adjustments + audit_logs
    await PriceAdjustmentService(dbA).applyRoomPriceChange(
      roomNumber: '701',
      oldPrice: 150,
      newPrice: 200.5,
      appliedBy: 'tester',
      reason: 'اختبار السلسلة',
    );

    // تسوية سعر مؤقتة على الحجز → booking_price_adjustments
    final booking = await (dbA.select(
      dbA.bookings,
    )..where((b) => b.id.equals(bookingId))).getSingle();
    await BookingPriceAdjustmentService(dbA).applyTemporaryAdjustment(
      bookingLocalUuid: booking.localUuid,
      amount: 25,
      type: AdjustmentType.discount,
      effectiveHotelDay: now.toIso8601String().substring(0, 10),
      reason: 'خصم السلسلة',
      appliedBy: 'tester',
    );

    // إبطال دفعة → payment_voids + payments update (is_voided)
    final payment = await (dbA.select(
      dbA.payments,
    )..where((p) => p.bookingLocalId.equals(bookingId))).getSingle();
    await PaymentVoidService(dbA).voidPayment(
      paymentUuid: payment.localUuid,
      voidReason: 'إبطال السلسلة',
      voidedBy: 'tester',
    );

    // app_users — الحمولة المرجعية الثابتة (نفس مسار الإنتاج)
    await outboxDao.merge(
      entity: 'app_users',
      op: 'create',
      localUuid: 'user-chain-1',
      payload: AuthLocalStore.appUsersSyncPayload(
        localUuid: 'user-chain-1',
        username: 'tester',
        fullName: 'مستخدم السلسلة',
        active: true,
        now: 1720000000,
        deviceId: 'contract-device-A',
      ),
      clientTs: 1720000000,
    );

    // devices — المنتج الحقيقي: registerDevice عبر HTTP موك 200
    final managerA = CloudflareSyncManager();
    managerA.reset();
    managerA.configureForTesting(
      database: dbA,
      httpClient: _MockDeviceRegisterClient(),
      token: 'test-token',
      deviceId: 'contract-device-A',
    );
    await managerA.registerDevice();

    // اقرأ outbox بالترتيب
    final rows = await (outboxDao.select(
      outboxDao.outbox,
    )..orderBy([(t) => d.OrderingTerm.asc(t.id)])).get();
    expect(rows, isNotEmpty, reason: 'المنتجون لم يكتبوا في outbox');
    final byEntity = <String, List<OutboxData>>{};
    for (final r in rows) {
      byEntity.putIfAbsent(r.entity, () => []).add(r);
    }
    return byEntity;
  }

  // ═════════════════════════════════════════════════════════════
  //  المجموعة 1: حدود النطاق المعماري (worker ↔ Dart ↔ Drift)
  // ═════════════════════════════════════════════════════════════
  group('حدود النطاق المعماري', () {
    test(
      'ENTITY_TABLES في الـ worker مطابقة تماماً لخريطة CloudflareConfig',
      () {
        final workerEntities = _loadWorkerEntities();
        final dartEntities = CloudflareConfig.entityToTable.keys.toSet();
        expect(
          dartEntities.difference(workerEntities),
          isEmpty,
          reason: 'كيانات في Dart بلا مرآة في worker ENTITY_TABLES',
        );
        expect(
          workerEntities.difference(dartEntities),
          isEmpty,
          reason: 'كيانات في worker بلا مرآة في CloudflareConfig',
        );
        for (final entity in workerEntities) {
          final table = CloudflareConfig.tableNameFor(entity);
          expect(table, isNotNull, reason: '$entity بلا جدول');
          expect(
            _loadSchema().containsKey(table),
            isTrue,
            reason: '$entity → جدول $table غير موجود في worker/schema.sql',
          );
        }
      },
    );

    test(
      'hotel_day_ledger محلي محسوب — مستبعد من المزامنة السحابية عمداً',
      () async {
        expect(
          _loadWorkerEntities().contains('hotel_day_ledger'),
          isFalse,
          reason: 'جدول مشتق محلي لا يجوز رفعه إلى D1',
        );
        expect(
          CloudflareConfig.entityToTable.containsKey('hotel_day_ledger'),
          isFalse,
        );
        // موجود محلياً فقط
        final tables = await dbA
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get();
        final names = tables.map((r) => r.data['name'] as String).toSet();
        expect(names.contains('hotel_day_ledger'), isTrue);
      },
    );

    test(
      'blacklist كيان سحابي بلا جدول Drift — يهبط في shift_notes الموسومة',
      () async {
        expect(_loadWorkerEntities().contains('blacklist'), isTrue);
        final tables = await dbA
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get();
        final names = tables.map((r) => r.data['name'] as String).toSet();
        expect(
          names.contains('blacklist'),
          isFalse,
          reason: 'لا جدول Drift محلياً — المسار خاص عبر shift_notes',
        );
        expect(names.contains('shift_notes'), isTrue);
      },
    );
  });

  // ═════════════════════════════════════════════════════════════
  //  المجموعة 2: عقد الرفع — حقول المزامنة العامة لكل كيان
  // ═════════════════════════════════════════════════════════════
  group('عقد الرفع: حقول المزامنة العامة لكل كيان', () {
    test('كل عملية دفع تحمل العقد العام وتلتزم أعمدة D1 وأنواعها', () async {
      final byEntity = await _produceAll();
      final ops = <Map<String, dynamic>>[];
      for (final entry in byEntity.entries) {
        for (final item in entry.value) {
          ops.add(
            await buildPushOperation(
              item,
              resolveRowVectorClock: (_, __) async => null,
            ),
          );
        }
      }
      expect(ops.length, byEntity.values.fold<int>(0, (a, l) => a + l.length));

      final failures = <String>[];
      for (final op in ops) {
        final entity = op['entity'] as String;
        final table = CloudflareConfig.tableNameFor(entity)!;
        final cols = _loadSchema()[table]!;
        final data = (op['data'] as Map).cast<String, dynamic>();
        final where = '$entity/$table';

        // 1) عقد مستوى العملية
        if ((op['idempotencyKey'] as String?)!.isEmpty) {
          failures.add('$where: idempotencyKey فارغ');
        }
        if (!_loadWorkerEntities().contains(entity)) {
          failures.add('$where: كيان خارج ENTITY_TABLES');
        }
        if (!['create', 'update', 'delete'].contains(op['operation'])) {
          failures.add('$where: operation غير صالح');
        }
        final vc = op['vectorClock'] as String;
        try {
          jsonDecode(vc) as Map<String, dynamic>;
        } catch (_) {
          failures.add('$where: vectorClock ليس JSON كائن: $vc');
        }
        if ((op['updatedAt'] as int?) == null ||
            (op['updatedAt'] as int) <= 0) {
          failures.add('$where: updatedAt يجب أن يكون عدداً موجباً');
        }

        // 2) عقد الهوية (requireEntityId)
        final localUuid = data['local_uuid'];
        if (localUuid is! String || localUuid.isEmpty) {
          failures.add('$where: local_uuid مطلوب نصاً غير فارغ');
          continue;
        }

        // 3) كل مفتاح عمود D1 فعلي — وإلا سقط صمتاً في الـ worker
        for (final key in data.keys) {
          if (!cols.containsKey(key) && !_droppableKeys.contains(key)) {
            failures.add('$where: العمود $key غير موجود في D1 — فقدان صامت');
          }
        }

        // 4) الأنواع: لا bool (D1 يرفض JS boolean) ولا List/Map (bind يفشل)
        for (final entry0 in data.entries) {
          final v = entry0.value;
          if (v is bool) {
            failures.add('$where: قيمة bool في ${entry0.key} — D1 يرفضها');
          }
          if (v is List || v is Map) {
            failures.add(
              '$where: قيمة ${v.runtimeType} في ${entry0.key} — '
              'bind في D1 يفشل، يجب ترميزها نصاً',
            );
          }
          if (v == null || v is String || v is num) continue;
          failures.add(
            '$where: نوع غير متوقع ${v.runtimeType} في ${entry0.key}',
          );
        }

        // 5) created_at إن وُجد يجب أن يكون عدداً موجباً (worker يحترمه)
        final createdAt = data['created_at'];
        if (createdAt != null && (createdAt is! num || createdAt <= 0)) {
          failures.add('$where: created_at غير صالح: $createdAt');
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  // ═════════════════════════════════════════════════════════════
  //  المجموعة 3: السلسلة الكاملة — رفع ثم محاكاة worker ثم سحب عكسي
  //  على قاعدة ناظرة (جهاز آخر) بلا فقدان أو تغيير نوع.
  // ═════════════════════════════════════════════════════════════
  group('السلسلة الكاملة: رفع → worker → سحب عكسي على جهاز آخر', () {
    test(
      'كل ما أُنتج محلياً يهبط في الجهاز الآخر بقيمه وأنواعه',
      () async {
        final byEntity = await _produceAll();

        // 1) بنية عمليات الدفع بالترتيب الإنتاجي + توزيع معرفات السلك
        // (محاكاة D1 autoincrement: عدّاد لكل جدول بترتيب الوصول —
        // نفس الحالة الثابتة الإنتاجية حيث كلا الجهازين انطلقا من
        // bootstrap كامل فتتطابق مساحات المعرفات).
        final ops = <(String, Map<String, dynamic>)>[];
        final wireIdByUuid = <String, Map<String, int>>{};
        var serverTs = 1750000000; // موزّع updated_at أحادي
        for (final entry in byEntity.entries) {
          for (final item in entry.value) {
            final op = await buildPushOperation(
              item,
              resolveRowVectorClock: (_, __) async => null,
            );
            ops.add((entry.key, op));
            final data = op['data'] as Map<String, dynamic>;
            final ids = wireIdByUuid.putIfAbsent(entry.key, () => {});
            ids.putIfAbsent(
              data['local_uuid'] as String,
              () => ids.length + 1,
            );
            serverTs += 1;
          }
        }

        // 2) محاكاة createRecord في الـ worker لكل عملية
        final records = <({String entity, Map<String, dynamic> record})>[];
        for (final (entity, op) in ops) {
          final data = op['data'] as Map<String, dynamic>;
          final row = _simulateWorkerCreateRow(
            entity: entity,
            op: op,
            wireId: wireIdByUuid[entity]![data['local_uuid'] as String]!,
            serverUpdatedAt: serverTs,
            deviceId: 'contract-device-A',
          );
          records.add((entity: entity, record: row));
        }

        // 3) صفوف كيانات «سحب-فقط» بلا صانع محلي (أرض هبوط السحب):
        // booking_nights (اشتقاقي) + salary_cycles + salary_payments.
        final employeeWireId = wireIdByUuid['employees']!.values.first;
        final bookingWireId = wireIdByUuid['bookings']!.values.first;
        final bookingUuidOnWire =
            (ops.firstWhere((o) => o.$1 == 'bookings').$2['data']
                    as Map)['local_uuid']
                as String;
        final nightsRow = _simulateWorkerCreateRow(
          entity: 'booking_nights',
          op: {
            'data': {
              'local_uuid': 'wire-night-1',
              'booking_local_id': bookingWireId,
              'booking_uuid_cache': bookingUuidOnWire,
              'hotel_day_key': '2026-09-14',
              'night_start': '2026-09-14T14:00:00.000Z',
              'night_end': '2026-09-15T12:00:00.000Z',
              'nightly_rate': 150.0,
              'base_rate': 150.0,
              'adjustment': 0.0,
              'final_rate': 150.0,
              'sequence': 1,
              'created_at': 1750000000,
              'vector_clock': '{}',
            },
          },
          wireId: 1,
          serverUpdatedAt: ++serverTs,
          deviceId: 'contract-device-A',
        );
        records.add((entity: 'booking_nights', record: nightsRow));
        final cycleRow = _simulateWorkerCreateRow(
          entity: 'salary_cycles',
          op: {
            'data': {
              'local_uuid': 'wire-cycle-1',
              'employee_id': employeeWireId,
              'cycle_key': '2026-09',
              'hotel_day_start': '2026-09-01',
              'hotel_day_end': '2026-09-30',
              'expected_amount': 3000,
              'status': 'draft',
              'created_at': 1750000000,
              'vector_clock': '{}',
            },
          },
          wireId: 1,
          serverUpdatedAt: ++serverTs,
          deviceId: 'contract-device-A',
        );
        records.add((entity: 'salary_cycles', record: cycleRow));
        final salaryPaymentRow = _simulateWorkerCreateRow(
          entity: 'salary_payments',
          op: {
            'data': {
              'local_uuid': 'wire-spay-1',
              'cycle_id': 1,
              'amount': 1500,
              'hotel_day_key': '2026-09-14',
              'payment_date_iso': '2026-09-14T10:00:00.000Z',
              'method': 'cash',
              'created_at': 1750000000,
              'vector_clock': '{}',
            },
          },
          wireId: 1,
          serverUpdatedAt: ++serverTs,
          deviceId: 'contract-device-A',
        );
        records.add((entity: 'salary_payments', record: salaryPaymentRow));
        // salary_carry_over_logs — كيان سحب-فقط في بيئة الاختبار
        // (الصانع الحقيقي يعمل عند وجود دورة سابقة بترحيل)
        final carryRow = _simulateWorkerCreateRow(
          entity: 'salary_carry_over_logs',
          op: {
            'data': {
              'local_uuid': 'wire-carry-1',
              'employee_id': employeeWireId,
              'amount': 250.0,
              'reason': 'ترحيل السلسلة',
              'carried_at': 1750000000,
              'created_at': 1750000000,
              'vector_clock': '{}',
            },
          },
          wireId: 1,
          serverUpdatedAt: ++serverTs,
          deviceId: 'contract-device-A',
        );
        records.add((entity: 'salary_carry_over_logs', record: carryRow));

        // 4) السحب العكسي عبر applyPulledRecords الحقيقي — بلا شبكة
        final managerB = CloudflareSyncManager();
        managerB.reset();
        managerB.configureForTesting(
          database: dbB,
          httpClient: _NoNetworkClient(),
          token: 'test-token',
          deviceId: 'contract-device-B',
        );
        final report = await managerB.applyPulledRecords(records);

        // 5) لا أخطاء ولا مؤجلين — كل الصفوف هبطت
        expect(
          report.errors,
          isEmpty,
          reason: 'أخطاء تطبيق سحب حقيقية:\n${report.errors.join('\n')}',
        );
        expect(
          report.unresolvable,
          isEmpty,
          reason:
              'صفوف بلا أب (فشل ترجمة FK عبر الأجهزة):\n'
              '${report.unresolvable.join('\n')}',
        );
        expect(report.appliedCount, records.length);

        // 6) مطابقة القيم عموداً عموداً بين ما دُفع وما هبط
        final failures = <String>[];
        var checkedEntities = <String>{};
        for (final (entity, _) in ops) {
          checkedEntities.add(entity);
        }
        for (final (entity, op) in ops) {
          final data = (op['data'] as Map).cast<String, dynamic>();
          final localUuid = data['local_uuid'] as String;
          final table = CloudflareConfig.tableNameFor(entity)!;
          final localCols = await localColumns(dbB, table);

          if (entity == 'blacklist') {
            // المسار الخاص: يهبط في shift_notes الموسومة
            final row = await dbB
                .customSelect(
                  'SELECT * FROM shift_notes '
                  "WHERE local_uuid = ? AND created_by = 'blacklist'",
                  variables: [d.Variable.withString(localUuid)],
                )
                .getSingleOrNull();
            if (row == null) {
              failures.add('blacklist/$localUuid: لم يهبط في shift_notes');
              continue;
            }
            if (!_sameValue(row.data['title'], data['name'])) {
              failures.add(
                'blacklist: title=${row.data['title']} ≠ name=${data['name']}',
              );
            }
            final content =
                jsonDecode(row.data['content'] as String)
                    as Map<String, dynamic>;
            for (final pair in {
              'nationality': 'nationality',
              'reason': 'reason',
              'reportedBy': 'reported_by',
            }.entries) {
              if (!_sameValue(content[pair.key], data[pair.value])) {
                failures.add(
                  'blacklist: content.${pair.key}=${content[pair.key]} '
                  '≠ wire.${pair.value}=${data[pair.value]}',
                );
              }
            }
            final wireActive = (data['active'] as num? ?? 1) != 0;
            if (content['active'] != wireActive) {
              failures.add(
                'blacklist: active=${content['active']} ≠ $wireActive',
              );
            }
            continue;
          }

          final row = await dbB
              .customSelect(
                'SELECT * FROM $table WHERE local_uuid = ?',
                variables: [d.Variable.withString(localUuid)],
              )
              .getSingleOrNull();
          if (row == null) {
            failures.add('$entity/$localUuid: لم يهبط إلى الجدول $table');
            continue;
          }

          final fkRules = _fkPointers[entity] ?? const {};
          for (final entry0 in data.entries) {
            final key = entry0.key;
            final expected = entry0.value;

            if (key == 'id') continue; // يُحذف طرفا الرفع والسحب
            if (key == 'updated_at') {
              // ختم الخادم يفوز دائماً (موزّع أحادي)
              continue;
            }
            if (key == 'origin') {
              if (row.data[key] != 'cloud') {
                failures.add('$entity: origin=${row.data[key]} ≠ cloud');
              }
              continue;
            }
            if (key == 'version') {
              if (!_sameValue(row.data[key], 1)) {
                failures.add('$entity: version=${row.data[key]} ≠ 1');
              }
              continue;
            }
            if (key == 'device_id') {
              if (!_sameValue(row.data[key], 'contract-device-A')) {
                failures.add('$entity: device_id مفقود من الهبوط');
              }
              continue;
            }
            if (key == 'server_id') {
              // ظلّ هوية الخادم: id الصف على D1 يُخزَّن محلياً
              final wireId = wireIdByUuid[entity]![localUuid];
              if (!_sameValue(row.data[key], wireId)) {
                failures.add(
                  '$entity: server_id=${row.data[key]} ≠ wire id=$wireId '
                  '(ظلّ الهوية مكسور — الأبناء لن يترجموا مؤشراتهم)',
                );
              }
              continue;
            }
            if (fkRules.containsKey(key)) {
              // مؤشر FK رقمي: بعد الترجمة يجب أن يشير لأب موجود محلياً
              final landed = row.data[key];
              if (landed == null) {
                final nullableOnWire = expected == null;
                if (!nullableOnWire) {
                  failures.add(
                    '$entity: مؤشر $key صار NULL رغم أن السلك حمل $expected',
                  );
                }
                continue;
              }
              final parentTable = fkRules[key]!;
              final parent = await dbB
                  .customSelect(
                    'SELECT local_uuid FROM $parentTable WHERE id = ?',
                    variables: [d.Variable(landed)],
                  )
                  .getSingleOrNull();
              if (parent == null) {
                failures.add(
                  '$entity: مؤشر $key=$landed لا يشير لأب في $parentTable',
                );
              }
              continue;
            }
            if (key == 'vector_clock') {
              // ملك خادمي: عند فراغ ساعة العميل يبني الـ worker ساعة
              // جديدة {deviceId:1} — صحة العقد أُثبتت على مستوى العملية
              continue;
            }
            if (!localCols.contains(key)) {
              // عمود خادمي بلا مرآة محلية — إسقاط موثق فقط
              final allowed = _droppableKeys.union(
                _serverOnlyColumns[entity] ?? const <String>{},
              );
              if (!allowed.contains(key)) {
                failures.add(
                  '$entity: العمود $key على السلك بلا مرآة محلية — '
                  'أضفه لـ _droppableKeys/_serverOnlyColumns أو للمخططين',
                );
              }
              continue;
            }
            if (!_sameValue(row.data[key], expected)) {
              failures.add(
                '$entity.$key: هبط ${row.data[key]} '
                '(${row.data[key].runtimeType}) ≠ دُفع $expected '
                '(${expected?.runtimeType})',
              );
            }
          }
        }

        // الكيانات سحب-فقط: تحقق هبوط بقيمها الجوهرية
        final night = await dbB
            .customSelect(
              "SELECT * FROM booking_nights WHERE local_uuid = 'wire-night-1'",
            )
            .getSingleOrNull();
        if (night == null) {
          failures.add('booking_nights: الصف سحب-فقط لم يهبط');
        } else {
          if (!_sameValue(night.data['nightly_rate'], 150.0)) {
            failures.add(
              'booking_nights: nightly_rate=${night.data['nightly_rate']}',
            );
          }
          if (!_sameValue(
            night.data['booking_uuid_cache'],
            bookingUuidOnWire,
          )) {
            failures.add('booking_nights: booking_uuid_cache مفقود');
          }
        }
        final cycle = await dbB
            .customSelect(
              "SELECT * FROM salary_cycles WHERE local_uuid = 'wire-cycle-1'",
            )
            .getSingleOrNull();
        if (cycle == null) {
          failures.add('salary_cycles: الصف سحب-فقط لم يهبط');
        } else {
          if (!_sameValue(cycle.data['expected_amount'], 3000)) {
            failures.add(
              'salary_cycles: expected_amount=${cycle.data['expected_amount']}',
            );
          }
          if (cycle.data['employee_id'] == null) {
            failures.add('salary_cycles: employee_id لم يترجم');
          }
        }
        final spay = await dbB
            .customSelect(
              "SELECT * FROM salary_payments WHERE local_uuid = 'wire-spay-1'",
            )
            .getSingleOrNull();
        if (spay == null) {
          failures.add('salary_payments: الصف سحب-فقط لم يهبط');
        } else {
          if (!_sameValue(spay.data['amount'], 1500)) {
            failures.add('salary_payments: amount=${spay.data['amount']}');
          }
        }
        final carry = await dbB
            .customSelect(
              "SELECT * FROM salary_carry_over_logs WHERE local_uuid = 'wire-carry-1'",
            )
            .getSingleOrNull();
        if (carry == null) {
          failures.add('salary_carry_over_logs: الصف سحب-فقط لم يهبط');
        } else {
          if (!_sameValue(carry.data['amount'], 250.0)) {
            failures.add(
              'salary_carry_over_logs: amount=${carry.data['amount']}',
            );
          }
          if (carry.data['employee_id'] == null) {
            failures.add('salary_carry_over_logs: employee_id لم يترجم');
          }
        }

        expect(
          failures,
          isEmpty,
          reason:
              'فجوات السلسلة الكاملة (${checkedEntities.length} كياناً '
              'مدفوعاً):\n${failures.join('\n')}',
        );
      },
    );
  });

  // ═════════════════════════════════════════════════════════════
  //  المجموعة 4: الحقول الخاصة لكل جدول — موجودة على السلك وقيمها
  //  وصلت كما هي (عينات جوهرية من عقد كل جدول).
  // ═════════════════════════════════════════════════════════════
  group('الحقول الخاصة لكل جدول عبر السلسلة', () {
    test('عينات الحقول الخاصة للجداول الجوهرية', () async {
      final byEntity = await _produceAll();
      Map<String, dynamic> dataOf(String entity, {int index = 0}) {
        final list = byEntity[entity]!;
        // نفس نقطة الدفع: الحمولة تمر عبر PayloadNormalizer قبل الـ worker
        return PayloadNormalizer.normalize(
          jsonDecode(list[index].payload) as Map<String, dynamic>,
        );
      }

      final failures = <String>[];

      // bookings: بيانات النزيل والتواريخ
      final bookings = dataOf('bookings');
      for (final k in ['guest_name', 'room_number', 'checkin_date', 'status']) {
        if (!bookings.containsKey(k) || bookings[k] == null) {
          failures.add('bookings: حقل خاص $k مفقود من الحمولة');
        }
      }

      // payments: المستلم والجلسة (خيارات — تُرفع إن وُجدت) + المبلغ
      final payments = dataOf('payments');
      for (final k in ['amount', 'payment_method', 'revenue_type']) {
        if (!payments.containsKey(k)) {
          failures.add('payments: حقل خاص $k مفقود من الحمولة');
        }
      }
      for (final k in [
        'received_by_user_id',
        'received_by_name',
        'received_session_uuid',
      ]) {
        if (!_loadSchema()['payments']!.containsKey(k)) {
          failures.add('payments: عمود $k غير موجود في D1 أصلاً');
        }
      }

      // expenses: النوع والموظف والتدفق النقدي
      final expenses = dataOf('expenses');
      if (expenses['expense_type'] == null) {
        failures.add('expenses: expense_type مفقود');
      }
      for (final k in ['hotel_day_key', 'cash_flow_uuid', 'employee_uuid']) {
        if (!_loadSchema()['expenses']!.containsKey(k)) {
          failures.add('expenses: عمود $k غير موجود في D1 أصلاً');
        }
      }

      // debts: المبلغ والسداد والحجز
      final debts = dataOf('debts');
      for (final k in [
        'total_amount',
        'paid_amount',
        'remaining_amount',
        'booking_local_id',
      ]) {
        if (!debts.containsKey(k)) {
          failures.add('debts: حقل خاص $k مفقود من الحمولة');
        }
      }
      if (!_loadSchema()['debts']!.containsKey('booking_uuid_cache')) {
        failures.add('debts: عمود booking_uuid_cache غير موجود في D1');
      }

      // cash_transactions: نوع الحركة والمبلغ
      final cash = dataOf('cash_transactions');
      for (final k in ['transaction_type', 'amount', 'transaction_time']) {
        if (!cash.containsKey(k)) {
          failures.add('cash_transactions: حقل خاص $k مفقود');
        }
      }

      // salary_withdrawals: الموظف (معرف + uuid) والمبلغ
      final wd = dataOf('salary_withdrawals');
      for (final k in ['employee_id', 'amount']) {
        if (!wd.containsKey(k)) {
          failures.add('salary_withdrawals: حقل خاص $k مفقود');
        }
      }
      if (!_loadSchema()['salary_withdrawals']!.containsKey('employee_uuid')) {
        failures.add('salary_withdrawals: عمود employee_uuid غير موجود في D1');
      }

      // booking_price_adjustments: التعديل واليوم الفعلي
      final bpa = dataOf('booking_price_adjustments');
      for (final k in [
        'booking_local_uuid',
        'adjustment_type',
        'amount',
        'effective_hotel_day',
      ]) {
        if (!bpa.containsKey(k)) {
          failures.add('booking_price_adjustments: حقل خاص $k مفقود');
        }
      }

      // price_adjustments: القيم السابقة/الجديدة واليوم الفندقي
      final pa = dataOf('price_adjustments');
      for (final k in ['previous_value', 'new_value', 'hotel_day_key']) {
        if (!pa.containsKey(k)) {
          failures.add('price_adjustments: حقل خاص $k مفقود');
        }
      }

      // salary_carry_over_logs: أعمدته الجوهرية في D1 (الصانع يعمل في
      // الإنتاج عند وجود دورة سابقة بترحيل — لا يُستدعى هنا؛ هبوط السحب
      // يُغطى بصف مُصنَّع في مجموعة السلسلة الكاملة)
      final colSchema = _loadSchema()['salary_carry_over_logs']!;
      for (final k in ['employee_id', 'amount', 'reason', 'carried_at']) {
        if (!colSchema.containsKey(k)) {
          failures.add('salary_carry_over_logs: عمود $k غير موجود في D1');
        }
      }

      // devices: الهوية والحالة
      final dev = dataOf('devices');
      for (final k in ['device_id', 'platform', 'is_active']) {
        if (!dev.containsKey(k)) {
          failures.add('devices: حقل خاص $k مفقود');
        }
      }

      // app_users: العقد الثابت
      final au = dataOf('app_users');
      for (final k in ['username', 'active', 'device_id']) {
        if (!au.containsKey(k)) {
          failures.add('app_users: حقل خاص $k مفقود');
        }
      }

      // audit_logs: نوع العملية
      final audit = dataOf('audit_logs');
      if (audit['operation_type'] == null) {
        failures.add('audit_logs: operation_type مفقود');
      }

      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });
}

/// عميل وهمي: يقبل تسجيل الجهاز فقط (200) — لإثبات أن مسار
/// registerDevice الحقيقي يكتب صفاً محلياً + عنصر outbox بلا شبكة.
class _MockDeviceRegisterClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method == 'POST' &&
        request.url.path.endsWith('/api/devices/register')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{}')),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    throw StateError(
      '_MockDeviceRegisterClient: نداء غير متوقع '
      '${request.method} ${request.url}',
    );
  }
}

/// عميل وهمي يمنع أي وصول شبكي — لإثبات أن السحب العكسي محلي خالص.
class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError(
      '_NoNetworkClient: السحب العكسي لا يجوز أن يلمس الشبكة: '
      '${request.method} ${request.url}',
    );
  }
}
