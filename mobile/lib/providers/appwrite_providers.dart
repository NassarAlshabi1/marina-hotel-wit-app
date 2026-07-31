import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/cloudflare_sync_manager.dart';

final appwriteSyncManagerProvider = Provider<CloudflareSyncManager>((ref) {
  return CloudflareSyncManager();
});
