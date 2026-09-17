// test/unit/cloudflare_d1_upload_fields_test.dart
//
// ✅ اختبار انحدار لتثبيت خرائط الحقول في قسم الرفع إلى Cloudflare D1
// (شاشة الإعدادات → النسخ الاحتياطي والاستعادة → تبويب Cloudflare D1).
//
// مسار الرفع (CloudflareD1Tab → CloudflareD1Service) يقرأ الجداول المحلية
// بـ SELECT * ويرفع أسماء الأعمدة كما هي (بلا تحويل) — لذا صحة الخريطة
// camelCase → snake_case تعتمد كلياً على أعمدة مخطط drift المولّد.
// هذا الاختبار يفتح قاعدة drift حقيقية في الذاكرة ويقرأ أسماء الأعمدة
// الفعلية عبر PRAGMA table_info لكل جدول مزامنة (نفس الجداول التي يرفعها
// التبويب افتراضياً — kAppwriteSyncedTables) ويثبّت الحقول الـ 17:
//
//   localUuid → local_uuid            serverId → server_id
//   createdAt → created_at            updatedAt → updated_at
//   deletedAt → deleted_at            lastModified → last_modified
//   origin → origin                   createdAtIso → created_at_iso
//   updatedAtIso → updated_at_iso     deletedAtIso → deleted_at_iso
//   createdAtEpoch → created_at_epoch
//   lastModifiedEpoch → last_modified_epoch
//   version → version                 vectorClock → vector_clock
//   idempotencyKey → idempotency_key  syncTimestamp → sync_timestamp
//   deviceId → device_id
//
// إذا أعاد أحد توليد drift بصياغة أعمدة مختلفة (مثلاً camelCase) فسيفشل
// هذا الاختبار قبل وصول أعمدة خاطئة إلى قاعدة D1.
//
// الاستخدام: flutter test test/unit/cloudflare_d1_upload_fields_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/settings/backup/tabs/cloudflare_d1_tab.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

