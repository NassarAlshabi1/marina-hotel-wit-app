import 'package:drift/drift.dart' as d;
import '../utils/time.dart';
import 'local_db.dart';

class Seeder {
  Seeder(this.db);
  final AppDatabase db;

  Future<void> seedIfEmpty() async {
    final roomsCount =
        (await db.customSelect('SELECT COUNT(*) c FROM rooms').getSingle())
                .data['c']
            as int;
    if (roomsCount > 0) {
      return;
    }

    final roomsCompanions = [
      const RoomsCompanion(
        roomNumber: d.Value('101'),
        type: d.Value('سرير عائلي'),
        price: d.Value(15000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-101'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('102'),
        type: d.Value('سرير عائلي'),
        price: d.Value(15000),
        status: d.Value('محجوزة'),
        localUuid: d.Value('r-102'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('103'),
        type: d.Value('سرير فردي'),
        price: d.Value(12000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-103'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('104'),
        type: d.Value('سرير فردي'),
        price: d.Value(10000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-104'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('201'),
        type: d.Value('سرير فردي'),
        price: d.Value(15000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-201'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('202'),
        type: d.Value('سرير عائلي'),
        price: d.Value(17000),
        status: d.Value('محجوزة'),
        localUuid: d.Value('r-202'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('203'),
        type: d.Value('سرير عائلي'),
        price: d.Value(17000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-203'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('204'),
        type: d.Value('سرير فردي'),
        price: d.Value(15000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-204'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('301'),
        type: d.Value('سرير عائلي'),
        price: d.Value(7000),
        status: d.Value('شاغرة'),
        localUuid: d.Value('r-301'),
      ),
      const RoomsCompanion(
        roomNumber: d.Value('302'),
        type: d.Value('سرير فردي'),
        price: d.Value(15000),
        status: d.Value('محجوزة'),
        localUuid: d.Value('r-302'),
      ),
    ];

    for (final r in roomsCompanions) {
      final t = Time.nowEpoch();
      await db
          .into(db.rooms)
          .insert(
            r.copyWith(
              createdAt: d.Value(t),
              updatedAt: d.Value(t),
              lastModified: d.Value(t),
              version: const d.Value(1),
              origin: const d.Value('local'),
            ),
          );
    }

  }
}
