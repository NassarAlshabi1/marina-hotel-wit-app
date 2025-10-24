import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';

part 'guarantees_dao.g.dart';

@DriftAccessor(tables: [Guarantees])
class GuaranteesDao extends DatabaseAccessor<AppDatabase> with _$GuaranteesDaoMixin {
  GuaranteesDao(AppDatabase db) : super(db);

  Future<List<Guarantee>> list({int? bookingLocalId, int? debtLocalId, bool onlyUnreturned = false}) async {
    final q = select(guarantees);
    if (bookingLocalId != null) q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    if (debtLocalId != null) q.where((t) => t.debtLocalId.equals(debtLocalId));
    if (onlyUnreturned) q.where((t) => t.isReturned.equals(false));
    return q.get();
  }

  Stream<List<Guarantee>> watchList({int? bookingLocalId, int? debtLocalId, bool onlyUnreturned = false}) {
    final q = select(guarantees);
    if (bookingLocalId != null) q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    if (debtLocalId != null) q.where((t) => t.debtLocalId.equals(debtLocalId));
    if (onlyUnreturned) q.where((t) => t.isReturned.equals(false));
    return q.watch();
  }

  Future<Guarantee?> getById(int id) => (select(guarantees)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertOne(GuaranteesCompanion data) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      version: const Value(1),
      origin: const Value('local'),
    );
    return into(guarantees).insert(comp);
  }

  Future<int> updateById(int id, GuaranteesCompanion data) async {
    final now = Time.nowEpoch();
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    return (update(guarantees)..where((t) => t.id.equals(id))).write(comp);
  }

  Future<int> markAllReturnedForDebt(int debtLocalId, {String? dateReturnedIso}) async {
    final now = Time.nowEpoch();
    final dateIso = dateReturnedIso ?? Time.nowIso();
    return (update(guarantees)..where((t) => t.debtLocalId.equals(debtLocalId) & t.isReturned.equals(false))).write(
      GuaranteesCompanion(isReturned: const Value(true), dateReturned: Value(dateIso), updatedAt: Value(now), lastModified: Value(now)),
    );
  }

  Future<Map<int, int>> unreturnedCountsByDebt() async {
    final q = selectOnly(guarantees);
    final debtIdExp = guarantees.debtLocalId;
    final cntExp = guarantees.id.count();
    q.where(guarantees.isReturned.equals(false));
    q.addColumns([debtIdExp, cntExp]);
    q.groupBy([debtIdExp]);
    final rows = await q.get();
    final map = <int, int>{};
    for (final row in rows) {
      final k = row.read(debtIdExp);
      final v = row.read(cntExp) ?? 0;
      if (k != null) map[k] = v;
    }
    return map;
  }
}
