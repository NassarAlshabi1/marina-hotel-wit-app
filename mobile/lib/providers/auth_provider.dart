import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

class AuthState {
  final bool isAuthenticated;
  final String? error;
  const AuthState(this.isAuthenticated, {this.error});
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState(false));

  Future<void> login(String username, String password) async {
    final ok = await ApiService.I.login(username, password);
    if (ok) {
      state = const AuthState(true);
    } else {
      state = const AuthState(false, error: 'بيانات الدخول غير صحيحة');
    }
  }

  Future<void> logout() async {
    await ApiService.I.logout();
    state = const AuthState(false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());
