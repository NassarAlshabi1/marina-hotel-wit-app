/// نموذج نقطة نهاية Appwrite احتياطية (Slave)
class BackupEndpoint {
  BackupEndpoint({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.projectId,
    required this.databaseId,
    required this.apiKey,
    this.isActive = true,
    this.pushEnabled = true,
    this.pullEnabled = false,
    DateTime? createdAt,
    this.lastPushAt,
    this.lastPullAt,
  }) : createdAt = createdAt ?? DateTime.now();

  BackupEndpoint.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        endpoint = json['endpoint'] as String,
        projectId = json['projectId'] as String,
        databaseId = json['databaseId'] as String,
        apiKey = json['apiKey'] as String,
        isActive = json['isActive'] as bool? ?? true,
        pushEnabled = json['pushEnabled'] as bool? ?? true,
        pullEnabled = json['pullEnabled'] as bool? ?? false,
        createdAt = json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        lastPushAt = json['lastPushAt'] != null
            ? DateTime.tryParse(json['lastPushAt'] as String)
            : null,
        lastPullAt = json['lastPullAt'] != null
            ? DateTime.tryParse(json['lastPullAt'] as String)
            : null;

  BackupEndpoint copyWith({
    String? id,
    String? name,
    String? endpoint,
    String? projectId,
    String? databaseId,
    String? apiKey,
    bool? isActive,
    bool? pushEnabled,
    bool? pullEnabled,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    bool clearLastPushAt = false,
    bool clearLastPullAt = false,
  }) => BackupEndpoint(
    id: id ?? this.id,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    projectId: projectId ?? this.projectId,
    databaseId: databaseId ?? this.databaseId,
    apiKey: apiKey ?? this.apiKey,
    isActive: isActive ?? this.isActive,
    pushEnabled: pushEnabled ?? this.pushEnabled,
    pullEnabled: pullEnabled ?? this.pullEnabled,
    createdAt: createdAt,
    lastPushAt: clearLastPushAt ? null : (lastPushAt ?? this.lastPushAt),
    lastPullAt: clearLastPullAt ? null : (lastPullAt ?? this.lastPullAt),
  );

  final String id;
  final String name;
  final String endpoint;
  final String projectId;
  final String databaseId;
  final String apiKey;
  final bool isActive;
  final bool pushEnabled;
  final bool pullEnabled;
  final DateTime createdAt;
  final DateTime? lastPushAt;
  final DateTime? lastPullAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'projectId': projectId,
    'databaseId': databaseId,
    'apiKey': apiKey,
    'isActive': isActive,
    'pushEnabled': pushEnabled,
    'pullEnabled': pullEnabled,
    'createdAt': createdAt.toIso8601String(),
    'lastPushAt': lastPushAt?.toIso8601String(),
    'lastPullAt': lastPullAt?.toIso8601String(),
  };
}
