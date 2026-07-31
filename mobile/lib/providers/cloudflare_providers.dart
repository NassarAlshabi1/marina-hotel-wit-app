import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/appwrite_sync_manager.dart';
import '../services/sync_enums.dart';

final cloudflareSyncManagerProvider = Provider<AppwriteSyncManager>((ref) {
  return AppwriteSyncManager();
});
