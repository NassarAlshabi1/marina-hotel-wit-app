// test/unit/information_header_search_widget_test.dart
//
// ✅ (2026-10-06): اختبار واجهة بحث الهيد في «سجل المعلومية».
//
// المطلوب من صاحب الفندق: «عند الضغط عليه باستطاعتي البحث في سجل المعلومية
// بالاسم» — أي:
//   1. قبل الضغط: لا يوجد حقل بحث (الرأس نظيف).
//   2. الضغط على أيقونة البحث ⇒ يظهر الحقل في الهيد فوراً ومعه إمكانية الكتابة.
//   3. الكتابة تُصفّي السجل، وزر ✕ في الرأس يُغلق البحث ويُفرّغ العبارة.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/screens/information/information_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // سجلان مختلفان لتمييز نتيجة البحث.
    for (final row in [
      (room: '101', name: 'أحمد علي', id: '111'),
      (room: '102', name: 'خالد سعيد', id: '222'),
    ]) {
      await db
          .into(db.guestInfos)
          .insert(
            GuestInfosCompanion.insert(
              localUuid: 'g-${row.room}',
              createdAt: 1,
              updatedAt: 1,
              lastModified: 1,
              roomNumber: row.room,
              guestName: row.name,
              nationality: 'يمني',
              idNumber: row.id,
              idType: const Value('بطاقة شخصية'),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          simpleNotesUnreadCountProvider.overrideWith(
            (ref) => Stream.value(0),
          ),
        ],
        child: const MaterialApp(home: InformationScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('قبل الضغط: لا حقل بحث في الهيد', (tester) async {
    await pumpScreen(tester);

    expect(find.text('سجل المعلومية'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('بحث في السجل بالاسم'), findsOneWidget);
  });

  testWidgets('الضغط على أيقونة البحث يُظهر الحقل ويمكن الكتابة فيه',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('بحث في السجل بالاسم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.text('ابحث في سجل المعلومية بالاسم أو الغرفة أو الهوية…'),
      findsOneWidget,
    );

    // الكتابة تُظهر السجلين قبل التصفية.
    expect(find.text('أحمد علي', findRichText: true), findsOneWidget);
    expect(find.text('خالد سعيد', findRichText: true), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'خالد');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('خالد سعيد', findRichText: true), findsOneWidget);
    expect(
      find.text('أحمد علي', findRichText: true),
      findsNothing,
      reason: 'التصفية بالاسم يجب أن تُخفي غير المطابق',
    );
  });

  testWidgets('زر ✕ في الرأس يُغلق البحث ويُفرّغ العبارة', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('بحث في السجل بالاسم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'خالد');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('أحمد علي', findRichText: true), findsNothing);

    // الإغلاق: الحقل يختفي والعبارة تُفرَّغ (يعود السجلان).
    await tester.tap(find.byTooltip('إغلاق البحث'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TextField), findsNothing);
    expect(find.text('أحمد علي', findRichText: true), findsOneWidget);
    expect(find.text('خالد سعيد', findRichText: true), findsOneWidget);
  });

  testWidgets('البحث يتسامح مع الهمزات (أحمد/احمد)', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('بحث في السجل بالاسم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'احمد');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('أحمد علي', findRichText: true), findsOneWidget);
    expect(find.text('خالد سعيد', findRichText: true), findsNothing);
  });

  testWidgets('البحث برقم الغرفة يعمل كذلك', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('بحث في السجل بالاسم'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '102');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('خالد سعيد', findRichText: true), findsOneWidget);
    expect(find.text('أحمد علي', findRichText: true), findsNothing);
  });
}
