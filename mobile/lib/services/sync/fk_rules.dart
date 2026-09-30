// ══════════════════════════════════════════════════════════════════
//  fk_rules.dart — FK translation rules: server identity to local identity
// ══════════════════════════════════════════════════════════════════

// ─── قواعد ترجمة علاقات FK بين هوية الخادم والهوية المحلية ─────

/// نوع قاعدة FK:
/// - [numericPointer]: العمود الرقمي على الابن يحمل id الأب في فضاء
///   الخادم (D1) — تُترجم القيمة إلى id الصف المحلي عند التطبيق.
/// - [naturalKey]: العمود نصّي يحمل مفتاحاً عالمياً ثابتاً بين الأجهزة
///   (room_number أو local_uuid للأب) — القيمة تمر كما هي، والمطلوب
///   فقط التأكد من وجود الأب (وإلا يؤجَّل الصف).
enum FkKind { numericPointer, naturalKey }

class FkRule {
  const FkRule({
    required this.entity,
    required this.column,
    required this.kind,
    required this.parentTable,
    required this.parentKeyColumn,
    this.nullable = false,
    this.uuidCacheColumn,
    this.legacyServerBookingId = false,
    this.nullWhenUnresolvable = false,
  });

  /// كيان الابن (اسم جدول D1).
  final String entity;

  /// عمود FK على الابن.
  final String column;

  final FkKind kind;

  /// جدول الأب المحلي.
  final String parentTable;

  /// عمود المفتاح على الأب: 'id' للمؤشرات الرقمية، أو المفتاح الطبيعي
  /// (room_number / local_uuid) لقواعد naturalKey.
  final String parentKeyColumn;

  /// هل يقبل العمود NULL محلياً؟ (غير القابل للـ null بلا حل = تأجيل).
  final bool nullable;

  /// عمود uuid-cache على الابن يحمل local_uuid الأب — المفتاح العالمي
  /// الأول (مثل booking_uuid_cache / item_local_uuid).
  final String? uuidCacheColumn;

  /// جرّب أيضاً فضاء Appwrite القديم: server_booking_id على الابن ضد
  /// server_booking_id على الأب (الصفوف المهاجرة من Appwrite تشترك
  /// في فضاء المعرفات هذا).
  final bool legacyServerBookingId;

  /// مؤشر ثانوي غير جوهري (cash_transaction_local_id): تعذّرت الترجمة
  /// → NULL بدل تعطيل دورة السحب كلها. لا يُستخدم إلا مع nullable.
  final bool nullWhenUnresolvable;
}

/// خريطة علاقات FK المحلية التي تحمل هوية خادمية — مستخرجة آلياً من
/// local_db.dart (كل .references) وschema.sql الخادمي.
///
/// ملاحظات:
///  * payment_voids وprice_adjustments أعمدتها كلها uuid عالمية بلا
///    قيود FK محلية — تمر بلا ترجمة، فلا قاعدة لها هنا.
///  * bookings.room_number → rooms.room_number مفتاح طبيعي ثابت بين
///    الأجهزة (نفس النص)، المطلوب وجود الغرفة فقط.
const List<FkRule> fkRules = [
  // الحجوزات: room_number مفتاح طبيعي على الغرف.
  FkRule(
    entity: 'bookings',
    column: 'room_number',
    kind: FkKind.naturalKey,
    parentTable: 'rooms',
    parentKeyColumn: 'room_number',
  ),
  // ليالي الحجز → الحجز.
  FkRule(
    entity: 'booking_nights',
    column: 'booking_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'booking_uuid_cache',
    legacyServerBookingId: true,
  ),
  // ملاحظات الحجز → الحجز (لا uuid-cache على السلك — الاعتماد على
  // ظلّ server_id للأب أو فضاء Appwrite).
  FkRule(
    entity: 'booking_notes',
    column: 'booking_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    legacyServerBookingId: true,
  ),
  // المدفوعات → الحجز (قابل للـ null — دفعة بلا حجز تمر بـ NULL).
  FkRule(
    entity: 'payments',
    column: 'booking_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    nullable: true,
    uuidCacheColumn: 'booking_uuid_cache',
    legacyServerBookingId: true,
  ),
  // المدفوعات → معاملة الصندوق: مؤشر ثانوي بلا مفتاح عالمي على السلك
  // (local_id المحلي للجهاز الدافع لا معنى له بين الأجهزة) — تعذّرت
  // الترجمة → NULL ولا يُعطَّل السحب لمجرد مؤشر صندوق.
  FkRule(
    entity: 'payments',
    column: 'cash_transaction_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'cash_transactions',
    parentKeyColumn: 'id',
    nullable: true,
    nullWhenUnresolvable: true,
  ),
  // تسويات السعر → الحجز (بالمعرّفين معاً).
  FkRule(
    entity: 'booking_price_adjustments',
    column: 'booking_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    nullable: true,
    uuidCacheColumn: 'booking_uuid',
    legacyServerBookingId: true,
  ),
  FkRule(
    entity: 'booking_price_adjustments',
    column: 'booking_local_uuid',
    kind: FkKind.naturalKey,
    parentTable: 'bookings',
    parentKeyColumn: 'local_uuid',
  ),
  // دورات الرواتب → الموظف.
  FkRule(
    entity: 'salary_cycles',
    column: 'employee_id',
    kind: FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'employee_uuid',
  ),
  // دفعات الدورة → الدورة (سلّتان: موظف ثم دورة — ترتيب الأولويات
  // في إعادة المحاولة يضمن اكتمال السلسلة).
  FkRule(
    entity: 'salary_payments',
    column: 'cycle_id',
    kind: FkKind.numericPointer,
    parentTable: 'salary_cycles',
    parentKeyColumn: 'id',
  ),
  // السحب من الراتب → الموظف.
  FkRule(
    entity: 'salary_withdrawals',
    column: 'employee_id',
    kind: FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'employee_uuid',
  ),
  // سجلات ترحيل الراتب → الموظف.
  FkRule(
    entity: 'salary_carry_over_logs',
    column: 'employee_id',
    kind: FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
  ),
  // حركات المخزون → صنف المخزون (item_local_uuid مفتاح عالمي).
  FkRule(
    entity: 'inventory_transactions',
    column: 'item_id',
    kind: FkKind.numericPointer,
    parentTable: 'inventory_items',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'item_local_uuid',
  ),
];

final Map<String, List<FkRule>> fkRulesByEntity = (() {
  final map = <String, List<FkRule>>{};
  for (final rule in fkRules) {
    map.putIfAbsent(rule.entity, () => <FkRule>[]).add(rule);
  }
  return map;
})();
