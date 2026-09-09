// ═══════════════════════════════════════════════════════════════
//  cloudflare_sync_manager_core_test.dart
//  Tests for CloudflareSyncManagerCore orchestrator
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/cloudflare_sync_manager_core.dart';
import '../lib/services/local_db.dart';
import '../lib/services/vector_clock_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockVectorClockService extends Mock implements VectorClockService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ─── Entity Detection Tests ─────────────────────────────────

  group('detectEntity', () {
    test('detects rooms', () {
      final record = {'room_number': '101', 'price': 100.0};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'rooms');
    });

    test('detects bookings', () {
      final record = {'guest_name': 'Ahmed', 'checkin_date': '2026-01-01'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'bookings');
    });

    test('detects payments', () {
      final record = {'amount': 50.0, 'payment_method': 'cash'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'payments');
    });

    test('detects expenses', () {
      final record = {'expense_type': 'maintenance', 'description': 'fix'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'expenses');
    });

    test('detects employees', () {
      final record = {'basic_salary': 500, 'position': 'cleaner'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'employees');
    });

    test('detects debts', () {
      final record = {'debt_reason': 'advance', 'remaining_amount': 200};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'debts');
    });

    test('detects booking_nights', () {
      final record = {'final_rate': 80.0, 'hotel_day_key': '2026-09-01'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'booking_nights');
    });

    test('detects booking_price_adjustments', () {
      final record = {
        'adjustment_type': 'discount',
        'effective_hotel_day': '2026-09-01',
      };
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'booking_price_adjustments',
      );
    });

    test('detects booking_notes', () {
      final record = {'note_text': 'Late checkout', 'alert_type': 'info'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'booking_notes');
    });

    test('detects guest_infos', () {
      final record = {'guest_name': 'Sara', 'id_number': '12345'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'guest_infos');
    });

    test('detects shift_notes', () {
      final record = {'shift_date': '2026-09-01', 'is_read': 0};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'shift_notes');
    });

    test('detects cash_transactions', () {
      final record = {
        'transaction_type': 'income',
        'transaction_time': '10:00',
      };
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'cash_transactions',
      );
    });

    test('detects salary_cycles', () {
      final record = {'cycle_key': '2026-W1', 'expected_amount': 5000};
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'salary_cycles',
      );
    });

    test('detects salary_payments', () {
      final record = {'payment_date_iso': '2026-09-01', 'cycle_id': 1};
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'salary_payments',
      );
    });

    test('detects salary_withdrawals', () {
      final record = {'withdrawal_type': 'advance', 'amount': 200};
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'salary_withdrawals',
      );
    });

    test('detects salary_carry_over_logs', () {
      final record = {
        'previous_cycle_start': '2026-08-01',
        'new_cycle_start': '2026-09-01',
      };
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'salary_carry_over_logs',
      );
    });

    test('detects price_adjustments', () {
      final record = {'target_type': 'booking', 'target_uuid': 'uuid-123'};
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'price_adjustments',
      );
    });

    test('detects audit_logs', () {
      final record = {'operation_type': 'create', 'entity_type': 'booking'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'audit_logs');
    });

    test('detects payment_voids', () {
      final record = {'void_reason': 'duplicate', 'voided_by': 'admin'};
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'payment_voids',
      );
    });

    test('detects inventory_items', () {
      final record = {'minimum_quantity': 5};
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'inventory_items',
      );
    });

    test('detects inventory_transactions', () {
      final record = {'movement_type': 'in', 'balance_after': 100};
      expect(
        CloudflareSyncManagerCore.detectEntity(record),
        'inventory_transactions',
      );
    });

    test('detects devices', () {
      final record = {'device_name': 'Galaxy S24'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'devices');
    });

    test('detects blacklist', () {
      final record = {'reported_by': 'admin'};
      expect(CloudflareSyncManagerCore.detectEntity(record), 'blacklist');
    });

    test('detects app_users', () {
      final record = {
        'username': 'admin',
        'credentials_version': 1,
      };
      expect(CloudflareSyncManagerCore.detectEntity(record), 'app_users');
    });

    test('returns null for unknown record', () {
      final record = {'foo': 'bar'};
      expect(CloudflareSyncManagerCore.detectEntity(record), isNull);
    });
  });

  // ─── FK Rules Tests ─────────────────────────────────────────

  group('FK Rules', () {
    test('fkRulesByEntity contains all entities with FK rules', () {
      expect(fkRulesByEntity.containsKey('bookings'), isTrue);
      expect(fkRulesByEntity.containsKey('booking_nights'), isTrue);
      expect(fkRulesByEntity.containsKey('booking_notes'), isTrue);
      expect(fkRulesByEntity.containsKey('payments'), isTrue);
      expect(fkRulesByEntity.containsKey('booking_price_adjustments'), isTrue);
      expect(fkRulesByEntity.containsKey('salary_cycles'), isTrue);
      expect(fkRulesByEntity.containsKey('salary_payments'), isTrue);
      expect(fkRulesByEntity.containsKey('salary_withdrawals'), isTrue);
      expect(fkRulesByEntity.containsKey('salary_carry_over_logs'), isTrue);
      expect(fkRulesByEntity.containsKey('inventory_transactions'), isTrue);
    });

    test('bookings has naturalKey rule for room_number', () {
      final rules = fkRulesByEntity['bookings']!;
      expect(rules.length, 1);
      expect(rules.first.column, 'room_number');
      expect(rules.first.kind, FkKind.naturalKey);
      expect(rules.first.parentTable, 'rooms');
      expect(rules.first.parentKeyColumn, 'room_number');
    });

    test('payments has two FK rules', () {
      final rules = fkRulesByEntity['payments']!;
      expect(rules.length, 2);
      expect(rules[0].column, 'booking_local_id');
      expect(rules[0].nullable, isTrue);
      expect(rules[1].column, 'cash_transaction_local_id');
      expect(rules[1].nullWhenUnresolvable, isTrue);
    });

    test('salary_payments depends on salary_cycles', () {
      final rules = fkRulesByEntity['salary_payments']!;
      expect(rules.first.column, 'cycle_id');
      expect(rules.first.parentTable, 'salary_cycles');
    });

    test('total FK rules count', () {
      expect(fkRules.length, 12);
    });
  });

  // ─── Pull Apply Priority Tests ──────────────────────────────

  group('pullApplyPriority', () {
    test('rooms is first (priority 0)', () {
      expect(pullApplyPriority['rooms'], 0);
    });

    test('employees and inventory_items have same priority', () {
      expect(pullApplyPriority['employees'], 1);
      expect(pullApplyPriority['inventory_items'], 1);
    });

    test('bookings come before booking_nights', () {
      expect(pullApplyPriority['bookings']!, lessThan(
        pullApplyPriority['booking_nights']!,
      ));
    });

    test('salary_cycles before salary_withdrawals', () {
      expect(pullApplyPriority['salary_cycles']!, lessThan(
        pullApplyPriority['salary_withdrawals']!,
      ));
    });
  });

  // ─── Quarantine State Tests ─────────────────────────────────

  group('QuarantineState', () {
    late QuarantineState quarantine;

    setUp(() {
      quarantine = QuarantineState();
    });

    test('initial state is empty', () {
      expect(quarantine.blockCounts, isEmpty);
      expect(quarantine.quarantinedRecords, isEmpty);
      expect(quarantine.totalQuarantined, 0);
    });

    test('isQuarantined returns false when empty', () {
      expect(quarantine.isQuarantined('bookings', 'uuid-1'), isFalse);
    });

    test('recordBlock increments count', () {
      quarantine.recordBlock('bookings', 'uuid-1');
      expect(quarantine.blockCounts['bookings/uuid-1'], 1);
      quarantine.recordBlock('bookings', 'uuid-1');
      expect(quarantine.blockCounts['bookings/uuid-1'], 2);
    });

    test('quarantine stores record and makes isQuarantined true', () {
      quarantine.quarantine('bookings', 'uuid-1', {'updated_at': 100});
      expect(quarantine.isQuarantined('bookings', 'uuid-1'), isTrue);
      expect(quarantine.totalQuarantined, 1);
    });

    test('clearRecord removes both block count and quarantined record', () {
      quarantine.recordBlock('bookings', 'uuid-1');
      quarantine.recordBlock('bookings', 'uuid-1');
      quarantine.quarantine('bookings', 'uuid-1', {'updated_at': 100});

      quarantine.clearRecord('bookings', 'uuid-1');
      expect(quarantine.isQuarantined('bookings', 'uuid-1'), isFalse);
      expect(quarantine.blockCounts.containsKey('bookings/uuid-1'), isFalse);
    });

    test('loadFromPrefs restores state', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(QuarantineState.countsKey, jsonEncode({
        'bookings/uuid-1': 2,
      }));
      await prefs.setString(QuarantineState.recordsKey, jsonEncode({
        'bookings/uuid-1': {
          'entity': 'bookings',
          'local_uuid': 'uuid-1',
          'first_seen': 1000,
        },
      }));

      final loaded = QuarantineState();
      loaded.loadFromPrefs(prefs);
      expect(loaded.blockCounts['bookings/uuid-1'], 2);
      expect(loaded.isQuarantined('bookings', 'uuid-1'), isTrue);
    });

    test('persist saves to SharedPreferences', () async {
      quarantine.recordBlock('payments', 'uuid-2');
      quarantine.quarantine('payments', 'uuid-2', {'updated_at': 200});

      final prefs = await SharedPreferences.getInstance();
      await quarantine.persist(prefs);

      final loaded = QuarantineState();
      loaded.loadFromPrefs(prefs);
      expect(loaded.blockCounts['payments/uuid-2'], 1);
      expect(loaded.isQuarantined('payments', 'uuid-2'), isTrue);
    });

    test('identity format is entity/local_uuid', () {
      quarantine.recordBlock('bookings', 'abc-123');
      expect(quarantine.blockCounts.containsKey('bookings/abc-123'), isTrue);
    });

    test('handles null local_uuid', () {
      quarantine.recordBlock('blacklist', null);
      expect(quarantine.blockCounts.containsKey('blacklist/null'), isTrue);
    });
  });

  // ─── SyncStats Tests ────────────────────────────────────────

  group('SyncStats', () {
    late SyncStats stats;

    setUp(() {
      stats = SyncStats();
    });

    test('initial state has zeros', () {
      expect(stats.totalSyncs, 0);
      expect(stats.successfulSyncs, 0);
      expect(stats.failedSyncs, 0);
      expect(stats.totalPushed, 0);
      expect(stats.totalPulled, 0);
      expect(stats.lastSyncTime, isNull);
    });

    test('recordOutcome increments correctly', () async {
      final startedAt = DateTime(2026, 9, 10);
      await stats.recordOutcome(
        success: true,
        pushed: 5,
        pulled: 10,
        startedAt: startedAt,
      );

      expect(stats.totalSyncs, 1);
      expect(stats.successfulSyncs, 1);
      expect(stats.failedSyncs, 0);
      expect(stats.totalPushed, 5);
      expect(stats.totalPulled, 10);
      expect(stats.lastSyncTime, startedAt);
    });

    test('recordOutcome with failure increments failedSyncs', () async {
      await stats.recordOutcome(
        success: false,
        pushed: 0,
        pulled: 0,
        startedAt: DateTime.now(),
      );

      expect(stats.totalSyncs, 1);
      expect(stats.successfulSyncs, 0);
      expect(stats.failedSyncs, 1);
    });

    test('toMap returns correct structure', () {
      stats.totalSyncs = 10;
      stats.successfulSyncs = 8;
      stats.totalPushed = 50;
      stats.totalPulled = 100;

      final map = stats.toMap(
        outboxCount: 5,
        fullSyncCompleted: true,
        lastError: null,
      );

      expect(map['totalSyncs'], 10);
      expect(map['successfulSyncs'], 8);
      expect(map['totalRecordsPushed'], 50);
      expect(map['totalRecordsPulled'], 100);
      expect(map['successRate'], 0.8);
      expect(map['outboxCount'], 5);
      expect(map['fullSyncCompleted'], true);
    });

    test('successRate is 0 when totalSyncs is 0', () {
      final map = stats.toMap();
      expect(map['successRate'], 0.0);
    });

    test('loadFromPrefs restores stats', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cf_sync_stats_v1', jsonEncode({
        'totalSyncs': 5,
        'successfulSyncs': 4,
        'failedSyncs': 1,
        'totalPushed': 20,
        'totalPulled': 50,
        'lastSyncMs': DateTime(2026, 9, 10).millisecondsSinceEpoch,
      }));

      final loaded = SyncStats();
      loaded.loadFromPrefs(prefs);
      expect(loaded.totalSyncs, 5);
      expect(loaded.successfulSyncs, 4);
      expect(loaded.failedSyncs, 1);
      expect(loaded.totalPushed, 20);
      expect(loaded.totalPulled, 50);
      expect(loaded.lastSyncTime, isNotNull);
    });
  });

  // ─── SyncResult Tests ───────────────────────────────────────

  group('SyncResult', () {
    test('isSuccess returns true for success status', () {
      final result = SyncResult(
        status: SyncStatus.success,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
      expect(result.isSuccess, isTrue);
    });

    test('isSuccess returns false for failed status', () {
      final result = SyncResult(
        status: SyncStatus.failed,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
      expect(result.isSuccess, isFalse);
    });

    test('hasConflicts returns true when conflicts > 0', () {
      final result = SyncResult(
        status: SyncStatus.success,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        conflicts: 3,
      );
      expect(result.hasConflicts, isTrue);
    });

    test('hasConflicts returns false when conflicts is 0', () {
      final result = SyncResult(
        status: SyncStatus.success,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
      expect(result.hasConflicts, isFalse);
    });

    test('default values are correct', () {
      final result = SyncResult(
        status: SyncStatus.idle,
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
      expect(result.recordsPushed, 0);
      expect(result.recordsPulled, 0);
      expect(result.conflicts, 0);
      expect(result.errorMessage, isNull);
    });
  });

  // ─── PullApplyReport Tests ──────────────────────────────────

  group('PullApplyReport', () {
    test('isClean returns true when no unresolvable or errors', () {
      final report = PullApplyReport(
        appliedCount: 10,
        deferredCount: 0,
        touchedEntities: {'bookings'},
        unresolvable: [],
        errors: [],
      );
      expect(report.isClean, isTrue);
    });

    test('isClean returns false when unresolvable exists', () {
      final report = PullApplyReport(
        appliedCount: 10,
        deferredCount: 2,
        touchedEntities: {'bookings'},
        unresolvable: ['payments/uuid-1'],
        errors: [],
      );
      expect(report.isClean, isFalse);
    });

    test('isClean returns false when errors exist', () {
      final report = PullApplyReport(
        appliedCount: 10,
        deferredCount: 0,
        touchedEntities: {'bookings'},
        unresolvable: [],
        errors: ['payments/uuid-1: db error'],
      );
      expect(report.isClean, isFalse);
    });
  });

  // ─── toDriftValue Tests ─────────────────────────────────────

  group('toDriftValue', () {
    test('null returns null', () {
      expect(CloudflareSyncManagerCore.toDriftValue(null), isNull);
    });

    test('bool true returns 1', () {
      expect(CloudflareSyncManagerCore.toDriftValue(true), 1);
    });

    test('bool false returns 0', () {
      expect(CloudflareSyncManagerCore.toDriftValue(false), 0);
    });

    test('List returns JSON string', () {
      final result = CloudflareSyncManagerCore.toDriftValue([1, 2, 3]);
      expect(result, '[1,2,3]');
    });

    test('Map returns JSON string', () {
      final result = CloudflareSyncManagerCore.toDriftValue({'a': 1});
      expect(result, '{"a":1}');
    });

    test('int passes through', () {
      expect(CloudflareSyncManagerCore.toDriftValue(42), 42);
    });

    test('double passes through', () {
      expect(CloudflareSyncManagerCore.toDriftValue(3.14), 3.14);
    });

    test('String passes through', () {
      expect(CloudflareSyncManagerCore.toDriftValue('hello'), 'hello');
    });
  });

  // ─── Derived Refresh Entities Tests ─────────────────────────

  group('derivedRefreshEntities', () {
    test('contains bookings', () {
      expect(derivedRefreshEntities.contains('bookings'), isTrue);
    });

    test('contains booking_nights', () {
      expect(derivedRefreshEntities.contains('booking_nights'), isTrue);
    });

    test('contains payments', () {
      expect(derivedRefreshEntities.contains('payments'), isTrue);
    });

    test('contains payment_voids', () {
      expect(derivedRefreshEntities.contains('payment_voids'), isTrue);
    });
  });

  // ─── CloudflareSyncManagerCore Integration Tests ────────────

  group('CloudflareSyncManagerCore', () {
    late CloudflareSyncManagerCore core;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;
    late MockVectorClockService mockVectorClock;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();
      mockVectorClock = MockVectorClockService();

      core = CloudflareSyncManagerCore(
        database: mockDatabase,
        httpClient: mockHttpClient,
        vectorClockService: mockVectorClock,
      );
    });

    test('creates sub-services', () {
      expect(core.deviceService, isNotNull);
      expect(core.pushService, isNotNull);
      expect(core.pullService, isNotNull);
    });

    test('quarantine starts empty', () {
      expect(core.quarantine.totalQuarantined, 0);
    });

    test('stats start at zero', () {
      expect(core.stats.totalSyncs, 0);
    });

    test('failedCollectionsInLastSync starts empty', () {
      expect(core.failedCollectionsInLastSync, isEmpty);
    });

    test('resetCycleState clears failed collections', () {
      core.failedCollectionsInLastSync.add('bookings');
      core.failedCollectionsInLastSync.add('payments');
      core.resetCycleState();
      expect(core.failedCollectionsInLastSync, isEmpty);
    });

    test('applyPulledRecords with empty list returns clean report', () async {
      final report = await core.applyPulledRecords([]);
      expect(report.appliedCount, 0);
      expect(report.deferredCount, 0);
      expect(report.isClean, isTrue);
    });

    test('setCredentials delegates to sub-services', () {
      core.setCredentials('test-token', 'device-123');
      expect(core.deviceService.token, 'test-token');
      expect(core.deviceService.deviceId, 'device-123');
      expect(core.pushService.token, isA<String>());
      expect(core.pullService.token, isA<String>());
    });

    test('clearColumnsCache clears the cache', () {
      core.clearColumnsCache();
      // No assertion needed — just verifying no exception
    });

    test('dispose cleans up', () {
      core.dispose();
      // No assertion needed — just verifying no exception
    });
  });
}
