import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marina_hotel_mobile/services/auth_local_store.dart';
import 'package:marina_hotel_mobile/services/password_hasher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryAuthAccountCache cache;
  late Map<String, Map<String, dynamic>> onlineAccounts;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = _MemoryAuthAccountCache();
    onlineAccounts = {
      'frontdesk': {
        'password': PasswordHasher.hash('secret-pass'),
        'full_name': 'موظف الاستقبال',
        'user_type': 'employee',
        'id': 12,
        'cloud_user_id': 'cloud-user-12',
        'doc_id': 'cloud-user-12',
        'is_cloud': true,
        'permissions_json': '["dashboard","bookings"]',
        'active': true,
        'is_locked': false,
        'credentials_version': 7,
      },
    };
  });

  test('يسجل دخول الحساب السحابي من النسخة الآمنة عند فشل الاتصال', () async {
    final onlineStore = AuthLocalStore(
      accountCache: cache,
      cloudAccountsLoader: ({bool includeInactive = false}) async =>
          onlineAccounts,
    );
    await onlineStore.loadCloudAccounts();

    final offlineStore = AuthLocalStore(
      accountCache: cache,
      cloudAccountsLoader: ({bool includeInactive = false}) async {
        throw const SocketException('offline');
      },
    );
    final user = await offlineStore.validateCredentials(
      'frontdesk',
      'secret-pass',
    );

    expect(user, isNotNull);
    expect(user!['username'], 'frontdesk');
    expect(user['permissions'], ['dashboard', 'bookings']);
    expect(await offlineStore.getCredentialsVersion(), 7);
  });

  test('لا يبقي الحساب المعطّل في النسخة المحلية المشفّرة', () async {
    onlineAccounts['frontdesk']!['active'] = false;
    final onlineStore = AuthLocalStore(
      accountCache: cache,
      cloudAccountsLoader: ({bool includeInactive = false}) async =>
          onlineAccounts,
    );
    await onlineStore.loadCloudAccounts(includeInactive: true);

    final offlineStore = AuthLocalStore(
      accountCache: cache,
      cloudAccountsLoader: ({bool includeInactive = false}) async {
        throw const SocketException('offline');
      },
    );
    expect(
      await offlineStore.validateCredentials('frontdesk', 'secret-pass'),
      isNull,
    );
  });

  test('تحديث سحابي ناجح بلا حسابات يمسح الحسابات القديمة من النسخة', () async {
    final firstOnlineStore = AuthLocalStore(
      accountCache: cache,
      cloudAccountsLoader: ({bool includeInactive = false}) async =>
          onlineAccounts,
    );
    await firstOnlineStore.loadCloudAccounts();

    final refreshedOnlineStore = AuthLocalStore(
      accountCache: cache,
      cloudAccountsLoader: ({bool includeInactive = false}) async => {},
    );
    await refreshedOnlineStore.loadCloudAccounts();

    final offlineStore = AuthLocalStore(
      accountCache: cache,
      cloudAccountsLoader: ({bool includeInactive = false}) async {
        throw const SocketException('offline');
      },
    );
    expect(
      await offlineStore.validateCredentials('frontdesk', 'secret-pass'),
      isNull,
    );
  });
}

class _MemoryAuthAccountCache implements AuthAccountCache {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}
