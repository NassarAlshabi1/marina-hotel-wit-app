// ============================================================================
//  Marina Hotel — Integration Test: SyncIndicator (Patrol)
//  ============================================================================
//  السيناريو: Sync — مؤشر حالة المزامنة الحيّ يُبنى ويقرأ مزوّدات
//  المزامنة (cloudflareSyncStatusProvider / outboxCountProvider /
//  cloudflarePullProgressProvider / connectionStatusProvider) على جهاز
//  حقيقي دون انهيار (lib/widgets/sync/sync_indicator.dart — السطر 57-60).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/widgets/sync/sync_indicator.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest(
    'يعرض مؤشر حالة المزامنة ويقرأ مزوّدات المزامنة دون انهيار',
    config: const PatrolTesterConfig(),
    ($) async {
      await $.tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(body: SyncIndicator()),
            ),
          ),
        ),
      );

      // انتظار قراءة مزوّدات المزامنة غير المتزامنة
      await $.tester.pump(const Duration(seconds: 1));
      await $.tester.pump(const Duration(seconds: 1));

      expect(
        $(SyncIndicator),
        findsOneWidget,
        reason: 'مؤشر المزامنة يجب أن يُبنى بنجاح على الجهاز الحقيقي',
      );
    },
  );
}
