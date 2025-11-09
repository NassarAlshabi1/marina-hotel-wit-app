import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ditto_cloud_sync_service.dart';

/// Provider لخدمة Ditto Cloud Sync
final dittoCloudSyncProvider = Provider<DittoCloudSyncService>((ref) {
  return DittoCloudSyncService.instance;
});

/// Provider لحالة المزامنة
final dittoSyncStatusProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final dittoService = ref.watch(dittoCloudSyncProvider);
  return await dittoService.getSyncStatus();
});

/// Provider للحجوزات الحالية من Ditto
final dittoBookingsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dittoService = ref.watch(dittoCloudSyncProvider);
  return await dittoService.getCurrentBookings();
});

/// Provider لحالة الغرف من Ditto
final dittoRoomsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dittoService = ref.watch(dittoCloudSyncProvider);
  return await dittoService.getRoomsStatus();
});

/// Provider للحجوزات في الوقت الفعلي (Stream)
final dittoLiveBookingsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final dittoService = ref.watch(dittoCloudSyncProvider);
  return dittoService.watchBookings();
});