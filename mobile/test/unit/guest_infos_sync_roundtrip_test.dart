// test/unit/guest_infos_sync_roundtrip_test.dart
//
// ✅ اختبار تحقق شامل لمزامنة guest_infos في الاتجاهين:
//
//  الرفع (Push):
//    Repository.create/update/delete → صف محلي + عنصر outbox
//    → guestInfoToRemote → filterPayloadForCollection (لا يُسقط أي حقل)
//    → الحذف الناعم يرفع tombstone (deletedAt) إلى السحابة
//
//  السحب (Pull):
//    مستند Appwrite → BaseRepository.upsertFromJson(Source.appwrite)
//    → صف محلي كامل الحقول origin='server'، بلا تكرار، مع تحديث في المكان
//    → tombstone بعيد يُطبَّق محلياً ويُستبعد من listAll
//
//  رحلة ذهاب وعودة (جهازان):
//    payload الجهاز A → سحب الجهاز B → رفع B → الحقول التسعة مستقرة بلا انحراف.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/guest_infos_repository.dart';
import 'package:marina_hotel_mobile/services/sync/payload_mapper.dart';

import '../helpers/test_database.dart';

/// الحقول التسعة التي يدخلها المستخدم في شاشة «معلومات النزلاء».
const List<String> kGuestDataFields = [
  'roomNumber',
  'guestName',
  'nationality',
  'idNumber',
  'idType',
  'issueDate',
  'issuePlace',
  'governorate',
  'notes',
];

const int kBaseEpoch = 1760000000;

