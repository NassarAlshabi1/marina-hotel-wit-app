import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync_core/sync_backend.dart';

final syncBackendManagerProvider = Provider<SyncBackendManager>((ref) {
  return SyncBackendManager.instance;
});

final activeSyncBackendProvider = Provider<SyncBackend?>((ref) {
  final manager = ref.watch(syncBackendManagerProvider);
  return manager.activeOrNull;
});
