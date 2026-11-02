// test/unit/silent_loss_remaining_entities_regression_test.dart
//
// ✅ درع انحدار لتعميم عقد «لا يتقدّم المؤشر فوق الفشل» (2026-11-03) على
// الكيانات التسعة المتبقية — المرحلة الثالثة بعد:
//   - bookings_pull_checkpoint_regression_test.dart (724610cf — bookings)
//   - silent_loss_checkpoint_regression_test.dart (796ea89c — 13 كياناً)
//
// الكيانات المشمولة هنا (كانت كلها تبتلع استثناء التطبيق بتحذير فقط
// فيتقدّم مؤشر المجموعة فوق المستند الفاشل ويُفقد من كل دلتا لاحقة):
//   expenses, guest_infos, blacklist, inventory_items, shift_notes,
//   cash_transactions, price_adjustments, audit_logs, payment_voids
//
// مسار الفشل القسري في الاختبار (حتمي بلا محاكاة):
//   - للكيانات الثمانية العاملة عبر BaseRepository.upsertFromJson: مستند
//     بمعرّف فارغ ($id='') بلا localUuid في البيانات → localUuid فارغ →
//     upsertFromJson يرمي StateError (رفض اختراع هوية لسجل بعيد — عقد
//     الهوية المستقرة) — قبل أي كتابة.
//   - blacklist (تعمل بـ companion مباشر بلا adapter): deletedAt بقيمة
//     رقمية (int) بدل ISO string → TypeError في الـ cast داخل الحلقة.
//
// العقد المُختبر لكل كيان (نفس فصول الملف المرجعي):
//   الفصل A — دفعة [سليم + فاشل]: StateError تحمل اسم الكيان، السليم
//             مُطبَّق (التطبيق الجزئي محفوظ)، الفاشل غير مدرَج.
//   الفصل B — إعادة الاستدعاء بالسليم وحده: لا رمي (لا حالة عالقة
//             بعد الفشل الجزئي — الشفاء في الدورة التالية).
//
// ⚠️ قاعدة واحدة لكل الملف (قيد singleton المدير — انظر
// silent_loss_checkpoint_regression_test.dart): AppwriteSyncManager بمُنشئ
// factory يتجاهل المعاملات بعد أول إنشاء؛ إقفال القاعدة بين الاختبارات
// يترك المدير يشير لقاعدة مغلقة.

// ignore_for_file: lines_longer_than_80_chars

import 'package:appwrite/models.dart' as models;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

const int _kBaseEpochSec = 1760000000;
const String _kGoodUuid = 'good-uuid-1';
const String _kBadUuid = ''; // معرّف فارغ → رفض الهوية في upsertFromJson

models.Document _doc({
  required String id,
  required String collectionId,
  required Map<String, dynamic> data,
}) {
  return models.Document(
    $id: id,
    $sequence: 0,
    $collectionId: collectionId,
    $databaseId: 'marina',
    $createdAt: '2026-11-01T00:00:00.000Z',
    $updatedAt: '2026-11-01T12:00:00.000Z',
    $permissions: const <String>[],
    data: data,
  );
}

/// الحقول المشتركة لكل مستند سليم — جديدة كلياً محلياً (تُطبَّق حتماً).
Map<String, dynamic> _commonGood({int lastModified = _kBaseEpochSec + 10}) => {
  'localUuid': _kGoodUuid,
  'lastModified': lastModified,
  'vectorClock': '{}',
  'deviceId': 'device-A',
};

/// مستند فاشل للكيانات العاملة عبر upsertFromJson: هوية فارغة →
/// StateError('... has no local_uuid') قبل أي كتابة.
models.Document _badAdapterDoc(String collectionId) => _doc(
  id: _kBadUuid,
  collectionId: collectionId,
  data: <String, dynamic>{
    // لا localUuid عمداً — ??= doc.$id يتركه فارغاً
    'lastModified': _kBaseEpochSec + 20,
    'vectorClock': '{}',
    'deviceId': 'device-A',
  },
);

// ── Fixtures: الحقول الإلزامية (NOT NULL بلا افتراضي) لكل كيان ──

models.Document _goodExpenseDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'expenses',
  data: {
    ..._commonGood(),
    'expenseType': 'صيانة',
    'description': 'مصروف اختبار',
    'amount': 100.0,
    'date': '2026-11-01',
    'createdAt': _kBaseEpochSec,
  },
);

models.Document _goodGuestInfoDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'guest_infos',
  data: {
    ..._commonGood(),
    'roomNumber': '101',
    'guestName': 'ضيف اختبار',
    'nationality': 'يمني',
    'idNumber': '123456789',
    'createdAt': _kBaseEpochSec,
  },
);

