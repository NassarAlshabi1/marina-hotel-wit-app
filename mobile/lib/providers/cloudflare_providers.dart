import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/appwrite_sync_manager.dart';

final cloudflareSyncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  return AppwriteSyncManager();
});
