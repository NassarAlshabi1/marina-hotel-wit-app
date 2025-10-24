import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/debts_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/guarantees_repository.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:drift/drift.dart' as d;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Runaway guest debt flow', () {
    late AppDatabase db;
    late RoomsRepository roomsRepo;
    late BookingsRepository bookingsRepo;
    late DebtsRepository debtsRepo;
    late GuaranteesRepository guaranteesRepo;

    setUp(() async {
      db = AppDatabase();
      roomsRepo = RoomsRepository(db);
      bookingsRepo = BookingsRepository(db);
      debtsRepo = DebtsRepository(db);
      guaranteesRepo = GuaranteesRepository(db);
      await roomsRepo.create(roomNumber: '101', type: 'قياسي', price: 100, status: 'محجوزة');
    });

    tearDown(() async {
      await db.close();
    });

    test('process and settle runaway debt', () async {
      final bookingId = await bookingsRepo.create(
        roomNumber: '101',
        guestName: 'ضيف تجريبي',
        guestPhone: '0500000000',
        guestNationality: 'سعودي',
        checkinDate: Time.nowIso(),
        status: 'نشط',
      );

      final debtId = await debtsRepo.processEvasiveGuestDebt(
        bookingLocalId: bookingId,
        amountDue: 250.0,
        guaranteeItems: ['هوية', 'حقيبة'],
      );

      final debt = await debtsRepo.getOne(debtId);
      expect(debt, isNotNull);
      expect(debt!.debtReason, 'Evasive Guest Debt');
      expect(debt.isSettled, isFalse);
      expect(debt.amountDue, 250.0);

      final guarantees = await guaranteesRepo.listByDebt(debtId);
      expect(guarantees.length, 2);

      await debtsRepo.settleDebtAndReturnGuarantees(debtLocalId: debtId, paymentMethod: 'نقدي');
      final updatedDebt = await debtsRepo.getOne(debtId);
      expect(updatedDebt!.isSettled, isTrue);

      final unreturned = await guaranteesRepo.listByDebt(debtId, onlyUnreturned: true);
      expect(unreturned.isEmpty, isTrue);
    });
  });
}
