// lib/providers/sync_providers.dart
// مزودات Riverpod لخدمات المزامنة العامة

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync/sync_gate.dart';
import '../services/sync/sync_constants.dart';

/// مزود بوابة المزامنة العامة (Singleton)
final syncGateProvider = Provider<SyncGate>((ref) {
  return SyncGate.instance;
});

/// مزود حالة بوابة المزامنة كـ Stream
final syncGateStateProvider = StreamProvider<SyncGateState>((ref) {
  final gate = ref.watch(syncGateProvider);
  return gate.notifier.stream;
});

/// مزود ما إذا كانت المزامنة مشغولة
final syncIsBusyProvider = Provider<bool>((ref) {
  final gate = ref.watch(syncGateProvider);
  return gate.isBusy;
});

/// مزود ثوابت المزامنة
final syncConstantsProvider = Provider<SyncConstants>((ref) {
  return SyncConstants.instance;
});

/// مزود مفتاح SharedPreferences لآخر سحب تلقائي
final lastAppOpenPullKeyProvider = Provider<String>((ref) {
  return SyncConstants.lastAppOpenPullKey;
});

/// مزود فاصل المزامنة التلقائية عند الفتح
final appOpenSyncIntervalProvider = Provider<Duration>((ref) {
  return SyncConstants.appOpenSyncInterval;
});
