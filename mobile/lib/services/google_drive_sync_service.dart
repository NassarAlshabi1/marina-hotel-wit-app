// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db.dart';

/// خيارات خدمة مزامنة Google Drive
class GoogleDriveSyncOptions {
  const GoogleDriveSyncOptions({
    required this.database,
    this.driveFileName = 'hotel_sync_snapshot.json.gz',
    this.syncFolder = 'appDataFolder',
    this.logFileName = 'drive_sync.log',
    this.pendingFileName = 'pending_sync_snapshot.bin',
    this.encryptBeforeUpload = false,
    this.encryptionKey,
    this.maxRetryCount = 3,
    this.retryBackoff = const Duration(seconds: 5),
    this.tableAdapters,
  }) : assert(!encryptBeforeUpload || (encryptionKey != null && encryptionKey.length >= 32),
            'عند تفعيل التشفير يجب توفير مفتاح بطول 32 حرفاً على الأقل.');

  /// قاعدة البيانات المحلية (Drift)
  final AppDatabase database;

  /// اسم الملف المخزن في Google Drive (داخل appDataFolder)
  final String driveFileName;

  /// المساحة المستخدمة في Google Drive (عادة appDataFolder)
  final String syncFolder;

  /// اسم ملف السجلات المحلي
  final String logFileName;

  /// اسم الملف المحلي الذي يحتفظ بنسخة معلقة عند انقطاع الإتصال
  final String pendingFileName;

  /// تفعيل التشفير قبل الرفع (AES)
  final bool encryptBeforeUpload;

  /// مفتاح التشفير (يجب أن يكون 32 بايت)
  final String? encryptionKey;

  /// أقصى عدد لمحاولات إعادة المحاولة
  final int maxRetryCount;

  /// الفاصل بين محاولات إعادة المحاولة (يتم مضاعفته تدريجياً)
  final Duration retryBackoff;

  /// مزودو الجداول المخصصة (إن لم يمرر سيتم استخدام المزود الافتراضي)
  final List<TableSyncAdapter>? tableAdapters;
}

enum BackupFormat { json, sqlite }

/// واجهة مجردة لمزامنة جدول محدد
abstract class TableSyncAdapter {
  const TableSyncAdapter({
    required this.tableName,
    required this.uuidColumn,
    required this.updatedAtColumn,
    required this.deletedAtColumn,
  });

  final String tableName;
  final String uuidColumn;
  final String updatedAtColumn;
  final String deletedAtColumn;

  Future<List<Map<String, dynamic>>> export(AppDatabase db);
  Future<void> applyMergedRows(AppDatabase db, List<Map<String, dynamic>> rows);
}

/// مزود بسيط يعتمد على استعلامات SQL الخام
class SqlTableSyncAdapter extends TableSyncAdapter {
  SqlTableSyncAdapter({
    required super.tableName,
    super.uuidColumn = 'local_uuid',
    super.updatedAtColumn = 'updated_at',
    super.deletedAtColumn = 'deleted_at',
  });

  @override
  Future<List<Map<String, dynamic>>> export(AppDatabase db) async {
    final result = await db.customSelect('SELECT * FROM $tableName').get();
    return result.map((row) => Map<String, dynamic>.from(row.data)).toList(growable: false);
  }

  @override
  Future<void> applyMergedRows(AppDatabase db, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    await db.transaction(() async {
      for (final row in rows) {
        final columns = row.keys.join(', ');
        final placeholders = List.filled(row.length, '?').join(', ');
        final values = row.values.toList(growable: false);
        final sql = 'INSERT OR REPLACE INTO $tableName ($columns) VALUES ($placeholders)';
        await db.customStatement(sql, values);
      }
    });
  }
}

/// معلومات ملف المزامنة المخزن على Google Drive (توافق مع النظام القديم)
class DriveBackupFile {
  DriveBackupFile({
    required this.fileId,
    required this.fileName,
    required this.createdTime,
    this.size,
    Map<String, String>? appProperties,
    this.metadata,
    this.format,
  }) : _appProperties = appProperties;

  final String fileId;
  final String fileName;
  final DateTime createdTime;
  final int? size;
  final Map<String, String>? _appProperties;
  final Map<String, dynamic>? metadata;
  final BackupFormat? format;

  Map<String, String> get appProperties {
    if (_appProperties != null) {
      return _appProperties!;
    }
    if (metadata != null) {
      return metadata!.map((key, value) => MapEntry(key, '${value ?? ''}'));
    }
    return const {};
  }

