import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/daos/expenses_dao.dart';
import 'package:marina_hotel_mobile/services/daos/outbox_dao.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ExpensesDao expensesDao;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    expensesDao = ExpensesDao(db, OutboxDao(db));
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'empty hotel_day_key falls back to date and includes the full end day',
    () async {
      final now = Time.nowEpoch();
      Future<void> insertExpense({
        required String date,
        required String hotelDayKey,
      }) async {
        await db
            .into(db.expenses)
            .insert(
              ExpensesCompanion(
                localUuid: Value(IdGen.uuid()),
                expenseType: const Value('صيانة'),
                description: const Value('fixture'),
                amount: const Value(10),
                date: Value(date),
                hotelDayKey: Value(hotelDayKey),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
              ),
            );
      }

      await insertExpense(date: '2026-09-25 23:59:59', hotelDayKey: '');
      await insertExpense(date: '2026-09-26 00:00:00', hotelDayKey: '');

      final rows = await expensesDao.listFilteredByHotelDay(
        fromHotelDay: '2026-09-25',
        toHotelDay: '2026-09-25',
      );

      expect(rows, hasLength(1));
      expect(rows.single.date, '2026-09-25 23:59:59');
    },
  );
}
