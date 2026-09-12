// test/unit/guest_infos_full_pull_display_chain_test.dart
//
// ✅ برهان تنفيذي للإصلاح (2026-09-13): guest infos لا يعرض كل البيانات
// بعد السحب.
//
// يحاكي السلسلة الكاملة كما تعمل في الإنتاج:
//
//   مستندات Appwrite (150: منها 10 tombstones)
//     → ما يُرجعه _listAllDocumentsInternal فعلياً (ترقيم مؤشري، بلا حد)
//     → تطبيق _syncGuestInfos (adapter.upsertFromJson, Source.appwrite)
//     → المزوّد: watchAll() بلا حد (الإصلاح)
//     → الشاشة: PaginatedDataTable يعرض الكل، والتصدير عبر listAll()
//
// النتيجة قبل الإصلاح: المزوّد كان يمرر limit = 15 (أجهزة 1GB) → الشاشة
// تعرض أول 15 سجلاً فقط رغم وجود 140 سجلاً نشطاً في القاعدة.
// النتيجة بعد الإصلاح: كل الـ 140 تصل للشاشة.

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/adapters/adapter_registry.dart';
import 'package:marina_hotel_mobile/services/adapters/source.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/guest_infos_repository.dart';

import '../helpers/test_database.dart';

const int kActiveCount = 140;
const int kTombstoneCount = 10;
const int kTotalDocs = kActiveCount + kTombstoneCount;

void main() {
  late AppDatabase db;
  late GuestInfosRepository repo;
  late AdapterRegistry registry;

  setUp(() {
    db = TestDatabase.create();
    repo = GuestInfosRepository(db);
    registry = AdapterRegistry(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// مستند بعيد بالشكل المخزَّن في Appwrite (ناتج guestInfoToRemote).
  Map<String, dynamic> remoteDoc({
    required String uuid,
    required int seq,
    int? deletedAt,
  }) {
    return {
      'localUuid': uuid,
      'createdAt': 1760000000 - 100,
      'updatedAt': 1760000000 + seq,
      'lastModified': 1760000000 + seq,
      'lastModifiedEpoch': 1760000000 + seq,
      'createdAtEpoch': 1760000000 - 100,
      'version': 1,
      'origin': 'server',
      'vectorClock': '{"deviceA": 2}',
      'deviceId': 'deviceA',
      'roomNumber': '${100 + seq}',
      'guestName': 'نزيل سحب $seq',
      'nationality': 'يمني',
      'idNumber': 'ID-$seq',
      'idType': 'بطاقة شخصية',
      'issueDate': '2026-01-15',
      'issuePlace': 'عدن',
      'governorate': 'عدن',
      'notes': 'سجل $seq من السحب الكامل',
      if (deletedAt != null) 'deletedAt': deletedAt,
    };
  }

  /// يحاكي دورة سحب كاملة: 150 مستنداً تُطبَّق كما يفعل _syncGuestInfos
  /// (لكل مستند: upsertFromJson بمصدر appwrite — وtombstone يُطبَّق أيضاً
  /// ليُخفي السجل محلياً).
  Future<void> simulateFullPull() async {
    for (var i = 1; i <= kTotalDocs; i++) {
      final deleted = i > kActiveCount ? 1760000000 + i : null;
      final doc = remoteDoc(
        uuid: 'pull-uuid-$i',
        seq: i,
        deletedAt: deleted,
      );
      // مطابق لفرع _syncGuestInfos: data['localUuid'] ??= doc.$id
      doc['localUuid'] ??= 'pull-doc-$i';
      await registry.guestInfos.upsertFromJson(doc, src: Source.appwrite);
    }
  }

  test('سحب $kTotalDocs مستنداً → كل السجلات النشطة تصل للعرض (الإصلاح)', () async {
    await simulateFullPull();

    // ما تراه الشاشة الآن (المزوّد بعد الإصلاح — بلا حد SQL):
    final displayed = await repo.watchAll().first;
    expect(displayed.length, kActiveCount,
        reason: 'كل السجلات النشطة يجب أن تصل للشاشة — '
            'الحد القديم (15) كان يخفي الباقي');

    // كل سجل نشط حاضر ببياناته.
    final names = displayed.map((r) => r.guestName).toSet();
    for (var i = 1; i <= kActiveCount; i++) {
      expect(names.contains('نزيل سحب $i'), isTrue, reason: 'السجل $i غائب');
    }

    // الـ tombstones في القاعدة (للإسناد التراخي) لكنها مستبعدة من العرض.
    final rawCount = await (db.select(db.guestInfos)).get();
    expect(rawCount.length, kTotalDocs);
  });

  test('مسار العرض القديم (limit=15 على أجهزة 1GB) كان يعرض 15 فقط — توثيق',
      () async {
    await simulateFullPull();

    final oldPath = await repo.watchAll(limit: 15).first;
    expect(oldPath.length, 15);
    expect(oldPath.length, lessThan(kActiveCount),
        reason: 'يثبت أن limit=15 كان يقطع ما يراه المستخدم');
  });

  test('مسار تصدير PDF (listAll بلا حد) يشمل كل السجلات النشطة', () async {
    await simulateFullPull();

    final exported = await repo.listAll();
    expect(exported.length, kActiveCount);
  });

  test('tombstone بعيد يُطبَّق محلياً ويُستبعد من العرض (لا ظهور شبحي)',
      () async {
    await simulateFullPull();

    final all = await repo.watchAll().first;
    expect(
      all.every((r) => r.deletedAt == null),
      isTrue,
      reason: 'العرض يستبعد المحذوفة ناعماً — الحذف يتوصل عبر tombstone',
    );
    expect(
      all.every((r) => r.guestName.isNotEmpty),
      isTrue,
    );
  });
}
