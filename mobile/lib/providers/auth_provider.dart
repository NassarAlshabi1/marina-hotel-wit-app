import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class AuthUser {
  final int id;
  final String username;
  final String fullName;
  final String userType;
  final List<String> permissions;

  const AuthUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.userType,
    this.permissions = const [],
  });

  String get name => fullName.isNotEmpty ? fullName : username;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawPerms = json['permissions'];
    final idValue = json['id'] ?? json['user_id'];
    final int parsedId;
    if (idValue is int) {
      parsedId = idValue;
    } else if (idValue is String) {
      parsedId = int.tryParse(idValue) ?? 0;
    } else {
      parsedId = 0;
    }
    return AuthUser(
      id: parsedId,
      username: (json['username'] ?? '').toString(),
      fullName: (json['full_name'] ?? json['name'] ?? '').toString(),
      userType: (json['user_type'] ?? '').toString(),
      permissions: rawPerms is List
          ? rawPerms.map((e) => e.toString()).toList()
          : const <String>[],
    );
  }
}

class AuthState {
  final bool isAuthenticated;
  final String? error;
  final AuthUser? currentUser;
  const AuthState(this.isAuthenticated, {this.error, this.currentUser});
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(true, currentUser: _defaultUser));

  static const AuthUser _defaultUser = AuthUser(
    id: 0,
    username: 'admin',
    fullName: 'مدير النظام',
    userType: 'admin',
    permissions: const ['all'],
  );

  Future<void> login(String username, String password) async {
    try {
      final userData = await ApiService.I.login(username, password);
      if (userData != null) {
        final user = AuthUser.fromJson(userData);
        state = AuthState(true, currentUser: user);
      } else {
        state = const AuthState(true, currentUser: _defaultUser, error: 'بيانات الدخول غير صحيحة');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        state = const AuthState(true, currentUser: _defaultUser, error: 'بيانات الدخول غير صحيحة');
        return;
      }
      state = AuthState(true, currentUser: _defaultUser, error: _errorMessage(e));
    } catch (_) {
      state = const AuthState(true, currentUser: _defaultUser, error: 'حدث خطأ غير متوقع');
    }
  }

  Future<void> logout() async {
    await ApiService.I.logout();
    state = const AuthState(true, currentUser: _defaultUser);
  }

  String _errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is String) {
      return data['error'] as String;
    }
    if (e.message != null && e.message!.isNotEmpty) {
      return e.message!;
    }
    return 'تعذر الاتصال بالخادم';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
