import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_realtime_sync.dart';

/// اختبارات عقد الدخول trigger-only لـ AppwriteRealtimeSync.
///
/// الخلفية المعمارية (بعد الدمج مع refactor/performance-fixes-v2):
/// نسخة هذا الملف كانت تختبر RemoteChangeQueue (تنفيذ v2). الدمج استعاد
/// نسخة الفرع الحالي من appwrite_realtime_sync.dart الأغنى وظيفياً
/// (ensureStarted + WS افتراضياً + debounce/cooldown/in-flight)، ودور
/// "طابور الأحداث" فيها تؤديه دورة: handleRemoteDataChange (ديبونس) ←
/// _schedulePull (cooldown + in-flight guard + trailing queue) ←
/// setSyncTrigger. الاختبارات أدناه تحقق **نفس القصد** الذي اختبره
/// إصدار v2: الحدث يدخل الطابور ولا يُطبَّق مباشرة، والانفجار يندمج في
/// سحب واحد، والفشل يحفظ الحالة المعلقة مع متابعة واحدة فقط.
void main() {
  group('AppwriteRealtimeSync trigger-only ingress', () {
    late AppwriteRealtimeSync realtime;

    setUp(() {
      // factory → singleton؛ resetForTesting يصفّر كل الحالة بما فيها
      // حقول debug (منع التسرب بين الاختبارات — راجع stop/reset).
      realtime = AppwriteRealtimeSync();
      realtime.resetForTesting();
      realtime.currentDeviceIdForTesting = 'test-device';
    });

    tearDown(() async {
      await realtime.stop();
    });

    test('coalesces a burst into one Delta pull trigger', () async {
      var pulls = 0;
      final completed = Completer<void>();
      realtime.debugEventDebounce = const Duration(milliseconds: 1);
      realtime.debugPullCooldown = Duration.zero;
      realtime.setSyncTrigger(() async {
        pulls++;
        if (!completed.isCompleted) completed.complete();
        return true;
      });

      // انفجار 10 أحداث متزامنة (من جهاز آخر) — الديبونس يندمجها في
      // دخول واحد للطابور ثم إطلاق سحب واحد.
      for (var i = 0; i < 10; i++) {
        realtime.handleRemoteDataChange(
          events: <String>['payments.update'],
          payload: <String, dynamic>{'deviceId': 'other-device'},
        );
      }

      await completed.future.timeout(const Duration(seconds: 2));
      // مهلة سماح قصيرة: أي إطلاق trailing إضافي سيظهر خلالها.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(pulls, 1, reason: 'الدفعة الواحدة = إطلاق سحب واحد فقط');
      expect(
        realtime.hasRemoteChanges.value,
        isFalse,
        reason: 'نجاح السحب يصفرّ شارة التغييرات',
      );
    });

    test('keeps pending state when trigger skips, retries once', () async {
      var attempts = 0;
      final first = Completer<void>();
      realtime.debugEventDebounce = const Duration(milliseconds: 1);
      realtime.debugPullCooldown = Duration.zero;
      realtime.setSyncTrigger(() async {
        attempts++;
        if (!first.isCompleted) first.complete();
        return false; // تخطٍّ (مثلاً: Outbox غير مفروغ بعد)
      });

      realtime.handleRemoteDataChange(
        events: <String>['payments.update'],
        payload: <String, dynamic>{'deviceId': 'other-device'},
      );

      await first.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        attempts,
        2,
        reason:
            'متابعة واحدة بعد أول تخطٍّ ثم التوقف — لا حلقة إعادة '
            'غير محدودة (تصميم _consecutiveSkips)',
      );
      expect(
        realtime.hasRemoteChanges.value,
        isTrue,
        reason: 'التخطي لا يصفرّ شارة التغييرات — الحالة ما زالت معلقة',
      );
    });

    test('ignores own-device events', () async {
      var pulls = 0;
      realtime.debugEventDebounce = const Duration(milliseconds: 1);
      realtime.debugPullCooldown = Duration.zero;
      realtime.setSyncTrigger(() async {
        pulls++;
        return true;
      });

      realtime.handleRemoteDataChange(
        events: <String>['payments.update'],
        payload: <String, dynamic>{'deviceId': 'test-device'},
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(pulls, 0, reason: 'تغييرات نفس الجهاز محلية أصلاً — لا سحب');
      expect(realtime.hasRemoteChanges.value, isFalse);
    });
  });
}
