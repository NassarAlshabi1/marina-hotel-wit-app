import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/smart_sync_manager.dart' show SmartSyncManager;
import 'backup_provider.dart';

// ═══════════════════════════════════════════════════════════════════
// ⚠️ Smart Sync (Google Drive) is DISABLED
// All providers below return safe defaults indicating disabled state.
// SmartSyncManager.initialize() is never called, so no sync timers
// or monitoring will start. Manual backup/restore still works.
// ═══════════════════════════════════════════════════════════════════

/// [DISABLED] Returns the SmartSyncManager instance (never initialized).
final smartSyncManagerProvider = Provider<SmartSyncManager>((ref) {
  return SmartSyncManager.instance;
});

/// [DISABLED] Always returns disabled status — never triggers sync.
final smartSyncStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      // Return disabled status so all UI widgets that watch this
      // will render themselves invisible / no-op.
      return {
        'enabled': false,
        'is_syncing': false,
        'signed_in': false,
        'sync_interval_minutes': 0,
        'last_sync_check': null,
        'device_id': null,
        'conflict_resolution': 'newerWins',
        'monitoring_active': false,
      };
    });

/// [DISABLED] Always returns false — no Google Drive sign-in via smart sync.
final smartSyncGoogleDriveSignInStatusProvider = Provider<bool>((ref) {
  final backupState = ref.watch(backupStatusProvider);
  return backupState.signedInAccount != null;
});

/// [DISABLED] Never initializes SmartSyncManager.
/// Previously this would call manager.initialize(backupService) when
/// signed in, which would start sync monitoring timers. Now it's a no-op.
final smartSyncInitProvider = FutureProvider<void>((ref) async {
  // ⚠️ Smart Sync initialization is DISABLED.
  // Do NOT call SmartSyncManager.initialize() — it would start
  // sync monitoring timers that should not run.
  // Manual backup/restore is handled by GoogleDriveBackupService directly.
});
