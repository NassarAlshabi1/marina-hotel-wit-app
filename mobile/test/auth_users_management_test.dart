// اختبارات قسم «إضافة مستخدمين» في شاشة الإعدادات — المسار الكامل:
// addUser/setPermissions/updateCloudUser/deleteCloudUser/deleteLocalUser
// + صف app_users المحلي (مرآة D1) + عمليات Outbox المحجوزة للرفع.
//
// ✅ (2026-09-07) تغطي إصلاحات: اتساق كلمة المرور المحلية بعد التعديل
// السحابي، عدم رفع credentials_version مع تعديل الصلاحيات فقط، tombstone
// الحساب المحلي المرفوع سابقاً (منع الزومبي)، وعدم كسر الإضافة أوفلاين.
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/auth_local_store.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/password_hasher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthLocalStore store;
  late OutboxDao outbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    DatabaseManager.attachForTesting(db);
    store = AuthLocalStore();
    outbox = OutboxDao(db, AdapterRegistry.testing(db));
  });

  tearDown(() async {
    DatabaseManager.detachForTesting();
    await db.close();
  });

  Future<List<Map<String, dynamic>>> appUsersRows(String username) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM app_users WHERE username = ?',
          variables: [Variable.withString(username)],
        )
        .get();
    return rows.map((r) => r.data).toList();
  }

  Future<List<Map<String, dynamic>>> outboxRows() async {
    final rows = await db
        .customSelect(
          'SELECT * FROM outbox WHERE entity = ? ORDER BY id',
          variables: [Variable.withString('app_users')],
        )
        .get();
    return rows.map((r) => r.data).toList();
  }

  test(
    'إضافة مستخدم: دخول فوري + صف app_users كامل + عملية create كاملة في Outbox',
    () async {
      await store.addUser(
        username: 'saleh',
        password: '1234',
        fullName: 'صالح علي',
        userType: 'employee',
        permissions: ['dashboard', 'bookings.create'],
      );

      // الدخول يعمل فوراً على جهاز الإنشاء
      final login = await store.validateCredentials('saleh', '1234');
      expect(login, isNotNull);
      expect(login!['full_name'], 'صالح علي');
      expect(login['user_type'], 'employee');

      // صف app_users المحلي (مرآة D1) كامل البيانات
      final rows = await appUsersRows('saleh');
      expect(rows.length, 1);
      final row = rows.first;
      expect(
        PasswordHasher.verify('1234', (row['password'] ?? '') as String),
        isTrue,
      );
      expect(row['full_name'], 'صالح علي');
      expect(row['user_type'], 'employee');
      expect(row['credentials_version'], 1);
      final active = row['active'];
      expect(active == 1 || active == true, isTrue);
      expect(row['deleted_at'], isNull);

      // عملية outbox واحدة (coalescing): create بحمولة كاملة بكلمة المرور
      final ops = await outboxRows();
      expect(ops.length, 1);
      expect(ops.first['op'], 'create');
      final payload = jsonDecode(ops.first['payload'] as String)
          as Map<String, dynamic>;
      expect(payload['username'], 'saleh');
      expect(
        PasswordHasher.verify('1234', payload['password'] as String),
        isTrue,
      );
      expect(jsonDecode(payload['permissions'] as String),
          contains('bookings.create'));
    },
  );

  test(
    'تعديل كلمة مرور مستخدم: النسخة المحلية تُحدَّث — الجديدة تعمل والقديمة تُرفض',
    () async {
      await store.addUser(
        username: 'nour',
        password: '1111',
        fullName: 'نور',
        userType: 'supervisor',
        permissions: ['dashboard'],
      );

      final before = await appUsersRows('nour');
      final docId = before.first['local_uuid'] as String;

      final ok = await store.updateCloudUser(
        username: 'nour',
        docId: docId,
        newPassword: '2222',
        newFullName: 'نور الجديد',
      );
      expect(ok, isTrue);

      // ✅ الإصلاح الجوهري: على جهاز الإنشاء كانت كلمة المرور الجديدة
      // تُرفض والقديمة تُقبل لأن validateCredentials يفحص custom_accounts أولاً.
      expect(await store.validateCredentials('nour', '2222'), isNotNull);
      expect(await store.validateCredentials('nour', '1111'), isNull);

      // credentials_version ارتفع (تغيير كلمة مرور = قطع جلسات مشروع)
      final after = await appUsersRows('nour');
      expect(after.first['credentials_version'], 2);
      expect(
        PasswordHasher.verify('2222', after.first['password'] as String),
        isTrue,
      );
    },
  );

  test(
    'تعديل الصلاحيات فقط لا يرفع credentials_version (لا قطع جلسات بلا سبب)',
    () async {
      await store.addUser(
        username: 'kareem',
        password: '3333',
        fullName: 'كريم',
        userType: 'accountant',
        permissions: ['dashboard'],
      );

      final before = await appUsersRows('kareem').then((r) => r.first);
      final credBefore = before['credentials_version'];
      final versionBefore = before['version'];

      final saved = await store.setPermissions('kareem', ['reports']);
      expect(saved, isTrue);

      final after = await appUsersRows('kareem').then((r) => r.first);
      // ✅ الإصلاح: عدّاد إبطال الجلسات لا يتحرك مع الصلاحيات
      expect(after['credentials_version'], credBefore);
      // version (LWW) ارتفع كي يفوز الرفع في فصل التعارضات
      expect(after['version'], versionBefore + 1);

      // الصلاحيات الجديدة في الصف المحلي وفي outbox
      final perms = jsonDecode(after['permissions'] as String) as List;
      expect(perms, ['reports']);
      final ops = await outboxRows();
      expect(ops.last['op'], 'update');
      final payload =
          jsonDecode(ops.last['payload'] as String) as Map<String, dynamic>;
      expect(jsonDecode(payload['permissions'] as String), ['reports']);
      expect(payload.containsKey('credentials_version'), isFalse);
    },
  );

  test('حذف مستخدم سحابي: tombstone محلي + عملية delete في Outbox', () async {
    await store.addUser(
      username: 'omar',
      password: '4444',
      fullName: 'عمر',
      userType: 'employee',
      permissions: ['dashboard'],
    );
    final rows = await appUsersRows('omar');
    final docId = rows.first['local_uuid'] as String;

    final ok = await store.deleteCloudUser(docId: docId);
    expect(ok, isTrue);

    final after = await appUsersRows('omar');
    expect(after.first['deleted_at'], isNotNull);

    // لم يعد يظهر في قائمة الحسابات السحابية (المصدر لشاشة الإدارة)
    final cloud = await store.loadCloudAccounts();
    expect(cloud.containsKey('omar'), isFalse);

    final ops = await outboxRows();
    final deleteOps = ops
        .where(
          (o) => o['op'] == 'delete' && o['local_uuid'] == docId,
        )
        .toList();
    expect(deleteOps, isNotEmpty);
    final payload = jsonDecode(deleteOps.first['payload'] as String)
        as Map<String, dynamic>;
    expect(payload['deleted_at'], isNotNull);
  });

  test(
    'حذف مستخدم محلي مخصص سبق رفعه: tombstone يمنع عودته من السحاب (زومبي)',
    () async {
      await store.addUser(
        username: 'hani',
        password: '5555',
        fullName: 'هاني',
        userType: 'employee',
        permissions: ['dashboard'],
      );
      // تأكيد: الحساب موجود في app_users (رُفع محلياً بانتظار الرفع)
      final before = await appUsersRows('hani');
      expect(before, isNotEmpty);
      final docId = before.first['local_uuid'] as String;

      final ok = await store.deleteLocalUser('hani');
      expect(ok, isTrue);

      // الحساب المخصص أُزيل من نسخة الدخول المحلية
      expect(await store.validateCredentials('hani', '5555'), isNull);
      final prefs = await SharedPreferences.getInstance();
      final custom = prefs.getString('custom_accounts');
      expect(custom, isNotNull);
      expect((jsonDecode(custom!) as Map).containsKey('hani'), isFalse);

      // ✅ الإصلاح: الصف المزامن حُذرن (tombstone) وعملية delete محجوزة
      // — دونها يعود المستخدم مع السحب التالي من D1.
      final after = await appUsersRows('hani');
      expect(after.first['deleted_at'], isNotNull);
      final ops = await outboxRows();
      final deleteOps = ops
          .where(
            (o) => o['op'] == 'delete' && o['local_uuid'] == docId,
          )
          .toList();
      expect(deleteOps, isNotEmpty);
    },
  );

  test(
    'إضافة مستخدم بدون قاعدة مهيأة (أوفلاين مبكر): لا تنكسر — الدخول المحلي يعمل',
    () async {
      DatabaseManager.detachForTesting();

      await store.addUser(
        username: 'rawan',
        password: '6666',
        fullName: 'روان',
        userType: 'employee',
        permissions: ['dashboard'],
      );

      // نسخة الدخول المحلية سليمة — المزامنة ستُحجز عند توفر القاعدة لاحقاً
      final login = await store.validateCredentials('rawan', '6666');
      expect(login, isNotNull);
      expect(login!['username'], 'rawan');
    },
  );
}
