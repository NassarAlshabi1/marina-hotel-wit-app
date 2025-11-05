import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import '../services/auth_local_store.dart';
import '../utils/supabase_config.dart';
import '../utils/env.dart';

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

  bool get isAdmin => userType == 'admin' || permissions.contains('all');

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'full_name': fullName,
        'user_type': userType,
        'permissions': permissions,
      };

  AuthUser copyWith({
    List<String>? permissions,
  }) {
    return AuthUser(
      id: id,
      username: username,
      fullName: fullName,
      userType: userType,
      permissions: permissions ?? this.permissions,
    );
  }
}

class AuthState {
  final bool isAuthenticated;
  final bool isRestoring;
  final String? error;
  final AuthUser? currentUser;
  const AuthState({
    required this.isAuthenticated,
    this.isRestoring = false,
    this.error,
    this.currentUser,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isRestoring,
    String? error,
    AuthUser? currentUser,
  }) => AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isRestoring: isRestoring ?? this.isRestoring,
        error: error,
        currentUser: currentUser ?? this.currentUser,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(isAuthenticated: false, isRestoring: true)) {
    restoreSession();
  }

  final _store = AuthLocalStore();

  Future<void> restoreSession() async {
    state = state.copyWith(isRestoring: true, error: null);
    final json = await _store.loadCurrentUser();
    if (json == null) {
      state = const AuthState(isAuthenticated: false, isRestoring: false);
      return;
    }
    final user = AuthUser.fromJson(json);
    state = AuthState(isAuthenticated: true, isRestoring: false, currentUser: user);

    try {
      if (!SupabaseConfig.isLoggedIn &&
          Env.supabaseLoginEmail.isNotEmpty &&
          Env.supabaseLoginPassword.isNotEmpty) {
        await SupabaseConfig.signInWithEmail(
          email: Env.supabaseLoginEmail,
          password: Env.supabaseLoginPassword,
        );
        debugPrint('✅ Supabase session restored after local session');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to restore Supabase session: $e');
    }
  }

  Future<void> login(String username, String password) async {
    state = state.copyWith(error: null);
    final data = await _store.validateCredentials(username, password);
    if (data == null) {
      state = AuthState(isAuthenticated: false, isRestoring: false, error: 'اسم المستخدم أو كلمة المرور غير صحيحة');
      return;
    }
    final user = AuthUser.fromJson(data);
    await _store.saveCurrentUser(user.toJson());
    state = AuthState(isAuthenticated: true, isRestoring: false, currentUser: user);

    // Link to Supabase session for sync
    try {
      if (!SupabaseConfig.isLoggedIn &&
          Env.supabaseLoginEmail.isNotEmpty &&
          Env.supabaseLoginPassword.isNotEmpty) {
        await SupabaseConfig.signInWithEmail(
          email: Env.supabaseLoginEmail,
          password: Env.supabaseLoginPassword,
        );
        debugPrint('✅ Supabase sign-in completed after app login');
      }
    } catch (e) {
      debugPrint('⚠️ Supabase sign-in failed after app login: $e');
    }
  }

  Future<void> logout() async {
    await _store.clearSession();
    try {
      await SupabaseConfig.signOut();
    } catch (e) {
      debugPrint('⚠️ Supabase sign-out failed: $e');
    }
    state = const AuthState(isAuthenticated: false, isRestoring: false);
  }

  Future<void> updateUserPermissions(String username, List<String> permissions) async {
    await _store.setPermissions(username, permissions);
    if (state.currentUser != null && state.currentUser!.username == username) {
      final updated = state.currentUser!.copyWith(permissions: username == 'admin' ? ['all'] : permissions);
      await _store.saveCurrentUser(updated.toJson());
      state = state.copyWith(currentUser: updated);
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());