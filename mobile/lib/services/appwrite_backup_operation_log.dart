/// سجل عملية رفع/سحب لنقطة نهاية احتياطية
class BackupOperationLog {
  BackupOperationLog({
    required this.id,
    required this.endpointId,
    required this.endpointName,
    required this.operationType,
    required this.timestamp,
    required this.stats,
    required this.success,
    this.errorMessage,
  });

  BackupOperationLog.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        endpointId = json['endpointId'] as String,
        endpointName = json['endpointName'] as String,
        operationType = json['operationType'] as String,
        timestamp = DateTime.parse(json['timestamp'] as String),
        stats = Map<String, int>.from(json['stats'] as Map),
        success = json['success'] as bool,
        errorMessage = json['errorMessage'] as String?;

  final String id;
  final String endpointId;
  final String endpointName;
  final String operationType; // 'push' or 'pull'
  final DateTime timestamp;
  final Map<String, int> stats;
  final bool success;
  final String? errorMessage;

  int get totalRecords {
    final errorCount = stats['errors'] ?? 0;
    final total = stats.values.fold<int>(0, (sum, v) => sum + v);
    return total - errorCount;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'endpointId': endpointId,
    'endpointName': endpointName,
    'operationType': operationType,
    'timestamp': timestamp.toIso8601String(),
    'stats': stats,
    'success': success,
    'errorMessage': errorMessage,
  };
}