models.Document _goodBlacklistDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'blacklist',
  data: {
    ..._commonGood(),
    'name': 'اسم اختبار',
    'nationality': 'يمني',
    'nationalId': '987654321',
    'reason': 'سبب اختبار',
    'createdAt': '2026-11-01T08:00:00.000Z',
    'updatedAt': '2026-11-01T08:00:00.000Z',
  },
);

/// مستند فاشل للقائمة السوداء: deletedAt رقمي → TypeError في الـ cast.
models.Document _badBlacklistDoc() => _doc(
  id: 'blacklist-bad',
  collectionId: 'blacklist',
  data: {
    'localUuid': 'blacklist-bad-uuid',
    'name': 'اسم فاشل',
    'createdAt': '2026-11-01T08:00:00.000Z',
    'lastModified': _kBaseEpochSec + 20,
    'deletedAt': 12345, // int بدل ISO string — يُسقط الـ cast
  },
);

models.Document _goodInventoryItemDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'inventory_items',
  data: {
    ..._commonGood(),
    'name': 'عنصر اختبار',
    'quantity': 5,
    'createdAt': _kBaseEpochSec,
  },
);

models.Document _goodShiftNoteDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'shift_notes',
  data: {
    ..._commonGood(),
    'title': 'عنوان اختبار',
    'content': 'محتوى اختبار',
    'createdAt': _kBaseEpochSec,
  },
);

models.Document _goodCashTransactionDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'cash_transactions',
  data: {
    ..._commonGood(),
    'transactionType': 'income',
    'amount': 500.0,
    'transactionTime': '2026-11-01T10:00:00Z',
    'createdAt': _kBaseEpochSec,
  },
);

models.Document _goodPriceAdjustmentDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'price_adjustments',
  data: {
    ..._commonGood(),
    'targetType': 'room',
    'targetUuid': 'room-uuid-not-exist',
    'adjustmentType': 'increase',
    'previousValue': 100.0,
    'newValue': 120.0,
    'effectiveDate': '2026-11-01',
    'appliedBy': 'admin',
    'createdAt': _kBaseEpochSec,
  },
);

models.Document _goodAuditLogDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'audit_logs',
  data: {
    ..._commonGood(),
    'operationType': 'create',
    'entityType': 'booking',
    'entityUuid': 'booking-uuid-1',
    'performedBy': 'admin',
    'hotelDayKey': '2026-11-01',
    'timestamp': _kBaseEpochSec,
    'timestampIso': '2026-11-01T10:00:00.000Z',
  },
);

