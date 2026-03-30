import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/smart_initializers/delta_sync_initializer.dart';
import '../../services/smart_initializers/network_monitor.dart';
import 'delta_sync_init_state.dart';

/// Provider لحالة تهيئة Delta Sync.
///
/// يُحدَّث من [DeltaSyncInitializer] عند تغيير الحالة.
final deltaSyncInitStateProvider = StateProvider<DeltaSyncInitState>((ref) {
  return DeltaSyncInitState.idle;
});

/// Provider يُرجع [true] إذا كانت تهيئة Delta Sync مكتملة.
final isDeltaSyncReadyProvider = Provider<bool>((ref) {
  final state = ref.watch(deltaSyncInitStateProvider);
  return state == DeltaSyncInitState.ready;
});

/// Provider لحالة الشبكة الحالية.
final networkStateProvider = Provider<NetworkState>((ref) {
  return NetworkMonitor.instance.currentState;
});

/// يربط [DeltaSyncInitializer.stateStream] بـ [deltaSyncInitStateProvider].
///
/// يُستدعى مرة واحدة من initState في App أو من main.
/// يعيد [StreamSubscription] للتنظيف عند الـ dispose.
StreamSubscription<DeltaSyncInitState> bindSmartInitToProviders(
  Ref<Object?> ref,
) {
  final initializer = DeltaSyncInitializer.instance;

  // تحديث الحالة الحالية فوراً
  ref.read(deltaSyncInitStateProvider.notifier).state =
      initializer.currentState;

  // الاستماع للتغييرات — لا نحتاج mounted check لأن
  // StreamController يُغلق عند dispose والاشتراك يُلغى خارجياً.
  final subscription = initializer.stateStream.listen((
    DeltaSyncInitState state,
  ) {
    // استخدم try-catch لأن Ref قد يصبح unmounted
    try {
      ref.read(deltaSyncInitStateProvider.notifier).state = state;
    } catch (_) {
      // Ref غير mounted — تجاهل
    }
  });

  return subscription;
}
