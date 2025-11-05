import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_local_store.dart';
import '../utils/supabase_config.dart';
import '../utils/env.dart';

export 'package:marina_hotel_wit_app/services/auth_local_store.dart' show AuthType;

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
  final bool rememberMe;
  final AuthType authType;
  final bool isSupabaseConnected;
  
  const AuthState({
    required this.isAuthenticated,
    this.isRestoring = false,
    this.error,
    this.currentUser,
    this.rememberMe = false,
    this.authType = AuthType.local,
    this.isSupabaseConnected = false,
  });

  AuthState copyWith({
    bool? isAuthenticated,
    bool? isRestoring,
    String? error,
    AuthUser? currentUser,
    bool? rememberMe,
    AuthType? authType,
    bool? isSupabaseConnected,
  }) => AuthState(
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        isRestoring: isRestoring ?? this.isRestoring,
        error: error,
        currentUser: currentUser ?? this.currentUser,
        rememberMe: rememberMe ?? this.rememberMe,
        authType: authType ?? this.authType,
        isSupabaseConnected: isSupabaseConnected ?? this.isSupabaseConnected,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(isAuthenticated: false, isRestoring: true)) {
    restoreSession();
  }

  final _store = AuthLocalStore();

  Future<void> restoreSession() async {
    state = state.copyWith(isRestoring: true, error: null);
    
    final rememberMe = await _store.getRememberMe();
    if (!rememberMe) {
      state = const AuthState(isAuthenticated: false, isRestoring: false);
      return;
    }
    
    final json = await _store.loadCurrentUser();
    if (json == null) {
      state = const AuthState(isAuthenticated: false, isRestoring: false);
      return;
    }
    
    final user = AuthUser.fromJson(json);
    final authType = await _store.getAuthType();
    
    bool supabaseConnected = false;
    try {
      final sessionString = await _store.loadSupabaseSession();
      if (sessionString != null && sessionString.isNotEmpty) {
        await SupabaseConfig.client.auth.recoverSession(sessionString);
        
        if (SupabaseConfig.isLoggedIn) {
          supabaseConnected = true;
          debugPrint('✅ تم استعادة جلسة Supabase');
        }
      }
    } catch (e) {
      debugPrint('⚠️ فشلت استعادة جلسة Supabase: $e');
    }
    
    state = AuthState(
      isAuthenticated: true,
      isRestoring: false,
      currentUser: user,
      rememberMe: rememberMe,
      authType: authType,
      isSupabaseConnected: supabaseConnected,
    );
  }

  Future<void> login(String username, String password, {bool rememberMe = false}) async {
    state = state.copyWith(error: null);
    
    final data = await _store.validateCredentials(username, password);
    if (data == null) {
      state = AuthState(
        isAuthenticated: false,
        isRestoring: false,
        error: 'اسم المستخدم أو كلمة المرور غير صحيحة',
      );
      return;
    }
    
    final user = AuthUser.fromJson(data);
    await _store.saveCurrentUser(user.toJson());
    await _store.setRememberMe(rememberMe);
    await _store.setAuthType(AuthType.local);
    
    state = AuthState(
      isAuthenticated: true,
      isRestoring: false,
      currentUser: user,
      rememberMe: rememberMe,
      authType: AuthType.local,
    );

    bool supabaseConnected = false;
    try {
      if (Env.supabaseLoginEmail.isNotEmpty && Env.supabaseLoginPassword.isNotEmpty) {
        await SupabaseConfig.signInWithEmail(
          email: Env.supabaseLoginEmail,
          password: Env.supabaseLoginPassword,
        );
        
        final session = SupabaseConfig.client.auth.currentSession;
        if (session != null) {
          await _store.saveSupabaseSession(session.persistSessionString);
          await _store.setAuthType(AuthType.hybrid);
          supabaseConnected = true;
          debugPrint('✅ Supabase تم الاتصال بـ');
        }
      }
    } catch (e) {
      debugPrint('⚠️ فشل الاتصال بـ Supabase: $e');
    }
    
    state = state.copyWith(
      isSupabaseConnected: supabaseConnected,
      authType: supabaseConnected ? AuthType.hybrid : AuthType.local,
    );
  }

  Future<void> logout() async {
    await _store.clearSession();
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

  Future<bool> checkSupabaseConnection() async {
    try {
      final isConnected = await SupabaseConfig.testConnection();
      state = state.copyWith(isSupabaseConnected: isConnected);
      return isConnected;
    } catch (e) {
      debugPrint('❌ خطأ في فحص اتصال Supabase: $e');
      state = state.copyWith(isSupabaseConnected: false);
      return false;
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());