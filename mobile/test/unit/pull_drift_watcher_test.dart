// ═══════════════════════════════════════════════════════════════
//  pull_drift_watcher_test.dart — (2026-09-25) انحدار Bug Dashboard
//
//  العَرَض المُبلَّغ: بعد سحب البيانات، بطاقات Dashboard (المدفوعات/
//  المصروفات/المتبقي) لا تتحدث إلا بعد الانتقال لشاشة أخرى والعودة.
//
//  الجذر (من الكود لا التخمين): كل كتابات تطبيق السحب في
//  CloudflareSyncManager تمر عبر customStatement (SQL خام)، وdrift
//  لا يُشعر stream queries إلا عن كتابات واجهته المولَّدة. البطاقات
//  تشترك في تيارات customSelect(..., readsFrom).watchSingle() فتظل
//  على القيمة القديمة؛ والعودة من شاشة أخرى تُعيد إنشاء مزوّد
//  autoDispose فتقرأ القيمة الجديدة.
//
//  الإصلاح: _notifyTableTouched → db.notifyUpdates بعد كل كتابة سحب.
//
//  هذا الاختبار يثبت المسار نفسه الذي تشترك فيه البطاقات: تيار
//  drift واحد يبقى مشتركاً عبر السحب ويستقبل قيماً جديدة بلا إعادة
//  إنشاء. كان يفشل قبل الإصلاح (تيار واحد صامت إلى الأبد).
// ═══════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:marina_hotel_mobile/services/cloudflare_sync_manager.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/screens/settings/error_tracker_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// عميل HTTP وهمي: تطبيق السحب المحلي لا يستدعي الشبكة أصلاً —
/// يكفي فقط استيفاء توقيع configureForTesting.
class _NoNetworkClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('no network expected in this test');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cloudflare_sync_local_override': true,
    });
    ErrorTrackerStore.instance.clear();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    CloudflareSyncManager.instance.reset();
    await db.close();
  });

  Future<CloudflareSyncManager> makeManager() async {
    final manager = CloudflareSyncManager();
    manager.reset();
    manager.configureForTesting(
      database: db,
      httpClient: _NoNetworkClient(),
      token: 'watch-test-token',
      deviceId: 'watch-test-device',
    );
    return manager;
  }

  Map<String, dynamic> paymentRecord(
    String uuid, {
    required double amount,
    required int updatedAt,
  }) {
    return <String, dynamic>{
      'local_uuid': uuid,
      'server_id': uuid.hashCode.abs() % 100000,
      'amount': amount,
      'payment_date': '2026-09-25 15:00',
      'payment_method': 'cash',
      'revenue_type': 'room',
      'hotel_day_key': '2026-09-25',
      'created_at': updatedAt,
      'updated_at': updatedAt,
      'last_modified': updatedAt,
      'version': 1,
      'device_id': 'other-device',
    };
  }

  /// نفس استعلام بطاقة «المدفوعات اليوم» في Dashboard بالحرف —
  /// (customSelect + readsFrom + watchSingle).
  Stream<double> dashboardPaymentsTotalStream() {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0',
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((r) => (r.data['total'] as num).toDouble());
  }

  test(
    'pulled payment INSERT wakes the live dashboard stream (no rebuild)',
    () async {
      final manager = await makeManager();

      final emissions = <double>[];
      final sub = dashboardPaymentsTotalStream().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions, [0.0], reason: 'الحالة الابتدائية قبل السحب');

      final report = await manager.applyPulledRecords([
        (
          entity: 'payments',
          record: paymentRecord(
            'pay-watch-1',
            amount: 500,
            updatedAt: 1758800000,
          ),
        ),
      ]);
      expect(report.appliedCount, 1, reason: 'الصف يُطبَّق فعلاً');
      expect(report.errors, isEmpty);

      // نفس الاشتراك (بلا إعادة إنشاء) يجب أن يستقبل القيمة الجديدة.
      await expectLater(
        dashboardPaymentsTotalStream().map((_) => true).take(1),
        emitsInOrder([true]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        emissions,
        contains(500.0),
        reason: 'التيار الحيّ يستيقظ بعد إشعار notifyUpdates — نفس الاشتراك',
      );
      await sub.cancel();
    },
  );

  test(
    'pulled payment UPDATE and tombstone both wake the live stream',
    () async {
      final manager = await makeManager();

      final emissions = <double>[];
      final sub = dashboardPaymentsTotalStream().listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 1) إدخال من جهاز آخر
      await manager.applyPulledRecords([
        (
          entity: 'payments',
          record: paymentRecord(
            'pay-watch-2',
            amount: 300,
            updatedAt: 1758800001,
          ),
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(emissions, contains(300.0));

      // 2) تعديل بعيد لنفس الصف (LWW sequential update)
      await manager.applyPulledRecords([
        (
          entity: 'payments',
          record: paymentRecord(
            'pay-watch-2',
            amount: 450,
            updatedAt: 1758800002,
          ),
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        emissions,
        contains(450.0),
        reason: 'مسار UPDATE الخام يستيقظ التيار أيضاً',
      );

      // 3) tombstone من جهاز آخر — حذف ناعم عبر UPDATE خام
      await manager.applyPulledRecords([
        (
          entity: 'payments',
          record: <String, dynamic>{
            ...paymentRecord('pay-watch-2', amount: 450, updatedAt: 1758800003),
            'deleted_at': 1758800003,
          },
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        emissions,
        contains(0.0),
        reason: 'الحذف الناعم الخام يعيد الإجمالي إلى صفر على التيار الحيّ',
      );

      await sub.cancel();
    },
  );
}
