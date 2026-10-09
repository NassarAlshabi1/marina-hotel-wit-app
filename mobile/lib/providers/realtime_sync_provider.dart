// lib/providers/realtime_sync_provider.dart
// مزود Riverpod لـ AppwriteRealtimeSync

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/appwrite_realtime_sync.dart';

/// مزود مزامنة Appwrite Realtime (Singleton)
final appwriteRealtimeSyncProvider = Provider<AppwriteRealtimeSync>((ref) {
  final sync = AppwriteRealtimeSync();

  // تهيئة الجهاز ID
  ref.onDispose(() {
    // لا نريد استدعاء dispose() هنا لأن الـ singleton يشارك في التطبيق كله
  });

  return sync;
});

/// مزود حالة الاتصال بالـ Realtime
final realtimeSyncStateProvider = Provider<RealtimeSyncState>((ref) {
  final sync = ref.watch(appwriteRealtimeSyncProvider);
  return RealtimeSyncState(
    isListening: sync.isListening,
    hasRemoteChanges: sync.hasRemoteChanges.value,
    pendingRemoteChangesCount: sync.pendingRemoteChangesCount.value,
  );
});

/// مزود Stream للتغييرات المعلقة
final pendingRemoteChangesProvider = StreamProvider<int>((ref) {
  final sync = ref.watch(appwriteRealtimeSyncProvider);
  final notifier = sync.pendingRemoteChangesCount;
  final controller = StreamController<int>.broadcast();
  void onChanged() => controller.add(notifier.value);
  controller.add(notifier.value);
  notifier.addListener(onChanged);
  ref.onDispose(() {
    notifier.removeListener(onChanged);
    unawaited(controller.close());
  });
  return controller.stream;
});

/// مزود Stream للتغييرات من السيرفر
final hasRemoteChangesProvider = StreamProvider<bool>((ref) {
  final sync = ref.watch(appwriteRealtimeSyncProvider);
  final notifier = sync.hasRemoteChanges;
  final controller = StreamController<bool>.broadcast();
  void onChanged() => controller.add(notifier.value);
  controller.add(notifier.value);
  notifier.addListener(onChanged);
  ref.onDispose(() {
    notifier.removeListener(onChanged);
    unawaited(controller.close());
  });
  return controller.stream;
});

/// حالة مزامنة Realtime للـ UI
class RealtimeSyncState {
  RealtimeSyncState({
    required this.isListening,
    required this.hasRemoteChanges,
    required this.pendingRemoteChangesCount,
  });

  final bool isListening;
  final bool hasRemoteChanges;
  final int pendingRemoteChangesCount;
}
