// ═══════════════════════════════════════════════════════════════
//  cloudflare_providers.dart — Riverpod Providers for Cloudflare
//  Replaces appwrite_providers.dart
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cloudflare_sync_manager.dart';

final cloudflareSyncManagerProvider = Provider<CloudflareSyncManager>((ref) {
  return CloudflareSyncManager();
});

final cloudflareSyncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final manager = ref.watch(cloudflareSyncManagerProvider);
  // Emit current status periodically
  yield manager.currentStatus;
  await Future.delayed(const Duration(seconds: 1));
  yield manager.currentStatus;
});
