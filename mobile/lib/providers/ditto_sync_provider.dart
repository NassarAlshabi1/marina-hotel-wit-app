import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ditto_local_sync_service.dart';

final dittoSyncServiceProvider = Provider<DittoLocalSyncService>((ref) {
  return DittoLocalSyncService();
});

final dittoAutoSyncStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  final service = ref.watch(dittoSyncServiceProvider);
  return service.isAutoSyncEnabled();
});
