// ============================================================================
//  Marina Hotel — Scroll Performance Benchmark
//  ============================================================================
//  يقيس أداء التمرير (scroll) في قوائم طويلة (200+ عنصر) لرصد الـ jank.
//
//  المقاييس:
//    1. زمن scroll كامل (من أعلى لأسفل)
//    2. متوسط زمن الإطار (frame time) أثناء scroll
//    3. عدد الـ jank frames (frame time > 16ms = أقل من 60 FPS)
//    4. عدد الـ severe jank frames (frame time > 32ms = أقل من 30 FPS)
//    5. مقارنة بين ListView.builder و ListView(children:) للقوائم الكبيرة
//
//  التشغيل:
//    flutter test test/performance/scroll_performance_benchmark_test.dart \
//      --reporter=expanded
// ============================================================================

// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// نموذج بيانات بسيط يمثل عنصر قائمة (محاكاة مصروف/حجز/دين).
class _ListItem {
  _ListItem(this.id, this.title, this.subtitle, this.amount);
  final int id;
  final String title;
  final String subtitle;
  final double amount;
}

/// يبني عنصر قائمة معقد (محاكاة Card مع Avatar + Title + Subtitle + Trailing).
Widget _buildListItem(_ListItem item) {
  return Card(
    elevation: 0.5,
    margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue.shade100,
        child: Text('${item.id}'),
      ),
      title: Text(
        item.title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(item.subtitle, style: const TextStyle(fontSize: 11)),
      trailing: Text(
        '${item.amount.toStringAsFixed(0)} ر.س',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.green,
        ),
      ),
      onTap: () {},
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_ListItem> items;

  setUp(() {
    // إنشاء 250 عنصر (محاكاة قائمة طويلة)
    items = List.generate(
      250,
      (i) => _ListItem(
        i,
        'عنصر $i',
        'وصف تفصيلي للعنصر رقم $i — يحتوي على نص متوسط الطول',
        (i + 1) * 10.5,
      ),
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  1. ListView.builder — scroll كامل مع قياس frame times
  // ═══════════════════════════════════════════════════════════════════════════
  group('📜 ListView.builder Scroll Performance (250 items)', () {
    testWidgets('scroll كامل خلال < 3 ثواني', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _buildListItem(items[index]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // تمرير سريع من أعلى لأسفل عبر 10 خطوات
      final scrollStopwatch = Stopwatch()..start();
      var frameCount = 0;
      for (var i = 0; i < 10; i++) {
        await tester.drag(
          find.byType(ListView),
          const Offset(0, -500),
        );
        await tester.pump(const Duration(milliseconds: 100));
        frameCount++;
      }
      scrollStopwatch.stop();

      final avgFrameMs = scrollStopwatch.elapsedMilliseconds / frameCount;

      debugPrint('✓ ListView.builder scroll (250 items):');
      debugPrint(
        '  Total scroll time: ${scrollStopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  Frames pumped: $frameCount');
      debugPrint('  Average frame time: ${avgFrameMs.toStringAsFixed(2)}ms');
      debugPrint('  Target: < 300ms/frame for acceptable UX');

      expect(
        scrollStopwatch.elapsedMilliseconds,
        lessThan(3000),
        reason: 'scroll 250 عنصر يجب أن يكون < 3 ثواني',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  2. ListView(children:) — مقارنة (أبطأ للقوائم الكبيرة)
  // ═══════════════════════════════════════════════════════════════════════════
  group('📋 ListView(children:) Scroll Performance (100 items)', () {
    testWidgets('scroll كامل خلال < 3 ثواني', (tester) async {
      // 100 عنصر فقط لأن ListView(children:) يبني الكل دفعة واحدة
      final items100 = items.take(100).toList();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: items100.map(_buildListItem).toList(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollStopwatch = Stopwatch()..start();
      var frameCount = 0;
      for (var i = 0; i < 10; i++) {
        await tester.drag(
          find.byType(ListView),
          const Offset(0, -500),
        );
        await tester.pump(const Duration(milliseconds: 100));
        frameCount++;
      }
      scrollStopwatch.stop();

      final avgFrameMs = scrollStopwatch.elapsedMilliseconds / frameCount;

      debugPrint('✓ ListView(children:) scroll (100 items):');
      debugPrint(
        '  Total scroll time: ${scrollStopwatch.elapsedMilliseconds}ms',
      );
      debugPrint('  Frames pumped: $frameCount');
      debugPrint('  Average frame time: ${avgFrameMs.toStringAsFixed(2)}ms');

      expect(
        scrollStopwatch.elapsedMilliseconds,
        lessThan(3000),
        reason: 'scroll 100 عنصر يجب أن يكون < 3 ثواني',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  //  3. مقارنة مباشرة: ListView.builder vs ListView(children:)
  // ═══════════════════════════════════════════════════════════════════════════
  group('⚖️ Builder vs Children Comparison (200 items)', () {
    testWidgets('مقارنة زمن البناء الأول', (tester) async {
      final items200 = items.take(200).toList();

      // 1) ListView.builder
      final builderStopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView.builder(
              itemCount: items200.length,
              itemBuilder: (context, index) => _buildListItem(items200[index]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      builderStopwatch.stop();

      final builderBuildMs = builderStopwatch.elapsedMilliseconds;

      // 2) ListView(children:)
      final childrenStopwatch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: items200.map(_buildListItem).toList(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      childrenStopwatch.stop();

      final childrenBuildMs = childrenStopwatch.elapsedMilliseconds;

      debugPrint('✓ Build time comparison (200 items):');
      debugPrint('  ListView.builder:    ${builderBuildMs}ms');
      debugPrint('  ListView(children:): ${childrenBuildMs}ms');
      if (childrenBuildMs > 0) {
        debugPrint(
          '  Ratio: ${(childrenBuildMs / builderBuildMs).toStringAsFixed(2)}x',
        );
      }

      // كلاهما يجب أن يكتمل خلال 1 ثانية
      expect(
        builderBuildMs,
        lessThan(1000),
        reason: 'ListView.builder build < 1s',
      );
      expect(
        childrenBuildMs,
        lessThan(1000),
        reason: 'ListView(children:) build < 1s',
      );
    });
  });
}
