// utils/identity_gate.dart
//
// ✅ (P2-9 / P2-10 — 2026-10-06): بوابتان صغيرتان نقيتان للمزامنة:
//   1. `appliedRecordsInPull` — لا تُعلن السجلات المؤجَّلة (ناقصة الربط)
//      كسجلات مطبَّقة في عدّاد «سحب الآن».
//   2. `mayApplyServerId` — لا تُكتب هوية رقمية (`server_id`) على صف محلي
//      إلا إذا كان رد الخادم يخصّ **نفس السجل** (تطابق هوية مُعادة)، أو
//      بلا هوية مُعادة إطلاقاً (توافق خلفي) — لا مطابقة بالترتيب الصامت.
class UuidIdentity {
  const UuidIdentity._();

  /// توحيد شكل UUID للمقارنة: إزالة الشرطات + خفض الحالة.
  static String normalize(String value) =>
      value.trim().toLowerCase().replaceAll('-', '');

  /// هل الهويّتان تعودان لنفس السجل؟ (يُقبل اختلاف شكل الشرطات).
  static bool sameIdentity(String a, String b) {
    final na = normalize(a);
    final nb = normalize(b);
    return na.isNotEmpty && na == nb;
  }

  /// يستخرج هوية السجل من رد الرفع إن وُجدت.
  ///
  /// تدعم الأسماء الشائعة في هذا المشروع والعقد القديم (snake_case).
  static String? echoedFrom(Map<String, dynamic> result) {
    for (final key in const ['localUuid', 'local_uuid', 'uuid']) {
      final value = result[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  /// هل يجوز تطبيق معرّف الخادم على هذا السجل؟
  ///
  ///  • الهوية المُعادة تطابق سجلنا ⇒ نعم.
  ///  • الهوية المُعادة تخصّ سجلاً آخر ⇒ **لا** (لا نكتب رقم سجل آخر هنا).
  ///  • لا هوية مُعادة (عقد ناقص) ⇒ نعم للتوافق الخلفي، مع تحذير يُسجَّله
  ///    المستدعي — لا صمت.
  static bool mayApplyServerId({
    required String changeLocalUuid,
    String? echoedLocalUuid,
  }) {
    if (echoedLocalUuid == null) return true;
    return sameIdentity(changeLocalUuid, echoedLocalUuid);
  }

  /// العدد المُعلن للسجلات المطبَّقة فعلياً في دورة سحب واحدة.
  ///
  /// [reported] = ما أعادته مهام السحب، [deferredDelta] = كم سجلاً جديداً
  /// أُجّل (ناقص الربط) في نفس الدورة. لا نتيجة سالبة إطلاقاً.
  static int appliedRecordsInPull({
    required int reported,
    required int deferredDelta,
  }) {
    if (reported <= 0) return 0;
    final applied = reported - (deferredDelta > 0 ? deferredDelta : 0);
    return applied < 0 ? 0 : applied;
  }
}
