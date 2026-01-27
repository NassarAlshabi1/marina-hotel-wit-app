import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_notification_manager.dart';

void main() {
  testWidgets('showSyncSuccess builds overlay with correct text', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Scaffold(key: key)));
    SyncNotificationManager.showSyncSuccess(
      key.currentContext!,
      fromDevice: 'deviceA',
      recordsCount: 3,
      syncTime: DateTime.now(),
    );
    await tester.pump();
    expect(find.textContaining('تم تحديث 3 سجل'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_sync), findsOneWidget);
  });

  testWidgets('showSyncError builds overlay and retry button works', (
    tester,
  ) async {
    final key = GlobalKey();
    var retried = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(key: key)));
    SyncNotificationManager.showSyncError(
      key.currentContext!,
      error: 'fail',
      onRetry: () => retried = true,
    );
    await tester.pump();
    expect(find.textContaining('fail'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    expect(retried, isTrue);
  });
}
