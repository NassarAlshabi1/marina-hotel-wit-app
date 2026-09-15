import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/payment_session_context.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';

/// ✅ (2026-09-16) عقد هوية مستلم الدفعة السحابية [_resolveReceiverCloudId]:
/// الجلسة المستعادة تفقد cloud_user_id (AuthUser.toJson لا يضمّنه) —
/// الدفعة يجب أن تحمل الهوية السحابية الثابتة عبر مطابقة الاسم الفريدة
/// في مرآة app_users، وأي غموض يعيد NULL (السلوك السابق) بلا إسناد خاطئ.
void main() {
  const paymentDate = '2026-08-21T15:00:00.000Z';

  Future<PaymentsRepository> buildRepo(AppDatabase db) async {
    AdapterRegistry.initialize(db);
    return PaymentsRepository(db);
  }

  test('هوية الجلسة السحابية تُتّبع كما هي دون أي مطابقة', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      PaymentSessionContext.clear();
      await db.close();
    });
    final repository = await buildRepo(db);

    PaymentSessionContext.start(
      userId: 3,
      userName: 'موظف الاستقبال',
      cloudUserId: 'cloud-session-id',
      sessionUuid: 'session-a',
    );
    await repository.create(
      amount: 100,
      paymentDate: paymentDate,
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    final saved = await db.select(db.payments).get();
    expect(saved.single.receivedByCloudId, 'cloud-session-id');
  });

  test(
    'الجلسة المستعادة بلا هوية تُستبدل من مرآة app_users بالاسم الفريد',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        PaymentSessionContext.clear();
        await db.close();
      });
      final repository = await buildRepo(db);

      // صف مرآة حي وحيد: مستخدم سحابي باسم مطابق لاسم جلسة الدخول.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.appUsers)
          .insert(
            AppUsersCompanion.insert(
              username: 'receptionist',
              localUuid: 'user_receptionist',
              createdAt: nowMs,
              updatedAt: nowMs,
              lastModified: nowMs,
              fullName: Value('موظف الاستقبال'),
            ),
          );

      // لا cloudUserId — محاكاة جلسة مستعادة بعد إعادة تشغيل التطبيق.
      PaymentSessionContext.start(
        userId: 7,
        userName: 'موظف الاستقبال',
        sessionUuid: 'session-restored',
      );
      await repository.create(
        amount: 250,
        paymentDate: paymentDate,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );

      final saved = await db.select(db.payments).get();
      expect(saved.single.receivedByCloudId, 'user_receptionist');
    },
  );

  test('المطابقة بحساب الدخول (username) أيضاً لا بالاسم الكامل فقط', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      PaymentSessionContext.clear();
      await db.close();
    });
    final repository = await buildRepo(db);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // صف بلا full_name (فارغ) — المطابقة تتم عبر username.
    await db
        .into(db.appUsers)
        .insert(
          AppUsersCompanion.insert(
            username: 'nightshift',
            localUuid: 'user_nightshift',
            createdAt: nowMs,
            updatedAt: nowMs,
            lastModified: nowMs,
          ),
        );

    PaymentSessionContext.start(
      userId: 9,
      userName: 'nightshift',
      sessionUuid: 'session-username-match',
    );
    await repository.create(
      amount: 90,
      paymentDate: paymentDate,
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    final saved = await db.select(db.payments).get();
    expect(saved.single.receivedByCloudId, 'user_nightshift');
  });

  test('اسمان متطابقان لمدونة سحابيتين مختلفتين = غموض يعيد NULL', () async {
    // لا إسناد خاطئ أبداً: أكثر من هوية مطابقة → NULL = السلوك السابق.
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      PaymentSessionContext.clear();
      await db.close();
    });
    final repository = await buildRepo(db);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.appUsers)
        .insert(
          AppUsersCompanion.insert(
            username: 'ahmad1',
            localUuid: 'cloud-ahmad-1',
            createdAt: nowMs,
            updatedAt: nowMs,
            lastModified: nowMs,
            fullName: Value('أحمد'),
          ),
        );
    await db
        .into(db.appUsers)
        .insert(
          AppUsersCompanion.insert(
            username: 'ahmad2',
            localUuid: 'cloud-ahmad-2',
            createdAt: nowMs,
            updatedAt: nowMs,
            lastModified: nowMs,
            fullName: Value('أحمد'),
          ),
        );

    PaymentSessionContext.start(
      userId: 5,
      userName: 'أحمد',
      sessionUuid: 'session-ambiguous',
    );
    await repository.create(
      amount: 500,
      paymentDate: paymentDate,
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    final saved = await db.select(db.payments).get();
    expect(saved.single.receivedByCloudId, isNull);
  });

  test('لا صف مطابق في المرآة = NULL كما كان قبل الإصلاح', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      PaymentSessionContext.clear();
      await db.close();
    });
    final repository = await buildRepo(db);

    PaymentSessionContext.start(
      userId: 7,
      userName: 'موظف غير متزامن',
      sessionUuid: 'session-no-mirror',
    );
    await repository.create(
      amount: 70,
      paymentDate: paymentDate,
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    final saved = await db.select(db.payments).get();
    expect(saved.single.receivedByCloudId, isNull);
  });

  test('الصفوف المحجوب (tombstone) لا تُستخدم للمطابقة', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async {
      PaymentSessionContext.clear();
      await db.close();
    });
    final repository = await buildRepo(db);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.appUsers)
        .insert(
          AppUsersCompanion.insert(
            username: 'deleted_user',
            localUuid: 'cloud-deleted-user',
            createdAt: nowMs,
            updatedAt: nowMs,
            lastModified: nowMs,
            fullName: Value('موظف محذوف'),
            deletedAt: Value(nowMs),
          ),
        );

    PaymentSessionContext.start(
      userId: 4,
      userName: 'موظف محذوف',
      sessionUuid: 'session-tombstone',
    );
    await repository.create(
      amount: 60,
      paymentDate: paymentDate,
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    final saved = await db.select(db.payments).get();
    expect(saved.single.receivedByCloudId, isNull);
  });
}