models.Document _goodPaymentVoidDoc() => _doc(
  id: _kGoodUuid,
  collectionId: 'payment_voids',
  data: {
    ..._commonGood(),
    'originalPaymentUuid': 'pay-uuid-1',
    'originalPaymentId': 1,
    'bookingUuid': 'booking-uuid-1',
    'voidedAmount': 100,
    'voidReason': 'سبب اختبار',
    'voidedBy': 'admin',
    'voidedAt': _kBaseEpochSec,
    'voidedAtIso': '2026-11-01T10:00:00.000Z',
    'hotelDayKey': '2026-11-01',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AppwriteSyncManager manager;

  // ⚠️ قاعدة واحدة للملف كله (قيد singleton المدير — انظر الترويسة).
  setUpAll(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AdapterRegistry.initialize(db);
    manager = AppwriteSyncManager(
      appwriteService: AppwriteService(),
      database: db,
    );
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    // تنظيف شامل بين الاختبارات — الأبناء قبل الآباء احترازياً لقيود FK.
    await db.delete(db.inventoryTransactions).go();
    await db.delete(db.inventoryItems).go();
    await db.delete(db.payments).go();
    await db.delete(db.cashTransactions).go();
    await db.delete(db.expenses).go();
    await db.delete(db.guestInfos).go();
    await db.delete(db.blacklist).go();
    await db.delete(db.shiftNotes).go();
    await db.delete(db.priceAdjustments).go();
    await db.delete(db.auditLogs).go();
    await db.delete(db.paymentVoids).go();
    await db.delete(db.outbox).go();
  });

  /// العقد الكامل لكيان واحد: الفصل A (رمي + تطبيق جزئي) ثم الفصل B (شفاء).
  Future<void> assertContract({
    required String entityName,
    required Future<void> Function(List<models.Document>) syncForTesting,
    required models.Document goodDoc,
    required models.Document badDoc,
    required Future<bool> Function() goodRowExists,
  }) async {
    // ═══ الفصل A — دفعة مختلطة: الفاشل يُفشل المهمة والسليم يُطبَّق ═══
    // رسالة الفشل يجب أن تحمل اسم الكيان كي يسجّله المحرك في
    // failedCollections ولا يثبّت المؤشر فوق المستند الفاشل.
    await expectLater(
      syncForTesting([goodDoc, badDoc]),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', contains(entityName))
            .having(
              (e) => e.message,
              'message',
              contains('checkpoint must not advance'),
            ),
      ),
      reason:
          'قبل الإصلاح كان الاستثناء يُبتلع بتحذير فقط فيتقدّم مؤشر '
          '$entityName فوق المستند الفاشل ويُفقد من كل دلتا لاحقة '
          'بينما تُظهر الواجهة نجاحاً أخضر زائفاً',
    );

    // التطبيق الجزئي محفوظ: السليم وصل رغم فشل زميله.
    expect(
      await goodRowExists(),
      isTrue,
      reason: 'التطبيق الجزئي محفوظ: المستند السليم وصل رغم فشل زميله',
    );

    // ═══ الفصل B — الشفاء: إعادة الاستدعاء بالسليم وحده لا ترمي ═══
    await expectLater(
      syncForTesting([goodDoc]),
      completes,
      reason:
          'لا حالة عالقة بعد الفشل الجزئي — الدورة التالية تنجح '
          'والمؤشر يتقدم فوق ما طُبِّق فعلاً',
    );
  }

  test(
    'درع فقدان expenses الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'expenses',
      syncForTesting: (docs) => manager.syncExpensesForTesting(docs),
      goodDoc: _goodExpenseDoc(),
      badDoc: _badAdapterDoc('expenses'),
      goodRowExists: () async =>
          (await (db.select(db.expenses)
                    ..where((e) => e.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان guest_infos الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'guest_infos',
      syncForTesting: (docs) => manager.syncGuestInfosForTesting(docs),
      goodDoc: _goodGuestInfoDoc(),
      badDoc: _badAdapterDoc('guest_infos'),
      goodRowExists: () async =>
          (await (db.select(db.guestInfos)
                    ..where((g) => g.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان blacklist الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'blacklist',
      syncForTesting: (docs) => manager.syncBlacklistForTesting(docs),
      goodDoc: _goodBlacklistDoc(),
      badDoc: _badBlacklistDoc(),
      goodRowExists: () async =>
          (await (db.select(db.blacklist)
                    ..where((b) => b.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان inventory_items الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'inventory_items',
      syncForTesting: (docs) => manager.syncInventoryItemsForTesting(docs),
      goodDoc: _goodInventoryItemDoc(),
      badDoc: _badAdapterDoc('inventory_items'),
      goodRowExists: () async =>
          (await (db.select(db.inventoryItems)
                    ..where((i) => i.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان shift_notes الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'shift_notes',
      syncForTesting: (docs) => manager.syncShiftNotesForTesting(docs),
      goodDoc: _goodShiftNoteDoc(),
      badDoc: _badAdapterDoc('shift_notes'),
      goodRowExists: () async =>
          (await (db.select(db.shiftNotes)
                    ..where((s) => s.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان cash_transactions الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'cash_transactions',
      syncForTesting: (docs) => manager.syncCashTransactionsForTesting(docs),
      goodDoc: _goodCashTransactionDoc(),
      badDoc: _badAdapterDoc('cash_transactions'),
      goodRowExists: () async =>
          (await (db.select(db.cashTransactions)
                    ..where((c) => c.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان price_adjustments الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'price_adjustments',
      syncForTesting: (docs) => manager.syncPriceAdjustmentsForTesting(docs),
      goodDoc: _goodPriceAdjustmentDoc(),
      badDoc: _badAdapterDoc('price_adjustments'),
      goodRowExists: () async =>
          (await (db.select(db.priceAdjustments)
                    ..where((p) => p.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان audit_logs الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'audit_logs',
      syncForTesting: (docs) => manager.syncAuditLogsForTesting(docs),
      goodDoc: _goodAuditLogDoc(),
      badDoc: _badAdapterDoc('audit_logs'),
      goodRowExists: () async =>
          (await (db.select(db.auditLogs)
                    ..where((a) => a.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );

  test(
    'درع فقدان payment_voids الصامت: مستند فاشل يرمي StateError والسليم يُطبَّق',
    () => assertContract(
      entityName: 'payment_voids',
      syncForTesting: (docs) => manager.syncPaymentVoidsForTesting(docs),
      goodDoc: _goodPaymentVoidDoc(),
      badDoc: _badAdapterDoc('payment_voids'),
      goodRowExists: () async =>
          (await (db.select(db.paymentVoids)
                    ..where((v) => v.localUuid.equals(_kGoodUuid))
                    ..limit(1))
                  .get())
              .isNotEmpty,
    ),
  );
}
