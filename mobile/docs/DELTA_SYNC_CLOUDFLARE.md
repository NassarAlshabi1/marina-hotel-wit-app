# Delta Sync Service — Cloudflare D1 Migration

## 📋 نظرة عامة

تم تحويل `DeltaSyncService` من نمط Appwrite القديم إلى نمط **Cloudflare D1** الحديث مع دعم كامل لـ:
- ✅ Vector Clocks للمزامنة متعددة الأجهزة
- ✅ تتبع الجهاز الأصلي (origin tracking)
- ✅ كشف التضارعات عبر إصدار الصف (version)
- ✅ مفاتيح عدم التكرار للأمان في الإعادة (idempotency keys)

---

## 🏗️ البنية المعمارية

### قبل (Legacy Appwrite):
```
DeltaSyncChange {
  entity: String
  operation: String (insert | update)
  data: Map
  rowHash: String
  localUuid: String
  clientTimestamp: int
}
```

### بعد (Cloudflare D1):
```
DeltaSyncChange {
  entity: String
  operation: String (insert | update | delete)
  data: Map
  rowHash: String
  localUuid: String
  clientTimestamp: int
  vectorClock: String      // ✅ NEW: "device1:5,device2:3,..."
  origin: String           // ✅ NEW: device UUID
  version: int             // ✅ NEW: conflict detection
  idempotencyKey: String   // ✅ NEW: retry safety
}
```

---

## 🔄 سير العمل

### 1️⃣ استخراج البيانات (Extraction)
```dart
final changes = await deltaSyncService.compute(since: lastPushTs);
// يُرجع DeltaSyncComputation {
//   changes: List<DeltaSyncChange>,
//   mirrorSnapshot: Map<entity, Map<uuid, MirrorRow>>,
//   fallbackTables: Set<entity>
// }
```

### 2️⃣ البيانات المستخرجة
```
كل DeltaSyncChange يتضمن:
┌─────────────────────────────────────────┐
│ entity: "bookings"                      │
│ operation: "update"                     │
├─────────────────────────────────────────┤
│ data: {                                 │
│   id: 123,                              │
│   room_id: 45,                          │
│   check_in: 1725715200000,              │
│   total_due: 500.00,                    │
│   ...                                   │
│ }                                       │
├─────────────────────────────────────────┤
│ vectorClock: "device-001:42,device-002:8" │
│ origin: "device-001"                    │
│ version: 42                             │
│ idempotencyKey: "uuid-abc123"           │
│ rowHash: "sha1-hash-of-payload"         │
└─────────────────────────────────────────┘
```

### 3️⃣ الإرسال إلى Cloudflare D1
```dart
// في CloudflareSync Manager:
final payload = changes.map((c) => c.toMap()).toList();
// إرسال إلى API:
POST /api/sync/delta
{
  "changes": [
    {
      "entity": "bookings",
      "operation": "update",
      "data": {...},
      "vector_clock": "device-001:42,device-002:8",
      "origin": "device-001",
      "version": 42,
      "idempotency_key": "uuid-abc123",
      ...
    }
  ]
}
```

### 4️⃣ معالجة الخادم (Server Processing)
```
Cloudflare D1 يقوم بـ:
1. التحقق من idempotencyKey (تجنب التكرار)
2. دمج vectorClocks من جميع الأجهزة
3. حل التضارعات عبر version + timestamp
4. تطبيق التغييرات على جدول السحابة
5. إرجاع تأكيد النجاح + vectorClock المحدّث
```

---

## 📊 Vector Clock (ساعة المتجهات)

### الفكرة
كل جهاز له عداد للإصدار. عند تطبيق تغيير محلي، يزداد عداد الجهاز.

```
الحالة الأولية:
┌──────────────────────────────┐
│ Device-001: 0                │
│ Device-002: 0                │
│ Device-003: 0                │
└──────────────────────────────┘

بعد تطبيق تغيير محلي على Device-001:
┌──────────────────────────────┐
│ Device-001: 1 ← تزايد        │
│ Device-002: 0                │
│ Device-003: 0                │
└──────────────────────────────┘
vectorClock = "device-001:1"

بعد مزامنة ورجوع vectorClock من الخادم:
┌──────────────────────────────┐
│ Device-001: 5                │
│ Device-002: 3                │
│ Device-003: 0                │
└──────────────────────────────┘
vectorClock = "device-001:5,device-002:3"
```

### كشف التضارعات
```
إذا حدث تغييران متزامنان من جهازين:

Device-001:
  version: 42
  timestamp: 1725715200000
  vectorClock: "device-001:42"

Device-002:
  version: 35
  timestamp: 1725715199999  ← أقدم بـ 1ms
  vectorClock: "device-002:35"

🔧 حل التضارع (Conflict Resolution):
1. التحقق من vectorClocks (كلاهما يكتب لأول مرة)
2. فحص timestamp (device-002 أقدم)
3. تطبيق device-001 أولاً (الأحدث)
4. device-002 يتجاوز والتغيير يبقى في التاريخ
```

---

## 🔐 Idempotency Keys

### المشكلة
عند فشل الشبكة أثناء الإرسال، قد يُعيد المحاولة التطبيق:
```
الإرسال الأول: bookings/123 amount=500
[❌ فشل الاتصال]
الإرسال الثاني: bookings/123 amount=500
[✅ نجح]
```

