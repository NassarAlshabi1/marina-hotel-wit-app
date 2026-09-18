import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/providers/auth_provider.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/auth_local_store.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('تسجيل الدخول لا ينشئ بيانات اختبارية أو Outbox', () async {
    final notifier = AuthNotifier(
      store: _LocalOnlyAuthStore(),
      restoreSessionOnCreate: false,
    );
    addTearDown(notifier.dispose);

    final outbox = OutboxDao(db, AdapterRegistry.testing(db));
    expect(await outbox.count(), 0);

    await notifier.login('operator', 'password');

    expect(notifier.state.isAuthenticated, isTrue);
    expect(notifier.state.currentUser?.username, 'operator');
    expect(await outbox.count(), 0);
  });

  test('تُحفظ جلسة الدخول وتُستعاد بعد إعادة إنشاء AuthNotifier', () async {
    final first = AuthNotifier(restoreSessionOnCreate: false);
    addTearDown(first.dispose);

    await first.login('admin', 'admin');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('remember_me'), isTrue);
    expect(prefs.getString('current_user'), isNotNull);

    final restored = AuthNotifier(restoreSessionOnCreate: false);
    addTearDown(restored.dispose);
    await restored.restoreSession();

    expect(restored.state.isAuthenticated, isTrue);
    expect(restored.state.currentUser?.username, 'admin');
    expect(await OutboxDao(db, AdapterRegistry.testing(db)).count(), 0);
  });

  test('إلغاء تذكر الجلسة يمنع الاستعادة بعد إعادة التشغيل', () async {
    final first = AuthNotifier(restoreSessionOnCreate: false);
    addTearDown(first.dispose);

    await first.login('admin', 'admin', rememberMe: false);

    final restored = AuthNotifier(restoreSessionOnCreate: false);
    addTearDown(restored.dispose);
    await restored.restoreSession();

    expect(restored.state.isAuthenticated, isFalse);
    expect(restored.state.currentUser, isNull);
  });

  test('التحقق الحقيقي من الحساب المحلي لا ينشئ Outbox', () async {
    final store = AuthLocalStore();
    final outbox = OutboxDao(db, AdapterRegistry.testing(db));

    final user = await store.validateCredentials('admin', 'admin');

    expect(user, isNotNull);
    expect(user?['username'], 'admin');
    expect(await outbox.count(), 0);
  });

  test('فشل تسجيل الدخول لا ينشئ Outbox أيضاً', () async {
    final notifier = AuthNotifier(
      store: _LocalOnlyAuthStore(),
      restoreSessionOnCreate: false,
    );
    addTearDown(notifier.dispose);

    await notifier.login('unknown', 'wrong-password');

    expect(notifier.state.isAuthenticated, isFalse);
    expect(notifier.state.error, isNotNull);
    expect(await OutboxDao(db, AdapterRegistry.testing(db)).count(), 0);
  });
}

class _LocalOnlyAuthStore extends AuthLocalStore {
  @override
  Future<Map<String, dynamic>?> validateCredentials(
    String username,
    String password,
  ) async {
    if (username == 'operator' && password == 'password') {
      return {
        'id': 7,
        'username': username,
        'full_name': 'موظف اختبار المسار المحلي',
        'user_type': 'employee',
        'permissions': <String>['dashboard.view'],
      };
    }
    return null;
  }

  @override
  Future<void> saveCurrentUser(Map<String, dynamic> userJson) async {}

  @override
  Future<void> setRememberMe(bool value) async {}

  @override
  Future<void> setAuthType(AuthType type) async {}

  @override
  bool isFixedAccount(String username) => true;
}
