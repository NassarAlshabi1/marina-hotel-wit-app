import 'package:drift/drift.dart';

import 'optimistic_lock_exception.dart';
import '../local_db.dart';

mixin OptimisticLockDaoMixin<T extends Table, D extends DataClass>
    on DatabaseAccessor<AppDatabase> {
  TableInfo<T, D> get optimisticTable;
  String get optimisticTableName;
  GeneratedColumn<String> get optimisticLocalUuid;
  GeneratedColumn<int> get optimisticVersion;

  Future<bool> updateWithOptimisticLock(
    String localUuid,
    UpdateCompanion<D> companion,
    int expectedVersion,
  ) async {
    return transaction(() async {
      final existing = await (select(optimisticTable)
            ..where((_) => optimisticLocalUuid.equals(localUuid)))
          .getSingleOrNull();

      if (existing == null) {
        throw OptimisticLockException(
          table: optimisticTableName,
          uuid: localUuid,
          expectedVersion: expectedVersion,
          actualVersion: null,
        );
      }

      final currentVersion = existing.toJson()[optimisticVersion.$name] as int?;
      if (currentVersion != expectedVersion) {
        throw OptimisticLockException(
          table: optimisticTableName,
          uuid: localUuid,
          expectedVersion: expectedVersion,
          actualVersion: currentVersion,
        );
      }

      final data = companion.toColumns(false);
      data[optimisticVersion.$name] = Variable<int>(expectedVersion + 1);

      final updated = await (update(optimisticTable)
            ..where((_) => optimisticLocalUuid.equals(localUuid) &
                optimisticVersion.equals(expectedVersion)))
          .write(RawValuesInsertable(data));

      if (updated == 0) {
        throw OptimisticLockException(
          table: optimisticTableName,
          uuid: localUuid,
          expectedVersion: expectedVersion,
          actualVersion: currentVersion,
        );
      }

      return true;
    });
  }

  Future<D?> getByUuid(String uuid) async {
    return (select(optimisticTable)
          ..where((_) => optimisticLocalUuid.equals(uuid)))
        .getSingleOrNull();
  }
}
