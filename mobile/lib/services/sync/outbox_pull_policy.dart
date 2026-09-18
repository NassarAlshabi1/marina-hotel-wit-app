/// سياسة Offline-first للسحب من Appwrite.
///
/// لا يُسمح بالسحب ما دامت هناك عناصر Outbox غير مُسلّمة. بهذه القاعدة
/// تصبح قاعدة البيانات المحلية وOutbox مصدر الحقيقة حتى يكتمل الرفع.
abstract final class OutboxPullPolicy {
  static bool canPull({required int undeliveredOutboxCount}) {
    return undeliveredOutboxCount == 0;
  }

  static String blockedMessage({required int undeliveredOutboxCount}) {
    return 'تم تعطيل السحب مؤقتاً حتى رفع '
        '$undeliveredOutboxCount تغييراً محلياً معلّقاً';
  }
}
