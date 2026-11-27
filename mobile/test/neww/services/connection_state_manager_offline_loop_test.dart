import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/connection_state_manager.dart';

void main() {
  late ConnectivityPlatform originalPlatform;
  late FakeConnectivityPlatform fakePlatform;

  setUp(() {
    originalPlatform = ConnectivityPlatform.instance;
    fakePlatform = FakeConnectivityPlatform();
    ConnectivityPlatform.instance = fakePlatform;
  });

  tearDown(() {
    ConnectivityPlatform.instance = originalPlatform;
    fakePlatform.dispose();
  });

  test('لا يستدعي probe عند بدء التطبيق دون اتصال', () async {
    fakePlatform.current = const [ConnectivityResult.none];
    var probeCalls = 0;
    final manager = ConnectionStateManager.forTesting(
      connectivity: Connectivity(),
      appwriteProbe: () async => probeCalls++,
    );

    await manager.init();
    await manager.checkConnection();

    expect(manager.status, ConnectionStatus.offline);
    expect(probeCalls, 0);
    expect(fakePlatform.checkCalls, 1);

    manager.dispose();
  });

  test('المؤقت الدوري لا يعيد محاولة Appwrite أثناء offline', () {
    fakeAsync((async) {
      fakePlatform.current = const [ConnectivityResult.none];
      var probeCalls = 0;
      final manager = ConnectionStateManager.forTesting(
        connectivity: Connectivity(),
        appwriteProbe: () async => probeCalls++,
      );

      unawaited(manager.init());
      async.flushMicrotasks();
      expect(manager.status, ConnectionStatus.offline);
      expect(probeCalls, 0);

      async.elapse(const Duration(seconds: 91));
      async.flushMicrotasks();

      expect(manager.status, ConnectionStatus.offline);
      expect(probeCalls, 0);
      manager.dispose();
    });
  });

  test(
    'عودة الاتصال تنفذ probe واحداً ولا تكرر الطلب مع أحداث online متتابعة',
    () async {
      fakePlatform.current = const [ConnectivityResult.none];
      var probeCalls = 0;
      final manager = ConnectionStateManager.forTesting(
        connectivity: Connectivity(),
        appwriteProbe: () async => probeCalls++,
      );

      await manager.init();
      expect(probeCalls, 0);

      fakePlatform.emit(const [ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(manager.status, ConnectionStatus.online);
      expect(probeCalls, 1);

      // لا يوجد انتقال offline → online هنا؛ يجب ألا يبدأ probe إضافياً.
      fakePlatform.emit(const [ConnectivityResult.mobile]);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(manager.status, ConnectionStatus.online);
      expect(probeCalls, 1);
      manager.dispose();
    },
  );
}

class FakeConnectivityPlatform extends ConnectivityPlatform {
  final StreamController<List<ConnectivityResult>> _events =
      StreamController<List<ConnectivityResult>>.broadcast();

  List<ConnectivityResult> current = const [ConnectivityResult.none];
  int checkCalls = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checkCalls++;
    return current;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _events.stream;

  void emit(List<ConnectivityResult> results) {
    current = results;
    _events.add(results);
  }

  void dispose() {
    unawaited(_events.close());
  }
}
