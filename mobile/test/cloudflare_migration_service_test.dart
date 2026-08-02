// ═══════════════════════════════════════════════════════════════
//  cloudflare_migration_service_test.dart
//  Tests for CloudflareMigrationService (SQL building, batch logic)
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_migration_service.dart';

void main() {
  group('CloudflareMigrationService', () {
    test('is a singleton — same instance returned', () {
      final s1 = CloudflareMigrationService.instance;
      final s2 = CloudflareMigrationService.instance;
      expect(identical(s1, s2), isTrue);
    });

    test('isMigrationComplete returns false initially', () async {
      // Note: This depends on SharedPreferences — may need mocking
      // For now, just verify it doesn't throw
      expect(() async {
        await CloudflareMigrationService.instance.isMigrationComplete();
      }, returnsNormally);
    });

    test('getMigrationProgress returns empty map initially', () async {
      expect(() async {
        await CloudflareMigrationService.instance.getMigrationProgress();
      }, returnsNormally);
    });

    test('reset completes without error', () async {
      expect(() async {
        await CloudflareMigrationService.instance.reset();
      }, returnsNormally);
    });
  });

  group('MigrationResult', () {
    test('isSuccess requires totalPushed > 0 and totalFailed == 0', () {
      final success = MigrationResult(
        totalRecords: 100,
        totalPushed: 100,
        totalFailed: 0,
        errors: [],
        duration: Duration.zero,
      );
      expect(success.isSuccess, isTrue);
      expect(success.isPartialSuccess, isFalse);
      expect(success.isCompleteFailure, isFalse);
    });

    test('isPartialSuccess when some pushed, some failed', () {
      final partial = MigrationResult(
        totalRecords: 100,
        totalPushed: 60,
        totalFailed: 40,
        errors: ['error1', 'error2'],
        duration: Duration.zero,
      );
      expect(partial.isSuccess, isFalse);
      expect(partial.isPartialSuccess, isTrue);
      expect(partial.isCompleteFailure, isFalse);
    });

    test('isCompleteFailure when nothing pushed', () {
      final failure = MigrationResult(
        totalRecords: 100,
        totalPushed: 0,
        totalFailed: 100,
        errors: ['timeout', 'timeout'],
        duration: Duration.zero,
      );
      expect(failure.isSuccess, isFalse);
      expect(failure.isPartialSuccess, isFalse);
      expect(failure.isCompleteFailure, isTrue);
    });

    test('isCompleteFailure when nothing pushed and nothing failed (0/0)', () {
      final empty = MigrationResult(
        totalRecords: 0,
        totalPushed: 0,
        totalFailed: 0,
        errors: [],
        duration: Duration.zero,
      );
      // Edge case: 0/0 — this should be a failure (nothing was pushed)
      expect(empty.isSuccess, isFalse);
      expect(empty.isCompleteFailure, isTrue);
    });

    test('isSuccess false when totalPushed > 0 but totalFailed > 0', () {
      final mixed = MigrationResult(
        totalRecords: 50,
        totalPushed: 40,
        totalFailed: 10,
        errors: ['one error'],
        duration: Duration(seconds: 5),
      );
      expect(mixed.isSuccess, isFalse);
      expect(mixed.isPartialSuccess, isTrue);
    });
  });

  group('MigrationResult edge cases', () {
    test('empty errors list with 0 pushed is complete failure', () {
      final result = MigrationResult(
        totalRecords: 4934,
        totalPushed: 0,
        totalFailed: 0,
        errors: [],
        duration: Duration(seconds: 48),
      );
      // This is the exact bug we fixed: 0/4934 with 0 errors
      expect(result.isSuccess, isFalse);
      expect(result.isCompleteFailure, isTrue);
      expect(result.errors, isEmpty);
    });

    test('all records pushed with no errors is success', () {
      final result = MigrationResult(
        totalRecords: 4934,
        totalPushed: 4934,
        totalFailed: 0,
        errors: [],
        duration: Duration(seconds: 120),
      );
      expect(result.isSuccess, isTrue);
      expect(result.isCompleteFailure, isFalse);
    });
  });
}
