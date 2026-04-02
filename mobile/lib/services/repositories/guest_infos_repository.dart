import 'package:drift/drift.dart' as d;

import '../local_db.dart';

class GuestInfosRepository {
  GuestInfosRepository(this._db);

  final AppDatabase _db;

  /// جلب كل السجلات
  Future<List<GuestInfo>> listAll() async {
    return _db.select(_db.guestInfos).get();
  }

  /// مراقبة التغييرات
  Stream<List<GuestInfo>> watchAll() {
    return _db.select(_db.guestInfos).watch();
  }

  /// إنشاء سجل جديد
  Future<int> create({
    required String roomNumber,
    required String guestName,
    required String nationality,
    required String idNumber,
    String idType = 'بطاقة شخصية',
    String? issueDate,
    String? issuePlace,
    String? governorate,
    String? notes,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();
    return _db.into(_db.guestInfos).insert(
      GuestInfosCompanion(
        roomNumber: d.Value(roomNumber),
        guestName: d.Value(guestName),
        nationality: d.Value(nationality),
        idNumber: d.Value(idNumber),
        idType: d.Value(idType),
        issueDate: d.Value(issueDate),
        issuePlace: d.Value(issuePlace),
        governorate: d.Value(governorate),
        notes: d.Value(notes),
        localUuid: d.Value(_uuid()),
        createdAt: d.Value(now),
        updatedAt: d.Value(now),
        lastModified: d.Value(now),
        createdAtIso: d.Value(nowIso),
        updatedAtIso: d.Value(nowIso),
        version: const d.Value(1),
        origin: const d.Value('local'),
        vectorClock: const d.Value('{}'),
      ),
    );
  }

  /// تحديث سجل موجود
  Future<void> update(
    int id, {
    required String roomNumber,
    required String guestName,
    required String nationality,
    required String idNumber,
    String idType = 'بطاقة شخصية',
    String issueDate = '',
    String issuePlace = '',
    String governorate = '',
    String notes = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final nowIso = DateTime.now().toIso8601String();
    await (_db.update(_db.guestInfos)..where((t) => t.id.equals(id))).write(
      GuestInfosCompanion(
        roomNumber: d.Value(roomNumber),
        guestName: d.Value(guestName),
        nationality: d.Value(nationality),
        idNumber: d.Value(idNumber),
        idType: d.Value(idType),
        issueDate: d.Value(issueDate.isEmpty ? null : issueDate),
        issuePlace: d.Value(issuePlace.isEmpty ? null : issuePlace),
        governorate: d.Value(governorate.isEmpty ? null : governorate),
        notes: d.Value(notes.isEmpty ? null : notes),
        updatedAt: d.Value(now),
        lastModified: d.Value(now),
        updatedAtIso: d.Value(nowIso),
      ),
    );
  }

  /// حذف سجل
  Future<void> delete(int id) async {
    await (_db.delete(_db.guestInfos)..where((t) => t.id.equals(id))).go();
  }

  String _uuid() {
    // Simple UUID v4-like generator without external dependency
    const hexChars = '0123456789abcdef';
    final now = DateTime.now().microsecondsSinceEpoch;
    final rng = now & 0xFFFFFFFF;
    return '${hexChars[(rng >> 28) & 0xF]}${hexChars[(rng >> 24) & 0xF]}${hexChars[(rng >> 20) & 0xF]}${hexChars[(rng >> 16) & 0xF]}-'
        '${hexChars[(rng >> 12) & 0xF]}${hexChars[(rng >> 8) & 0xF]}${hexChars[(rng >> 4) & 0xF]}${hexChars[rng & 0xF]}-'
        '${hexChars[(now >> 60) & 0xF]}${hexChars[(now >> 56) & 0xF]}${hexChars[(now >> 52) & 0xF]}${hexChars[(now >> 48) & 0xF]}-'
        '${hexChars[(now >> 44) & 0xF]}${hexChars[(now >> 40) & 0xF]}${hexChars[(now >> 36) & 0xF]}${hexChars[(now >> 32) & 0xF]}';
  }
}
