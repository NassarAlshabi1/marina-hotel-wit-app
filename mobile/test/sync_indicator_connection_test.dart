// ═══════════════════════════════════════════════════════════════
//  sync_indicator_connection_test.dart — ✅ (2026-09-17)
//  عقود انعكاس فحص الاتصال التلقائي (طلب المستخدم: «عند فتح التطبيق
//  يفترض يفحص تلقائيا الاتصال مع cloudflare worker d1») في مؤشر
//  AppBar:
//   • لم يُفحص بعد → السلوك القديم (لا وميض أحمر عند الإقلاع).
//   • فحص مكتمل + سحابة غير قابلة للوصول → سحابة حمراء + تلميح.
//   • فحص مكتمل + D1 لا يستجيب → سحابة برتقالية + تلميح السبب.
//   • متصل + D1 يستجيب → أخضر مع زمن الاستجابة في التلميح.
//   • مزامنة جارية تتفوق على حالة عدم الاتصال (حلقة السحب تبقى).
//  كل المزودات الثقيلة (قاعدة بيانات/مدير) محقونة بأبدال خفيفة.
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/providers/appwrite_providers.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_manager.dart'
    show AppwriteSyncManager, SyncPullProgress, SyncStatus;
import 'package:marina_hotel_mobile/widgets/sync/sync_indicator.dart';

/// حالة اتصال ثابتة قابلة للضبط لكل اختبار — بلا طلبات شبكة.
class _StaticConnectionNotifier extends ConnectionStatusNotifier {
  _StaticConnectionNotifier(super.ref, ConnectionState fixed) {
    state = fixed;
  }
}

void main() {
  Widget harness({
    required ConnectionState connection,
    SyncStatus syncStatus = SyncStatus.idle,
  }) {
    return ProviderScope(
      overrides: [
        // مدير خفيف (مصنع singleton بلا initialize) — يمنع بناء القاعدة.
        appwriteSyncManagerProvider.overrideWith((ref) => AppwriteSyncManager()),
        cloudflareSyncStatusProvider.overrideWith(
          (ref) => Stream.value(syncStatus),
        ),
        outboxCountProvider.overrideWith((ref) => Stream.value(0)),
        cloudflarePullProgressProvider.overrideWith(
          (ref) => Stream.value(SyncPullProgress(pulledRows: 0, isDone: true)),
        ),
        connectionStatusProvider.overrideWith(
          (ref) => _StaticConnectionNotifier(ref, connection),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: SyncIndicator())),
    );
  }

  String tooltipMessage(WidgetTester tester) {
    return tester.widget<Tooltip>(find.byType(Tooltip)).message!;
  }

  testWidgets('قبل أول فحص (لم يُفحص) — السلوك القديم بلا وميض أحمر', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        connection: ConnectionState(isConnected: false, lastCheckedAt: null),
      ),
    );

    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(
      tooltipMessage(tester),
      'اتصال Cloudflare — اضغط لإدارة تسجيل الدخول',
    );
  });

  testWidgets('فحص مكتمل والسحابة غير قابلة للوصول → سحابة حمراء معلّقة', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        connection: ConnectionState(
          isConnected: false,
          errorMessage: 'خطأ في الاتصال',
          lastCheckedAt: DateTime(2026, 9, 17, 8, 30),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.cloud_off));
    expect(icon.color, Colors.red);
    expect(
      tooltipMessage(tester),
      contains('تعذر الوصول لخادم Cloudflare'),
    );
    expect(tooltipMessage(tester), contains('8:30'));
  });

  testWidgets('السحابة حية لكن D1 لا يستجيب → سحابة برتقالية + سبب D1', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        connection: ConnectionState(
          isConnected: true,
          isD1Connected: false,
          d1Error: 'انتهت صلاحية الجلسة — أعد تسجيل الدخول',
          lastCheckedAt: DateTime(2026, 9, 17, 8, 30),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(Icons.cloud));
    expect(icon.color, Colors.orange);
    expect(tooltipMessage(tester), contains('قاعدة D1 لا تستجيب'));
    expect(tooltipMessage(tester), contains('انتهت صلاحية الجلسة'));
  });

  testWidgets('متصل وD1 يستجيب → أخضر مع زمن استجابة D1 في التلميح', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        connection: ConnectionState(
          isConnected: true,
          isD1Connected: true,
          d1LatencyMs: 12,
          lastCheckedAt: DateTime(2026, 9, 17, 8, 30),
        ),
      ),
    );

    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(tooltipMessage(tester), contains('D1 يستجيب (12 ms)'));
  });

  testWidgets('مزامنة جارية تتفوق على حالة عدم الاتصال — حلقة السحب تبقى', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        syncStatus: SyncStatus.syncing,
        connection: ConnectionState(
          isConnected: false,
          lastCheckedAt: DateTime(2026, 9, 17, 8, 30),
        ),
      ),
    );
    // Stream.value يسجّل الحدث بعد أول إطار — مضخة إضافية تُثبّته.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off), findsNothing);
    expect(tooltipMessage(tester), contains('جاري السحب'));
  });
}
