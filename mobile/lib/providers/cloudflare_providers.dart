import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/cloudflare_sync_manager.dart';
import '../services/sync_enums.dart';

final cloudflareSyncManagerProvider = Provider<CloudflareSyncManager>((ref) {
  return CloudflareSyncManager();
});
