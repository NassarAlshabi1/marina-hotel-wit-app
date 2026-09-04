// ═══════════════════════════════════════════════════════════════
//  cloudflare_dual_run_service_test.dart — plan phases 5.3/6
//
//  تغطية: مفتاح الإيقاف (تجاوز محلي + قيمة بعيدة افتراضية) والمقارنة
//  الظلّية (تطابق، فروق تُسجَّل، تعذّر القياس -1 لا يُحتسب، فشل
//  /api_STATS كامل يُبلَّغ ولا يُرمى).
// ═══════════════════════════════════════════════════════════════

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:marina_hotel_mobile/services/cloudflare_dual_run_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('kill switch (plan phase 6)', () {
    test('defaults to enabled when no override and no remote config', () async {
      final enabled = await CloudflareDualRunService()
          .isCloudflareSyncEnabled();
      expect(enabled, isTrue, reason: 'لا نُعطّل المزامنة لإخفاق قياس');
    });

    test('local override false disables without remote config', () async {
      final service = CloudflareDualRunService();
      await service.setLocalOverride(false);
      expect(await service.isCloudflareSyncEnabled(), isFalse);
    });

    test('local override true forces enable', () async {
      final service = CloudflareDualRunService();
      await service.setLocalOverride(true);
      expect(await service.isCloudflareSyncEnabled(), isTrue);
    });

    test('removing override returns to remote/default control', () async {
      final service = CloudflareDualRunService();
      await service.setLocalOverride(false);
      expect(await service.isCloudflareSyncEnabled(), isFalse);
      await service.setLocalOverride(null);
      expect(await service.isCloudflareSyncEnabled(), isTrue);
    });
  });

  group('shadow comparison (plan phase 5.3)', () {
    test('matching counts produce zero mismatches and persist summary',
        () async {
      final service = CloudflareDualRunService();
      service.statsFetcherForTest = () async => {
            'tables': {'rooms': 10, 'bookings': 5},
          };
      service.configure(
        tokenProvider: () async => 'token',
        // الكيانات خارج نطاق الـ stub تُعدّ غير قابلة للقياس (-1)
        appwriteCounter: (entity) async =>
            entity == 'rooms' ? 10 : (entity == 'bookings' ? 5 : -1),
      );

      final result = await service.runShadowComparison();
      expect(result.error, isNull);
      expect(result.mismatchCount, 0);
      expect(result.comparisons, isNotEmpty);

      final persisted = await service.lastComparisonJson();
      expect(persisted, isNotNull);
      expect(persisted!['mismatches'], 0);
    });

    test('mismatched counts are reported per entity', () async {
      final service = CloudflareDualRunService();
      service.statsFetcherForTest = () async => {
            'tables': {'rooms': 10},
          };
      service.configure(
        tokenProvider: () async => 'token',
        appwriteCounter: (entity) async => 7,
      );

      final result = await service.runShadowComparison();
      final rooms = result.comparisons
          .firstWhere((c) => c.entity == 'rooms', orElse: () => throw StateError('rooms missing'));
      expect(rooms.matches, isFalse);
      expect(result.mismatchCount, greaterThanOrEqualTo(1));
    });

    test('unmeasurable counts (-1) are recorded but not mismatches',
        () async {
      final service = CloudflareDualRunService();
      service.statsFetcherForTest = () async => {
            'tables': {'rooms': 10},
          };
      service.configure(
        tokenProvider: () async => 'token',
        // rooms: تعذّر عدّ Appwrite؛ البقية: لا وجود لها في stats (cf=-1)
        appwriteCounter: (entity) async => entity == 'rooms' ? -1 : 0,
      );

      final result = await service.runShadowComparison();
      final rooms =
          result.comparisons.firstWhere((c) => c.entity == 'rooms');
      expect(rooms.cloudflareCount, 10);
      expect(rooms.appwriteCount, -1);
      // -1 مقابل 10 — القاعدة: القياس الغائب (-1) لا يُحتسب عدم تطابق
      expect(result.mismatchCount, 0, reason: 'تعذّر القياس ≠ اختلاف بيانات');
    });

    test('stats fetch failure is captured in error, not thrown', () async {
      final service = CloudflareDualRunService();
      service.statsFetcherForTest = () async => throw StateError('down');
      service.configure(
        tokenProvider: () async => 'token',
        appwriteCounter: (entity) async => 3,
      );

      final result = await service.runShadowComparison();
      expect(result.error, isNotNull);
      expect(result.error, contains('stats fetch failed'));
      // كل الكيانات بقيمة cloudflare=-1 (قياس غائب)
      expect(
        result.comparisons.every((c) => c.cloudflareCount == -1),
        isTrue,
      );
    });

    test('unknown entity in stats does not crash (count = -1)', () async {
      final service = CloudflareDualRunService();
      service.statsFetcherForTest = () async => {
            'tables': <String, dynamic>{},
          };
      service.configure(
        tokenProvider: () async => 'token',
        appwriteCounter: (entity) async => 0,
      );

      final result = await service.runShadowComparison();
      expect(result.error, isNull);
      expect(result.comparisons, isNotEmpty);
    });
  });
}
