// test/unit/wave6_debts_fields_test.dart
//
// ✅ Wave 6 (2026-08-12) — debts fields: bookingUuidCache, debtorName, amount, date
//
// يثبت هذا الملف أن:
// 1. Push payload لـ debts يحتوي على bookingUuidCache, debtorName, amount, date
// 2. Pull/apply path يحفظ هذه الحقول محلياً
// 3. Migration 58 أضاف الأعمدة لجدول debts
// 4. filterPayload يسمح بهذه الحقول (تم التحقق منه من الكود)
// 5. Drive sync (toJson) يرسل هذه الحقول أيضاً
// 6. القيم null لا تُرسل (سلوك putIfStringNotEmpty)

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/debts_adapter.dart';
import 'package:marina_hotel_mobile/services/adapters/id_resolver.dart';
import 'package:marina_hotel_mobile/services/adapters/resolve_result.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/payload_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PayloadMapper payloadMapper;
  late DebtsAdapter debtsAdapter;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    payloadMapper = const PayloadMapper();
    debtsAdapter = DebtsAdapter(_StubResolver());
  });

  tearDown(() async {
    await db.close();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 1: Push payload يحتوي على الحقول الأربعة
  // ═══════════════════════════════════════════════════════════════════════
  group('Push: debtToRemote يحتوي على الحقول الأربعة', () {
    test('1a. payload يحتوي على bookingUuidCache', () async {
      final debt = await _insertDebt(db, bookingUuidCache: 'booking-uuid-123');
      final payload = payloadMapper.debtToRemote(debt);
      expect(payload['bookingUuidCache'], 'booking-uuid-123');
    });

    test('1b. payload يحتوي على debtorName', () async {
      final debt = await _insertDebt(db, debtorName: 'Ahmed Ali');
      final payload = payloadMapper.debtToRemote(debt);
      expect(payload['debtorName'], 'Ahmed Ali');
    });

    test('1c. payload يحتوي على amount', () async {
      final debt = await _insertDebt(db, amount: 1500.50);
      final payload = payloadMapper.debtToRemote(debt);
      expect(payload['amount'], 1500.50);
    });

    test('1d. payload يحتوي على date', () async {
      final debt = await _insertDebt(db, date: '2026-08-12');
      final payload = payloadMapper.debtToRemote(debt);
      expect(payload['date'], '2026-08-12');
    });

    test(
      '1e. payload لا يحتوي على amount عندما null (سلوك putIfNotNull)',
      () async {
        final debt = await _insertDebt(db, amount: null);
        final payload = payloadMapper.debtToRemote(debt);
        expect(
          payload.containsKey('amount'),
          isFalse,
          reason: 'amount null يجب ألا يُرسل في الـ payload',
        );
      },
    );

    test('1f. payload لا يحتوي على bookingUuidCache عندما null/فارغ', () async {
      final debt = await _insertDebt(db, bookingUuidCache: null);
      final payload = payloadMapper.debtToRemote(debt);
      // putIfStringNotEmpty لا يرسل القيم الفارغة
      expect(payload.containsKey('bookingUuidCache'), isFalse);
    });

    test('1g. payload يحتوي على كل الحقول الأربعة معاً', () async {
      final debt = await _insertDebt(
        db,
        bookingUuidCache: 'booking-uuid-all',
        debtorName: 'Salem',
        amount: 750.25,
        date: '2026-08-12T10:30',
      );
      final payload = payloadMapper.debtToRemote(debt);
      expect(payload['bookingUuidCache'], 'booking-uuid-all');
      expect(payload['debtorName'], 'Salem');
      expect(payload['amount'], 750.25);
      expect(payload['date'], '2026-08-12T10:30');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 2: Pull/apply path يحفظ الحقول محلياً
  // ═══════════════════════════════════════════════════════════════════════
  group('Pull: DebtsAdapter.fromJson يحفظ الحقول محلياً', () {
    test('2a. fromJson يقرأ bookingUuidCache ويحفظه', () async {
      final json = {
        'localUuid': 'debt-1',
        'guestName': 'Guest 1',
        'checkinDate': '2026-08-01',
        'totalAmount': 1000.0,
        'paidAmount': 500.0,
        'bookingUuidCache': 'booking-uuid-789',
      };
      final companion = await debtsAdapter.resolveAndFromJson(
        db,
        json,
        src: Source.appwrite,
      );
      await db.into(db.debts).insert(companion);

      final saved = await (db.select(
        db.debts,
      )..where((t) => t.localUuid.equals('debt-1'))).getSingle();
      expect(saved.bookingUuidCache, 'booking-uuid-789');
    });

    test('2b. fromJson يقرأ debtorName ويحفظه', () async {
      final json = {
        'localUuid': 'debt-2',
        'guestName': 'Guest 2',
        'checkinDate': '2026-08-01',
        'totalAmount': 1000.0,
        'paidAmount': 500.0,
        'debtorName': 'Mohammed Saleh',
      };
      final companion = await debtsAdapter.resolveAndFromJson(
        db,
        json,
        src: Source.appwrite,
      );
      await db.into(db.debts).insert(companion);

      final saved = await (db.select(
        db.debts,
      )..where((t) => t.localUuid.equals('debt-2'))).getSingle();
      expect(saved.debtorName, 'Mohammed Saleh');
    });

    test('2c. fromJson يقرأ amount ويحفظه', () async {
      final json = {
        'localUuid': 'debt-3',
        'guestName': 'Guest 3',
        'checkinDate': '2026-08-01',
        'totalAmount': 1000.0,
        'paidAmount': 500.0,
        'amount': 2500.75,
      };
      final companion = await debtsAdapter.resolveAndFromJson(
        db,
        json,
        src: Source.appwrite,
      );
      await db.into(db.debts).insert(companion);

      final saved = await (db.select(
        db.debts,
      )..where((t) => t.localUuid.equals('debt-3'))).getSingle();
      expect(saved.amount, 2500.75);
    });

    test('2d. fromJson يقرأ date ويحفظه', () async {
      final json = {
        'localUuid': 'debt-4',
        'guestName': 'Guest 4',
        'checkinDate': '2026-08-01',
        'totalAmount': 1000.0,
        'paidAmount': 500.0,
        'date': '2026-08-12',
      };
      final companion = await debtsAdapter.resolveAndFromJson(
        db,
        json,
        src: Source.appwrite,
      );
      await db.into(db.debts).insert(companion);

      final saved = await (db.select(
        db.debts,
      )..where((t) => t.localUuid.equals('debt-4'))).getSingle();
      expect(saved.date, '2026-08-12');
    });

    test(
      '2e. fromJson يقرأ snake_case variants (booking_uuid_cache, debtor_name)',
      () async {
        // Drive sync يستخدم snake_case
        final json = {
          'local_uuid': 'debt-5',
          'guest_name': 'Guest 5',
          'checkin_date': '2026-08-01',
          'total_amount': 1000.0,
          'paid_amount': 500.0,
          'booking_uuid_cache': 'booking-snake',
          'debtor_name': 'Snake Debtor',
          'amount': 300.0,
          'date': '2026-08-13',
        };
        final companion = await debtsAdapter.resolveAndFromJson(
          db,
          json,
          src: Source.drive,
        );
        await db.into(db.debts).insert(companion);

        final saved = await (db.select(
          db.debts,
        )..where((t) => t.localUuid.equals('debt-5'))).getSingle();
        expect(saved.bookingUuidCache, 'booking-snake');
        expect(saved.debtorName, 'Snake Debtor');
        expect(saved.amount, 300.0);
        expect(saved.date, '2026-08-13');
      },
    );

    test('2f. fromJson يتعامل مع القيم المفقودة (null بأمان)', () async {
      final json = {
        'localUuid': 'debt-6',
        'guestName': 'Guest 6',
        'checkinDate': '2026-08-01',
        'totalAmount': 1000.0,
        'paidAmount': 500.0,
        // لا bookingUuidCache, debtorName, amount, date
      };
      final companion = await debtsAdapter.resolveAndFromJson(
        db,
        json,
        src: Source.appwrite,
      );
      await db.into(db.debts).insert(companion);

      final saved = await (db.select(
        db.debts,
      )..where((t) => t.localUuid.equals('debt-6'))).getSingle();
      expect(saved.bookingUuidCache, isNull);
      expect(saved.debtorName, isNull);
      expect(saved.amount, isNull);
      expect(saved.date, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 3: Migration 58 — أعمدة debts الجديدة موجودة
  // ═══════════════════════════════════════════════════════════════════════
  group('Migration 58: أعمدة debts الجديدة', () {
    test('3a. عمود booking_uuid_cache موجود في debts', () async {
      final result = await db
          .customSelect('PRAGMA table_info(debts)', readsFrom: {db.debts})
          .get();
      final columnNames = result
          .map((row) => row.read<String>('name'))
          .toList();
      expect(columnNames, contains('booking_uuid_cache'));
    });

    test('3b. عمود debtor_name موجود في debts', () async {
      final result = await db
          .customSelect('PRAGMA table_info(debts)', readsFrom: {db.debts})
          .get();
      final columnNames = result
          .map((row) => row.read<String>('name'))
          .toList();
      expect(columnNames, contains('debtor_name'));
    });

    test('3c. عمود amount موجود في debts', () async {
      final result = await db
          .customSelect('PRAGMA table_info(debts)', readsFrom: {db.debts})
          .get();
      final columnNames = result
          .map((row) => row.read<String>('name'))
          .toList();
      expect(columnNames, contains('amount'));
    });

    test('3d. عمود date موجود في debts', () async {
      final result = await db
          .customSelect('PRAGMA table_info(debts)', readsFrom: {db.debts})
          .get();
      final columnNames = result
          .map((row) => row.read<String>('name'))
          .toList();
      expect(columnNames, contains('date'));
    });

    test('3e. أحدث schemaVersion = 60', () {
      expect(db.schemaVersion, 60);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 4: filterPayload يسمح بالحقول الأربعة
  // ═══════════════════════════════════════════════════════════════════════
  group('filterPayload: debts يسمح بالحقول الأربعة', () {
    test('4a. filterPayload يحتفظ بـ bookingUuidCache', () {
      final payload = {
        'localUuid': 'x',
        'bookingUuidCache': 'booking-1',
        'unknownField': 'should-be-removed',
      };
      final filtered = AppwriteSyncUtils.filterPayloadForCollection(
        'debts',
        payload,
      );
      expect(filtered.containsKey('bookingUuidCache'), isTrue);
      expect(filtered['bookingUuidCache'], 'booking-1');
      expect(
        filtered.containsKey('unknownField'),
        isFalse,
        reason: 'الحقول غير المدرجة يجب أن تُزال',
      );
    });

    test('4b. filterPayload يحتفظ بـ debtorName', () {
      final filtered = AppwriteSyncUtils.filterPayloadForCollection('debts', {
        'debtorName': 'X',
      });
      expect(filtered.containsKey('debtorName'), isTrue);
    });

    test('4c. filterPayload يحتفظ بـ amount', () {
      final filtered = AppwriteSyncUtils.filterPayloadForCollection('debts', {
        'amount': 100.0,
      });
      expect(filtered.containsKey('amount'), isTrue);
    });

    test('4d. filterPayload يحتفظ بـ date', () {
      final filtered = AppwriteSyncUtils.filterPayloadForCollection('debts', {
        'date': '2026-08-12',
      });
      expect(filtered.containsKey('date'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 5: Drive sync (toJson) يرسل الحقول الأربعة
  // ═══════════════════════════════════════════════════════════════════════
  group('Drive sync: DebtsAdapter.toJson يرسل الحقول الأربعة', () {
    test('5a. toJson (drive) يحتوي على booking_uuid_cache', () async {
      final debt = await _insertDebt(db, bookingUuidCache: 'booking-drive-1');
      final json = debtsAdapter.toJson(debt, src: Source.drive);
      expect(json['booking_uuid_cache'], 'booking-drive-1');
    });

    test('5b. toJson (drive) يحتوي على debtor_name', () async {
      final debt = await _insertDebt(db, debtorName: 'Drive Debtor');
      final json = debtsAdapter.toJson(debt, src: Source.drive);
      expect(json['debtor_name'], 'Drive Debtor');
    });

    test('5c. toJson (drive) يحتوي على amount', () async {
      final debt = await _insertDebt(db, amount: 999.99);
      final json = debtsAdapter.toJson(debt, src: Source.drive);
      expect(json['amount'], 999.99);
    });

    test('5d. toJson (drive) يحتوي على date', () async {
      final debt = await _insertDebt(db, date: '2026-08-15');
      final json = debtsAdapter.toJson(debt, src: Source.drive);
      expect(json['date'], '2026-08-15');
    });

    test('5e. toJson (appwrite) يحتوي على الحقول بـ camelCase', () async {
      final debt = await _insertDebt(
        db,
        bookingUuidCache: 'b-1',
        debtorName: 'd-1',
        amount: 100.0,
        date: '2026-01-01',
      );
      final json = debtsAdapter.toJson(debt, src: Source.appwrite);
      expect(json['bookingUuidCache'], 'b-1');
      expect(json['debtorName'], 'd-1');
      expect(json['amount'], 100.0);
      expect(json['date'], '2026-01-01');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // المجموعة 6: round-trip — push ثم pull يحافظ على الحقول
  // ═══════════════════════════════════════════════════════════════════════
  group('Round-trip: push → pull يحافظ على الحقول', () {
    test('6a. push payload يمر عبر filterPayload بدون فقدان', () async {
      final debt = await _insertDebt(
        db,
        bookingUuidCache: 'rt-1',
        debtorName: 'RT Debtor',
        amount: 500.0,
        date: '2026-08-20',
      );
      // 1. push payload (debtToRemote + sanitizePayload)
      final payload = payloadMapper.debtToRemote(debt);
      // 2. filterPayload يحتفظ بالحقول المسموح بها فقط
      // (debtToRemote يستدعي sanitizePayload داخلياً، لكن نختبر مرة أخرى)
      final filtered = AppwriteSyncUtils.filterPayloadForCollection(
        'debts',
        payload,
      );
      // 3. محاكاة pull على جهاز ثانٍ/قاعدة خالية. لا يستخدم Drift
      // localUuid كمفتاح conflict، لذلك insertOnConflictUpdate لا يصلح
      // لمحاكاة upsert عبر UUID في هذا الاختبار.
      await (db.delete(db.debts)..where((t) => t.id.equals(debt.id))).go();
      final companion = await debtsAdapter.resolveAndFromJson(
        db,
        filtered,
        src: Source.appwrite,
      );
      await db.into(db.debts).insert(companion);

      // 4. التحقق أن القيم محفوظة بعد round-trip
      final saved = await (db.select(
        db.debts,
      )..where((t) => t.localUuid.equals(debt.localUuid))).getSingle();
      expect(saved.bookingUuidCache, 'rt-1');
      expect(saved.debtorName, 'RT Debtor');
      expect(saved.amount, 500.0);
      expect(saved.date, '2026-08-20');
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════

extension on DebtsAdapter {
  /// Helper: يجمع resolveRefs + fromJson في خطوة واحدة للاختبار.
  Future<DebtsCompanion> resolveAndFromJson(
    AppDatabase db,
    Map<String, dynamic> json, {
    required Source src,
  }) async {
    final refs = await resolveRefs(db, json, src: src);
    return fromJson(json, src: src, refs: refs);
  }
}

/// Stub resolver — لا يحل FK، فقط يُرجع null.
class _StubResolver implements IdResolver {
  @override
  Future<int?> resolveBooking({
    int? localId,
    int? serverId,
    String? uuid,
    bool fromRemote = false,
  }) async => localId;

  @override
  Future<int?> resolveEmployee({
    int? localId,
    String? uuid,
    int? serverId,
    int? employeeId,
  }) async => localId;

  @override
  Future<int?> resolveSalaryCycle({
    int? localId,
    int? serverId,
    String? uuid,
  }) async => localId;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Helper: إنشاء Debt في DB بحقول إضافية.
Future<Debt> _insertDebt(
  AppDatabase db, {
  String? bookingUuidCache,
  String? debtorName,
  double? amount,
  String? date,
}) async {
  final uuid = 'debt-${DateTime.now().microsecondsSinceEpoch}';
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await db
      .into(db.debts)
      .insert(
        DebtsCompanion.insert(
          localUuid: uuid,
          guestName: 'Test Guest',
          checkinDate: '2026-08-01',
          checkoutDate: '2026-08-10',
          totalAmount: 1000.0,
          paidAmount: 500.0,
          remainingAmount: 500.0,
          paymentDate: '2026-08-10',
          isSettled: const drift.Value(0),
          createdAt: now,
          updatedAt: now,
          lastModified: now,
          syncTimestamp: drift.Value(now),
          // ✅ حقول Wave 6 الجديدة
          bookingUuidCache: bookingUuidCache != null
              ? drift.Value(bookingUuidCache)
              : const drift.Value.absent(),
          debtorName: debtorName != null
              ? drift.Value(debtorName)
              : const drift.Value.absent(),
          amount: amount != null
              ? drift.Value(amount)
              : const drift.Value.absent(),
          date: date != null ? drift.Value(date) : const drift.Value.absent(),
        ),
      );
  return (db.select(
    db.debts,
  )..where((t) => t.localUuid.equals(uuid))).getSingle();
}
