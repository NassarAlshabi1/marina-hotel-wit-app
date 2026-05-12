import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('نجاح تسجيل الدخول للمسؤول admin/admin', () async {
    final notifier = AuthNotifier();
    // انتظار restoreSession حتى تكتمل
    await Future.delayed(const Duration(milliseconds: 100));
    await notifier.login('admin', 'admin');
    expect(notifier.state.isAuthenticated, true);
    expect(notifier.state.currentUser?.username, 'admin');
    expect(notifier.state.currentUser?.permissions.contains('all'), true);
  });

  test('فشل تسجيل الدخول لبيانات خاطئة', () async {
    final notifier = AuthNotifier();
    await Future.delayed(const Duration(milliseconds: 100));
    await notifier.login('admin', 'wrong');
    expect(notifier.state.isAuthenticated, false);
    expect(notifier.state.error, isNotNull);
  });

  test('m يسجل دخول بدون صلاحيات افتراضيًا', () async {
    final notifier = AuthNotifier();
    await Future.delayed(const Duration(milliseconds: 100));
    await notifier.login('m', '1');
    expect(notifier.state.isAuthenticated, true);
    expect(notifier.state.currentUser?.username, 'm');
    // المستخدم 'm' ليس admin لذا لا يملك صلاحية 'all'، لكن قد يملك صلاحيات أخرى
    expect(notifier.state.currentUser?.permissions.contains('all'), isFalse);
  });
}
