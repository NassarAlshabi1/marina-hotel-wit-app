// ══════════════════════════════════════════════════════════════════
//  pull_apply_rules.dart — pull-apply ordering and natural dedup keys
// ══════════════════════════════════════════════════════════════════

/// أولوية الآباء عند إعادة محاولة الصفوف المؤجلة — الأب قبل الابن.
const Map<String, int> pullApplyPriority = {
  'rooms': 0,
  'employees': 1,
  'inventory_items': 1,
  'cash_transactions': 1,
  'bookings': 2,
  'salary_cycles': 3,
  'booking_nights': 4,
  'payments': 4,
  'booking_notes': 4,
  'guest_infos': 4,
  'booking_price_adjustments': 4,
  'inventory_transactions': 4,
  'salary_withdrawals': 4,
  'salary_carry_over_logs': 4,
  'salary_payments': 5,
};

/// ✅ (2026-09-09) إصلاح تجميد السحب (398 ليلة): المفاتيح الطبيعية
/// الفريدة محلياً لكل كيان (uniqueKeys في local_db.dart). صف خادمي
/// يصل بـ local_uuid جديد لكن بمفتاح طبيعي موجود محلياً = نسخة
/// مكررة منطقياً (أصل: سطر restore نسخة احتياطية بـ idempotency_key
/// «backup_*»، أو إعادة بناء مشتقات محلية origin='auto_fix' مقابل
/// نسخ خادمية لنفس الليلة). INSERT عليها كان يرمي SqliteException(2067)
/// فيُفشل كل دورة سحب إلى الأبد.
///
/// العقد: قبل INSERT نبحث بالمفتاح الطبيعي — إن وُجد صف محلي فالوارد
/// نسخة مكررة تُدمج بـ LWW (الأحدث بيانات يفوز، هوية الصف المحلي
/// تبقى) ولا يُدرج صف ثانٍ. UNIQUE المحلي يبقى ضامناً لصف واحد لكل
/// ليلة، والدورة تكمل بدل أن تتجمد.
const Map<String, List<String>> naturalUniqueKeys = {
  'booking_nights': ['booking_local_id', 'hotel_day_key'],
};
