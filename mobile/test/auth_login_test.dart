import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('نجاح تسجيل الدخول للمسؤول admin/admin', () async {
    final notifier = AuthNotifier();
    await notifier.login('admin', 'admin');
    expect(notifier.state.isAuthenticated, true);
    expect(notifier.state.currentUser?.username, 'admin');
    expect(notifier.state.currentUser?.permissions.contains('all'), true);
  });

  test('فشل تسجيل الدخول لبيانات خاطئة', () async {
    final notifier = AuthNotifier();
    await notifier.login('admin', 'wrong');
    expect(notifier.state.isAuthenticated, false);
    expect(notifier.state.error, isNotNull);
  });

  test('mohammed يسجل دخول بدون صلاحيات افتراضيًا', () async {
    final notifier = AuthNotifier();
    await notifier.login('mohammed', '1111');
    expect(notifier.state.isAuthenticated, true);
    expect(notifier.state.currentUser?.username, 'mohammed');
    expect(notifier.state.currentUser?.permissions.isEmpty, true);
  });
}