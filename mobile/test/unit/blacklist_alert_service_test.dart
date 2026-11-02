import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/blacklist_alert_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/blacklist_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late BlacklistRepository repo;
  late BlacklistAlertService alerts;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = BlacklistRepository(db);
    alerts = BlacklistAlertService(repo);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedWanted() async {
    await repo.addEntry(
      name: 'أحمد محمد علي',
      nationalId: '123456',
      reason: 'مطلوب أمني',
    );
  }

  test('يعيد المطابقة عند تسجيل اسم مطلوب (ويطلق التنبيه)', () async {
    await seedWanted();

    // قناة إشعارات النظام غير متاحة في الاختبار — يجب أن يعيد المطابقة
    // رغم ذلك (فشل الإشعار لا يلغي النتيجة).
    final match = await alerts.notifyIfBlacklisted(
      guestName: 'أحمد محمد علي',
      bookingId: 42,
      roomNumber: '101',
    );

    expect(match, isNotNull);
    expect(match!.name, 'أحمد محمد علي');
  });

  test('يعيد null للاسم غير المسجل دون إطلاق تنبيه', () async {
    await seedWanted();

    final match = await alerts.notifyIfBlacklisted(
      guestName: 'خالد عبدالله سالم',
    );

    expect(match, isNull);
  });

  test('يطابق أول 3 أسماء مثل شاشة الحجز', () async {
    await seedWanted();

    final match = await alerts.notifyIfBlacklisted(
      guestName: 'أحمد محمد علي الحداد',
    );

    expect(match, isNotNull);
  });

  test('لا يكسر مسار الحجز أبداً (لا يرمي استثناء)', () async {
    // قاعدة فارغة تماماً — يجب أن يعيد null بهدوء.
    final match = await alerts.notifyIfBlacklisted(guestName: 'أي اسم');

    expect(match, isNull);
  });
}
