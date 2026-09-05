// ✅ (2026-09-06) تغطية BootstrapFullPull.evaluate — طلب المستخدم:
// «عند تثبيت التطبيق والضغط على زر المتابعة بدون مزامنة يتم سحب
// full sync» — سياسة العلم: يُضبط بعد اكتمال السحب فقط، والفشل
// يتركه فارغاً لإعادة المحاولة عند الإطلاق القادم.
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/bootstrap_full_pull.dart';

void main() {
  group('BootstrapFullPull.evaluate — سياسة السحب الكامل بعد التخطي', () {
    test('1. بلا تخطٍّ: لا سحب ولا كتابة علم (notApplicable)', () async {
      var pullCalled = false;
      var flagWrites = 0;
      final outcome = await BootstrapFullPull.evaluate(
        driveLoginSkipped: false,
        pullDoneFlag: false,
        isFullSyncCompleted: false,
        initializeAndFullPull: () async {
          pullCalled = true;
          return true;
        },
        setPullDoneFlag: (_) async => flagWrites++,
      );

      expect(outcome, BootstrapFullPullOutcome.notApplicable);
      expect(pullCalled, isFalse, reason: 'من لم يتخطَّ لا يُسحب له شيء');
      expect(flagWrites, 0, reason: 'لا كتابة علم لمستخدم غير مُتخطٍ');
    });

    test('2. العلم مضبوط سلفاً: alreadyDone بلا سحب ولا إعادة كتابة', () async {
      var pullCalled = false;
      var flagWrites = 0;
      final outcome = await BootstrapFullPull.evaluate(
        driveLoginSkipped: true,
        pullDoneFlag: true,
        isFullSyncCompleted: false,
        initializeAndFullPull: () async {
          pullCalled = true;
          return true;
        },
        setPullDoneFlag: (_) async => flagWrites++,
      );

      expect(outcome, BootstrapFullPullOutcome.alreadyDone);
      expect(pullCalled, isFalse, reason: 'لا سحب كامل مكرر');
      expect(flagWrites, 0, reason: 'العلم مضبوط — لا كتابة إضافية');
    });

    test(
      '3. علم فارغ لكن isFullSyncCompleted=true: تقارب العلم بلا سحب',
      () async {
        var pullCalled = false;
        final writtenValues = <bool>[];
        final outcome = await BootstrapFullPull.evaluate(
          driveLoginSkipped: true,
          pullDoneFlag: false,
          isFullSyncCompleted: true,
          initializeAndFullPull: () async {
            pullCalled = true;
            return true;
          },
          setPullDoneFlag: (v) async => writtenValues.add(v),
        );

        expect(outcome, BootstrapFullPullOutcome.alreadyDone);
        expect(pullCalled, isFalse);
        expect(writtenValues, [
          true,
        ], reason: 'تقارب علامة الإتمام مع علامة التخطي');
      },
    );

    test('4. تخطٍ + علم فارغ + نجاح السحب: succeeded والعلم يُضبط', () async {
      var pullCalled = false;
      final writtenValues = <bool>[];
      final outcome = await BootstrapFullPull.evaluate(
        driveLoginSkipped: true,
        pullDoneFlag: false,
        isFullSyncCompleted: false,
        initializeAndFullPull: () async {
          pullCalled = true;
          return true;
        },
        setPullDoneFlag: (v) async => writtenValues.add(v),
      );

      expect(outcome, BootstrapFullPullOutcome.succeeded);
      expect(pullCalled, isTrue);
      expect(writtenValues, [true], reason: 'العلم يُضبط بعد النجاح فقط');
    });

    test(
      '5. تخطٍ + علم فارغ + فشل السحب: failed والعلم يبقى فارغاً',
      () async {
        var pullCalled = false;
        var flagWrites = 0;
        final outcome = await BootstrapFullPull.evaluate(
          driveLoginSkipped: true,
          pullDoneFlag: false,
          isFullSyncCompleted: false,
          initializeAndFullPull: () async {
            pullCalled = true;
            return false;
          },
          setPullDoneFlag: (_) async => flagWrites++,
        );

        expect(outcome, BootstrapFullPullOutcome.failed);
        expect(pullCalled, isTrue);
        expect(
          flagWrites,
          0,
          reason: 'فشل السحب لا يضبط العلم — إعادة المحاولة قادمة',
        );
      },
    );

    test(
      '6. أولوية العلم على isFullSyncCompleted=false: flag=true يفوز',
      () async {
        var pullCalled = false;
        final outcome = await BootstrapFullPull.evaluate(
          driveLoginSkipped: true,
          pullDoneFlag: true,
          isFullSyncCompleted: false,
          initializeAndFullPull: () async {
            pullCalled = true;
            return false;
          },
          setPullDoneFlag: (_) async {},
        );

        expect(outcome, BootstrapFullPullOutcome.alreadyDone);
        expect(pullCalled, isFalse);
      },
    );

    test('7. مفاتيح الأعلام ثابتة ومتوافقة مع التركيبات القائمة', () {
      // توافق صريح مع 2026-09-01: نفس مفتاح العلم القديم — تغييره
      // يُعيد السحب الكامل لتركيبات أنهت السحب سلفاً (كرر العمل بلا داعٍ).
      expect(
        BootstrapFullPull.pullDoneFlagKey,
        'appwrite_pull_after_drive_skip_done',
      );
      // توافق مع BackupStatusNotifier._driveLoginSkippedKey
      // (backup_provider.dart) — دون هذا التطابق لا تعرف الخدمة
      // أن المستخدم اختار التخطي أصلاً.
      expect(BootstrapFullPull.driveLoginSkippedKey, 'drive_login_skipped');
    });
  });
}
