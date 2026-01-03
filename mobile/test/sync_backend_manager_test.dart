import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_core/sync_backend.dart';
import 'package:marina_hotel_mobile/services/google_drive_unified_sync_coordinator.dart';

class StubBackend implements SyncBackend {
  StubBackend(this.kind);

  @override
  final SyncBackendKind kind;

  final _controller = StreamController<SyncResult>.broadcast();
  int syncCalls = 0;
  int localChangeCount = 0;
  bool signedIn = false;

  @override
  Stream<SyncResult> get results => _controller.stream;

  @override
  bool get isReady => true;

  @override
  Future<SyncResult> performSync({required SyncTrigger trigger, SyncMode mode = SyncMode.smart}) async {
    syncCalls++;
    final result = SyncResult.success(message: 'ok', pushed: 0, pulled: 0);
    _controller.add(result);
    return result;
  }

  @override
  Future<void> notifyLocalChange({String? table, String? operation, int count = 1}) async {
    localChangeCount += count;
  }

  @override
  Future<void> onSignInChanged(bool isSignedIn) async {
    signedIn = isSignedIn;
  }

  @override
  Future<void> onAppForeground() async {}

  @override
  Future<void> setDebounceSeconds(int seconds) async {}

  @override
  Future<void> setPullInterval(int minutes) async {}

  @override
  Future<Map<String, dynamic>> status() async => {'syncCalls': syncCalls};

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('SyncBackendManager', () {
    final manager = SyncBackendManager.instance;

    setUp(() {
      manager.reset();
    });

    test('activeOrNull returns null before activation', () {
      expect(manager.activeOrNull, isNull);
    });

    test('routes sync calls through active backend', () async {
      final backend = StubBackend(SyncBackendKind.googleDrive);
      manager.register(backend, activate: true);

      final result = await manager.active.performSync(
        trigger: SyncTrigger.manual,
        mode: SyncMode.smart,
      );

      expect(result.success, isTrue);
      expect(backend.syncCalls, 1);
      backend.dispose();
    });

    test('activates specified backend', () {
      final first = StubBackend(SyncBackendKind.googleDrive);
      final second = StubBackend(SyncBackendKind.restApi);
      manager.register(first, activate: true);
      manager.register(second);

      manager.activate(SyncBackendKind.restApi);

      expect(manager.active.kind, SyncBackendKind.restApi);
      first.dispose();
      second.dispose();
    });

    test('emits sync results from active backend stream', () async {
      final backend = StubBackend(SyncBackendKind.googleDrive);
      manager.register(backend, activate: true);
      final received = <SyncResult>[];
      final sub = manager.active.results.listen(received.add);

      await manager.active.performSync(
        trigger: SyncTrigger.manual,
        mode: SyncMode.smart,
      );

      expect(received.length, 1);
      await sub.cancel();
      backend.dispose();
    });
  });
}
