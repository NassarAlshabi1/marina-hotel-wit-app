import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../data/sync_models.dart';
import 'sync_constants.dart';

const _kPrimarySnapshotName = 'sync_data.json.gz';
const _kIndexFileName = 'sync_index.json';
const _kDeltaPrefix = 'delta_';
const _kShardExtension = '.json.gz';
const _kDefaultShardBytes = SyncConstants.googleDriveDefaultShardBytes;

/// نتيجة التحميل من Google Drive بعد فك الضغط والتشفير
class DriveSyncDownloadResult {
  DriveSyncDownloadResult({
    required this.snapshot,
    required this.metadata,
    required this.shards,
    required this.driveVersion,
  });

  final SyncSnapshot snapshot;
  final SyncMetadata metadata;
  final List<DriveSyncShard> shards;
  final int driveVersion;
}

/// وصف جزء مخزن داخل appDataFolder
class DriveSyncShard {
  DriveSyncShard({
    required this.fileId,
    required this.name,
    required this.index,
    required this.totalParts,
    required this.size,
    required this.checksum,
    required this.modifiedAt,
    required this.version,
  });

  final String fileId;
  final String name;
  final int index;
  final int totalParts;
  final int size;
  final String checksum;
  final DateTime modifiedAt;
  final int version;

  Map<String, dynamic> toJson() {
    return {
      'fileId': fileId,
      'name': name,
      'index': index,
      'totalParts': totalParts,
      'size': size,
      'checksum': checksum,
      'modifiedAt': modifiedAt.toIso8601String(),
      'version': version,
    };
  }

  factory DriveSyncShard.fromJson(Map<String, dynamic> json) {
    return DriveSyncShard(
      fileId: json['fileId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      index: json['index'] as int? ?? 0,
      totalParts: json['totalParts'] as int? ?? 1,
      size: json['size'] as int? ?? 0,
      checksum: json['checksum'] as String? ?? '',
      modifiedAt: DateTime.tryParse(json['modifiedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      version: json['version'] as int? ?? 1,
    );
  }
}

/// ملف فهرس الأجزاء لتسهيل إعادة البناء
class DriveSyncIndex {
  DriveSyncIndex({
    required this.version,
    required this.checksum,
    required this.lastDeviceId,
    required this.lastSyncId,
    required this.updatedAt,
    required this.totalParts,
    required this.shards,
    required this.snapshotSize,
  });

  final int version;
  final String checksum;
  final String lastDeviceId;
  final String lastSyncId;
  final String updatedAt;
  final int totalParts;
  final List<DriveSyncShard> shards;
  final int snapshotSize;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'checksum': checksum,
      'lastDeviceId': lastDeviceId,
      'lastSyncId': lastSyncId,
      'updatedAt': updatedAt,
      'totalParts': totalParts,
      'snapshotSize': snapshotSize,
      'shards': shards.map((s) => s.toJson()).toList(),
    };
  }

  factory DriveSyncIndex.fromJson(Map<String, dynamic> json) {
    final rawShards = (json['shards'] as List<dynamic>? ?? [])
        .map(
          (item) =>
              DriveSyncShard.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
    return DriveSyncIndex(
      version: json['version'] as int? ?? 1,
      checksum: json['checksum'] as String? ?? '',
      lastDeviceId: json['lastDeviceId'] as String? ?? '',
      lastSyncId: json['lastSyncId'] as String? ?? '',
      updatedAt: json['updatedAt'] as String? ?? '',
      totalParts: json['totalParts'] as int? ?? rawShards.length,
      snapshotSize: json['snapshotSize'] as int? ?? 0,
      shards: rawShards,
    );
  }
}

/// عميل HTTP يضيف رؤوس Google Sign-In تلقائياً
class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers) : _client = http.Client();

