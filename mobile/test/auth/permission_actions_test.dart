import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/auth_provider.dart';
import 'package:marina_hotel_mobile/services/auth_local_store.dart';

void main() {
  test('granular permissions allow create without delete', () {
    const user = AuthUser(
      id: 10,
      username: 'stock-clerk',
      fullName: 'موظف المخزون',
      userType: 'employee',
      permissions: ['inventory.view', 'inventory.create'],
    );

    expect(user.canAccessModule('inventory'), isTrue);
    expect(user.canPerform('inventory', 'view'), isTrue);
    expect(user.canPerform('inventory', 'create'), isTrue);
    expect(user.canPerform('inventory', 'update'), isFalse);
    expect(user.canPerform('inventory', 'delete'), isFalse);
  });

  test('view-only permission allows access but not mutations', () {
    const user = AuthUser(
      id: 12,
      username: 'viewer',
      fullName: 'مستخدم عرض',
      userType: 'employee',
      permissions: ['inventory.view'],
    );

    expect(user.canAccessModule('inventory'), isTrue);
    expect(user.canPerform('inventory', 'view'), isTrue);
    expect(user.canPerform('inventory', 'create'), isFalse);
    expect(user.canPerform('inventory', 'update'), isFalse);
    expect(user.canPerform('inventory', 'delete'), isFalse);
  });

  test('admin and all permissions retain full access', () {
    const admin = AuthUser(
      id: 13,
      username: 'admin-user',
      fullName: 'مدير النظام',
      userType: 'admin',
    );
    const allPermissions = AuthUser(
      id: 14,
      username: 'all-user',
      fullName: 'مستخدم شامل',
      userType: 'employee',
      permissions: ['all'],
    );

    for (final user in [admin, allPermissions]) {
      expect(user.canAccessModule('inventory'), isTrue);
      expect(user.canPerform('inventory', 'view'), isTrue);
      expect(user.canPerform('inventory', 'create'), isTrue);
      expect(user.canPerform('inventory', 'update'), isTrue);
      expect(user.canPerform('inventory', 'delete'), isTrue);
    }
  });

  test('legacy module permissions remain backward compatible', () {
    const user = AuthUser(
      id: 11,
      username: 'legacy-user',
      fullName: 'مستخدم سابق',
      userType: 'employee',
      permissions: ['inventory'],
    );

    expect(user.canAccessModule('inventory'), isTrue);
    expect(user.canPerform('inventory', 'create'), isTrue);
    expect(user.canPerform('inventory', 'delete'), isTrue);
  });

  group('module grant helpers (grouped editor)', () {
    test('moduleFullyGranted detects legacy key or all four operations', () {
      expect(AuthLocalStore.moduleFullyGranted(['rooms'], 'rooms'), isTrue);
      expect(
        AuthLocalStore.moduleFullyGranted(
          ['rooms.view', 'rooms.create', 'rooms.update', 'rooms.delete'],
          'rooms',
        ),
        isTrue,
      );
      expect(
        AuthLocalStore.moduleFullyGranted(['rooms.view'], 'rooms'),
        isFalse,
      );
      expect(AuthLocalStore.moduleFullyGranted([], 'rooms'), isFalse);
    });

    test('withModuleGranted normalizes to a single legacy key', () {
      final granted = AuthLocalStore.withModuleGranted(
        ['rooms.view', 'payments'],
        'rooms',
        true,
      );
      expect(granted, contains('rooms'));
      expect(granted.where((k) => k.startsWith('rooms.')), isEmpty);
      expect(granted, contains('payments'));

      final revoked = AuthLocalStore.withModuleGranted(
        ['rooms', 'rooms.view', 'payments'],
        'rooms',
        false,
      );
      expect(revoked, isNot(contains('rooms')));
      expect(revoked.where((k) => k.startsWith('rooms.')), isEmpty);
      expect(revoked, contains('payments'));
    });

    test(
      'withOperationToggled folds complete sets and expands legacy keys',
      () {
        // إكمال الرابعة يطوي الكل في المفتاح القديم وحده.
        final folded = AuthLocalStore.withOperationToggled(
          ['rooms.view', 'rooms.create', 'rooms.update'],
          'rooms',
          'delete',
          true,
        );
        expect(folded, contains('rooms'));
        expect(folded.where((k) => k.startsWith('rooms.')), isEmpty);

        // إسقاط عملية من مفتاح قديم يُبقي الثلاث الباقية (لا ضياع).
        final expanded = AuthLocalStore.withOperationToggled(
          ['rooms'],
          'rooms',
          'delete',
          false,
        );
        expect(expanded, isNot(contains('rooms')));
        expect(
          expanded,
          containsAll(['rooms.view', 'rooms.create', 'rooms.update']),
        );
        expect(expanded, isNot(contains('rooms.delete')));

        // منح عملية مغطاة بالمفتاح القديم أصلاً = بلا تغيير.
        expect(
          AuthLocalStore.withOperationToggled(['rooms'], 'rooms', 'view', true),
          ['rooms'],
        );
      },
    );
  });
}
