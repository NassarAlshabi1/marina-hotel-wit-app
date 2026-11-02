// test/unit/outbox_manual_push_test.dart
//
// ✅ (2026-11-03) درع انحدار لزر «رفع التغييرات» في Dashboard.
//
// المشكلة المُثبتة قبل الإصلاح:
//   `_pushAllEntities` كان يبدأ بـ `outboxDao.reclaimForPush()` فقط، وهو
//   يتعمّد عدم إعادة السجلات التي تجاوزت `maxFailedAttempts` (5) — تُترك
//   لمؤقّت `retryFailedWithBackoff` الدوري المرتبط بالمزامنة التلقائية.
//   النتيجة عند تعطيل المزامنة التلقائية (أو قبل انقضاء دورة المؤقّت):
//   السجل يُحتسب في شارة «تغييرات معلّقة»، لكن الضغط على الزر لا يلمسه
//   `takeBatch` أبداً ⇒ تغيير محلي لا يمكن رفعه بأي طريقة، وشارة دائمة.
//
// الإصلاح: `OutboxDao.prepareForManualPush()` = reclaimForPush +
// retryFailedWithBackoff (والأخير يحترم مهلة التراجع بمدّة 30 دقيقة).

// ignore_for_file: lines_longer_than_80_chars

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao dao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dao = OutboxDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seed({required String uuid, required int clientTs}) {
    return dao.merge(
      entity: 'rooms',
      op: 'create',
      localUuid: uuid,
      payload: <String, dynamic>{'roomNumber': uuid},
      clientTs: clientTs,
      source: 'local',
    );
  }

  Future<String> statusOf(int id) async {
    final row = await (db.select(
      db.outbox,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row!.processingStatus;
  }

  group('OutboxDao.prepareForManualPush', () {
    test('يُعيد السجل العالق في processing إلى pending', () async {
      final id = await seed(uuid: 'r-stuck', clientTs: _nowSec());
      await db.customStatement(
        "UPDATE outbox SET processing_status = 'processing', "
        'processing_started_at = ? WHERE id = ?',
        [_nowSec() - 3600, id],
      );

      final reclaimed = await dao.prepareForManualPush();

      expect(reclaimed, greaterThanOrEqualTo(1));
      expect(await statusOf(id), 'pending');
    });

    test('يُعيد السجل الفاشل قليل المحاولات إلى pending', () async {
      final id = await seed(uuid: 'r-few', clientTs: _nowSec());
      await dao.setError(id, 'transient', 3);

      await dao.prepareForManualPush();

      expect(await statusOf(id), 'pending');
    });

    test('يُعيد السجل الفاشل كثير المحاولات بعد انقضاء مهلة التراجع', () async {
      // clientTs قبل ساعتين ⇒ تجاوز مهلة التراجع (30 دقيقة).
      final id = await seed(uuid: 'r-many-old', clientTs: _nowSec() - 7200);
      await dao.setError(id, 'chronic', 12);

      // قبل الإصلاح: reclaimForPush لا يلمسه ⇒ يبقى failed للأبد.
      final onlyReclaim = await dao.reclaimForPush();
      expect(onlyReclaim, 0, reason: 'سلوك ما قبل الإصلاح — توثيق للسبب');
      expect(await statusOf(id), 'failed');

      await dao.prepareForManualPush();

      expect(
        await statusOf(id),
        'pending',
        reason: 'زر الرفع يجب أن يستطيع إعادة محاولة ما تجاوز سقف المحاولات',
      );
    });

    test('لا يخترق مهلة التراجع: السجل الفاشل حديثاً يبقى failed', () async {
      final id = await seed(uuid: 'r-many-new', clientTs: _nowSec());
      await dao.setError(id, 'chronic', 12);

      await dao.prepareForManualPush();

      expect(
        await statusOf(id),
        'failed',
        reason: 'التراجع الأسّي محفوظ — لا إغراق الخادم بسجل فاشل حديثاً',
      );
    });

    test('لا يلمس السجلات المُسلَّمة للرئيسي', () async {
      final id = await seed(uuid: 'r-delivered', clientTs: _nowSec());
      await db.customStatement(
        'UPDATE outbox SET delivered_to_primary = 1, '
        "processing_status = 'pending' WHERE id = ?",
        [id],
      );

      await dao.prepareForManualPush();

      final row = await (db.select(
        db.outbox,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      expect(row!.deliveredToPrimary, isTrue);
      expect(await dao.countUndeliveredToPrimary(sources: const ['local']), 0);
    });
  });
}
