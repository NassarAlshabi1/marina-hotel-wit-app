import 'package:shared_preferences/shared_preferences.dart';

import 'sync_checkpoint_store.dart';

/// ✅ إصلاح تسليم الآباء المحذوفين (2026-09-13):
///
/// **المشكلة**: الموظفون المحذوفون ناعماً (tombstones) على السحابة كانوا
/// يُستبعدون من Full pull لكل المجموعات — راجع
/// `SyncPullService.entityNeedsTombstoneParents('employees')`. الإصلاح
/// الموثق بتاريخ 2026-09-02 عرّف الاستثناء لكنه لم يُوصَّل بالمحرك الموحد،
/// فبقيت سحوبات الرواتب القديمة (بلا employeeUuid) تُتخطى كأيتام على كل
/// جهاز لا يملك صفّ الموظف محلياً.
///
/// **الفجوة التي يعالجها هذا الصنف**: حتى بعد توصيل الاستثناء في
/// `UnifiedPullEngine.plan()`، الإصلاح يغطي التثبيتات الجديدة فقط —
/// الأجهزة الموجودة أكملت Full pull للموظفين سابقاً (checkpoint سليم
/// ومؤشر أحدث من تواريخ الحذف)، والدلتا لن تعيد جلب tombstones قديمة
/// ($updatedAt لم يتغير). زر «سحب الآن» دلتا أيضاً.
///
/// **الحل**: إعادة ضبط checkpoint مجموعة `employees` مرة واحدة لكل جهاز
/// (عند أول تشغيل بعد الترقية) — الدورة التالية تجري Full pull للموظفين
/// شاملاً tombstones (بفضل استثناء الآباء)، وتُخزَّن صفوفاً غير مرئية
/// (deletedAt > 0) يُحل ضدها FK السحوبات القديمة عبر uuid/serverId.
///
/// العلم [doneKey] يُكتب **فقط بعد** نجاح إعادة الضبط — فشل عابر (قفل
/// قاعدة بيانات مثلاً) يعيد المحاولة في التهيئة التالية بدل فقدان الإصلاح.
///
/// إعادة السحب آمنة وقابلة للتكرار: `_isRemoteDataNewer` يطبق فقط ما
/// هو أحدث (الموظفون غير المتغيرون يُتخطون)، والتكلفة = عدد الموظفين
/// على السحابة (عشرات، صفحات قليلة).
class TombstoneParentsRepull {
  TombstoneParentsRepull._();

  /// مفتاح العلم — v1 للسماح بإصدارات مستقبلية لكيانات أخرى.
  static const String doneKey =
      'sync_tombstone_parents_repull_employees_v1';

  /// المجموعة الوحيدة المصنفة "أصل مرجعي" حالياً (نفس قرار
  /// [SyncPullService.entityNeedsTombstoneParents]).
  static const String collection = 'employees';

  /// ينفذ إعادة الضبط لمرة واحدة إن لزم.
  ///
  /// يعيد true إذا نُفذت إعادة الضبط في هذا الاستدعاء، وfalse إذا كان
  /// منفذاً سابقاً (أو اعتُبر غير لازم).
  static Future<bool> runIfNeeded({
    required SyncCheckpointStore checkpoints,
    required SharedPreferences prefs,
  }) async {
    if (prefs.getBool(doneKey) ?? false) return false;

    await checkpoints.reset(collection);
    await prefs.setBool(doneKey, true);
    return true;
  }
}
