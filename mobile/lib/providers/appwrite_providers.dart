import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/appwrite_sync_manager.dart';

// Backward-compatible provider name (replaces appwriteSyncManagerProvider)
final appwriteSyncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  return AppwriteSyncManager();
});

// Stub providers for backward compat with screens that still reference them
final appwriteServiceProvider = Provider<dynamic>((ref) => null);
final appwriteLoggerProvider = Provider<dynamic>((ref) => null);
final connectionStatusProvider = StreamProvider<bool>((ref) async* {
  yield true;
});
