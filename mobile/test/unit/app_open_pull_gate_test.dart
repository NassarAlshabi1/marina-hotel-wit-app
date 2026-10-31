import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync/app_open_pull_gate.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppOpenPullGate', () {
    const lastPull = 1_800_000_000_000;
    final lastPullAt = DateTime.fromMillisecondsSinceEpoch(lastPull);

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('does not pull before one hour and becomes due at one hour', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        SyncConstants.lastPullWallClockKey: lastPull,
      });
      final prefs = await SharedPreferences.getInstance();

      final beforeHour = AppOpenPullGate.check(
        prefs,
        now: lastPullAt.add(const Duration(minutes: 59, seconds: 59)),
      );
      final atHour = AppOpenPullGate.check(
        prefs,
        now: lastPullAt.add(const Duration(hours: 1)),
      );

      expect(beforeHour.shouldPull, isFalse);
      expect(beforeHour.remainingUntilNextPull, const Duration(seconds: 1));
      expect(atHour.shouldPull, isTrue);
      expect(atHour.remainingUntilNextPull, Duration.zero);
    });

    test(
      'reads the legacy app-open timestamp when no pull timestamp exists',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          SyncConstants.lastAppOpenPullKey: lastPull,
        });
        final prefs = await SharedPreferences.getInstance();

        final gate = AppOpenPullGate.check(
          prefs,
          now: lastPullAt.add(const Duration(minutes: 30)),
        );

        expect(gate.shouldPull, isFalse);
        expect(gate.elapsedSinceLastPull, const Duration(minutes: 30));
      },
    );

    test(
      'markPulled writes the same wall-clock timestamp to both keys',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final pullTime = lastPullAt.add(const Duration(hours: 2));

        await AppOpenPullGate.markPulled(prefs, now: pullTime);

        expect(
          prefs.getInt(SyncConstants.lastPullWallClockKey),
          pullTime.millisecondsSinceEpoch,
        );
        expect(
          prefs.getInt(SyncConstants.lastAppOpenPullKey),
          pullTime.millisecondsSinceEpoch,
        );
      },
    );
  });
}
