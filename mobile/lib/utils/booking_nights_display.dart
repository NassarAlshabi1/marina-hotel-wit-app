import 'status_utils.dart';
import 'time.dart';

/// عرض الليالي في قائمة الحجوزات — مصدر واحد للنسختين
/// (الجدول العريض والبطاقات المدمجة).
///
/// قبل توحيد هذه القاعدة كان منطق الحساب مكرّراً حرفياً في نسختين داخل
/// شاشة القائمة، وفيه عيبان يمسّان «انقطاع العرض عند المغادرة الفعلية»:
///
///  1. fallback الليالي المتوقعة كان يمرّر plannedCheckout (قابل
///     للإفراغ) مباشرة إلى Time.nightsWithCutoff — فإذا غاب المخطط
///     (حجوزات legacy بلا checkoutDate وexpectedNights=0) وسُجّلت
///     مغادرة فعلية، احتُسبت الليالي حتى «الآن» إلى ما لا نهاية رغم
///     خروج الضيف فعلياً.
///  2. المغادرة الفعلية المسجّلة بتاريخ مستقبلي (شذوذ بيانات) كانت
///     تُستخدم كما هي فتجاوز العرض اللحظة الحالية — خلافاً لسياسة مصدر
///     الحقيقة في BookingPaymentScreen وStayBalanceCalculator.
class BookingNightsDisplay {
  BookingNightsDisplay._();

  /// ليالي العرض (المتوقعة والفعلية) لصف واحد في قائمة الحجوزات.
  ///
  /// [now] يُمرَّر من الاختبارات فقط للحتمية؛ الإنتاج يتركه فارغاً.
  ///
  /// سياسة نهاية الإقامة (الليالي الفعلية) — نفس قاعدة مصدر الحقيقة
  /// في `BookingPaymentScreen._calculateStay` و`StayBalanceCalculator`:
  ///  * actualCheckout مسجّل وفي الماضي → عنده تنقطع الليالي نهائياً.
  ///  * actualCheckout مسجّل مستقبلاً (شذوذ بيانات) → يُقصّ إلى «الآن».
  ///  * لا actualCheckout والحجز نشط → تراكم ديناميكي حتى «الآن».
  ///  * لا actualCheckout وحجز غير نشط → plannedCheckout إن وُجد.
  ///
  /// سياسة الليالي المتوقعة:
  ///  * [storedExpectedNights] > 0 → هي المرجع الأول.
  ///  * حجز مفتوح بلا أي موعد (لا مخطط ولا فعلي) → ديناميكية حتى «الآن».
  ///  * دخول غير قابل للتحليل → القيمة المحفوظة أو 1.
  ///  * خلاف ذلك → من الدخول حتى نهاية الإقامة المعروفة: المخطط أولاً
  ///    وإلا actualCheckout المسجّل — لا «الآن» أبداً بعد مغادرة مسجّلة.
  static ({int expectedNights, int actualNights}) forList({
    required String status,
    required int storedExpectedNights,
    required DateTime? checkin,
    DateTime? plannedCheckout,
    DateTime? actualCheckout,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final bool activeStay =
        actualCheckout == null && StatusUtils.isActiveBooking(status);

    // ─── الليالي المتوقعة ───
    final int expectedNights;
    if (checkin == null) {
      expectedNights = storedExpectedNights > 0 ? storedExpectedNights : 1;
    } else if (plannedCheckout == null && actualCheckout == null) {
      // حجز مفتوح بلا أي موعد خروج → احتساب ديناميكي من «الآن».
      expectedNights = Time.nightsWithCutoff(checkin, checkout: moment);
    } else if (storedExpectedNights > 0) {
      expectedNights = storedExpectedNights;
    } else {
      // لا قيمة محفوظة ولا مخطط: نهاية الإقامة المعروفة — المخطط أولاً
      // وإلا المغادرة الفعلية المسجّلة (كانت قبل الإصلاح تتراكم حتى «الآن»).
      expectedNights = Time.nightsWithCutoff(
        checkin,
        checkout: plannedCheckout ?? actualCheckout,
      );
    }

    // ─── نهاية الإقامة للليالي الفعلية (سياسة مصدر الحقيقة نفسها) ───
    final DateTime? effectiveStayEnd;
    if (actualCheckout != null && !actualCheckout.isAfter(moment)) {
      // مغادرة فعلية ماضية → الإقامة تنتهي عندها ولا تتراكم بعدها أبداً.
      effectiveStayEnd = actualCheckout;
    } else if (actualCheckout != null || activeStay) {
      // مغادرة مسجّلة بتاريخ مستقبلي (شذوذ بيانات) تُقصّ إلى «الآن»،
      // والحجز النشط بلا مغادرة يتراكم ديناميكياً حتى «الآن».
      effectiveStayEnd = moment;
    } else {
      // حجز غير نشط بلا مغادرة فعلية → نهاية العرض عند المخطط إن وُجد.
      effectiveStayEnd = plannedCheckout;
    }

    final int actualNights = checkin == null
        ? expectedNights
        : Time.nightsWithCutoff(checkin, checkout: effectiveStayEnd);

    return (expectedNights: expectedNights, actualNights: actualNights);
  }
}
