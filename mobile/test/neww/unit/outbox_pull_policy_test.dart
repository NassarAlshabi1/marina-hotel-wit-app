import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync/outbox_pull_policy.dart';

void main() {
  group('OutboxPullPolicy', () {
    test('تسمح بالسحب فقط بعد تفريغ Outbox بالكامل', () {
      expect(OutboxPullPolicy.canPull(undeliveredOutboxCount: 0), isTrue);
      expect(OutboxPullPolicy.canPull(undeliveredOutboxCount: 1), isFalse);
      expect(OutboxPullPolicy.canPull(undeliveredOutboxCount: 25), isFalse);
    });

    test('رسالة الحظر توضّح أولوية رفع التغييرات المحلية', () {
      final message = OutboxPullPolicy.blockedMessage(
        undeliveredOutboxCount: 3,
      );

      expect(message, contains('3'));
      expect(message, contains('رفع'));
      expect(message, contains('السحب'));
    });
  });
}
