enum BackupFormat { json, sqlite }

class BackupMetadata {
  BackupMetadata({
    required this.appVersion,
    required this.databaseVersion,
    required this.backupTimestamp,
    required this.totalRecords,
    required this.deviceInfo,
    this.format = BackupFormat.json,
  });

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    final rawFormat = json['format'] as String?;
    final format = BackupFormat.values.firstWhere(
      (value) => value.name == rawFormat,
      orElse: () => BackupFormat.json,
    );
    return BackupMetadata(
      appVersion: json['app_version'] as String? ?? '',
      databaseVersion: (json['database_version'] as num?)?.toInt() ?? 1,
      backupTimestamp: DateTime.parse(
        (json['backup_timestamp'] as String?) ?? DateTime.now().toIso8601String(),
      ),
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      deviceInfo: json['device_info'] as String? ?? '',
      format: format,
    );
  }
  final String appVersion;
  final int databaseVersion;
  final DateTime backupTimestamp;
  final int totalRecords;
  final String deviceInfo;
  final BackupFormat format;

  Map<String, dynamic> toJson() => {
    'app_version': appVersion,
    'database_version': databaseVersion,
    'backup_timestamp': backupTimestamp.toIso8601String(),
    'total_records': totalRecords,
    'device_info': deviceInfo,
    'format': format.name,
  };
}
