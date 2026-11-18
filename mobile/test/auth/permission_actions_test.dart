import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/auth_provider.dart';

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

  test(
    'explicit update permission grants editing without granting deletion',
    () {
      for (final module in ['expenses', 'rooms', 'inventory', 'bookings']) {
        final user = AuthUser(
          id: 20,
          username: 'editor',
          fullName: 'مستخدم تعديل',
          userType: 'employee',
          permissions: ['$module.update'],
        );

        expect(user.canAccessModule(module), isTrue);
        expect(
          user.canPerform(module, 'update'),
          isTrue,
          reason: 'يجب أن تعمل صلاحية $module.update التي فُعّلت صراحةً',
        );
        expect(user.canPerform(module, 'delete'), isFalse);
      }
    },
  );

  test('view-only permission allows access and create but not mutations', () {
    // العرض والإضافة متاحان لدخول الوحدة؛ ومفتاح العرض وحده لا يمنح
    // التعديل أو الحذف ما لم يكن الدور إدارياً أو يُمنح الفعل صراحةً.
    const user = AuthUser(
      id: 12,
      username: 'viewer',
      fullName: 'مستخدم عرض',
      userType: 'employee',
      permissions: ['inventory.view'],
    );

    expect(user.canAccessModule('inventory'), isTrue);
    expect(user.canPerform('inventory', 'view'), isTrue);
    expect(user.canPerform('inventory', 'create'), isTrue);
    expect(user.canPerform('inventory', 'update'), isFalse);
    expect(user.canPerform('inventory', 'delete'), isFalse);
  });

  test('admin and all permissions retain full access', () {
    const admin = AuthUser(
      id: 13,
      username: 'admin-user',
      fullName: 'مدير النظام',
      userType: 'admin',
      permissions: const [],
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

  test(
    'legacy module permissions remain backward compatible for access and create',
    () {
      // مفتاح الوحدة القديم يمنح دخول الوحدة والإضافة كما كان، لكنه لا يمنح
      // التعديل أو الحذف وحده؛ يلزم الدور الإداري أو المفتاح الدقيق للفعل.
      const user = AuthUser(
        id: 11,
        username: 'legacy-user',
        fullName: 'مستخدم سابق',
        userType: 'employee',
        permissions: ['inventory'],
      );

      expect(user.canAccessModule('inventory'), isTrue);
      expect(user.canPerform('inventory', 'create'), isTrue);
      expect(user.canPerform('inventory', 'update'), isFalse);
      expect(user.canPerform('inventory', 'delete'), isFalse);
    },
  );
}