بدون idempotency key، قد يتم تطبيق التغيير مرتين!

### الحل
```dart
idempotencyKey: "uuid-abc123-attempt-1"
```

Cloudflare D1 يتحقق:
```
إذا idempotencyKey موجود في سجل المعاملات السابقة:
  → رجّع النتيجة السابقة (لا تطبق مجدداً)

وإلا:
  → طبّق التغيير
  → احفظ idempotencyKey
```

---

## 🎯 استخدام عملي

### إنشاء تغيير وإرساله
```dart
// 1. محلياً: تطبيق التغيير
final booking = Booking(
  id: 123,
  totalDueCached: 500.00,
  lastModified: DateTime.now().millisecondsSinceEpoch,
  vectorClock: "device-001:42",
  origin: "device-001",
  version: 42,
  idempotencyKey: "uuid-abc123",
);
await db.bookings.insertOne(booking);

// 2. حساب الـ delta
final computation = await deltaSyncService.compute();
// DeltaSyncChange {
//   entity: "bookings",
//   operation: "insert",
//   vectorClock: "device-001:42",
//   origin: "device-001",
//   version: 42,
//   idempotencyKey: "uuid-abc123",
//   ...
// }

// 3. إرسال إلى Cloudflare D1
final result = await cloudflareSync.pushChanges(computation.changes);
// تحديث vectorClock محلياً من الخادم:
// vectorClock = "device-001:42,device-002:3,..."
```

---

## 📈 كل 22 جدول محدّث

| الجدول | الحالة |
|--------|--------|
| rooms | ✅ |
| bookings | ✅ |
| booking_notes | ✅ |
| employees | ✅ |
| inventory_items | ✅ |
| inventory_transactions | ✅ |
| expenses | ✅ |
| cash_transactions | ✅ |
| payments | ✅ |
| debts | ✅ |
| booking_nights | ✅ |
| guest_infos | ✅ |
| salary_withdrawals | ✅ |
| salary_carry_over_logs | ✅ |
| salary_cycles | ✅ |
| salary_payments | ✅ |
| shift_notes | ✅ |
| price_adjustments | ✅ |
| audit_logs | ✅ |
| payment_voids | ✅ |
| booking_price_adjustments | ✅ |

---

## 🔧 تحسينات الأداء

### Isolate-Based Computation
```dart
// الحساب يحدث في عملية منفصلة (لا يوقف UI)
final output = await Isolate.run(
  () => _computeDeltaSyncInIsolate(isolateInput),
);
// ✅ لا تأثير على الـ UI أثناء الحساب
// ✅ يمكن للمستخدم الاستمرار في العمل
```

### Normalized Timestamps
```dart
// تحويل آلي من ثوانٍ إلى مللي ثانية
input: 1725715200 (ثوانٍ)
output: 1725715200000 (مللي ثانية)

// توحيد صيغة الطابع الزمني في جميع الجداول
```

### Mirror Table for Delta Detection
```dart
sync_mirror TABLE:
  table_name | local_uuid | row_hash | payload | last_seen_at
  
✅ المقارنة السريعة: rowHash (SHA-1) vs rowHash المحفوظ
✅ تجنب فحص كل حقل واحداً تلو الآخر
✅ دعم soft-delete (تتبع deleted_at)
```

---

## ⚠️ الحالات الخاصة

### 1. Hard Delete (حذف حقيقي)
```
إذا كان السجل موجوداً في Mirror لكن غير موجود الآن:
→ تم حذفه محلياً
→ إرسال operation: "delete"
→ حفظ deleted_at timestamp
```

### 2. First Sync
```
إذا لم توجد Mirror للجدول (أول مرة):
→ افترض أن كل السجلات جديدة
→ أرسل operation: "insert" للكل
→ لا تقارن مع Mirror (غير موجود)
```

### 3. Fallback Mode
```
إذا فشل بناء Mirror (مثلاً: بيانات كبيرة جداً):
→ استخدم lastModified timestamp بدلاً من Mirror
→ تسجيل تحذير في السجلات
→ الأداء أقل قليلاً لكن آمن تماماً
```

---

## 🚀 الخطوات التالية

### Phase 1: Integration (هذا الأسبوع)
- [ ] تحديث `cloudflare_sync_manager.dart` لاستخدام الحقول الجديدة
- [ ] اختبار الحساب مع بيانات حقيقية
- [ ] التحقق من صحة vectorClocks

### Phase 2: Conflict Resolution (الأسبوع المقبل)
- [ ] تطبيق منطق حل التضارعات على الجهاز المحمول
- [ ] اختبار سيناريوهات متزامنة متعددة الأجهزة
- [ ] مراقبة الأداء

### Phase 3: Production Rollout (في غضون أسبوعين)
- [ ] نشر على الخادم الفاصل (staging)
- [ ] اختبار الحمل مع 1000+ سجل
- [ ] مراقبة الأخطاء الحقيقية
- [ ] النشر التدريجي (canary deployment)

---

## 📝 المراجع

- Vector Clocks: https://en.wikipedia.org/wiki/Vector_clock
- Idempotency: https://en.wikipedia.org/wiki/Idempotence
- Cloudflare D1: https://developers.cloudflare.com/d1/
- Conflict Resolution: Conflict-free Replicated Data Type (CRDT)

---

**الحالة الحالية:** ✅ **جاهز للتكامل مع Cloudflare D1**
