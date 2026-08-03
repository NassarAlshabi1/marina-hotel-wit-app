@Skip('Causes segmentation fault on CI headless runners (uses widgets bindings). Run locally.')
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/components/admin_sidebar.dart';
import 'package:marina_hotel_mobile/providers/auth_provider.dart';

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier(AuthState state) : super() {
    this.state = state;
  }
  @override
  Future<void> restoreSession() async {}
  @override
  Future<void> login(
    String username,
    String password, {
    bool rememberMe = false,
  }) async {}
  @override
  Future<void> logout() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('إخفاء عنصر الغرف بدون صلاحية rooms', (tester) async {
    final user = AuthUser(
      id: 2,
      username: 'm',
      fullName: 'محمد',
      userType: 'supervisor',
      permissions: const ['dashboard'],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => FakeAuthNotifier(
              AuthState(isAuthenticated: true, currentUser: user),
            ),
          ),
        ],
        child: const Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: Scaffold(
              body: AdminSidebar(
                currentRoute: '/dashboard',
                onRouteSelected: _noop,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('إدارة الغرف'), findsNothing);
    expect(find.text('لوحة التحكم'), findsOneWidget);
  });
}

void _noop(String _) {}