  Map<String, dynamic> toJson() => {
        'file_id': fileId,
        'file_name': fileName,
        'created_time': createdTime.toIso8601String(),
        'size': size ?? 0,
        if (_appProperties != null) 'app_properties': _appProperties,
        if (metadata != null) 'metadata': metadata,
        if (format != null) 'format': format!.name,
      };
}

/// بيانات وصفية للنسخة (توافق مع النظام القديم)
class BackupMetadata {
  BackupMetadata({
    required this.appVersion,
    required this.databaseVersion,
    required this.backupTimestamp,
    required this.totalRecords,
    required this.deviceInfo,
    this.backupType = '',
    this.triggerReason = '',
    this.deviceId = '',
    this.createdByDevice = '',
    this.format,
  });

  final String appVersion;
  final int databaseVersion;
  final DateTime backupTimestamp;
  final int totalRecords;
  final String deviceInfo;
  final String backupType;
  final String triggerReason;
  final String deviceId;
  final String createdByDevice;
  final BackupFormat? format;

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    DateTime parseTimestamp(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now().toUtc();
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      return DateTime.now().toUtc();
    }

    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    BackupFormat? parseFormat(String? value) {
      if (value == null) return null;
      return BackupFormat.values.firstWhere(
        (e) => e.name == value || e.toString() == 'BackupFormat.$value',
        orElse: () => BackupFormat.json,
      );
    }

    return BackupMetadata(
      appVersion: json['app_version']?.toString() ?? '',
      databaseVersion: parseInt(json['database_version']),
      backupTimestamp: parseTimestamp(json['backup_timestamp']),
      totalRecords: parseInt(json['total_records']),
      deviceInfo: json['device_info']?.toString() ?? '',
      backupType: json['backup_type']?.toString() ?? '',
      triggerReason: json['trigger_reason']?.toString() ?? '',
      deviceId: json['device_id']?.toString() ?? '',
      createdByDevice: json['created_by_device']?.toString() ?? '',
      format: parseFormat(json['format']?.toString()),
    );
  }

  Map<String, dynamic> toJson() => {
        'app_version': appVersion,
        'database_version': databaseVersion,
        'backup_timestamp': backupTimestamp.toIso8601String(),
        'total_records': totalRecords,
        'device_info': deviceInfo,
        if (backupType.isNotEmpty) 'backup_type': backupType,
        if (triggerReason.isNotEmpty) 'trigger_reason': triggerReason,
        if (deviceId.isNotEmpty) 'device_id': deviceId,
        if (createdByDevice.isNotEmpty) 'created_by_device': createdByDevice,
        if (format != null) 'format': format!.name,
      };
}

/// استثناء عام لعمليات المزامنة
class GoogleDriveSyncException implements Exception {
  GoogleDriveSyncException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'GoogleDriveSyncException: $message${cause != null ? ' ($cause)' : ''}';
}

class GoogleDriveSyncService {
  GoogleDriveSyncService._(this._options);

  /// إنشاء نسخة مخصصة بالخيار المناسب
  factory GoogleDriveSyncService.custom(GoogleDriveSyncOptions options) {
    return GoogleDriveSyncService._(options);
  }

  /// استخدام النسخة المشتركة (Singleton) باستدعاء المنشئ الافتراضي.
  factory GoogleDriveSyncService() {
    _shared ??= GoogleDriveSyncService._(_defaultOptions());
    return _shared!;
  }

  static GoogleDriveSyncService? _shared;

  final GoogleDriveSyncOptions _options;

  GoogleSignInAccount? _user;
  drive.DriveApi? _driveApi;
  AuthenticatedClient? _authClient;
  drive.File? _remoteFile;

  // ************ الإعدادات الافتراضية للجداول ************
  static GoogleDriveSyncOptions _defaultOptions() {
    final db = DatabaseManager.instance;
    final adapters = <TableSyncAdapter>[
      SqlTableSyncAdapter(tableName: 'rooms'),
      SqlTableSyncAdapter(tableName: 'bookings'),
      SqlTableSyncAdapter(tableName: 'booking_notes'),
      SqlTableSyncAdapter(tableName: 'employees'),
      SqlTableSyncAdapter(tableName: 'expenses'),
      SqlTableSyncAdapter(tableName: 'cash_transactions'),
      SqlTableSyncAdapter(tableName: 'payments'),
      SqlTableSyncAdapter(tableName: 'debts'),
    ];

    return GoogleDriveSyncOptions(
      database: db,
      tableAdapters: adapters,
    );
  }

