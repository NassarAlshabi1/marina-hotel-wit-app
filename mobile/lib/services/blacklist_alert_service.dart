import 'repositories/blacklist_repository.dart';
import 'sync_notification_manager.dart';

/// تنبيه أمني عند تسجيل مطلوب في الحجوزات.
///
/// القائمة السوداء تسجّل مطلوبين أمنياً لدى الشرطة. عند إنشاء حجز باسم
/// مطابق (كامل أو أول 3 أسماء) يُرسل إشعار نظام فوري يظهر على الشاشة
/// الرئيسية حتى لو غادر المستخدم شاشة الحجز.
///
/// القاعدة الذهبية: التنبيه لا يكسر مسار الحجز أبداً — أي خطأ يُبتلع
/// بصمت ويُعاد `null`/السجل المطابق حسب الحالة.
class BlacklistAlertService {
  BlacklistAlertService(this._repository);

  final BlacklistRepository _repository;

  /// يفحص [guestName] ضد القائمة السوداء، ويرسل إشعار نظام عند المطابقة.
  ///
  /// يعيد عنصر القائمة المطابق أو `null` عند عدم المطابقة/الفشل.
  /// فشل الإشعار نفسه لا يمنع إرجاع المطابقة (مفيد للاختبارات حيث قناة
  /// الإشعارات غير متاحة).
  Future<BlacklistEntry?> notifyIfBlacklisted({
    required String guestName,
    int? bookingId,
    String? roomNumber,
  }) async {
    try {
      final match = await _repository.findBlacklistMatch(guestName);
      if (match == null) return null;
      try {
        final where = [
          if (roomNumber != null && roomNumber.isNotEmpty) 'غرفة $roomNumber',
          if (bookingId != null) 'حجز #$bookingId',
        ].join(' — ');
        await SyncNotificationManager.instance.showSystemNotification(
          title: 'تحذير أمني — مطلوب في القائمة السوداء',
          body:
              '${match.name}${where.isEmpty ? '' : ' ($where)'} '
              'تم تسجيله في الحجوزات. يُرجى إبلاغ الشرطة.',
          payload: 'blacklist:${match.localUuid ?? match.id}',
        );
      } catch (_) {
        // فشل الإشعار لا يلغي المطابقة — المتصل قد يعرض تنبيهاً بديلاً.
      }
      return match;
    } catch (_) {
      return null;
    }
  }
}
