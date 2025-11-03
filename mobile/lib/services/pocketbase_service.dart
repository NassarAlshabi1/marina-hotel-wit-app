import 'package:pocketbase/pocketbase.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/env.dart';

class PocketBaseService {
  static final PocketBaseService I = PocketBaseService._internal();

  PocketBaseService._internal() {
    _pb = PocketBase(Env.pocketbaseUrl);
  }

  late final PocketBase _pb;
  static const _storage = FlutterSecureStorage();
  static const _kAuthToken = 'pb_auth_token';
  static const _kAuthModel = 'pb_auth_model';

  PocketBase get client => _pb;

  Future<bool> login(String email, String password) async {
    try {
      final authData = await _pb.collection('users').authWithPassword(email, password);
      await _storage.write(key: _kAuthToken, value: authData.token);
      await _storage.write(key: _kAuthModel, value: authData.record?.id ?? '');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> restoreAuth() async {
    try {
      final token = await _storage.read(key: _kAuthToken);
      if (token != null && token.isNotEmpty) {
        _pb.authStore.save(token, null);
        try {
          await _pb.collection('users').authRefresh();
          return true;
        } catch (_) {
          await _storage.delete(key: _kAuthToken);
          await _storage.delete(key: _kAuthModel);
          return false;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _pb.authStore.clear();
    await _storage.delete(key: _kAuthToken);
    await _storage.delete(key: _kAuthModel);
  }

  Future<bool> isAuthenticated() async {
    return _pb.authStore.isValid;
  }
}
