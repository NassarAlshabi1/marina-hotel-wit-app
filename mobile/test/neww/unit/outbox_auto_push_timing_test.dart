import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_constants.dart';

void main() {
  group('Outbox auto-push timing', () {
    test('يجمع التغييرات المحلية ثم يبدأ الدفع بعد ثانيتين من آخر تغيير', () {
      expect(SyncConstants.outboxDebounceWindow, const Duration(seconds: 2));
    });

    test('لا يساوي مهلة المزامنة الدورية التي تعمل بالدقائق', () {
      expect(
        SyncConstants.outboxDebounceWindow,
        lessThan(SyncConstants.defaultAutoSyncInterval),
      );
    });

    test('تبقى إعدادات التطبيق محلية ولا تدخل في Appwrite حالياً', () {
      expect(SyncConstants.appSettingsSyncEnabled, isFalse);
    });
  });
}
