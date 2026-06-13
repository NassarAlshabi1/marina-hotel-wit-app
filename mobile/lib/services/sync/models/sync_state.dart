/// حالات المزامنة الممكنة
enum SyncStatus {
  idle,
  syncing,
  error,
  disabled,
  offline,
}

/// أولوية المزامنة
enum SyncPriority {
  low,
  normal,
  high,
  critical,
}

/// نموذج حالة المزامنة
class SyncState {
  const SyncState({
    required this.status,
    this.progress = 0,
    this.message,
    this.lastSyncTime,
    this.pendingChanges = 0,
    this.error,
  });

  factory SyncState.idle() => const SyncState(status: SyncStatus.idle);

  factory SyncState.syncing({
    int progress = 0,
    String? message,
  }) =>
      SyncState(
        status: SyncStatus.syncing,
        progress: progress,
        message: message,
      );

  factory SyncState.error(String error) => SyncState(
        status: SyncStatus.error,
        error: error,
      );

  factory SyncState.offline() => const SyncState(status: SyncStatus.offline);

  factory SyncState.disabled() => const SyncState(status: SyncStatus.disabled);

  final SyncStatus status;
  final int progress;
  final String? message;
  final DateTime? lastSyncTime;
  final int pendingChanges;
  final String? error;

  bool get isIdle => status == SyncStatus.idle;
  bool get isSyncing => status == SyncStatus.syncing;
  bool get hasError => status == SyncStatus.error;
  bool get isOffline => status == SyncStatus.offline;
  bool get isDisabled => status == SyncStatus.disabled;

  SyncState copyWith({
    SyncStatus? status,
    int? progress,
    String? message,
    DateTime? lastSyncTime,
    int? pendingChanges,
    String? error,
  }) {
    return SyncState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingChanges: pendingChanges ?? this.pendingChanges,
      error: error ?? this.error,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncState &&
          status == other.status &&
          progress == other.progress &&
          message == other.message &&
          lastSyncTime == other.lastSyncTime &&
          pendingChanges == other.pendingChanges &&
          error == other.error;

  @override
  int get hashCode =>
      status.hashCode ^
      progress.hashCode ^
      message.hashCode ^
      lastSyncTime.hashCode ^
      pendingChanges.hashCode ^
      error.hashCode;

  @override
  String toString() =>
      'SyncState(status: $status, progress: $progress, message: $message, lastSyncTime: $lastSyncTime, pendingChanges: $pendingChanges, error: $error)';
}

/// إعدادات المزامنة
class SyncSettings {
  const SyncSettings({
    this.autoSyncEnabled = true,
    this.syncIntervalMinutes = 5,
    this.syncOnWifiOnly = true,
    this.compressData = true,
    this.defaultPriority = SyncPriority.normal,
  });

  factory SyncSettings.fromJson(Map<String, dynamic> json) {
    return SyncSettings(
      autoSyncEnabled: json['autoSyncEnabled'] as bool? ?? true,
      syncIntervalMinutes: json['syncIntervalMinutes'] as int? ?? 5,
      syncOnWifiOnly: json['syncOnWifiOnly'] as bool? ?? true,
      compressData: json['compressData'] as bool? ?? true,
      defaultPriority: SyncPriority.values.firstWhere(
        (e) => e.name == json['defaultPriority'],
        orElse: () => SyncPriority.normal,
      ),
    );
  }

  final bool autoSyncEnabled;
  final int syncIntervalMinutes;
  final bool syncOnWifiOnly;
  final bool compressData;
  final SyncPriority defaultPriority;

  SyncSettings copyWith({
    bool? autoSyncEnabled,
    int? syncIntervalMinutes,
    bool? syncOnWifiOnly,
    bool? compressData,
    SyncPriority? defaultPriority,
  }) {
    return SyncSettings(
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      syncIntervalMinutes: syncIntervalMinutes ?? this.syncIntervalMinutes,
      syncOnWifiOnly: syncOnWifiOnly ?? this.syncOnWifiOnly,
      compressData: compressData ?? this.compressData,
      defaultPriority: defaultPriority ?? this.defaultPriority,
    );
  }

  Map<String, dynamic> toJson() => {
        'autoSyncEnabled': autoSyncEnabled,
        'syncIntervalMinutes': syncIntervalMinutes,
        'syncOnWifiOnly': syncOnWifiOnly,
        'compressData': compressData,
        'defaultPriority': defaultPriority.name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncSettings &&
          autoSyncEnabled == other.autoSyncEnabled &&
          syncIntervalMinutes == other.syncIntervalMinutes &&
          syncOnWifiOnly == other.syncOnWifiOnly &&
          compressData == other.compressData &&
          defaultPriority == other.defaultPriority;

  @override
  int get hashCode =>
      autoSyncEnabled.hashCode ^
      syncIntervalMinutes.hashCode ^
      syncOnWifiOnly.hashCode ^
      compressData.hashCode ^
      defaultPriority.hashCode;

  @override
  String toString() =>
      'SyncSettings(autoSyncEnabled: $autoSyncEnabled, syncIntervalMinutes: $syncIntervalMinutes, syncOnWifiOnly: $syncOnWifiOnly, compressData: $compressData, defaultPriority: $defaultPriority)';
}
