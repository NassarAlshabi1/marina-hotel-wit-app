// test/unit/guest_infos_watch_all_unlimited_test.dart
//
// ✅ إصلاح (2026-09-13): guest infos لا يعرض كل البيانات بعد السحب.
//
// الجذر: `guestInfoListProvider` كان يمرر
// `limit: WeakDeviceOptimizer.instance.maxListItemsBeforePagination`
// (15/20/50/100 حسب مستوى الجهاز) إلى `watchAll()` — أي LIMIT على مستوى
// SQLite. بعد سحب ناجح يفوق عدد سجلاته الحد، كانت الشاشة تعرض أول N سجل
// فقط بصمت وتبدو باقي البيانات "مفقودة" رغم وجودها كاملاً في القاعدة.
//
// الإصلاح: المزوّد يسحب الكل (بلا LIMIT)، والشاشة تعرض عبر PaginatedDataTable
// (صفوف الصفحة المرئية فقط — حماية الأداء انتقلت من SQL إلى العرض)،
// وتصدير PDF يجلب الكل عبر listAll().
//
// هذه الاختبارات توثّق:
//  1. watchAll() بلا حد يرجع كل السجلات النشطة مهما كان عددها (الإصلاح).
//  2. watchAll(limit: N) يقصّ عند N (توثيق السلوك القديم المرجعي).
//  3. listAll() بلا حد يرجع الكل (مسار تصدير PDF).
//  4. الحذف الناعم مستبعد في المسارين محدود وغير محدود.

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/guest_infos_repository.dart';

import '../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late GuestInfosRepository repo;

  /// عدد سجلات أعلى من كل حدود الجهاز (15/20/50/100) لإثبات القصّ سابقاً.
  const int kTotal = 120;

  setUp(() {
    db = TestDatabase.create();
    repo = GuestInfosRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedRecords(int count) async {
    for (var i = 1; i <= count; i++) {
      await repo.create(
        roomNumber: '$i',
        guestName: 'نزيل $i',
        nationality: 'يمني',
        idNumber: 'ID-$i',
      );
    }
  }

  group('watchAll بلا حد — الإصلاح', () {
    test('يرجع كل السجلات النشطة ($kTotal سجلاً) رغم تجاوز حدود الأجهزة', () async {
      await seedRecords(kTotal);

      final all = await repo.watchAll().first;
      expect(all.length, kTotal, reason:
          'watchAll بلا حد يجب أن يرجع كل السجلات — الحد القديم (15/20/50/100) '
          'كان يُخفي الباقي بعد السحب الناجح');
    });

    test('السجلات كلها غير محذوفة وبياناتها سليمة', () async {
      await seedRecords(5);
      final rows = await repo.watchAll().first;
      expect(rows.length, 5);
      expect(rows.every((r) => r.deletedAt == null), isTrue);
      expect(rows.every((r) => r.guestName.startsWith('نزيل')), isTrue);
    });
  });

  group('watchAll بحد — توثيق السلوك القديم', () {
    test('limit=15 (أجهزة 1GB سابقاً) يقصّ $kTotal سجلاً إلى 15', () async {
      await seedRecords(kTotal);

      final limited = await repo.watchAll(limit: 15).first;
      expect(limited.length, 15);
      expect(limited.length, lessThan(kTotal));
    });

    test('limit=100 (أجهزة قوية سابقاً) يقصّ أيضاً', () async {
      await seedRecords(kTotal);

      final limited = await repo.watchAll(limit: 100).first;
      expect(limited.length, 100);
    });

    test('الحذف الناعم مستبعد حتى مع الحد', () async {
      await seedRecords(20);
      final rows = await repo.watchAll(limit: 15).first;
      final deleted = rows.first;
      await repo.delete(deleted.id);

      // الحد يعيد ملء الصفحة بالسجل رقم 16 (تبقى 15 عناصر)،
      // لكن المحذوف ناعماً غائب حتماً من النتائج.
      final after = await repo.watchAll(limit: 15).first;
      expect(after.length, 15);
      expect(after.every((r) => r.id != deleted.id), isTrue);
      // وعدد السجلات النشطة الكلي انخفض فعلياً إلى 19.
      expect((await repo.watchAll().first).length, 19);
    });
  });

  group('listAll بلا حد — مسار تصدير PDF', () {
    test('يرجع كل السجلات النشطة لتصدير PDF كامل', () async {
      await seedRecords(kTotal);

      final all = await repo.listAll();
      expect(all.length, kTotal);
    });

    test('يرجع أحدث تحديثاً أولاً (ترتيب updatedAt DESC)', () async {
      await seedRecords(3);
      final rows = await repo.listAll();
      for (var i = 0; i < rows.length - 1; i++) {
        expect(
          rows[i].updatedAt >= rows[i + 1].updatedAt,
          isTrue,
          reason: 'الترتيب يجب أن يكون تنازلياً حسب updatedAt',
        );
      }
    });
  });
}
