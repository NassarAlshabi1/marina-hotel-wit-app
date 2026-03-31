import 'package:drift/drift.dart' as d;

import '../daos/guest_info_dao.dart';
import '../local_db.dart';

class GuestInfoRepository {
  GuestInfoRepository(this.db) : dao = GuestInfoDao(db);

  final AppDatabase db;
  final GuestInfoDao dao;

  Stream<List<GuestInfo>> watchAll({String? search}) =>
      dao.watchList(search: search);

  Future<List<GuestInfo>> listAll({String? search}) => dao.list(search: search);

  Future<int> create({
    required String roomNumber,
    required String guestName,
    required String nationality,
    required String idNumber,
    required String idType,
    String? issueDate,
    String? issuePlace,
    String? governorate,
    String? notes,
  }) {
    return dao.insertOne(
      GuestInfosCompanion(
        roomNumber: d.Value(roomNumber.trim()),
        guestName: d.Value(guestName.trim()),
        nationality: d.Value(nationality.trim()),
        idNumber: d.Value(idNumber.trim()),
        idType: d.Value(idType.trim()),
        issueDate: _nullableValue(issueDate),
        issuePlace: _nullableValue(issuePlace),
        governorate: _nullableValue(governorate),
        notes: _nullableValue(notes),
      ),
    );
  }

  Future<int> update(
    int id, {
    String? roomNumber,
    String? guestName,
    String? nationality,
    String? idNumber,
    String? idType,
    String? issueDate,
    String? issuePlace,
    String? governorate,
    String? notes,
  }) {
    return dao.updateById(
      id,
      GuestInfosCompanion(
        roomNumber: roomNumber != null
            ? d.Value(roomNumber.trim())
            : const d.Value.absent(),
        guestName: guestName != null
            ? d.Value(guestName.trim())
            : const d.Value.absent(),
        nationality: nationality != null
            ? d.Value(nationality.trim())
            : const d.Value.absent(),
        idNumber: idNumber != null
            ? d.Value(idNumber.trim())
            : const d.Value.absent(),
        idType: idType != null
            ? d.Value(idType.trim())
            : const d.Value.absent(),
        issueDate: _nullableValue(issueDate),
        issuePlace: _nullableValue(issuePlace),
        governorate: _nullableValue(governorate),
        notes: _nullableValue(notes),
      ),
    );
  }

  Future<int> delete(int id) => dao.softDelete(id);

  Future<void> clearAll() => dao.clearAllData();

  d.Value<String> _nullableValue(String? source) {
    if (source == null) {
      return const d.Value.absent();
    }
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return const d.Value.absent();
    }
    return d.Value(trimmed);
  }
}
