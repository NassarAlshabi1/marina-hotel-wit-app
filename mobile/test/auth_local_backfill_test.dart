import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/auth_local_store.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/password_hasher.dart';

/// ✅ (2026-09-16) عقد ردّم الحسابات المحلية المخصصة إلى السحابة
/// [AuthLocalStore.backfillLocalAccountsToCloud]:
/// حساب بلا صف حي في مرآة app_users → صف محلي + عملية create في
/// Outbox بهوية حتمية — بلا تشفير مزدوج لكلمة المرور، بلا لمس
/// الحسابات المتزامنة أو الثابتة (admin)، ومتكرر الاستدعاء بأمان.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late OutboxDao outbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseManager.attachForTesting(db);
    AdapterRegistry.initialize(db);
    outbox = OutboxDao(db, AdapterRegistry.testing(db));
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedCustomAccount(
    String username, {
    String fullName = 'موظف الاستقبال',
    String userType = 'employee',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_accounts',
      jsonEncode({
        username: {
          'password': PasswordHasher.hash('secret123'),
          'full_name': fullName,
          'user_type': userType,
          'id': 2,
        },
      }),
    );
    await prefs.setString(
      'user_permissions',
      jsonEncode({
        username: ['dashboard.view'],
      }),
    );
  }

  test(
    'حساب مخصص بلا صف سحابي يُردَّم: صف محلي + عملية create في Outbox',
    () async {
      await seedCustomAccount('receptionist');
      final store = AuthLocalStore();
      expect(await outbox.count(), 0);

      final backfilled = await store.backfillLocalAccountsToCloud();

      expect(backfilled, 1);
      expect(await outbox.count(), 1);

      final mirror = await db
          .customSelect(
            'SELECT local_uuid, username, full_name, user_type, active, '
            'permissions FROM app_users LIMIT 1',
          )
          .get();
      expect(mirror.single.data['local_uuid'], 'user_receptionist');
      expect(mirror.single.data['username'], 'receptionist');
      expect(mirror.single.data['full_name'], 'موظف الاستقبال');
      expect(mirror.single.data['user_type'], 'employee');
      expect(jsonDecode(mirror.single.data['permissions'] as String), [
        'dashboard.view',
      ]);

      final op = await db.select(db.outbox).get();
      expect(op.single.entity, 'app_users');
      expect(op.single.op, 'create');
      expect(op.single.localUuid, 'user_receptionist');
    },
  );

  test('كلمة المرور تُرفع بالهاش المخزن كما هي — لا تشفير مزدوج', () async {
    await seedCustomAccount('receptionist');
    final prefs = await SharedPreferences.getInstance();
    final accounts =
        jsonDecode(prefs.getString('custom_accounts')!) as Map<String, dynamic>;
    final storedHash =
        (accounts['receptionist'] as Map<String, dynamic>)['password']
            as String;
    expect(PasswordHasher.isHashed(storedHash), isTrue);

    final store = AuthLocalStore();
    await store.backfillLocalAccountsToCloud();

    final mirror = await db
        .customSelect('SELECT password FROM app_users LIMIT 1')
        .get();
    expect(mirror.single.data['password'], storedHash);
  });

  test('الردم idempotent — الحساب المتزامن لا يُعاد رفعه أبداً', () async {
    await seedCustomAccount('receptionist');
    final store = AuthLocalStore();

    expect(await store.backfillLocalAccountsToCloud(), 1);
    expect(await store.backfillLocalAccountsToCloud(), 0);
    expect(await outbox.count(), 1);
  });

  test('حساب وصل بالسحب من جهاز آخر (صف مرآة موجود) لا يُردَّم', () async {
    // السيناريو: نفس المستخدم موجود في D1 من جهاز آخر — نسخة D1 هي
    // المرجع، ولا إعادة كتابة كلمة مرور/صلاحيات هذا الجهاز فوقها.
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
          ),
        );
    await seedCustomAccount('receptionist');

    final store = AuthLocalStore();
    expect(await store.backfillLocalAccountsToCloud(), 0);
    expect(await outbox.count(), 0);
  });

  test('الحساب الثابت admin لا يُردَّم أبداً', () async {
    // دفاعي: custom_accounts لا يقبل admin أصلاً، لكن الحارس صريح.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_accounts',
      jsonEncode({
        'admin': {
          'password': PasswordHasher.hash('whatever'),
          'full_name': 'مدير',
          'user_type': 'admin',
          'id': 9,
        },
      }),
    );

    final store = AuthLocalStore();
    expect(await store.backfillLocalAccountsToCloud(), 0);
    expect(await outbox.count(), 0);
  });

  test('بلا حسابات مخصصة = أثر صفر (عقد اختبارات الدخول القائمة)', () async {
    final store = AuthLocalStore();
    expect(await store.backfillLocalAccountsToCloud(), 0);
    expect(await outbox.count(), 0);
  });
}