  List<TableSyncAdapter> get _tables => _options.tableAdapters ?? _defaultOptions().tableAdapters!;

  // ************ مسارات الملفات المحلية ************

  Future<Directory> get _supportDir async => getApplicationSupportDirectory();

  Future<File> get _logFile async {
    final dir = await _supportDir;
    return File(p.join(dir.path, _options.logFileName));
  }

  Future<File> get _pendingFile async {
    final dir = await _supportDir;
    return File(p.join(dir.path, _options.pendingFileName));
  }

  Future<void> _appendLog(String message) async {
    final logLine = '[${DateTime.now().toIso8601String()}] $message\n';
    final file = await _logFile;
    await file.writeAsString(logLine, mode: FileMode.append, flush: true);
    if (kDebugMode) print(logLine.trim());
  }

  // ************ تسجيل الدخول إلى Google ************

  static const _scopes = [
    drive.DriveApi.driveAppdataScope,
    drive.DriveApi.driveFileScope,
  ];

  GoogleSignIn get _signIn => GoogleSignIn(scopes: _scopes);

  Future<drive.DriveApi> _ensureDrive() async {
    if (_driveApi != null) return _driveApi!;

    final signIn = _signIn;
    _user = await signIn.signInSilently();
    _user ??= await signIn.signIn();

    if (_user == null) {
      throw GoogleDriveSyncException('فشل تسجيل الدخول إلى Google Drive');
    }

    final headers = await _user!.authHeaders;
    final client = IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 30));
    _authClient = AuthenticatedClient(headers, client);
    _driveApi = drive.DriveApi(_authClient!);
    await _appendLog('✅ تم تسجيل الدخول إلى Google Drive باسم ${_user!.email}');
    return _driveApi!;
  }

  Future<drive.File> _ensureRemoteFile() async {
    if (_remoteFile != null) return _remoteFile!;
    final api = await _ensureDrive();
    final query = "name='${_options.driveFileName}' and '${_options.syncFolder}' in parents and trashed=false";

    final files = await api.files.list(
      spaces: _options.syncFolder,
      q: query,
      $fields: 'files(id, name, modifiedTime, size)',
    );

    if (files.files == null || files.files!.isEmpty) {
      final file = drive.File()
        ..name = _options.driveFileName
        ..parents = [_options.syncFolder];
      _remoteFile = await api.files.create(file);
      await _appendLog('📄 تم إنشاء ملف مزامنة جديد (${_remoteFile!.id}).');
    } else {
      _remoteFile = files.files!.first;
      await _appendLog('📄 تم العثور على ملف المزامنة (${_remoteFile!.id}).');
    }
    return _remoteFile!;
  }

  // ************ ضغط / تشفير ************

  Uint8List _compressJson(Map<String, dynamic> data) {
    final jsonBytes = utf8.encode(jsonEncode(data));
    final compressed = GZipEncoder().encode(jsonBytes)!;
    if (!_options.encryptBeforeUpload) return Uint8List.fromList(compressed);
    return _encrypt(Uint8List.fromList(compressed));
  }

  Map<String, dynamic> _decompressJson(Uint8List bytes) {
    final decompressed = GZipDecoder().decodeBytes(_options.encryptBeforeUpload ? _decrypt(bytes) : bytes);
    return jsonDecode(utf8.decode(decompressed)) as Map<String, dynamic>;
  }

  Uint8List _deriveKey() {
    final keyBytes = utf8.encode(_options.encryptionKey!);
    if (keyBytes.length >= 32) {
      return Uint8List.fromList(keyBytes.sublist(0, 32));
    }
    final extended = Uint8List(32);
    extended.setRange(0, keyBytes.length, keyBytes);
    return extended;
  }

  Uint8List _encrypt(Uint8List data) {
    final key = _deriveKey();
    final iv = Uint8List(12);
    final random = Random.secure();
    for (int i = 0; i < iv.length; i++) {
      iv[i] = random.nextInt(256);
    }

    final cipher = pc.GCMBlockCipher(pc.AESFastEngine());
    final params = pc.AEADParameters(pc.KeyParameter(key), 128, iv, Uint8List(0));
    cipher.init(true, params);

    final out = Uint8List(cipher.getOutputSize(data.length));
    var len = cipher.processBytes(data, 0, data.length, out, 0);
    len += cipher.doFinal(out, len);
    final cipherText = out.sublist(0, len);
    final mac = Uint8List.fromList(cipher.mac);

    final builder = BytesBuilder();
    builder.add(iv);
    builder.add(cipherText);
    builder.add(mac);
    return builder.takeBytes();
  }

  Uint8List _decrypt(Uint8List data) {
    if (data.length <= 28) {
      throw GoogleDriveSyncException('الملف المشفر تالف أو غير مكتمل');
    }
    final key = _deriveKey();
    final iv = data.sublist(0, 12);
    final mac = data.sublist(data.length - 16);
    final cipherText = data.sublist(12, data.length - 16);

    final cipher = pc.GCMBlockCipher(pc.AESFastEngine());
    final params = pc.AEADParameters(pc.KeyParameter(key), 128, iv, Uint8List(0));
    cipher.init(false, params);

    final full = Uint8List(cipherText.length + mac.length)
      ..setRange(0, cipherText.length, cipherText)
      ..setRange(cipherText.length, cipherText.length + mac.length, mac);

    final out = Uint8List(cipher.getOutputSize(full.length));
    var len = cipher.processBytes(full, 0, full.length, out, 0);
    len += cipher.doFinal(out, len);
    return out.sublist(0, len);
  }

  // ************ إدارة اللقطة المحلية ************

  Future<Map<String, dynamic>> _exportSnapshot() async {
    final db = _options.database;
    final snapshot = <String, dynamic>{};

    for (final adapter in _tables) {
      final rows = await adapter.export(db);
      snapshot[adapter.tableName] = rows;
    }

    final metadata = BackupMetadata(
      appVersion: '1.0.0',
      databaseVersion: db.schemaVersion,
      backupTimestamp: DateTime.now().toUtc(),
      totalRecords: snapshot.values.fold<int>(0, (sum, rows) => sum + ((rows as List).length)),
      deviceInfo: Platform.operatingSystem,
    );
    snapshot['metadata'] = metadata.toJson();
    return snapshot;
  }

  Future<File> _writeTempSnapshot(Uint8List bytes) async {
    final dir = await _supportDir;
    final file = File(p.join(dir.path, 'snapshot_${DateTime.now().millisecondsSinceEpoch}.bin'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _storePending(Uint8List bytes) async {
    final file = await _pendingFile;
    await file.writeAsBytes(bytes, flush: true);
    await _appendLog('💾 تم حفظ نسخة محلية مؤقتة عند انقطاع الاتصال.');
  }

  Future<Uint8List?> _consumePending() async {
    final file = await _pendingFile;
    if (!await file.exists()) return null;
    final data = await file.readAsBytes();
    await file.delete();
    await _appendLog('♻️ تم استهلاك نسخة محلية معلّقة.');
    return data;
  }

  // ************ تحميل / رفع ************

  Future<Uint8List?> _downloadRemoteSnapshot() async {
    final api = await _ensureDrive();
    final file = await _ensureRemoteFile();
    if (file.id == null) return null;

    try {
      final media = await api.files.get(file.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media?;
      if (media == null) return null;
      final builder = BytesBuilder();
      await for (final chunk in media.stream) {
        builder.add(chunk);
      }
      final data = builder.takeBytes();
      await _appendLog('⬇️ تم تحميل لقطة (${data.length} بايت).');
      return data;
    } catch (error) {
      await _appendLog('⚠️ فشل تحميل اللقطة: $error');
      return null;
    }
  }

  Future<void> _uploadSnapshot(Uint8List bytes) async {
    final api = await _ensureDrive();
    final file = await _ensureRemoteFile();
    final media = drive.Media(Stream.value(bytes), bytes.length);
    await api.files.update(drive.File(), file.id!, uploadMedia: media);
    await _appendLog('⬆️ تم رفع اللقطة المحدثة (${bytes.length} بايت).');
  }

  // ************ الدمج ************

  Map<String, dynamic> _mergeTable({
    required TableSyncAdapter adapter,
    required List<Map<String, dynamic>> localRows,
    required List<Map<String, dynamic>> remoteRows,
  }) {
    final uuidKey = adapter.uuidColumn;
    final updatedKey = adapter.updatedAtColumn;
    final deletedKey = adapter.deletedAtColumn;

    num _parse(dynamic value) {
      if (value is num) return value;
      if (value is String) {
        final parsed = num.tryParse(value);
        if (parsed != null) return parsed;
      }
      return 0;
    }

    final localMap = {for (final row in localRows) row[uuidKey] as String: row};
    final remoteMap = {for (final row in remoteRows) row[uuidKey] as String: row};

    final merged = <Map<String, dynamic>>[];
    final localUpdates = <Map<String, dynamic>>[];

    final allKeys = <String>{...localMap.keys, ...remoteMap.keys};

    for (final key in allKeys) {
      final local = localMap[key];
      final remote = remoteMap[key];

      Map<String, dynamic>? winner;

      if (local == null) {
        winner = Map<String, dynamic>.from(remote!);
      } else if (remote == null) {
        winner = Map<String, dynamic>.from(local);
      } else {
        final localUpdated = _parse(local[updatedKey]);
        final remoteUpdated = _parse(remote[updatedKey]);
        if (remoteUpdated > localUpdated) {
          winner = Map<String, dynamic>.from(remote);
        } else {
          winner = Map<String, dynamic>.from(local);
        }
      }

      final isDeleted = winner[deletedKey];
      if (isDeleted != null && _parse(isDeleted) > 0) {
        merged.add(winner);
        if (!_mapEquals(local, winner)) localUpdates.add(winner);
        continue;
      }

      merged.add(winner);
      if (!_mapEquals(local, winner)) localUpdates.add(winner);
    }

    return {
      'merged': merged,
      'localUpdates': localUpdates,
    };
  }

  bool _mapEquals(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (entry.value is num && other is num) {
        if ((entry.value as num) != (other as num)) return false;
      } else if ('${entry.value}' != '$other') {
        return false;
      }
    }
    return true;
  }

  Future<void> _applyMergedSnapshot(Map<String, dynamic> merged, Map<String, dynamic> local) async {
    final db = _options.database;
    for (final adapter in _tables) {
      final mergedRows = (merged[adapter.tableName] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final localRows = (local[adapter.tableName] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final mergeResult = _mergeTable(
        adapter: adapter,
        localRows: localRows,
        remoteRows: mergedRows,
      );
      final rowsToApply = (mergeResult['localUpdates'] as List).cast<Map<String, dynamic>>();
      if (rowsToApply.isNotEmpty) {
        await adapter.applyMergedRows(db, rowsToApply);
        await _appendLog('🛠️ تم تطبيق ${rowsToApply.length} سجل على الجدول ${adapter.tableName}');
      }
    }
  }

  Future<T> _retry<T>(Future<T> Function() action) async {
    int attempt = 0;
    while (true) {
      try {
        return await action();
      } catch (error, stack) {
        attempt++;
        if (attempt >= _options.maxRetryCount) {
          await _appendLog('❌ تجاوزت محاولات إعادة المحاولة: $error\n$stack');
          rethrow;
        }
        await _appendLog('⏳ إعادة المحاولة $attempt بعد خطأ: $error');
        await Future.delayed(_options.retryBackoff * attempt);
      }
    }
  }

  /// المزامنة الكاملة (رفع + تنزيل + دمج)
  Future<void> syncAllTables() async {
    await _appendLog('🚀 بدء المزامنة الكاملة');
    try {
      await _retry(() async {
        final localSnapshot = await _exportSnapshot();
        Uint8List? remoteBytes = await _consumePending();
        remoteBytes ??= await _downloadRemoteSnapshot();
        Map<String, dynamic> remoteSnapshot = {};
        if (remoteBytes != null && remoteBytes.isNotEmpty) {
          remoteSnapshot = _decompressJson(remoteBytes);
        }

        final mergedSnapshot = <String, dynamic>{'metadata': localSnapshot['metadata']};
        for (final adapter in _tables) {
          final localRows = (localSnapshot[adapter.tableName] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final remoteRows = (remoteSnapshot[adapter.tableName] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final mergeResult = _mergeTable(adapter: adapter, localRows: localRows, remoteRows: remoteRows);
          mergedSnapshot[adapter.tableName] = mergeResult['merged'];
        }

        await _applyMergedSnapshot(mergedSnapshot, localSnapshot);

        final bytes = _compressJson(mergedSnapshot);
        final temp = await _writeTempSnapshot(bytes);
        await _uploadSnapshot(await temp.readAsBytes());
        await temp.delete();
      });
      await _appendLog('✅ انتهت المزامنة بنجاح');
    } catch (error) {
      await _appendLog('❌ فشلت المزامنة: $error');
      try {
        final snapshot = await _exportSnapshot();
        final bytes = _compressJson(snapshot);
        await _storePending(bytes);
      } catch (e) {
        await _appendLog('⚠️ فشل حفظ النسخة الاحتياطية المحلية بعد الخطأ: $e');
      }
      rethrow;
    }
  }

  // ************ واجهة توافقية مع النظام السابق ************

  Future<Map<String, dynamic>> exportDatabaseToJson() async => _exportSnapshot();

  Future<String> uploadBackup(Map<String, dynamic> backup) async {
    final bytes = _compressJson(backup);
    final temp = await _writeTempSnapshot(bytes);
    await _uploadSnapshot(await temp.readAsBytes());
    await temp.delete();
    final file = await _ensureRemoteFile();
    return file.id ?? 'snapshot';
  }

  Future<List<DriveBackupFile>> listBackupFiles() async {
    final api = await _ensureDrive();
    final file = await _ensureRemoteFile();
    final meta = await api.files.get(file.id!, $fields: 'id, name, createdTime, size');
    return [
      DriveBackupFile(
        fileId: meta.id!,
        fileName: meta.name!,
        createdTime: meta.createdTime ?? DateTime.now().toUtc(),
        size: meta.size != null ? int.tryParse(meta.size!) : null,
        appProperties: meta.appProperties,
        metadata: null,
        format: null,
      ),
    ];
  }

  Future<Map<String, dynamic>> downloadBackup(String fileId) async {
    final api = await _ensureDrive();
    final media = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media?;
    if (media == null) throw GoogleDriveSyncException('تعذر تنزيل الملف: $fileId');
    final builder = BytesBuilder();
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return _decompressJson(builder.takeBytes());
  }

  Future<void> restoreFromBackup(Map<String, dynamic> backup) async {
    await _appendLog('♻️ استعادة بيانات من النسخة الاحتياطية');
    await _applyMergedSnapshot(backup, {});
    final bytes = _compressJson(backup);
    await _uploadSnapshot(bytes);
  }

  Future<void> performAutoBackup() async => syncAllTables();

  Future<DateTime?> getLastBackupTime() async {
    final file = await _ensureRemoteFile();
    return file.modifiedTime;
  }

  Future<void> deleteBackupFile(String fileId) async {
    final api = await _ensureDrive();
    await api.files.delete(fileId);
    _remoteFile = null;
    await _appendLog('🗑️ تم حذف ملف المزامنة ($fileId). سيتم إعادة إنشائه عند المزامنة التالية.');
  }

  Future<int> estimateDatabaseSize() async {
    final snapshot = await _exportSnapshot();
    final jsonBytes = utf8.encode(jsonEncode(snapshot));
    return jsonBytes.length;
  }

  Future<void> signOut() async {
    await _appendLog('👋 تسجيل الخروج من Google Drive');
    try {
      _authClient?.close();
      await _signIn.disconnect();
    } catch (_) {}
    _authClient = null;
    _driveApi = null;
    _remoteFile = null;
    _user = null;
  }

  GoogleSignInAccount? get currentUser => _user;
  bool get isSignedIn => _user != null;

  Future<GoogleSignInAccount?> signInForDrive() async {
    final api = await _ensureDrive();
    return _user;
  }

  Future<GoogleSignInAccount?> attemptSilentSignIn() async {
    final signIn = _signIn;
    _user = await signIn.signInSilently(suppressErrors: true);
    if (_user != null) {
      final headers = await _user!.authHeaders;
      final client = IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 30));
      _authClient = AuthenticatedClient(headers, client);
      _driveApi = drive.DriveApi(_authClient!);
      await _appendLog('🔁 تم استعادة جلسة Google Drive تلقائياً باسم ${_user!.email}');
    }
    return _user;
  }

  // ************ إعدادات النسخ التلقائي (توافقية) ************

  static const _prefsEnabledKey = 'auto_backup_enabled';
  static const _prefsFrequencyKey = 'auto_backup_frequency';
  static const _prefsTimeKey = 'auto_backup_time';

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, enabled);
  }

  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsEnabledKey) ?? false;
  }

  Future<void> setAutoBackupFrequency(String frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsFrequencyKey, frequency);
  }

  Future<String> getAutoBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsFrequencyKey) ?? 'interval';
  }

  Future<void> setAutoBackupTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTimeKey, time);
  }

  Future<String> getAutoBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsTimeKey) ?? '00:15';
  }
}

/// عميل مصادق عليه يستخدمه Google APIs
class AuthenticatedClient extends http.BaseClient {
  AuthenticatedClient(this._headers, this._inner);

  final Map<String, String> _headers;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

typedef GoogleDriveBackupService = GoogleDriveSyncService;
