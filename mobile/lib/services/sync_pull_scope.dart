import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_constants.dart';

/// بيانات وصفية لجدول (collection) قابل للسحب من Appwrite.
class PullCollectionMeta {
  const PullCollectionMeta({
    required this.name,
    required this.label,
    required this.category,
    this.core = false,
  });

  /// اسم المجموعة كما يظهر في مهام السحب (مفتاح sync_checkpoints).
  final String name;

  /// الاسم المعروض بالعربية في واجهة الإعدادات.
  final String label;

  /// الفئة التي يُجمَّع تحتها الجدول في واجهة الاختيار.
  final String category;

  /// true → الجدول أصل مرجعي لأبناء (FK) — تعطيله قد يُنتج سجلات يتيمة.
  final bool core;
}

/// ✅ نطاق السحب (2026-09-12): التحكم من الإعدادات في الجداول التي يُسمح
/// بسحبها من Appwrite إلى الجهاز.
///
/// **المبدأ**: المفتاح واحد (`appwrite_pull_disabled_collections`) يُخزَّن
/// كقائمة أسماء الجداول *المعطّلة* — فارغ افتراضياً = كل الجداول مسموحة.
/// تخزين المعطّل بدل المفعّل يجعل أي جدول جديد يُضاف مستقبلاً يعمل فوراً
/// بلا حاجة لتحديث الإعدادات (Fail-safe الافتراضي هو السلوك الحالي).
///
/// **نقاط الربط**:
/// - [load] تُستدعى مرة واحدة من `AppwriteSyncManager.initialize()`.
/// - [isDisabled] تُقرأ بشكل متزامن داخل `_buildPullTasks()` — يغطي تلقائياً
///   كل مسارات السحب (المزامنة الكاملة، pullRemoteChanges، التثبيت الأول)
///   لأنها كلها تمر عبر قائمة المهام الموحدة.
/// - [setDisabled] تكتب الذاكرة + التخزين من شاشة الإعدادات — تؤثر من
///   الدورة التالية مباشرة دون إعادة تشغيل.
///
/// **أمان المؤشرات**: تعطيل جدول لا يلمس checkpoint الخاص به في
/// `sync_checkpoints` — عند إعادة تفعيله لاحقاً يُسحب كل ما فاته من نقطة
/// توقفه القديمة (Delta من المؤشر القديم) فلا تُفقد بيانات.
class SyncPullScope {
  SyncPullScope._();

  /// مفتاح SharedPreferences: قائمة أسماء الجداول المعطّلة للسحب.
  static const String prefsKey = 'appwrite_pull_disabled_collections';

  /// الذاكرة الحية للجداول المعطّلة — تُقرأ من حلقة السحب بشكل متزامن.
  static final Set<String> _disabled = <String>{};

  static bool _loaded = false;

