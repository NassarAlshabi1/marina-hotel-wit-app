import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/providers/auth_provider.dart';
import 'package:marina_hotel_mobile/providers/repository_providers.dart';
import 'package:marina_hotel_mobile/providers/room_payment_status_provider.dart';
import 'package:marina_hotel_mobile/screens/finance/finance_screen.dart';
import 'package:marina_hotel_mobile/services/local_db.dart' as db;
import 'package:marina_hotel_mobile/services/repositories/bookings_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/sync_service.dart';

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier() : super() {
    state = const AuthState(isAuthenticated: false);
  }

  @override
  Future<void> restoreSession() async {}

  @override
  Future<void> login(
    String username,
    String password, {
    bool rememberMe = false,
  }) async {}

  @override
  Future<void> logout() async {}
}

class _FakePaymentsRepository extends PaymentsRepository {
  _FakePaymentsRepository(super.db);

  @override
  Stream<List<db.Payment>> watchAll({bool includeDeleted = false}) =>
      Stream.value(const <db.Payment>[]);
}

class _FakeBookingsRepository extends BookingsRepository {
  _FakeBookingsRepository(super.db);

  @override
  Stream<List<db.Booking>> watchList({String? roomNumber, String? status}) =>
      Stream.value(const <db.Booking>[]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FinanceScreen renders cash status cards without overflow', (
    tester,
  ) async {
    final database = db.AppDatabase.forTesting(NativeDatabase.memory());

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await database.close();
      await tester.pump();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          paymentsRepoProvider.overrideWithValue(
            _FakePaymentsRepository(database),
          ),
          bookingsRepoProvider.overrideWithValue(
            _FakeBookingsRepository(database),
          ),
          simpleNotesUnreadCountProvider.overrideWith(
            (ref) => Stream.value(0),
          ),
          syncStatusProvider.overrideWith((ref) => Stream.value(SyncStatus.idle)),
          roomsWithPaymentStatusProvider.overrideWith(
            (ref) => Stream.value(const <RoomWithPaymentStatus>[]),
          ),
          todayPaymentsProvider.overrideWith((ref) => Stream.value(125000.0)),
          todayExpensesProvider.overrideWith((ref) => Stream.value(25000.0)),
          authProvider.overrideWith((ref) => _FakeAuthNotifier()),
        ],
        child: const MaterialApp(home: FinanceScreen()),
      ),
    );

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('حالة الصندوق'), findsOneWidget);
    expect(find.text('الايراد'), findsOneWidget);
    expect(find.text('المصروفات'), findsOneWidget);
    expect(find.text('المتبقي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
