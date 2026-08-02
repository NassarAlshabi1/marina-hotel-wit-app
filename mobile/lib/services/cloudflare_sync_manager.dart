// ═══════════════════════════════════════════════════════════════
//  cloudflare_sync_manager.dart — Cloudflare Sync Manager
//  Drop-in replacement for AppwriteSyncManager
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'cloudflare_config.dart';
import '../utils/env.dart';
import 'local_db.dart';
import 'daos/outbox_dao.dart';
import 'resilient_http_client.dart';
import 'sync_enums.dart';

// ─── SyncResult (same interface as AppwriteSyncManager) ────────

class SyncResult {
  SyncResult({
    required this.status,
    required this.timestamp,
    required this.duration,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
  });

  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
}

// ─── Realtime sync state ───────────────────────────────────────

class CloudflareRealtimeSync {
  final pendingRemoteChangesCount = ValueNotifier<int>(0);
  final hasRemoteChanges = ValueNotifier<bool>(false);

  Future<void> initialize({String? deviceId}) async {}
  Future<void> start() async {}
  void stop() {}
}

// ─── CloudflareSyncManager ─────────────────────────────────────

class CloudflareSyncManager {
  CloudflareSyncManager._();
  static final CloudflareSyncManager _instance = CloudflareSyncManager._();
  factory CloudflareSyncManager() => _instance;

  // ─── Static device ID (same interface as AppwriteSyncManager) ──
  static String? _staticDeviceId;
  static String? get currentDeviceIdStatic => _staticDeviceId;
  static void setStaticDeviceId(String id) => _staticDeviceId = id;

  // ─── State ──────────────────────────────────────────────────
  AppDatabase? _db;
  String? _token;
  String? _deviceId;
  String? _initError;
  String? _lastError;
  SyncStatus _currentStatus = SyncStatus.idle;
  Timer? _autoSyncTimer;
  int _lastPullCursor = 0;

  bool get isAvailable => _token != null;
  String? get token => _token;
  String? get initError => _initError;
  String? get lastError => _lastError;
  SyncStatus get currentStatus => _currentStatus;
  String? get currentDeviceId => _deviceId;

  // ─── Realtime status stream (used by UnifiedSyncOrchestrator) ──
  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _statusController.stream;

  // ─── HTTP client with DoH fallback (bypasses broken ISP DNS) ──
  // Solves DNS_PROBE_FINISHED_NXDOMAIN on Yemeni networks where ISP DNS
  // resolvers fail to resolve *.workers.dev. Falls back to Cloudflare DoH
  // (https://cloudflare-dns.com/dns-query) then Google DoH.
  // Uses 30s timeout (default) — generous enough for slow networks.
  final http.Client _httpClient = createResilientHttpClient(
    timeout: const Duration(seconds: 30),
  );

  // ─── Initialize ─────────────────────────────────────────────
  Future<void> initialize({AppDatabase? database, bool forceRetry = false}) async {
    if (_token != null && !forceRetry) return;

    _db = database ?? DatabaseManager.instance;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('cf_device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      _deviceId = _generateDeviceId();
      await prefs.setString('cf_device_id', _deviceId!);
    }
    setStaticDeviceId(_deviceId!);

    // Retry login up to 3 times for transient network failures (DNS, socket).
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await _httpClient.post(
          Uri.parse('${CloudflareConfig.workerUrl}/api/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'username': CloudflareConfig.username,
            'password': CloudflareConfig.password,
            'device_id': _deviceId,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _token = data['token'] as String?;
          Env.cloudflareAuthToken = _token;
          _initError = null;
          debugPrint(
            '✅ CloudflareSyncManager initialized — device: $_deviceId '
            '(attempt $attempt/$maxAttempts)',
          );
          return;
        } else {
          _initError = 'Login failed: ${response.statusCode}';
          debugPrint('⚠️ Cloudflare login failed: ${response.body}');
          return;
        }
      } catch (e) {
        final errStr = e.toString();
        final isTransient = errStr.contains('Failed host lookup') ||
            errStr.contains('No address associated with hostname') ||
            errStr.contains('SocketException') ||
            errStr.contains('HandshakeException') ||
            errStr.contains('TimeoutException');

        if (isTransient && attempt < maxAttempts) {
          debugPrint(
            '⚠️ Cloudflare init attempt $attempt failed (transient), retrying in 2s: $e',
          );
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        // Final attempt failed — set actionable error message
        if (errStr.contains('Failed host lookup') ||
            errStr.contains('No address associated with hostname')) {
          _initError =
              'لا يمكن الوصول إلى خادم Cloudflare (${CloudflareConfig.workerUrl}). '
              'تأكد من اتصالك بالإنترنت وأن الشبكة لا تحظر الدومين workers.dev. '
              'الخطأ الأصلي: $e';
        } else if (errStr.contains('SocketException') ||
            errStr.contains('HandshakeException')) {
          _initError =
              'فشل الاتصال بخادم Cloudflare. تحقق من الشبكة وأعد المحاولة. '
              'الخطأ الأصلي: $e';
        } else if (errStr.contains('TimeoutException')) {
          _initError =
              'انتهت مهلة الاتصال بخادم Cloudflare (15 ثانية). '
              'تحقق من سرعة الإنترنت وأعد المحاولة. الخطأ الأصلي: $e';
        } else {
          _initError = 'Init error: $e';
        }
        debugPrint('⚠️ CloudflareSyncManager init error: $e');
        return;
      }
    }
  }