  final Map<String, String> _headers;
  final http.Client _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

/// خدمة التعامل مع Google Drive (appDataFolder) ورفع اللقطات المجزأة
class GoogleDriveSyncService {
  GoogleDriveSyncService({
    GoogleSignIn? googleSignIn,
    drive.DriveApi? driveApi,
    int shardSizeBytes = _kDefaultShardBytes,
  })  : _googleSignIn = googleSignIn ??
            GoogleSignIn(scopes: const [drive.DriveApi.driveAppdataScope]),
        _driveApi = driveApi,
        _shardSizeBytes = shardSizeBytes;

  final GoogleSignIn _googleSignIn;
  drive.DriveApi? _driveApi;
  final int _shardSizeBytes;

  bool _encryptionEnabled = false;
  String? _encryptionKey;
  bool _allowInteractiveSignIn = true;

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// تهيئة الخدمة وخيار التشفير AES-256
  Future<void> init({
    bool enableEncryption = false,
    String? encryptionKey,
    bool allowInteractiveSignIn = true,
  }) async {
    _allowInteractiveSignIn = allowInteractiveSignIn;
    _encryptionEnabled = enableEncryption;
    if (_encryptionEnabled) {
      if (encryptionKey == null || encryptionKey.isEmpty) {
        throw ArgumentError('مطلوب مفتاح تشفير عند تفعيل التشفير.');
      }
      _encryptionKey = encryptionKey;
    } else {
      _encryptionKey = null;
    }
    await _ensureDriveApi();
  }

