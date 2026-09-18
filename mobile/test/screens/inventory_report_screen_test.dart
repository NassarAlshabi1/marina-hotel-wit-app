import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/screens/reports/inventory_report_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int itemId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = InventoryRepositoryForTest(db);
    itemId = await repository.createItem(
      name: 'مناديل',
      unit: 'كرتون',
      category: 'نظافة',
      initialQuantity: 2,
      minimumQuantity: 5,
    );
    await repository.recordMovement(
      itemId: itemId,
      movementType: 'in',
      quantity: 3,
      userName: 'اختبار',
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('يعرض التقرير المخزني من تجميع SQLite', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          simpleNotesUnreadCountProvider.overrideWith((ref) => Stream.value(0)),
          syncStatusProvider.overrideWith(
            (ref) => Stream.value(SyncStatus.idle),
          ),
        ],
        child: const MaterialApp(home: InventoryReportScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('التقرير المخزني'), findsWidgets);
    expect(find.text('مناديل'), findsOneWidget);
    expect(find.textContaining('تحت الحد'), findsOneWidget);
    expect(find.textContaining('الوارد'), findsOneWidget);
    expect(find.textContaining('الحركات'), findsOneWidget);
  });
}

/// واجهة اختبار صغيرة لتجنب إنشاء Outbox أو خدمة Cloud داخل test setup.
class InventoryRepositoryForTest {
  InventoryRepositoryForTest(this.db);

  final AppDatabase db;

  Future<int> createItem({
    required String name,
    required String unit,
    required String category,
    required int initialQuantity,
    required int minimumQuantity,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return db
        .into(db.inventoryItems)
        .insert(
          InventoryItemsCompanion.insert(
            name: name,
            localUuid: 'test-item-$now',
            unit: drift.Value(unit),
            category: drift.Value(category),
            quantity: drift.Value(initialQuantity),
            minimumQuantity: drift.Value(minimumQuantity),
            createdAt: now,
            updatedAt: now,
            lastModified: now,
          ),
        );
  }

  Future<void> recordMovement({
    required int itemId,
    required String movementType,
    required int quantity,
    String? userName,
  }) async {
    final item = await (db.select(
      db.inventoryItems,
    )..where((row) => row.id.equals(itemId))).getSingle();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.inventoryTransactions)
        .insert(
          InventoryTransactionsCompanion.insert(
            localUuid: 'test-movement-$now',
            itemLocalUuid: drift.Value(item.localUuid),
            itemId: itemId,
            movementType: movementType,
            quantity: quantity,
            balanceAfter: item.quantity + quantity,
            userName: drift.Value(userName),
            createdAt: now,
            createdAtEpoch: drift.Value(now),
            updatedAt: now,
            lastModified: now,
          ),
        );
  }
}
