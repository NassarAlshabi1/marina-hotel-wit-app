/// نموذج نقطة نهاية Appwrite احتياطية (Slave)
class BackupEndpoint {
  final String id;
  final String name;
  final String endpoint;
  final String projectId;
  final String databaseId;
  final String apiKey;
  final bool isActive;
  final DateTime createdAt;

  BackupEndpoint({
    required this.id,
    required this.name,
    required this.endpoint,
    required this.projectId,
    required this.databaseId,
    required this.apiKey,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'projectId': projectId,
    'databaseId': databaseId,
    'apiKey': apiKey,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
  };

  factory BackupEndpoint.fromJson(Map<String, dynamic> json) => BackupEndpoint(
    id: json['id'] as String,
    name: json['name'] as String,
    endpoint: json['endpoint'] as String,
    projectId: json['projectId'] as String,
    databaseId: json['databaseId'] as String,
    apiKey: json['apiKey'] as String,
    isActive: json['isActive'] as bool? ?? true,
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String)
        : null,
  );

  BackupEndpoint copyWith({
    String? id,
    String? name,
    String? endpoint,
    String? projectId,
    String? databaseId,
    String? apiKey,
    bool? isActive,
  }) => BackupEndpoint(
    id: id ?? this.id,
    name: name ?? this.name,
    endpoint: endpoint ?? this.endpoint,
    projectId: projectId ?? this.projectId,
    databaseId: databaseId ?? this.databaseId,
    apiKey: apiKey ?? this.apiKey,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
  );
}
