// ═══════════════════════════════════════════════════════════════
//  cloudflare_sync_manager_test.dart
//  Tests for CloudflareSyncManager (singleton, state, sync logic)
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/sync_enums.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  group('CloudflareSyncManager', () {
    test('is a singleton — same instance returned', () {
      final manager1 = CloudflareSyncManager();
      final manager2 = CloudflareSyncManager();
      expect(identical(manager1, manager2), isTrue);
    });

    test('initial state — not initialized, no token', () {
      final manager = CloudflareSyncManager();
      expect(manager.isAvailable, isFalse);
      expect(manager.token, isNull);
      expect(manager.currentStatus, equals(SyncStatus.idle));
      expect(manager.currentDeviceId, isNull);
    });

    test('reset clears token and status', () {
      final manager = CloudflareSyncManager();
      manager.reset();
      expect(manager.isAvailable, isFalse);
      expect(manager.currentStatus, equals(SyncStatus.idle));
    });

    test('resetSyncState sets status to idle', () async {
      final manager = CloudflareSyncManager();
      await manager.resetSyncState();
      expect(manager.currentStatus, equals(SyncStatus.idle));
      expect(manager.lastError, isNull);
    });

    test('syncStatusStream is a broadcast stream', () {
      final manager = CloudflareSyncManager();
      // Should allow multiple listeners (broadcast)
      final sub1 = manager.syncStatusStream.listen((_) {});
      final sub2 = manager.syncStatusStream.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      sub1.cancel();
      sub2.cancel();
    });

    test('sync without initialization returns failed SyncResult', () async {
      final manager = CloudflareSyncManager();
      manager.reset();
      final result = await manager.sync();
      expect(result.status, equals(SyncStatus.failed));
      expect(result.errorMessage, isNotNull);
      expect(result.errorMessage, contains('Not initialized'));
    });

    test('pushLocalChanges returns 0 when not initialized', () async {
      final manager = CloudflareSyncManager();
      manager.reset();
      final result = await manager.pushLocalChanges();
      expect(result, equals(0));
    });

    test('pullRemoteChanges returns false when not initialized', () async {
      final manager = CloudflareSyncManager();
      manager.reset();
      final result = await manager.pullRemoteChanges();
      expect(result, isFalse);
    });

    test(
      'pullAllRemoteData completes without throwing when not initialized',
      () async {
        final manager = CloudflareSyncManager();
        manager.reset();
        // Should not throw
        await manager.pullAllRemoteData();
      },
    );

    test(
      'pushAllLocalData throws StateError when not initialized (no fake success)',
      () async {
        final manager = CloudflareSyncManager();
        manager.reset();
        // ✅ (2026-09-05) كان يُرجع 0 دائماً والشاشة تعرض «تم رفع
        // البيانات بنجاح» — الآن يرمي ليُظهر الفشل في catch الشاشة.
        await expectLater(
          manager.pushAllLocalData(),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'getSyncStatistics returns real keys (never an empty fake)',
      () async {
        final manager = CloudflareSyncManager();
        final stats = await manager.getSyncStatistics();
        // ✅ (2026-09-05) كانت تُرجع {} فتعرض الشاشات أصفاراً دائمة —
        // الآن مفاتيح حقيقية تقرؤها شاشات الإحصائيات مباشرة.
        expect(stats, isNotEmpty);
        expect(stats, containsPair('totalSyncs', 0));
        expect(stats, containsPair('successfulSyncs', 0));
        expect(stats, containsPair('failedSyncs', 0));
        expect(stats['totalRecordsPushed'], isA<int>());
        expect(stats['totalRecordsPulled'], isA<int>());
        expect(stats['successRate'], isA<double>());
        expect(stats['outboxCount'], isA<int>());
        expect(stats['fullSyncCompleted'], isA<bool>());
      },
    );

    test(
      'resetSyncState clears the persisted pull cursor and full-sync flag',
      () async {
        // ✅ (2026-09-05) كانت تكتفي بضبط الحالة الظاهرة دون مسح
        // cursor/علامة full-sync بينما الرسالة تدّعي «إعادة التعيين».
        SharedPreferences.setMockInitialValues(<String, Object>{
          'cf_last_pull_cursor': 123456,
          'cf_full_sync_completed': true,
        });
        final manager = CloudflareSyncManager();
        await manager.resetSyncState();
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt('cf_last_pull_cursor'), isNull);
        expect(prefs.getBool('cf_full_sync_completed'), isNull);
        expect(manager.isFullSyncCompleted, isFalse);
      },
    );

    test(
      'sync() honors the local master toggle (appwrite_sync_enabled=false)',
      () async {
        // ✅ (2026-09-05) المفتاح المحلي كان يوقف الحلقات الخلفية فقط
        // والمزامنة اليدوية تتجاهله — الآن OFF يعني OFF لكل المسارات.
        SharedPreferences.setMockInitialValues(<String, Object>{
          'appwrite_sync_enabled': false,
        });
        final manager = CloudflareSyncManager();
        final result = await manager.sync();
        expect(result.status, equals(SyncStatus.idle));
        expect(result.errorMessage, contains('disabled locally'));
      },
    );

    test(
      'sync() proceeds past the local toggle when enabled (default true)',
      () async {
        final manager = CloudflareSyncManager();
        manager.reset();
        final result = await manager.sync();
        // بلا توكن → فشل «Not initialized» — أي أن الحارس المحلي لم يوقفها.
        expect(result.status, equals(SyncStatus.failed));
        expect(result.errorMessage, contains('Not initialized'));
      },
    );

    test('static device ID can be set and retrieved', () {
      CloudflareSyncManager.setStaticDeviceId('test-device-123');
      expect(
        CloudflareSyncManager.currentDeviceIdStatic,
        equals('test-device-123'),
      );
    });

    test('audit log can be written and cleared', () {
      final manager = CloudflareSyncManager();
      manager.clearAuditLog();
      expect(manager.auditLog, isEmpty);

      manager.logToAudit(
        userMessage: 'test message',
        aiResponse: 'test response',
        executionResult: 'success',
        wasConfirmed: true,
        commandType: 'sync',
      );
      expect(manager.auditLog.length, equals(1));
      expect(manager.auditLog.first['userMessage'], equals('test message'));

      manager.clearAuditLog();
      expect(manager.auditLog, isEmpty);
    });

    test('SyncResult computes isSuccess and hasConflicts correctly', () {
      final success = SyncResult(
        status: SyncStatus.success,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        recordsPushed: 10,
        recordsPulled: 5,
        conflicts: 0,
      );
      expect(success.isSuccess, isTrue);
      expect(success.hasConflicts, isFalse);

      final failed = SyncResult(
        status: SyncStatus.failed,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        errorMessage: 'test error',
      );
      expect(failed.isSuccess, isFalse);
      expect(failed.errorMessage, equals('test error'));

      final partial = SyncResult(
        status: SyncStatus.partial,
        timestamp: DateTime.now(),
        duration: Duration.zero,
        recordsPushed: 5,
        recordsPulled: 3,
        conflicts: 2,
      );
      expect(partial.isSuccess, isFalse);
      expect(partial.hasConflicts, isTrue);
    });

    test(
      'CloudflareRealtimeSync initializes and starts without errors',
      () async {
        final realtime = CloudflareRealtimeSync();
        await realtime.initialize(deviceId: 'test-device');
        await realtime.start();
        realtime.stop();
        expect(realtime.pendingRemoteChangesCount.value, equals(0));
        expect(realtime.hasRemoteChanges.value, isFalse);
      },
    );
  });

  group('SyncStatus enum', () {
    test('has all expected values', () {
      expect(SyncStatus.values, contains(SyncStatus.idle));
      expect(SyncStatus.values, contains(SyncStatus.syncing));
      expect(SyncStatus.values, contains(SyncStatus.success));
      expect(SyncStatus.values, contains(SyncStatus.failed));
      expect(SyncStatus.values, contains(SyncStatus.partial));
    });
  });

  group('AppwriteSyncManager typedef', () {
    test('AppwriteSyncManager is CloudflareSyncManager', () {
      // The typedef makes AppwriteSyncManager an alias for CloudflareSyncManager
      final manager = AppwriteSyncManager();
      expect(manager, isA<CloudflareSyncManager>());
    });

    test('AppwriteRealtimeSync is CloudflareRealtimeSync', () {
      final realtime = AppwriteRealtimeSync();
      expect(realtime, isA<CloudflareRealtimeSync>());
    });
  });
}
