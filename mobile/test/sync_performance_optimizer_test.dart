import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_performance_optimizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SyncPerformanceOptimizer', () {
    test('singleton instance is reused', () {
      final first = SyncPerformanceOptimizer();
      final second = SyncPerformanceOptimizer();
      expect(identical(first, second), isTrue);
    });

    test('shouldSkipSync returns Future<bool>', () async {
      final result = await SyncPerformanceOptimizer().shouldSkipSync();
      expect(result, isA<bool>());
    });
  });
}