  /// تحميل الجداول المعطّلة من التخزين (يُستدعى من تهيئة مدير المزامنة).
  /// فشل القراءة يُبقي الافتراض الآمن: كل الجداول مفعّلة.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(prefsKey) ?? const <String>[];
      _disabled
        ..clear()
        ..addAll(stored.where((n) => catalogNames.contains(n)));
      _loaded = true;
    } catch (_) {
      // فشل التحميل → الافتراضي (كل شيء مفعّل) — سلوك ما قبل الميزة.
      _disabled.clear();
      _loaded = true;
    }
  }

  /// هل الجدول معطّل للسحب؟ قبل التحميل يُعامل كل شيء كمفعّل (آمن).
  static bool isDisabled(String collectionName) =>
      _loaded && _disabled.contains(collectionName);

  /// عدد الجداول المعطّلة حالياً.
  static int get disabledCount => _disabled.length;

  /// نسخة غير قابلة للتعديل من المعطّل (للواجهة والاختبارات).
  static Set<String> disabledSnapshot() => Set<String>.unmodifiable(_disabled);

  /// تحديث قائمة المعطّل من واجهة الإعدادات: ذاكرة + تخزين معاً.
  /// الأسماء غير المعروفة في الكتالوج تُتجاهل حفظاً (تنظيف تلقائي).
  static Future<void> setDisabled(Set<String> names) async {
    _disabled
      ..clear()
      ..addAll(names.where((n) => catalogNames.contains(n)));
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(prefsKey, _disabled.toList());
  }

  /// حقن مباشر للاختبارات فقط (بلا تخزين).
  @visibleForTesting
  static void attachForTesting(Set<String> disabled) {
    _disabled
      ..clear()
      ..addAll(disabled);
    _loaded = true;
  }

  /// تصفير الحالة للاختبارات.
  @visibleForTesting
  static void resetForTesting() {
    _disabled.clear();
    _loaded = false;
  }

  /// كتالوج الجداول القابلة للسحب — بالترتيب نفسه لمهام `_buildPullTasks()`
  /// (ترتيب FK-آمن) ومصنّعة للعرض في واجهة الاختيار.
  ///
  /// `core = true` → أصل مرجعي: الغرف/الحجوزات أبناؤها ليالي وملاحظات
  /// ومدفوعات وديون، والموظفون أصل دورات وسحوبات الرواتب (نمط الأيتام
  /// الموثق في sync_pull_service.entityNeedsTombstoneParents).
  static const List<PullCollectionMeta> catalog = <PullCollectionMeta>[
    // ─── الإقامة والحجوزات ───
    PullCollectionMeta(
      name: 'rooms',
      label: 'الغرف',
      category: 'الإقامة والحجوزات',
      core: true,
    ),
    PullCollectionMeta(
      name: 'bookings',
      label: 'الحجوزات',
      category: 'الإقامة والحجوزات',
      core: true,
    ),
    PullCollectionMeta(
      name: 'booking_nights',
      label: 'ليالي الحجوزات',
      category: 'الإقامة والحجوزات',
    ),
    PullCollectionMeta(
      name: 'booking_notes',
      label: 'ملاحظات الحجوزات',
      category: 'الإقامة والحجوزات',
    ),
    PullCollectionMeta(
      name: 'guest_infos',
      label: 'معلومات النزلاء',
      category: 'الإقامة والحجوزات',
    ),
    PullCollectionMeta(
      name: 'blacklist',
      label: 'القائمة السوداء',
      category: 'الإقامة والحجوزات',
    ),
    // ─── المالية ───
    PullCollectionMeta(
      name: 'payments',
      label: 'المدفوعات',
      category: 'المالية',
    ),
    PullCollectionMeta(
      name: 'payment_voids',
      label: 'إلغاءات المدفوعات',
      category: 'المالية',
    ),
    PullCollectionMeta(name: 'debts', label: 'الديون', category: 'المالية'),
    PullCollectionMeta(
      name: 'expenses',
      label: 'المصاريف',
      category: 'المالية',
    ),
    PullCollectionMeta(
      name: 'cash_transactions',
      label: 'المعاملات النقدية',
      category: 'المالية',
      core: true,
    ),
    PullCollectionMeta(
      name: 'price_adjustments',
      label: 'تعديلات الأسعار',
      category: 'المالية',
    ),
    PullCollectionMeta(
      name: 'booking_price_adjustments',
      label: 'تعديلات أسعار الحجوزات',
      category: 'المالية',
    ),
    // ─── الموظفون والرواتب ───
    PullCollectionMeta(
      name: 'employees',
      label: 'الموظفون',
      category: 'الموظفون والرواتب',
      core: true,
    ),
    PullCollectionMeta(
      name: 'salary_cycles',
      label: 'دورات الرواتب',
      category: 'الموظفون والرواتب',
    ),
    PullCollectionMeta(
      name: 'salary_payments',
      label: 'مدفوعات الرواتب',
      category: 'الموظفون والرواتب',
    ),
    PullCollectionMeta(
      name: 'salary_withdrawals',
      label: 'سحوبات الرواتب',
      category: 'الموظفون والرواتب',
    ),
    PullCollectionMeta(
      name: 'salary_carry_over_logs',
      label: 'سجلات ترحيل الراتب',
      category: 'الموظفون والرواتب',
    ),
    PullCollectionMeta(
      name: 'shift_notes',
      label: 'ملاحظات الورديات',
      category: 'الموظفون والرواتب',
    ),
    // ─── المخزون ───
    PullCollectionMeta(
      name: 'inventory_items',
      label: 'أصناف المخزون',
      category: 'المخزون',
    ),
    PullCollectionMeta(
      name: 'inventory_transactions',
      label: 'حركات المخزون',
      category: 'المخزون',
    ),
    // ─── أخرى ───
    PullCollectionMeta(
      name: 'audit_logs',
      label: 'سجلات التدقيق',
      category: 'أخرى',
    ),
    if (SyncConstants.appSettingsSyncEnabled)
      PullCollectionMeta(
        name: 'app_settings',
        label: 'إعدادات التطبيق',
        category: 'أخرى',
      ),
  ];

  /// أسماء الكتالوج فقط (للتنظيف والتحقق).
  static Set<String> get catalogNames => catalog.map((m) => m.name).toSet();

  /// الكتالوج مجمّعاً حسب الفئة — بترتيب إدراج الفئات في الكتالوج.
  static Map<String, List<PullCollectionMeta>> get catalogByCategory {
    final grouped = <String, List<PullCollectionMeta>>{};
    for (final meta in catalog) {
      grouped.putIfAbsent(meta.category, () => []).add(meta);
    }
    return grouped;
  }
}
