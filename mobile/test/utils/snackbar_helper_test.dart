import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/snackbar_helper.dart';

void main() {
  testWidgets('replaces queued SnackBars instead of stacking them', (
    tester,
  ) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => SnackBarHelper.showSuccess(context, 'تم الحفظ'),
              child: const Text('حفظ'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('حفظ'));
    await tester.pump();
    expect(find.text('تم الحفظ'), findsOneWidget);

    final context = scaffoldKey.currentContext!;
    SnackBarHelper.showError(context, 'فشل الحفظ');
    await tester.pump();
    expect(find.text('تم الحفظ'), findsNothing);
    expect(find.text('فشل الحفظ'), findsOneWidget);
  });

  testWidgets('does not throw when no ScaffoldMessenger is available', (
    tester,
  ) async {
    BuildContext? capturedContext;
    await tester.pumpWidget(
      WidgetsApp(
        color: Colors.white,
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, __) => builder(context),
        ),
        builder: (context, child) => child ?? const SizedBox(),
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(capturedContext, isNotNull);
    expect(
      () => SnackBarHelper.show(capturedContext!, 'رسالة'),
      returnsNormally,
    );
  });
}