void main() {
  late AppDatabase db;
  late GuestInfosRepository repo;
  late AdapterRegistry registry;
  late PayloadMapper mapper;

  setUp(() {
    db = TestDatabase.create();
    repo = GuestInfosRepository(db);
    registry = AdapterRegistry(db);
    mapper = const PayloadMapper();
  });

  tearDown(() async {
    await db.close();
  });

  Future<GuestInfo> findByUuid(String uuid) => (db.select(
    db.guestInfos,
  )..where((t) => t.localUuid.equals(uuid))).getSingle();

  Future<List<OutboxData>> outboxFor(String uuid) =>
      (db.select(db.outbox)..where(
            (t) => t.entity.equals('guest_infos') & t.localUuid.equals(uuid),
          ))
          .get();

  Map<String, dynamic> outboxPayload(OutboxData entry) =>
      Map<String, dynamic>.from(jsonDecode(entry.payload) as Map);

  /// مستند بعيد بالشكل الذي يُخزَّن به في Appwrite (ناتج guestInfoToRemote
  /// بعد filterPayloadForCollection على الجهاز المرسل).
  Map<String, dynamic> remoteDoc({
    required String uuid,
    int lastModified = kBaseEpoch,
    int? deletedAt,
    String room = '101',
    String name = 'أحمد محمد صالح',
    String nationality = 'يمني',
    String idNumber = '0123456789',
    String notes = 'ملاحظة أصلية',
    String governorate = 'عدن',
    int version = 1,
  }) {
    return {
      'localUuid': uuid,
      'createdAt': kBaseEpoch - 100,
      'updatedAt': lastModified,
      'lastModified': lastModified,
      'lastModifiedEpoch': lastModified,
      'createdAtEpoch': kBaseEpoch - 100,
      'version': version,
      'origin': 'server',
      'sync_origin': 'server',
      'syncTimestamp': lastModified + 5,
      'vectorClock': '{"deviceA": 2}',
      'deviceId': 'deviceA',
      'roomNumber': room,
      'guestName': name,
      'nationality': nationality,
      'idNumber': idNumber,
      'idType': 'بطاقة شخصية',
      'issueDate': '2026-01-15',
      'issuePlace': 'صنعاء',
      'governorate': governorate,
      'notes': notes,
      'createdAtIso': '2026-01-01T00:00:00.000Z',
      'updatedAtIso': '2026-01-02T00:00:00.000Z',
      if (deletedAt != null) 'deletedAt': deletedAt,
      if (deletedAt != null) 'deletedAtIso': '2026-01-03T00:00:00.000Z',
    };
  }

  // ══════════════════════════════════════════════════════════════════════
  // الرفع (Push)
  // ══════════════════════════════════════════════════════════════════════
  group('رفع guest_infos (Push)', () {
    test('create يكتب صفّاً محلياً + عنصر outbox بكل الحقول', () async {
      await repo.create(
        roomNumber: '202',
        guestName: 'سالم ناصر',
        nationality: 'يمني',
        idNumber: '9988776655',
        idType: 'جواز سفر',
        issueDate: '2025-06-01',
        issuePlace: 'عدن',
        governorate: 'عدن',
        notes: 'وصول متأخر',
      );

      final row = await (db.select(
        db.guestInfos,
      )..where((t) => t.guestName.equals('سالم ناصر'))).getSingle();
      expect(row.localUuid, isNotEmpty);
      expect(row.roomNumber, '202');
      expect(row.deletedAt, isNull);
      expect(row.version, 1);

      final entries = await outboxFor(row.localUuid);
      expect(entries, hasLength(1));
      expect(entries.single.op, 'create');
      expect(entries.single.source, 'local');
      expect(entries.single.processingStatus, 'pending');

      final payload = outboxPayload(entries.single);
      for (final f in kGuestDataFields) {
        expect(payload, contains(f), reason: 'outbox payload يفتقد $f');
      }
      expect(payload['roomNumber'], '202');
      expect(payload['idType'], 'جواز سفر');
      expect(payload['notes'], 'وصول متأخر');
    });

    test('guestInfoToRemote يحتوي كل الحقول ولا تُصفّيها الـ schema', () async {
      await repo.create(
        roomNumber: '303',
        guestName: 'فهد علي',
        nationality: 'سعودي',
        idNumber: '1122334455',
        idType: 'بطاقة شخصية',
        issueDate: '2024-03-10',
        issuePlace: 'الرياض',
        governorate: 'الرياض',
        notes: 'إقامة قصيرة',
      );
      final row = await (db.select(
        db.guestInfos,
      )..where((t) => t.guestName.equals('فهد علي'))).getSingle();

      final payload = mapper.guestInfoToRemote(row);
      for (final f in kGuestDataFields) {
        expect(payload, contains(f), reason: 'guestInfoToRemote يفتقد $f');
      }

      // ⚠️ الفحص الحرج: التصفية قبل الإرسال يجب ألا تُسقط أي حقل بيانات
      final filtered = AppwriteSyncUtils.filterPayloadForCollection(
        'guest_infos',
        payload,
      );
      for (final f in kGuestDataFields) {
        expect(filtered[f], payload[f], reason: 'التصفية أسقطت/غيّرت $f');
      }
      // لا مفاتيح خارج مخطط Appwrite (يمنع خطأ Unknown attribute)
      for (final k in filtered.keys) {
        expect(
          k == 'idempotencyKey' || k.startsWith('\$') ? false : true,
          isTrue,
        );
      }
      expect(
        filtered.containsKey('id'),
        isFalse,
        reason: 'حقل id المحلي لا يُرفع',
      );
    });

    test('update يرفع version ويُوحِّد عناصر outbox لنفس السجل', () async {
      await repo.create(
        roomNumber: '404',
        guestName: 'ماجد حسن',
        nationality: 'يمني',
        idNumber: '5544332211',
        notes: 'قبل التعديل',
      );
      final created = await (db.select(
        db.guestInfos,
      )..where((t) => t.guestName.equals('ماجد حسن'))).getSingle();

      await repo.update(
        created.id,
        roomNumber: '405',
        guestName: 'ماجد حسن',
        nationality: 'يمني',
        idNumber: '5544332211',
        notes: 'بعد التعديل',
      );

      final updated = await findByUuid(created.localUuid);
      expect(updated.version, created.version + 1);
      expect(updated.lastModified, greaterThanOrEqualTo(created.lastModified));

      final entries = await outboxFor(created.localUuid);
      // coalescing: عنصر واحد pending فقط بعد create ثم update
      final pending = entries
          .where((e) => e.processingStatus == 'pending')
          .toList();
      expect(pending, hasLength(1));
      expect(pending.single.op, 'update');
      expect(outboxPayload(pending.single)['roomNumber'], '405');
      expect(outboxPayload(pending.single)['notes'], 'بعد التعديل');
    });

    test('الحذف الناعم يرفع tombstone (deletedAt) لا حذفاً صامتاً', () async {
      await repo.create(
        roomNumber: '505',
        guestName: 'وليد عبده',
        nationality: 'يمني',
        idNumber: '6677889900',
        notes: 'سيُحذف',
      );
      final row = await (db.select(
        db.guestInfos,
      )..where((t) => t.guestName.equals('وليد عبده'))).getSingle();

      await repo.delete(row.id);

      final deleted = await findByUuid(row.localUuid);
      expect(deleted.deletedAt, isNotNull, reason: 'حذف ناعم محلياً');

      // محاكاة _processGuestInfoEntry: يقرأ الصف كاملاً من المحلي ثم يرفعه
      final payload = mapper.guestInfoToRemote(deleted);
      final filtered = AppwriteSyncUtils.filterPayloadForCollection(
        'guest_infos',
        payload,
      );
      expect(
        filtered['deletedAt'],
        deleted.deletedAt,
        reason: 'tombstone يجب أن يصل للسحابة',
      );
      // العنصر الموجود في outbox بعد الحذف op='update' (وليس create)
      final entries = await outboxFor(row.localUuid);
      expect(entries, isNotEmpty);
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // السحب (Pull)
  // ══════════════════════════════════════════════════════════════════════
  group('سحب guest_infos (Pull)', () {
    test('مستند بعيد جديد يُدرج بكل الحقول وorigin=server', () async {
      const uuid = 'gi-pull-new-1';
      final doc = remoteDoc(uuid: uuid);

      final rowId = await registry.guestInfos.upsertFromJson(
        doc,
        src: Source.appwrite,
      );
      expect(rowId, greaterThan(0));

      final row = await findByUuid(uuid);
      expect(row.roomNumber, '101');
      expect(row.guestName, 'أحمد محمد صالح');
      expect(row.nationality, 'يمني');
      expect(row.idNumber, '0123456789');
      expect(row.idType, 'بطاقة شخصية');
      expect(row.issueDate, '2026-01-15');
      expect(row.issuePlace, 'صنعاء');
      expect(row.governorate, 'عدن');
      expect(row.notes, 'ملاحظة أصلية');
      expect(row.origin, 'server');
      expect(row.lastModified, kBaseEpoch);
      expect(row.version, 1);
      expect(row.deviceId, 'deviceA');
      expect(row.deletedAt, isNull);
    });

    test('سحب نفس المستند مرتين لا يُنشئ تكراراً', () async {
      const uuid = 'gi-pull-idem-1';
      await registry.guestInfos.upsertFromJson(
        remoteDoc(uuid: uuid),
        src: Source.appwrite,
      );
      await registry.guestInfos.upsertFromJson(
        remoteDoc(uuid: uuid),
        src: Source.appwrite,
      );

      final rows = await (db.select(
        db.guestInfos,
      )..where((t) => t.localUuid.equals(uuid))).get();
      expect(rows, hasLength(1));
    });

    test('نسخة بعيدة أحدث تُحدَّث في المكان (نفس الصف)', () async {
      const uuid = 'gi-pull-upd-1';
      final firstId = await registry.guestInfos.upsertFromJson(
        remoteDoc(uuid: uuid, version: 1),
        src: Source.appwrite,
      );

      final newerId = await registry.guestInfos.upsertFromJson(
        remoteDoc(
          uuid: uuid,
          lastModified: kBaseEpoch + 500,
          room: '102',
          notes: 'تحديث من جهاز آخر',
          version: 2,
        ),
        src: Source.appwrite,
      );

      expect(newerId, firstId, reason: 'تحديث في المكان لا إدراج جديد');
      final row = await findByUuid(uuid);
      expect(row.roomNumber, '102');
      expect(row.notes, 'تحديث من جهاز آخر');
      expect(row.version, 2);
      expect(row.lastModified, kBaseEpoch + 500);
    });

    test('tombstone بعيد يُطبَّق محلياً ويُستبعد من listAll', () async {
      const uuid = 'gi-pull-del-1';
      await registry.guestInfos.upsertFromJson(
        remoteDoc(uuid: uuid),
        src: Source.appwrite,
      );

      await registry.guestInfos.upsertFromJson(
        remoteDoc(
          uuid: uuid,
          lastModified: kBaseEpoch + 900,
          deletedAt: kBaseEpoch + 900,
        ),
        src: Source.appwrite,
      );

      final row = await findByUuid(uuid);
      expect(row.deletedAt, kBaseEpoch + 900);

      final visible = await repo.listAll();
      expect(
        visible.any((g) => g.localUuid == uuid),
        isFalse,
        reason: 'المحذوف يجب ألا يظهر في القائمة',
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════
  // رحلة ذهاب وعودة (جهازان عبر السحابة)
  // ══════════════════════════════════════════════════════════════════════
  group('رحلة ذهاب وعودة guest_infos (Two-device round trip)', () {
    test('A ينشئ → B يسحب → B يرفع → الحقول مستقرة بلا انحراف', () async {
      // ── الجهاز A: إنشاء محلي + حمولة الرفع
      await repo.create(
        roomNumber: '707',
        guestName: 'عمر الخطيب',
        nationality: 'يمني',
        idNumber: '0102030405',
        idType: 'جواز سفر',
        issueDate: '2023-11-05',
        issuePlace: 'المكلا',
        governorate: 'حضرموت',
        notes: 'إقامة عائلية',
      );
      final rowA = await (db.select(
        db.guestInfos,
      )..where((t) => t.guestName.equals('عمر الخطيب'))).getSingle();
      final wirePayloadA = AppwriteSyncUtils.filterPayloadForCollection(
        'guest_infos',
        mapper.guestInfoToRemote(rowA),
      );

      // ── الجهاز B: سحب المستند كما وصل عبر Appwrite
      final uuidB = rowA.localUuid;
      await registry.guestInfos.upsertFromJson(
        wirePayloadA,
        src: Source.appwrite,
      );
      final rowB = await findByUuid(uuidB);

      // الحقول التسعة مطابقة تماماً لدى B
      expect(rowB.roomNumber, rowA.roomNumber);
      expect(rowB.guestName, rowA.guestName);
      expect(rowB.nationality, rowA.nationality);
      expect(rowB.idNumber, rowA.idNumber);
      expect(rowB.idType, rowA.idType);
      expect(rowB.issueDate, rowA.issueDate);
      expect(rowB.issuePlace, rowA.issuePlace);
      expect(rowB.governorate, rowA.governorate);
      expect(rowB.notes, rowA.notes);

      // ── الجهاز B يرفع نسخته (بعد أن أصبحت origin=server)
      final wirePayloadB = AppwriteSyncUtils.filterPayloadForCollection(
        'guest_infos',
        mapper.guestInfoToRemote(rowB),
      );

      // لا انحراف في حقول البيانات بين حمولة A وحمولة B
      for (final f in kGuestDataFields) {
        expect(
          wirePayloadB[f],
          wirePayloadA[f],
          reason: 'انحراف بيانات في $f أثناء رحلة الذهاب والعودة',
        );
      }
      // حقول المزامنة الحرجة تنتقل سليمة
      expect(wirePayloadB['localUuid'], uuidB);
      expect(wirePayloadB['createdAt'], wirePayloadA['createdAt']);
    });
  });
}
