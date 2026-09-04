import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/local_db.dart';

enum MigrationStatus {
  idle,
  measuring,
  running,
  success,
  partial,
  failed,
}

@immutable
class MigrationState {
  final MigrationStatus status;
  final int totalRecords;
  final int totalPushed;
  final int totalFailed;
  final double networkSpeedKbps;
  final int batchSize;
  final int currentTableIndex;
  final String currentTable;
  final String? errorMessage;
  final Map<String, bool> tableProgress;
  final bool isComplete;

  const MigrationState({
    this.status = MigrationStatus.idle,
    this.totalRecords = 0,
    this.totalPushed = 0,
    this.totalFailed = 0,
    this.networkSpeedKbps = 0,
    this.batchSize = 0,
    this.currentTableIndex = 0,
    this.currentTable = '',
    this.errorMessage,
    this.tableProgress = const {},
    this.isComplete = false,
  });

  double get progress => totalRecords == 0 ? 0.0 : totalPushed / totalRecords;
  int get tablesDone => tableProgress.values.where((v) => v).length;

  /// Ordered list of entities the migration tracks (matches
  /// `CloudflareConfig.migrationOrder` in the api-cloudflare branch).
  /// Stored locally so this compiles on branches without that file.
  static const List<String> migrationOrder = [
    'rooms',
    'employees',
    'salary_cycles',
    'cash_transactions',
    'bookings',
    'guest_infos',
    'booking_notes',
    'booking_nights',
    'booking_price_adjustments',
    'payments',
    'expenses',
    'debts',
    'salary_payments',
    'salary_withdrawals',
    'salary_carry_over_logs',
    'audit_logs',
    'payment_voids',
    'shift_notes',
    'price_adjustments',
  ];

  List<String> get tables => migrationOrder;
  int get tablesTotal => tables.length;

  MigrationState copyWith({
    MigrationStatus? status,
    int? totalRecords,
    int? totalPushed,
    int? totalFailed,
    double? networkSpeedKbps,
    int? batchSize,
    int? currentTableIndex,
    String? currentTable,
    String? Function()? errorMessage,
    Map<String, bool>? tableProgress,
    bool? isComplete,
  }) {
    return MigrationState(
      status: status ?? this.status,
      totalRecords: totalRecords ?? this.totalRecords,
      totalPushed: totalPushed ?? this.totalPushed,
      totalFailed: totalFailed ?? this.totalFailed,
      networkSpeedKbps: networkSpeedKbps ?? this.networkSpeedKbps,
      batchSize: batchSize ?? this.batchSize,
      currentTableIndex: currentTableIndex ?? this.currentTableIndex,
      currentTable: currentTable ?? this.currentTable,
      errorMessage:
          errorMessage != null ? errorMessage!() : this.errorMessage,
      tableProgress: tableProgress ?? this.tableProgress,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

@immutable
class MigrationOutcome {
  final bool isSuccess;
  final bool isPartial;
  final int totalRecords;
  final int totalPushed;
  final int totalFailed;
  final List<String> errors;

  const MigrationOutcome({
    required this.isSuccess,
    required this.isPartial,
    required this.totalRecords,
    required this.totalPushed,
    required this.totalFailed,
    this.errors = const [],
  });
}

typedef ProgressCallback = void Function(
    int pushed, int total, String table);

abstract class MigrationBackend {
  const MigrationBackend();
  Future<bool> isAvailable();
  Future<MigrationOutcome> migrate({
    required AppDatabase db,
    required String token,
    required String deviceId,
    required ProgressCallback? onProgress,
  });
}

/// Default no-op backend.
/// When the `api-cloudflare` branch is present, the real
/// `CloudflareMigrationBackend` is injected via `ProviderScope.overrideWith`
/// in `cloudflare_sync_manager.dart` / main.dart.
class NoOpMigrationBackend extends MigrationBackend {
  const NoOpMigrationBackend();
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<MigrationOutcome> migrate({
    required AppDatabase db,
    required String token,
    required String deviceId,
    required ProgressCallback? onProgress,
  }) async {
    return const MigrationOutcome(
      isSuccess: false,
      isPartial: false,
      totalRecords: 0,
      totalPushed: 0,
      totalFailed: 0,
      errors: ['Cloudflare Worker services not present in this build'],
    );
  }
}

/// Inject this provider at the root to supply the real Cloudflare backend.
final migrationBackendProvider = Provider<MigrationBackend>(
  (ref) => const NoOpMigrationBackend(),
);

class CloudflareMigrationNotifier extends StateNotifier<MigrationState> {
  CloudflareMigrationNotifier(this._read) : super(const MigrationState());

  final Reader _read;

  Future<void> checkStatus() async {
    final complete = await _isComplete();
    final progress = await _getProgress();
    final all = {for (final t in MigrationState.migrationOrder) t: false};
    all.addAll(progress);
    state = state.copyWith(
      isComplete: complete,
      tableProgress: all,
      status: complete ? MigrationStatus.success : MigrationStatus.idle,
    );
  }

  Future<void> startMigration(AppDatabase db) async {
    final backend = _read(migrationBackendProvider);
    final available = await backend.isAvailable();
    if (!available) {
      state = state.copyWith(
        status: MigrationStatus.failed,
        errorMessage: () =>
            'Cloudflare Worker غير مهيأ. أضف CLOUDFLARE_* إلى .env وفعّل فرع api-cloudflare.',
      );
      return;
    }

    final token = await _readToken();
    final deviceId = await _readDeviceId();
    if (token == null || deviceId == null) {
      state = state.copyWith(
        status: MigrationStatus.failed,
        errorMessage: () => 'الرجاء تسجيل الدخول إلى Cloudflare أولاً',
      );
      return;
    }

    state = state.copyWith(status: MigrationStatus.measuring);

    try {
      final result = await backend.migrate(
        db: db,
        token: token,
        deviceId: deviceId,
        onProgress: (pushed, total, table) {
          state = state.copyWith(
            status: MigrationStatus.running,
            totalPushed: pushed,
            totalRecords: total,
            currentTable: table,
            networkSpeedKbps: 0,
          );
        },
      );
      final progress = Map<String, bool>.from(state.tableProgress);
      state = state.copyWith(
        status: result.isSuccess
            ? MigrationStatus.success
            : (result.isPartial ? MigrationStatus.partial : MigrationStatus.failed),
        isComplete: result.isSuccess,
        totalPushed: result.totalPushed,
        totalRecords: result.totalRecords,
        totalFailed: result.totalFailed,
        tableProgress: progress,
        errorMessage: () =>
            result.errors.isEmpty ? null : result.errors.join('\n'),
      );
    } catch (e) {
      state = state.copyWith(
        status: MigrationStatus.failed,
        errorMessage: () => e.toString(),
      );
    }
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cf_migration_complete');
    await prefs.remove('cf_migration_progress');
    await prefs.remove('cf_migration_ts_cursor');
    await checkStatus();
  }

  Future<bool> _isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('cf_migration_complete') ?? false;
  }

  Future<Map<String, bool>> _getProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('cf_migration_progress');
    if (json == null) return {};
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, v as bool));
  }

  Future<String?> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cf_auth_token');
  }

  Future<String?> _readDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cf_device_id');
  }
}

final cloudflareMigrationProvider =
    StateNotifierProvider<CloudflareMigrationNotifier, MigrationState>((ref) {
  final notifier = CloudflareMigrationNotifier(ref.read);
  notifier.checkStatus();
  return notifier;
});