  // ─── Register Device ────────────────────────────────────────
  Future<String> registerDevice() async {
    if (_token == null || _deviceId == null) {
      throw StateError('Not initialized');
    }

    final response = await _httpClient.post(
      Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'deviceId': _deviceId,
        'platform': 'android',
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      debugPrint('✅ Device registered: $_deviceId');
      return _deviceId!;
    }
    throw Exception('Device registration failed: ${response.statusCode}');
  }

  // ─── Set FCM Token ──────────────────────────────────────────
  Future<void> setFcmToken(String token) async {
    if (_token == null || _deviceId == null) return;

    try {
      await _httpClient.post(
        Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'deviceId': _deviceId,
          'fcmToken': token,
          'platform': 'android',
        }),
      ).timeout(const Duration(seconds: 10));
      debugPrint('✅ FCM token set for device: $_deviceId');
    } catch (e) {
      debugPrint('⚠️ Set FCM token error: $e');
    }
  }

  // ─── Sync (push + pull) ─────────────────────────────────────
  Future<SyncResult> sync({bool push = true, bool pull = true}) async {
    if (_token == null) {
      return SyncResult(
        status: SyncStatus.failed,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'Not initialized',
      );
    }

    final startTime = DateTime.now();
    _currentStatus = SyncStatus.syncing;
    _statusController.add(SyncStatus.syncing);
    int recordsPushed = 0;
    int recordsPulled = 0;
    String? errorMessage;

    try {
      if (push) {
        recordsPushed = await _pushOutbox();
      }
      if (pull) {
        recordsPulled = await _pullChanges();
      }

      _currentStatus = SyncStatus.success;
      _statusController.add(SyncStatus.success);
      _lastError = null;
    } catch (e) {
      _currentStatus = SyncStatus.failed;
      _statusController.add(SyncStatus.failed);
      errorMessage = e.toString();
      _lastError = errorMessage;
    }

    return SyncResult(
      status: _currentStatus,
      timestamp: startTime,
      duration: DateTime.now().difference(startTime),
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      errorMessage: errorMessage,
    );
  }

  // ─── Push outbox to D1 ──────────────────────────────────────
  Future<int> _pushOutbox() async {
    if (_db == null) return 0;

    final outboxDao = OutboxDao(_db!);
    final pending = await (outboxDao.select(outboxDao.outbox)
          ..where((t) => t.processingStatus.isIn(['pending', 'failed']))
          ..orderBy([(t) => OrderingTerm.asc(t.clientTs)])
          ..limit(CloudflareConfig.batchSize))
        .get();

    if (pending.isEmpty) return 0;

    final operations = pending.map((item) {
      final data = jsonDecode(item.payload) as Map<String, dynamic>;
      return {
        'idempotencyKey': item.idempotencyKey,
        'entity': item.entity,
        'operation': item.op,
        'data': data,
        'vectorClock': data['vector_clock'] as String? ?? '{}',
        'updatedAt': item.clientTs,
        if (_deviceId != null) 'deviceId': _deviceId,
      };
    }).toList();

    // ─── gzip compress the push payload for faster upload ───
    final jsonPayload = jsonEncode({'operations': operations});
    final jsonBytes = utf8.encode(jsonPayload);
    final gzipCodec = GZipCodec(level: 6); // level 6 = good balance of speed/ratio
    final compressedBytes = gzipCodec.encode(jsonBytes);

    final response = await _httpClient.post(
      Uri.parse('${CloudflareConfig.workerUrl}/api/sync/push'),
      headers: {
        'Authorization': 'Bearer $_token',
        'Content-Type': 'application/json',
        'Content-Encoding': 'gzip',
        'Content-Length': compressedBytes.length.toString(),
      },
      body: compressedBytes,
    ).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('Push failed: ${response.statusCode}');
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final results = result['results'] as List? ?? [];
    int successCount = 0;

    for (final r in results) {
      final item = r as Map<String, dynamic>;
      final key = item['idempotencyKey'] as String?;
      final success = item['success'] as bool? ?? false;

      if (key == null) continue;

      final outboxItem = pending.firstWhere(
        (p) => p.idempotencyKey == key,
        orElse: () => pending.first,
      );

      if (success) {
        await (outboxDao.delete(outboxDao.outbox)
              ..where((t) => t.id.equals(outboxItem.id)))
            .go();
        successCount++;
      } else {
        await (outboxDao.update(outboxDao.outbox)
              ..where((t) => t.id.equals(outboxItem.id)))
            .write(OutboxCompanion(
          processingStatus: const Value('failed'),
          attempts: Value(outboxItem.attempts + 1),
          lastError: Value(item['error'] as String?),
        ));
      }
    }

    debugPrint('📤 Pushed $successCount/${pending.length} operations');
    return successCount;
  }

  // ─── Pull changes from D1 ───────────────────────────────────
  Future<int> _pullChanges() async {
    if (_db == null) return 0;

    int totalPulled = 0;
    bool hasMore = true;

    while (hasMore) {
      final response = await _httpClient.get(
        Uri.parse('${CloudflareConfig.workerUrl}/api/sync/pull')
            .replace(queryParameters: {
          'cursor': _lastPullCursor.toString(),
          'limit': CloudflareConfig.batchSize.toString(),
        }),
        headers: {
          'Authorization': 'Bearer $_token',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Pull failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final changes = data['changes'] as List? ?? [];
      hasMore = data['has_more'] as bool? ?? false;
      _lastPullCursor = int.tryParse(data['cursor']?.toString() ?? '0') ?? _lastPullCursor;

      for (final change in changes) {
        final record = Map<String, dynamic>.from(change as Map);
        final entity = _detectEntity(record);
        if (entity != null) {
          await _applyChange(entity, record);
          totalPulled++;
        }
      }

      if (changes.isEmpty) break;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('cf_last_pull_cursor', _lastPullCursor);

    debugPrint('📥 Pulled $totalPulled changes');
    return totalPulled;
  }

  // ─── Apply change to local Drift DB ─────────────────────────
  Future<void> _applyChange(String entity, Map<String, dynamic> record) async {
    if (_db == null) return;

    final tableName = CloudflareConfig.tableNameFor(entity);
    if (tableName == null) return;

    final localUuid = record['local_uuid'] as String?;
    if (localUuid == null) return;

    final existing = await _db!.customSelect(
      'SELECT id FROM $tableName WHERE local_uuid = ?',
      variables: [Variable<String>(localUuid)],
    ).getSingleOrNull();

    final cleanRecord = Map<String, dynamic>.from(record);
    cleanRecord.remove('id');

    if (existing != null) {
      final localId = existing.data['id'];
      final setClauses = cleanRecord.keys.map((c) => '$c = ?').join(', ');
      final values = cleanRecord.values.map(_toDriftValue).toList();
      await _db!.customStatement(
        'UPDATE $tableName SET $setClauses WHERE id = ?',
        [...values, localId],
      );
    } else {
      final columns = cleanRecord.keys.join(', ');
      final placeholders = cleanRecord.keys.map((_) => '?').join(', ');
      final values = cleanRecord.values.map(_toDriftValue).toList();
      await _db!.customStatement(
        'INSERT OR IGNORE INTO $tableName ($columns) VALUES ($placeholders)',
        values,
      );
    }
  }

  // ─── Detect entity from record fields ───────────────────────
  String? _detectEntity(Map<String, dynamic> record) {
    if (record.containsKey('room_number') && record.containsKey('price')) return 'rooms';
    if (record.containsKey('guest_name') && record.containsKey('checkin_date')) return 'bookings';
    if (record.containsKey('amount') && record.containsKey('payment_method')) return 'payments';
    if (record.containsKey('expense_type') && record.containsKey('description')) return 'expenses';
    if (record.containsKey('basic_salary') && record.containsKey('position')) return 'employees';
    if (record.containsKey('debt_reason') && record.containsKey('remaining_amount')) return 'debts';
    if (record.containsKey('final_rate') && record.containsKey('hotel_day_key')) return 'booking_nights';
    if (record.containsKey('adjustment_type') && record.containsKey('amount')) return 'booking_price_adjustments';
    if (record.containsKey('guest_name') && record.containsKey('id_number')) return 'guest_infos';
    if (record.containsKey('withdrawal_type') && record.containsKey('amount')) return 'salary_withdrawals';
    return null;
  }

  // ─── Convert value for Drift ────────────────────────────────
  dynamic _toDriftValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is List || value is Map) return jsonEncode(value);
    return value;
  }

  // ─── Auto Sync ──────────────────────────────────────────────
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      sync().catchError((Object e) {
        debugPrint('⚠️ Auto-sync error: $e');
        return SyncResult(
          status: SyncStatus.failed,
          timestamp: DateTime.now(),
          duration: Duration.zero,
          errorMessage: e.toString(),
        );
      });
    });
    debugPrint('⏰ Auto-sync started: every ${interval.inMinutes} minutes');
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ─── Reset / Clear ──────────────────────────────────────────
  void reset() {
    _token = null;
    _currentStatus = SyncStatus.idle;
  }

  Future<void> resetSyncState() async {
    _currentStatus = SyncStatus.idle;
    _lastError = null;
    _statusController.add(SyncStatus.idle);
  }

  void clearHistory() {
    _lastPullCursor = 0;
  }

  // ─── Push all local data (stub) ─────────────────────────────
  Future<int> pushAllLocalDataToAppwrite() async {
    return 0;
  }

  // ─── Device ID generation ───────────────────────────────────
  String _generateDeviceId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'cf_dev_${now.toRadixString(36)}';
  }

  // ─── Audit log (stub — same interface as AppwriteSyncManager) ─
  final List<Map<String, dynamic>> _auditLog = [];
  List<Map<String, dynamic>> get auditLog => List.unmodifiable(_auditLog);

  void logToAudit({
    required String userMessage,
    required String aiResponse,
    required String executionResult,
    required bool wasConfirmed,
    String? commandType,
    String? commandDescription,
  }) {
    _auditLog.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'userMessage': userMessage,
      'aiResponse': aiResponse,
      'executionResult': executionResult,
      'wasConfirmed': wasConfirmed,
      'commandType': commandType,
      'commandDescription': commandDescription,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_auditLog.length > 100) _auditLog.removeAt(0);
  }

  void clearAuditLog() => _auditLog.clear();

// ─── Stubs for methods called by existing screens ──────────

  Future<int> pushLocalChanges() async => sync(pull: false).then((r) => r.recordsPushed);
  Future<int> pushAllLocalData() async => 0;
  Future<void> pullAllDataWithDisabledFK() async {}
  Future<void> pushAllEntities() async {}
  Future<Map<String, dynamic>> getSyncStatistics() async => {};
  Future<void> reinitializeAfterConfigChange() async { await initialize(forceRetry: true); }

  // ─── Pull remote changes (delta) — used by UnifiedSyncOrchestrator ──
  Future<bool> pullRemoteChanges() async {
    final result = await sync();
    return result.isSuccess;
  }

  // ─── Pull ALL remote data — used by appwrite_settings_screen ──
  Future<void> pullAllRemoteData() async {
    await sync(push: false);
  }

  // AppwriteService compatibility (some files pass this)
  dynamic get appwriteService => null;
}



// ═══ Backward compatibility aliases ═══════════════════════════
// All files that imported AppwriteSyncManager will get these aliases
// No need to change any imports or references in existing code.

typedef AppwriteSyncManager = CloudflareSyncManager;
typedef AppwriteRealtimeSync = CloudflareRealtimeSync;
