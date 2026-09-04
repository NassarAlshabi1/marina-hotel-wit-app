// Helper for creating an in-memory Drift database for testing.
import 'package:drift/native.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';

class TestDatabase {
  TestDatabase._();

  /// Creates a new in-memory [AppDatabase] with the latest schema.
  static AppDatabase create() {
    return AppDatabase.forTesting(NativeDatabase.memory());
  }
}