/// الخريطة المرجعية — اسم الحقل بصيغة Dart/Appwrite (camelCase) إلى اسم
/// عمود SQLite/D1 المتوقع (snake_case). أي انحراف = فشل الاختبار.
const Map<String, String> kExpectedSyncFieldMapping = <String, String>{
  'localUuid': 'local_uuid',
  'serverId': 'server_id',
  'createdAt': 'created_at',
  'updatedAt': 'updated_at',
  'deletedAt': 'deleted_at',
  'lastModified': 'last_modified',
  'origin': 'origin',
  'createdAtIso': 'created_at_iso',
  'updatedAtIso': 'updated_at_iso',
  'deletedAtIso': 'deleted_at_iso',
  'createdAtEpoch': 'created_at_epoch',
  'lastModifiedEpoch': 'last_modified_epoch',
  'version': 'version',
  'vectorClock': 'vector_clock',
  'idempotencyKey': 'idempotency_key',
  'syncTimestamp': 'sync_timestamp',
  'deviceId': 'device_id',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// قراءة أسماء أعمدة جدول كما هي فعلياً في SQLite (نفس ما يصل D1).
  Future<Set<String>> tableColumns(String table) async {
    final rows = await db
        .customSelect("SELECT name FROM pragma_table_info('$table')")
        .get();
    return rows.map((r) => r.data['name'].toString()).toSet();
  }

  test(
    'خريطة الحقول الـ 17 مكتملة وصحيحة كمرجع للاختبار',
    () {
      // حماية من التعديل العارض للخريطة المرجعية نفسها.
      expect(kExpectedSyncFieldMapping, hasLength(17));
      for (final entry in kExpectedSyncFieldMapping.entries) {
        final snake = entry.value;
        // كل اسم هدف يجب أن يكون snake_case خالصاً (بلا أحرف كبيرة).
        expect(
          snake,
          equals(snake.toLowerCase()),
          reason:
              '${entry.key} → $snake: الاسم المستهدف يجب أن يكون snake_case',
        );
        // والمصدر camelCase (بلا شرطة سفلية) — عدا origin/version أحادية الكلمة.
        expect(
          entry.key.contains('_'),
          isFalse,
          reason:
              '${entry.key}: اسم حقل Dart/Appwrite يجب أن يكون camelCase بلا "_"',
        );
      }
    },
  );

  test(
    'كل جدول مزامنة يحمل الأعمدة الـ 17 بصيغة snake_case (مسار رفع D1)',
    () async {
      // kAppwriteSyncedTables هي نفسها الجداول المحددة افتراضياً في تبويب
      // Cloudflare D1 بالشاشة — تحقق أن المجموعة غير فارغة قبل الفحص.
      expect(kAppwriteSyncedTables, isNotEmpty);

      final failures = <String>[];
      for (final table in kAppwriteSyncedTables) {
        final columns = await tableColumns(table);

        for (final entry in kExpectedSyncFieldMapping.entries) {
          final dartField = entry.key;
          final expectedColumn = entry.value;
          if (!columns.contains(expectedColumn)) {
            failures.add(
              '$table: عمود "$expectedColumn" (من $dartField) غير موجود. '
              'الأعمدة الفعلية: ${columns.toList()..sort()}',
            );
          }
        }
      }

      expect(
        failures,
        isEmpty,
        reason:
            'خرائط حقول المزامنة مكسورة في ${failures.length} موضعاً — '
            'هذه الأعمدة هي ما يرفعه تبويب Cloudflare D1 حرفياً إلى D1 '
            '(SELECT * بلا تحويل):\n${failures.join('\n')}',
      );
    },
  );

  test(
    'لا يوجد عمود camelCase في جداول المزامنة (منع ازدواج الأعمدة في D1)',
    () async {
      final camelRegExp = RegExp(r'[A-Z]');
      final offenders = <String>[];

      for (final table in kAppwriteSyncedTables) {
        final columns = await tableColumns(table);
        for (final column in columns) {
          if (camelRegExp.hasMatch(column)) {
            offenders.add('$table.$column');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'أعمدة camelCase في القاعدة المحلية سترفع إلى D1 كما هي وتنشئ '
            'أعمدة موازية للأعمدة snake_case (ازدواجية بيانات عبر '
            '_reconcileSchema): ${offenders.join('، ')}',
      );
    },
  );

  test(
    'الرفع الفعلي يرسل أسماء snake_case (إدراج ثم قراءة بنمط SELECT *)',
    () async {
      // محاكاة المسار الكامل: الإدراج عبر drift ثم القراءة بنفس استعلام
      // CloudflareD1Tab._upload (SELECT * FROM "table" LIMIT ? OFFSET ?)
      // والتحقق أن مفاتيح الخريطة هي أسماء snake_case الـ 17 نفسها.
      await db.into(db.rooms).insert(
        RoomsCompanion.insert(
          localUuid: 'room-101-uuid',
          createdAt: 1735689600000,
          updatedAt: 1735776000000,
          lastModified: 1735776001000,
          roomNumber: '101',
          type: 'double',
          price: 100,
          status: 'شاغرة',
          serverId: const Value(7),
          createdAtIso: const Value('2026-01-01T00:00:00.000Z'),
          updatedAtIso: const Value('2026-01-02T00:00:00.000Z'),
          createdAtEpoch: const Value(1735689600),
          lastModifiedEpoch: const Value(1735776000),
          version: const Value(3),
          origin: const Value('local'),
          vectorClock: const Value('{"dev-a":1}'),
          deviceId: const Value('dev-a'),
          syncTimestamp: const Value(1735776001),
          idempotencyKey: const Value('idem-key-1'),
        ),
      );

      // نفس قراءة التبويب: SELECT * — مفاتيح r.data هي ما يُرفع حرفياً إلى D1.
      final rows = await db.customSelect('SELECT * FROM "rooms"').get();
      expect(rows, hasLength(1));
      final uploaded = rows.first.data;

      for (final entry in kExpectedSyncFieldMapping.entries) {
        expect(
          uploaded.containsKey(entry.value),
          isTrue,
          reason:
              'الصف المرفوع لا يحتوي عمود "${entry.value}" (المتوقع من '
              '${entry.key}) — المفاتيح الفعلية: ${uploaded.keys.toList()..sort()}',
        );
      }
      // عينة قيم للتأكد من أن الأعمدة ليست موجودة فحسب بل تحمل بياناتنا.
      expect(uploaded['local_uuid'], 'room-101-uuid');
      expect(uploaded['server_id'], 7);
      expect(uploaded['last_modified'], 1735776001000);
      expect(uploaded['created_at_iso'], '2026-01-01T00:00:00.000Z');
      expect(uploaded['updated_at_iso'], '2026-01-02T00:00:00.000Z');
      expect(uploaded['created_at_epoch'], 1735689600);
      expect(uploaded['last_modified_epoch'], 1735776000);
      expect(uploaded['sync_timestamp'], 1735776001);
      expect(uploaded['vector_clock'], '{"dev-a":1}');
      expect(uploaded['device_id'], 'dev-a');
      expect(uploaded['origin'], 'local');
      expect(uploaded['version'], 3);
      expect(uploaded['idempotency_key'], 'idem-key-1');
    },
  );
}
