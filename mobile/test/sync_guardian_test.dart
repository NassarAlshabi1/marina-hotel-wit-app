import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_guardian.dart';

void main() {
  test('lock/unlock is reentrant and guards concurrent syncs', () async {
    final guardian = SyncGuardian();
    expect(await guardian.acquire('sync1'), isTrue);
    expect(await guardian.acquire('sync2'), isFalse);
    guardian.release('sync1');
    expect(await guardian.acquire('sync2'), isTrue);
  });

  test('withGuard runs callback only when lock acquired', () async {
    final guardian = SyncGuardian();
    var called = 0;
    await guardian.withGuard('s1', () async {
      called++;
      expect(await guardian.acquire('s2'), isFalse);
    });
    expect(called, 1);
  });
}
