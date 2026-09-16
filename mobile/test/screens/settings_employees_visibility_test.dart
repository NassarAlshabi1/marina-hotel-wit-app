// ignore_for_file: lines_longer_than_80_chars
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/screens/settings/settings_employees.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/employees_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ✅ (2026-09-17) عقد إخفاء المُنهية خدماتهم من قائمة إعدادات الموظفين:
/// عند فصل موظف أو الاستغناء عنه يختفي من القائمة الافتراضية (تُترك
/// الحالات الأخرى مثل المجمد/غير النشط ظاهرة)، ويُستعاد ظهوره عبر
/// includeTerminated أو بعد إعادة التفعيل. المستودع نفسه يبقى يرجّع
/// الجميع (الفلتر على مستوى الشاشة فقط — الاستحقاقات والشاشات الأخرى
/// غير متأثرة).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EmployeesRepository empRepo;

  setUp(() {
    // ✅ mock لمنع أخطاء AutoBackupManager (نمط employee_salary_crud_test)
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    empRepo = EmployeesRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<int>> seedEmployees() async {
    final activeId = await empRepo.create(
      name: 'أحمد النشط',
      basicSalary: 50000,
      position: 'استقبال',
      phone: '777111111',
      status: 'active',
    );
    final firedId = await empRepo.create(
      name: 'سالم المفصول',
      basicSalary: 60000,
      position: 'نادل',
      phone: '777222222',
      status: 'active',
    );
    final laidOffId = await empRepo.create(
      name: 'خالد المستغنى عنه',
      basicSalary: 70000,
      position: 'حارس',
      phone: '777333333',
      status: 'active',
    );
    final frozenId = await empRepo.create(
      name: 'منصور المجمد',
      basicSalary: 40000,
      position: 'تنظيف',
      phone: '777444444',
      status: 'frozen',
    );
    return [activeId, firedId, laidOffId, frozenId];
  }

  group('إخفاء المُنهية خدماتهم من قائمة الإعدادات', () {
    test('فصل موظف (مفصول) → يختفي من القائمة الافتراضية', () async {
      final ids = await seedEmployees();
      await empRepo.terminate(
        id: ids[1],
        terminationType: 'مفصول',
        terminationDate: '2026-09-17',
        terminationReason: 'اختبار فصل',
      );

      final all = await empRepo.watchAll().first;
      expect(all.length, 4, reason: 'المستودع يرجّع الجميع (عقد unchanged)');

      final visible = SettingsEmployeesScreen.filterVisible(
        all,
        includeTerminated: false,
      );
      expect(visible.length, 3, reason: 'المفصول مخفي، الباقي ظاهر');
      expect(
        visible.map((e) => e.name),
        isNot(contains('سالم المفصول')),
      );
      expect(
        SettingsEmployeesScreen.countTerminated(all),
        1,
      );
    });

    test('استغناء عن موظف → يختفي من القائمة الافتراضية', () async {
      final ids = await seedEmployees();
      await empRepo.terminate(
        id: ids[2],
        terminationType: 'استغناء',
        terminationDate: '2026-09-17',
      );

      final all = await empRepo.watchAll().first;
      // terminate يكتب الحالة الكانونية — استغناء → laid_off
      final laidOff = all.firstWhere((e) => e.id == ids[2]);
      expect(laidOff.status, 'laid_off');

      final visible = SettingsEmployeesScreen.filterVisible(
        all,
        includeTerminated: false,
      );
      expect(visible.length, 3);
      expect(visible.map((e) => e.name), isNot(contains('خالد المستغنى عنه')));
    });

    test('الحالات غير المنهية (مجمد/غير نشط) تبقى ظاهرة — لا يُخفى غير المُنهية', () async {
      final ids = await seedEmployees();
      await empRepo.terminate(
        id: ids[1],
        terminationType: 'استقالة',
        terminationDate: '2026-09-17',
      );

      final all = await empRepo.watchAll().first;
      final visible = SettingsEmployeesScreen.filterVisible(
        all,
        includeTerminated: false,
      );
      // الإنهاء كان استقالة لسالم فقط. الظاهرون: النشط (أحمد وخالد —
      // خالد لم يُنهَ في هذا السيناريو) + المجمد (منصور) = 3.
      expect(
        visible.map((e) => e.name),
        containsAll(['أحمد النشط', 'خالد المستغنى عنه', 'منصور المجمد']),
      );
      expect(visible.map((e) => e.name), isNot(contains('سالم المفصول')));
      expect(visible.length, 3);
    });

    test('includeTerminated يُظهر الجميع (مسار الإعادة/الاستحقاق)', () async {
      final ids = await seedEmployees();
      await empRepo.terminate(
        id: ids[1],
        terminationType: 'مفصول',
        terminationDate: '2026-09-17',
      );
      await empRepo.terminate(
        id: ids[2],
        terminationType: 'استغناء',
        terminationDate: '2026-09-17',
      );

      final all = await empRepo.watchAll().first;
      final visible = SettingsEmployeesScreen.filterVisible(
        all,
        includeTerminated: true,
      );
      expect(visible.length, 4);
      expect(SettingsEmployeesScreen.countTerminated(all), 2);
    });

    test('إعادة التفعيل → الموظف يعود للقائمة الافتراضية', () async {
      final ids = await seedEmployees();
      await empRepo.terminate(
        id: ids[1],
        terminationType: 'مفصول',
        terminationDate: '2026-09-17',
      );

      // قبل الإعادة: مخفي
      var all = await empRepo.watchAll().first;
      expect(
        SettingsEmployeesScreen.filterVisible(all, includeTerminated: false)
            .map((e) => e.name),
        isNot(contains('سالم المفصول')),
      );

      await empRepo.reactivate(id: ids[1]);

      all = await empRepo.watchAll().first;
      final visible = SettingsEmployeesScreen.filterVisible(
        all,
        includeTerminated: false,
      );
      expect(visible.map((e) => e.name), contains('سالم المفصول'));
      expect(SettingsEmployeesScreen.countTerminated(all), 0);
    });
  });
}
