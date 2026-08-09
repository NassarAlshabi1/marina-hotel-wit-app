import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/secondary_appwrite_config.dart';

/// حالة المزامنة الثانوية المعروضة في الواجهة
class SecondarySyncState {
  const SecondarySyncState({
    required this.isEnabled,
    required this.isPushEnabled,
    required this.isPullEnabled,
    required this.isConfigured,
    this.lastSync,
    this.pendingCount = 0,
  });

  final bool isEnabled;
  final bool isPushEnabled;
  final bool isPullEnabled;
  final bool isConfigured;
  final DateTime? lastSync;
  final int pendingCount;

  SecondarySyncState copyWith({
    bool? isEnabled,
    bool? isPushEnabled,
    bool? isPullEnabled,
    bool? isConfigured,
    DateTime? lastSync,
    int? pendingCount,
  }) {
    return SecondarySyncState(
      isEnabled: isEnabled ?? this.isEnabled,
      isPushEnabled: isPushEnabled ?? this.isPushEnabled,
      isPullEnabled: isPullEnabled ?? this.isPullEnabled,
      isConfigured: isConfigured ?? this.isConfigured,
      lastSync: lastSync ?? this.lastSync,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

/// Notifier يدير حالة المزامنة الثانوية
class SecondarySyncNotifier extends StateNotifier<SecondarySyncState> {
  SecondarySyncNotifier() : super(_loadInitialState());

  static SecondarySyncState _loadInitialState() {
    return SecondarySyncState(
      isEnabled: SecondaryAppwriteConfig.isEnabled,
      isPushEnabled: SecondaryAppwriteConfig.isPushEnabled,
      isPullEnabled: SecondaryAppwriteConfig.isPullEnabled,
      isConfigured: SecondaryAppwriteConfig.isConfigured,
      lastSync: SecondaryAppwriteConfig.lastSyncTime,
    );
  }

  /// تحديث الحالة من الإعدادات المحفوظة
  void refresh() {
    state = _loadInitialState();
  }

  /// تحديث وقت آخر مزامنة
  void updateLastSync(DateTime time) {
    state = state.copyWith(lastSync: time);
  }

  /// تحديث عدد السجلات غير المُسلّمة
  void updatePendingCount(int count) {
    state = state.copyWith(pendingCount: count);
  }
}

/// Provider لحالة المزامنة الثانوية
final secondarySyncProvider =
    StateNotifierProvider<SecondarySyncNotifier, SecondarySyncState>((ref) {
      return SecondarySyncNotifier();
    });
