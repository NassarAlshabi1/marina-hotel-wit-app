import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/settings/settings_maintenance.dart';

void main() {
  testWidgets('maintenance tools are hidden from non-admin users', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SettingsMaintenanceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('يتطلب هذا القسم صلاحية مدير النظام'), findsOneWidget);
    expect(find.text('إعادة تعيين التطبيق'), findsNothing);
    expect(find.text('ضغط قاعدة البيانات (VACUUM)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
