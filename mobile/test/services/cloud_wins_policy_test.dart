// اختبارات PR-4 (وثيقة الربط §7.5): سياسة Cloud Wins
// القاعدة: نسخة Appwrite هي الفائزة دائماً عند اختلاف الأجهزة —
// لا دمج حقول، ولا اعتماد على ساعة الجهاز، ولا إحياء بعد Tombstone.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync/cloud_wins_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CloudWinsPolicy.decide', () {
    test('وثيقة غير موجودة سحابياً ⇒ لا تعارض (رفع إنشاء طبيعي)', () {
      final decision = CloudWinsPolicy.decide(
        localVersion: 3,
        localDeletedAt: null,
        cloud: null,
      );
      expect(decision.supersededLocal, isFalse);
      expect(decision.reason, CloudWinsReason.none);
    });

    test('نسخة السحابة أحدث ⇒ تُعتمد وتُلغى النسخة المحلية', () {
      final decision = CloudWinsPolicy.decide(
        localVersion: 2,
        localDeletedAt: null,
        cloud: {'version': 5, 'amount': 999},
      );
      expect(decision.supersededLocal, isTrue);
      expect(decision.reason, CloudWinsReason.cloudNewerVersion);
      expect(decision.cloudData?['amount'], 999);
    });

    test('نسختان متساويتان ⇒ لا إلغاء (يُكمل الرفع بعد فحص OCC)', () {
      expect(
        CloudWinsPolicy.decide(
          localVersion: 4,
          localDeletedAt: null,
          cloud: {'version': 4},
        ).supersededLocal,
        isFalse,
      );
    });

    test('النسخة المحلية أحدث ⇒ لا إلغاء: التعديل المحلي يُرفع', () {
      expect(
        CloudWinsPolicy.decide(
          localVersion: 7,
          localDeletedAt: null,
          cloud: {'version': 4},
        ).supersededLocal,
        isFalse,
      );
    });

    test('Tombstone سحابي يفوز على تعديل محلي غير محذوف', () {
      final decision = CloudWinsPolicy.decide(
        localVersion: 9,
        localDeletedAt: null,
        cloud: {'version': 1, 'deletedAt': 1762300000},
      );
      expect(decision.reason, CloudWinsReason.cloudTombstone);
      expect(decision.supersededLocal, isTrue);
    });

    test('حذف سحابي على سجل محذوف محلياً ⇒ لا إلغاء مكرر', () {
      final decision = CloudWinsPolicy.decide(
        localVersion: 9,
        localDeletedAt: 1762200000,
        cloud: {'version': 1, 'deletedAt': 1762300000},
      );
      expect(decision.supersededLocal, isFalse);
    });

    test('version المقروء كنص رقمي يُقارن صحيحاً', () {
      expect(
        CloudWinsPolicy.decide(
          localVersion: 2,
          localDeletedAt: null,
          cloud: {'version': '6'},
        ).reason,
        CloudWinsReason.cloudNewerVersion,
      );
    });

    test('غياب version سحابياً ⇒ لا دليل حداثة ⇒ لا إلغاء', () {
      expect(
        CloudWinsPolicy.decide(
          localVersion: 2,
          localDeletedAt: null,
          cloud: {'amount': 10},
        ).reason,
        CloudWinsReason.none,
      );
    });

    test('deletedAt = 0 أو نص فارغ لا يُعدّ Tombstone', () {
      expect(CloudWinsPolicy.deletedAtOf({'deletedAt': 0}), isNull);
      expect(CloudWinsPolicy.deletedAtOf({'deletedAt': ''}), isNull);
      expect(CloudWinsPolicy.deletedAtOf({'deletedAt': null}), isNull);
      expect(CloudWinsPolicy.deletedAtOf({'deletedAt': 42}), 42);
    });
  });

  group('خريطة الجداول', () {
    test('كل كيان مالي معروف له جدول محلي', () {
      for (final entity in const [
        'employees',
        'expenses',
        'salary_withdrawals',
        'salary_cycles',
        'salary_payments',
        'salary_carry_over_logs',
      ]) {
        expect(
          CloudWinsPolicy.tableForEntity(entity),
          isNotNull,
          reason: 'entity=$entity',
        );
      }
      expect(CloudWinsPolicy.tableForEntity('nope'), isNull);
    });
  });

  group('OutboxDao.markSupersededByCloud', () {
    late AppDatabase db;
    late OutboxDao outbox;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      outbox = OutboxDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('يُخرج العنصر من المعلّق ويحفظ أثراً تشخيصياً', () async {
      final id = await outbox.merge(
        entity: 'expenses',
        op: 'update',
        localUuid: 'exp-uuid',
        payload: {'amount': 10},
        clientTs: 1000,
      );
      expect(await outbox.countPendingPushable(), 1);

      await outbox.markSupersededByCloud([
        id,
      ], note: 'superseded_by_cloud: cloud version 5 > local 2');

      expect(await outbox.countPendingPushable(), 0);
      expect(await outbox.countUndeliveredToPrimary(), 0);

      final rows = await db.select(db.outbox).get();
      expect(rows, hasLength(1), reason: 'لا حذف بلا تأكيد — يبقى الأثر');
      expect(
        rows.single.processingStatus,
        CloudWinsPolicy.supersededStatus,
      );
      expect(rows.single.lastError, contains('cloud version 5'));
    });

    test('العناصر الأخرى تبقى معلّقة (لا يتأثر غير المتعارض)', () async {
      final superseded = await outbox.merge(
        entity: 'expenses',
        op: 'update',
        localUuid: 'a',
        payload: {'amount': 1},
        clientTs: 1000,
      );
      await outbox.merge(
        entity: 'expenses',
        op: 'update',
        localUuid: 'b',
        payload: {'amount': 2},
        clientTs: 1001,
      );

      await outbox.markSupersededByCloud([superseded]);

      expect(await outbox.countPendingPushable(), 1);
    });

    test('قائمة فارغة لا تُغيّر شيئاً', () async {
      await outbox.merge(
        entity: 'expenses',
        op: 'create',
        localUuid: 'c',
        payload: {'amount': 3},
        clientTs: 1002,
      );
      await outbox.markSupersededByCloud(const []);
      expect(await outbox.countPendingPushable(), 1);
    });
  });
}