  /// تسجيل الدخول إلى Google Drive باستخدام Google Sign-In
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account =
          await _googleSignIn.signInSilently(suppressErrors: true) ??
              await _googleSignIn.signIn();
      if (account == null) {
        return null;
      }
      final headers = await account.authHeaders;
      _driveApi = drive.DriveApi(_GoogleAuthClient(headers));
      return account;
    } catch (error, stack) {
      debugPrint('❌ فشل تسجيل الدخول Google Drive: $error');
      debugPrint('$stack');
      rethrow;
    }
  }

  /// تسجيل الخروج وإعادة ضبط العميل
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } finally {
      _driveApi = null;
    }
  }

  /// تحميل آخر لقطة جاهزة من Google Drive وإرجاعها كموديل
  Future<DriveSyncDownloadResult?> downloadLatestSnapshot() async {
    final api = await _ensureDriveApi();
    final index = await _loadIndex(api);

    if (index == null || index.shards.isEmpty) {
      final singleShard = await _locateSingleSnapshot(api);
      if (singleShard == null) {
        return null;
      }
      final fileBytes = await _downloadFileBytes(api, singleShard.fileId);
      final payload = await _decodePayload(fileBytes);
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      final snapshot = SyncSnapshot.fromJson(json);
      return DriveSyncDownloadResult(
        snapshot: snapshot,
        metadata: snapshot.metadata,
        shards: [singleShard],
        driveVersion: singleShard.version,
      );
    }

    index.shards.sort((a, b) => a.index.compareTo(b.index));
    final accumulator = BytesBuilder(copy: false);
    for (final shard in index.shards) {
      final fileBytes = await _downloadFileBytes(api, shard.fileId);
      accumulator.add(fileBytes);
    }
    final payload = await _decodePayload(accumulator.toBytes());
    final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    final snapshot = SyncSnapshot.fromJson(json);
    return DriveSyncDownloadResult(
      snapshot: snapshot,
      metadata: snapshot.metadata,
      shards: index.shards,
      driveVersion: index.version,
    );
  }

  /// قراءة آخر وقت تعديل لملف الـ snapshot في Google Drive دون تنزيل المحتوى.
  Future<DateTime?> getLatestSnapshotModifiedTime() async {
    try {
      final api = await _ensureDriveApi();
      final indexList = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_kIndexFileName' and trashed=false",
        $fields: 'files(id,modifiedTime)',
      );
      final indexFile =
          (indexList.files ?? []).isNotEmpty ? indexList.files!.first : null;
      if (indexFile?.modifiedTime != null) {
        return indexFile!.modifiedTime;
      }

      final snapList = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_kPrimarySnapshotName' and trashed=false",
        $fields: 'files(id,modifiedTime)',
        orderBy: 'modifiedTime desc',
      );
      final snapFile =
          (snapList.files ?? []).isNotEmpty ? snapList.files!.first : null;
      return snapFile?.modifiedTime;
    } catch (error) {
      debugPrint('⚠️ تعذر قراءة modifiedTime من Google Drive: $error');
      return null;
    }
  }

  /// رفع لقطة كاملة مع التحقق من الإصدار وتجزئة الملفات
  Future<DriveSyncIndex> uploadSnapshot({
    required SyncSnapshot snapshot,
    required String deviceId,
    required int expectedVersion,
  }) async {
    final api = await _ensureDriveApi();

    final existingIndex = await _loadIndex(api);
    if (existingIndex != null && existingIndex.version != expectedVersion) {
      throw StateError(
        'تغير إصدار البيانات في Google Drive. يجب تنفيذ عملية سحب قبل الرفع.',
      );
    }
    if (existingIndex == null) {
      final single = await _locateSingleSnapshot(api);
      if (single != null && expectedVersion != single.version) {
        throw StateError(
          'تم العثور على نسخة مختلفة من الملف. الرجاء المزامنة قبل الرفع.',
        );
      }
    }

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final tablesPayload = {'tables': snapshot.tables};
    final checksum = SyncChecksum.compute(tablesPayload);
    final rawLength = utf8.encode(jsonEncode(tablesPayload)).length;

    final normalizedMetadata = SyncMetadata(
      version: expectedVersion + 1,
      lastUpdatedAt: nowIso,
      devicePriority: snapshot.metadata.devicePriority,
      snapshotSize: rawLength,
      lastSyncId: snapshot.metadata.lastSyncId,
      checksum: checksum,
      lastDeviceId: deviceId,
    );

    final normalizedSnapshot = SyncSnapshot(
      metadata: normalizedMetadata,
      tables: snapshot.tables,
    );
    final encoded = utf8.encode(jsonEncode(normalizedSnapshot.toJson()));
    final compressed = Uint8List.fromList(gzip.encode(encoded));
    final processed = await _encodePayload(compressed);

    final shards = _splitIntoShards(processed);
    final uploadedShards = await _uploadShards(
      api,
      shards,
      normalizedMetadata,
      deviceId,
    );

    final index = DriveSyncIndex(
      version: normalizedMetadata.version,
      checksum: checksum,
      lastDeviceId: deviceId,
      lastSyncId: normalizedMetadata.lastSyncId,
      updatedAt: normalizedMetadata.lastUpdatedAt,
      totalParts: uploadedShards.length,
      snapshotSize: processed.length,
      shards: uploadedShards,
    );

    await _uploadIndex(api, index);
    await _cleanupLegacySnapshot(
      api,
      keepShardIds: uploadedShards.map((s) => s.fileId).toList(),
    );
    return index;
  }

  /// رفع ملف دلتا اختياري للتوسعة المستقبلية
  Future<String> uploadDelta(
    Uint8List deltaBytes, {
    required DateTime timestamp,
  }) async {
    final api = await _ensureDriveApi();
    final compressed = Uint8List.fromList(gzip.encode(deltaBytes));
    final processed = await _encodePayload(compressed);
    final name =
        '$_kDeltaPrefix${timestamp.toUtc().toIso8601String()}$_kShardExtension';

    final file = drive.File()
      ..name = name
      ..parents = const ['appDataFolder']
      ..appProperties = {
        'type': 'delta',
        'timestamp': timestamp.toIso8601String(),
        'size': processed.length.toString(),
      };

    final media = drive.Media(Stream.value(processed), processed.length);
    final created = await api.files.create(file, uploadMedia: media);
    return created.id!;
  }

  /// إزالة ملفات الدلتا الأقدم لتقليل استهلاك التخزين
  Future<void> pruneOldDeltas({int keepLatest = 10}) async {
    final api = await _ensureDriveApi();
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains '$_kDeltaPrefix' and trashed=false",
      orderBy: 'createdTime desc',
      $fields: 'files(id,name,createdTime)',
    );
    final files = list.files ?? [];
    for (var i = keepLatest; i < files.length; i++) {
      final file = files[i];
      if (file.id != null) {
        await api.files.delete(file.id!);
      }
    }
  }

  /// التأكد من جاهزية driveApi مع محاولة تسجيل الدخول الصامتة
  Future<drive.DriveApi> _ensureDriveApi() async {
    if (_driveApi != null) {
      return _driveApi!;
    }

    final account = await _googleSignIn.signInSilently(suppressErrors: true) ??
        (_allowInteractiveSignIn ? await _googleSignIn.signIn() : null);

    if (account == null) {
      throw StateError('لم يتم تسجيل الدخول إلى Google Drive.');
    }

    final headers = await account.authHeaders;
    _driveApi = drive.DriveApi(_GoogleAuthClient(headers));
    return _driveApi!;
  }

  Future<DriveSyncIndex?> _loadIndex(drive.DriveApi api) async {
    try {
      final result = await api.files.list(
        spaces: 'appDataFolder',
        q: "name='$_kIndexFileName' and trashed=false",
        $fields: 'files(id,name,modifiedTime,version)',
      );
      if (result.files == null || result.files!.isEmpty) {
        return null;
      }
      final file = result.files!.first;
      final bytes = await _downloadFileBytes(api, file.id!);
      final payload = await _decodePayload(bytes);
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      return DriveSyncIndex.fromJson(json);
    } catch (error) {
      debugPrint('⚠️ تعذر تحميل ملف الفهرس: $error');
      return null;
    }
  }

  Future<void> _uploadIndex(drive.DriveApi api, DriveSyncIndex index) async {
    final data = utf8.encode(jsonEncode(index.toJson()));
    final compressed = Uint8List.fromList(gzip.encode(data));
    final processed = await _encodePayload(compressed);

    final existing = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_kIndexFileName' and trashed=false",
      $fields: 'files(id)',
    );

    final file = drive.File()
      ..name = _kIndexFileName
      ..parents = const ['appDataFolder']
      ..appProperties = {
        'type': 'index',
        'version': index.version.toString(),
        'checksum': index.checksum,
        'updatedAt': index.updatedAt,
      };

    final media = drive.Media(Stream.value(processed), processed.length);

    if (existing.files != null && existing.files!.isNotEmpty) {
      final id = existing.files!.first.id;
      if (id != null) {
        await api.files.update(file, id, uploadMedia: media);
        return;
      }
    }
    await api.files.create(file, uploadMedia: media);
  }

  Future<DriveSyncShard?> _locateSingleSnapshot(drive.DriveApi api) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name='$_kPrimarySnapshotName' and trashed=false",
      $fields: 'files(id,name,modifiedTime,size,appProperties,version)',
      orderBy: 'modifiedTime desc',
    );
    if (result.files == null || result.files!.isEmpty) {
      return null;
    }
    final file = result.files!.first;
    final rawVersion =
        file.appProperties?['version'] ?? file.version?.toString() ?? '1';
    final version = int.tryParse(rawVersion) ?? 1;
    return DriveSyncShard(
      fileId: file.id!,
      name: file.name!,
      index: 0,
      totalParts: 1,
      size: int.tryParse(file.size ?? '0') ?? 0,
      checksum: file.appProperties?['checksum'] ?? '',
      modifiedAt: file.modifiedTime ?? DateTime.now().toUtc(),
      version: version,
    );
  }

  Future<List<DriveSyncShard>> _uploadShards(
    drive.DriveApi api,
    List<Uint8List> shards,
    SyncMetadata metadata,
    String deviceId,
  ) async {
    final cleanup = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains 'sync_data' and trashed=false",
      $fields: 'files(id,name)',
    );
    for (final file in cleanup.files ?? []) {
      if (file.id != null && (file.name?.startsWith('sync_data') ?? false)) {
        await api.files.delete(file.id!);
      }
    }

    final uploaded = <DriveSyncShard>[];
    for (var index = 0; index < shards.length; index++) {
      final isPrimary = index == 0;
      final name = isPrimary
          ? _kPrimarySnapshotName
          : 'sync_data.part${index.toString().padLeft(3, '0')}$_kShardExtension';

      final props = {
        'type': 'snapshot',
        'partIndex': index.toString(),
        'totalParts': shards.length.toString(),
        'version': metadata.version.toString(),
        'checksum': metadata.checksum,
        'lastDeviceId': deviceId,
        'updatedAt': metadata.lastUpdatedAt,
      };

      final file = drive.File()
        ..name = name
        ..parents = const ['appDataFolder']
        ..appProperties = props;

      final media = drive.Media(
        Stream.value(shards[index]),
        shards[index].length,
      );
      final created = await api.files.create(file, uploadMedia: media);

      uploaded.add(
        DriveSyncShard(
          fileId: created.id!,
          name: name,
          index: index,
          totalParts: shards.length,
          size: shards[index].length,
          checksum: metadata.checksum,
          modifiedAt: DateTime.now().toUtc(),
          version: metadata.version,
        ),
      );
    }
    return uploaded;
  }

  Future<void> _cleanupLegacySnapshot(
    drive.DriveApi api, {
    required List<String> keepShardIds,
  }) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name contains 'sync_data' and trashed=false",
      $fields: 'files(id)',
    );
    for (final file in result.files ?? []) {
      if (file.id == null) continue;
      if (!keepShardIds.contains(file.id)) {
        await api.files.delete(file.id!);
      }
    }
  }

  List<Uint8List> _splitIntoShards(Uint8List bytes) {
    if (bytes.length <= _shardSizeBytes) {
      return [bytes];
    }
    final chunks = <Uint8List>[];
    var offset = 0;
    while (offset < bytes.length) {
      final end = min(offset + _shardSizeBytes, bytes.length);
      chunks.add(Uint8List.sublistView(bytes, offset, end));
      offset = end;
    }
    return chunks;
  }

  Future<Uint8List> _downloadFileBytes(
    drive.DriveApi api,
    String fileId,
  ) async {
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  Future<Uint8List> _encodePayload(Uint8List bytes) async {
    if (!_encryptionEnabled) {
      return bytes;
    }
    final key = _deriveKey(_encryptionKey!);
    final ivBytes = _generateIv();
    final aes = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
    );
    final encrypted = aes.encryptBytes(bytes, iv: encrypt.IV(ivBytes));
    return Uint8List.fromList(ivBytes + encrypted.bytes);
  }

  Future<Uint8List> _decodePayload(Uint8List bytes) async {
    if (!_encryptionEnabled) {
      return Uint8List.fromList(gzip.decode(bytes));
    }
    if (bytes.length < 16) {
      throw StateError('البيانات المشفرة غير صالحة.');
    }
    final ivBytes = bytes.sublist(0, 16);
    final cipher = bytes.sublist(16);
    final key = _deriveKey(_encryptionKey!);
    final aes = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(key), mode: encrypt.AESMode.cbc),
    );
    final decrypted = aes.decryptBytes(
      encrypt.Encrypted(cipher),
      iv: encrypt.IV(ivBytes),
    );
    return Uint8List.fromList(gzip.decode(decrypted));
  }

  Uint8List _deriveKey(String key) {
    final bytes = utf8.encode(key);
    final hash = sha256.convert(bytes).bytes;
    final buffer = Uint8List(32);
    buffer.setRange(0, 32, hash);
    return buffer;
  }

  Uint8List _generateIv() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return Uint8List.fromList(bytes);
  }
}
