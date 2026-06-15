# Memory - ملخص المحادثة والتعديلات

## التاريخ
15 يونيو 2026

## المشروع
تطبيق Flutter لإدارة الفنادق - نظام مزامنة ثنائي الاتجاه (Bi-directional Sync) عبر Appwrite Cloud و SQLite (Drift ORM)

## إجمالي التعديلات
**14 ملفاً معدلاً، 78 إضافة، 6 حذف**
**الالتزام:** `b678214`

---

## 1. ترتيب الدفع الصارم (Push Order)

**الملف:** `mobile/lib/services/daos/outbox_dao.dart`
**الدالة:** `takeBatch()`

**قبل:**
```dart
'  SELECT id FROM outbox WHERE processing_status = ?$sourceCondition ORDER BY client_ts ASC LIMIT ? '
```

**بعد:**
```dart
'  SELECT id FROM outbox WHERE processing_status = ?$sourceCondition ORDER BY CASE WHEN entity = \'rooms\' THEN 1 WHEN entity = \'employees\' THEN 2 WHEN entity = \'bookings\' THEN 3 WHEN entity = \'payments\' THEN 4 WHEN entity = \'expenses\' THEN 5 WHEN entity = \'debts\' THEN 6 WHEN entity = \'booking_notes\' THEN 7 WHEN entity = \'shift_notes\' THEN 8 WHEN entity = \'cash_transactions\' THEN 9 ELSE 10 END ASC, client_ts ASC LIMIT ? '
```

**الترتيب:** rooms(1) → employees(2) → bookings(3) → payments(4) → expenses(5) → debts(6) → booking_notes(7) → shift_notes(8) → cash_transactions(9) → باقي الجداول(10)

---

## 2. إعادة المحاولة مع تأخير أسي (Exponential Backoff)

**الملف:** `mobile/lib/services/daos/outbox_dao.dart`
**الدالة:** `retryFailedWithBackoff()` — جديدة

```dart
Future<int> retryFailedWithBackoff({
  int maxAttempts = 5,
  int backoffMinutes = 30,
}) async {
  final cutoff = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - (backoffMinutes * 60);
  
  // عناصر قليلة المحاولات → retry فوراً
  final lowAttempts = await (update(outbox)
        ..where((t) =>
            t.processingStatus.equals('failed') &
            t.attempts.isSmallerOrEqualValue(maxAttempts)))
      .write(const OutboxCompanion(
    processingStatus: Value('pending'),
    processingStartedAt: Value(null),
    processingWorker: Value(null),
  ),);
  
  // عناصر كثيرة المحاولات → انتظر backoffMinutes قبل إعادة المحاولة
  final highAttempts = await (update(outbox)
        ..where((t) =>
            t.processingStatus.equals('failed') &
            t.attempts.isBiggerThanValue(maxAttempts) &
            t.clientTs.isSmallerOrEqualValue(cutoff)))
      .write(const OutboxCompanion(
    processingStatus: Value('pending'),
    processingStartedAt: Value(null),
    processingWorker: Value(null),
  ),);
  
  return lowAttempts + highAttempts;
}
```

---

## 3. فحص الشبكة قبل الرفع

**الملف:** `mobile/lib/services/appwrite_sync_manager.dart`
**الدالة:** `_pushAllEntities()`

**قبل:**
```dart
Future<int> _pushAllEntities() async {
  final perfSettings = SyncPerformanceOptimizer.instance.getCurrentPerformanceSettings();
  final batchSize = perfSettings['batchSize'] as int? ?? 50;
  int totalProcessed = 0;
```

**بعد:**
```dart
Future<int> _pushAllEntities() async {
  // ✅ فحص الاتصال أولاً
  try {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      _logger.warning('⚠️ لا يوجد اتصال بالإنترنت - تم تأجيل الرفع', tag: 'SYNC');
      return 0;
    }
  } catch (_) {}

  final perfSettings = SyncPerformanceOptimizer.instance.getCurrentPerformanceSettings();
  final batchSize = perfSettings['batchSize'] as int? ?? 50;
  int totalProcessed = 0;
```

---

## 4. تحديث مؤقت إعادة المحاولة

**الملف:** `mobile/lib/services/appwrite_sync_manager.dart`
**الدالة:** `_startFailedRetryTimer()`

**قبل:**
```dart
await outboxDao.retryFailed();
```

**بعد:**
```dart
final resetCount = await outboxDao.retryFailedWithBackoff(
  maxAttempts: 5,
  backoffMinutes: 30,
);
if (resetCount == 0) return;
```

---

## 5. إضافة `version` في softDelete (9 DAOs)

**الملفات:**
- `bookings_dao.dart`، `booking_notes_dao.dart`، `cash_transactions_dao.dart`
- `debts_dao.dart`، `employees_dao.dart`، `expenses_dao.dart`
- `payments_dao.dart`، `rooms_dao.dart`، `shift_notes_dao.dart`

**قبل:**
```dart
BookingsCompanion(
  deletedAt: Value(now),
  updatedAt: Value(now),
  lastModified: Value(now),
  // ❌ version: Value(existing.version + 1) — مفقود!
)
```

**بعد:**
```dart
BookingsCompanion(
  deletedAt: Value(now),
  updatedAt: Value(now),
  lastModified: Value(now),
  version: Value(existing.version + 1),  // ✅ إضافة
)
```

**السبب:** بدون زيادة `version` عند soft delete، الحذف لا يعتبر أحدث من التعديلات الأخرى → فقدان الحذف عند المزامنة.

---

## 6. إصلاح guest_infos_repository.dart

**الملف:** `mobile/lib/services/repositories/guest_infos_repository.dart`

**إصلاح 1 - إضافة `version`:**
```dart
GuestInfosCompanion(
  deletedAt: d.Value(now),
  updatedAt: d.Value(now),
  lastModified: d.Value(now),
  version: d.Value(existing.version + 1),  // ✅ إضافة
  updatedAtIso: d.Value(nowIso),
  deletedAtIso: d.Value(nowIso),
),
```

**إصلاح 2 - تصحيح op:**
```dart
// قبل:  op: 'delete',  ← يمسح المستند من Appwrite بالكامل!
// بعد:  op: 'update',  ← يُحدّث deletedAt على Appwrite (soft delete)
```

---

## 7. إصلاح blacklist_repository.dart

**الملف:** `mobile/lib/services/repositories/blacklist_repository.dart`

```dart
ShiftNotesCompanion(
  deletedAt: d.Value(now),
  deletedAtIso: d.Value(nowIso),
  updatedAt: d.Value(now),
  lastModified: d.Value(now),
  version: d.Value(existing.version + 1),  // ✅ إضافة
),
```

---

## 8. إضافة `version` في تعديلات الأسعار

**الملف:** `mobile/lib/services/booking_price_adjustment_service.dart`

**في `cancelAdjustment()`:**
```dart
final update = BookingPriceAdjustmentsCompanion(
  isActive: Value(!fullyCancelled),
  endHotelDay: Value(effectiveEnd),
  cancelledAt: Value(nowIso),
  cancelledBy: Value(cancelledBy),
  updatedAt: Value(now),
  lastModified: Value(now),
  version: Value(adjustment.version + 1),  // ✅ إضافة
);
```

**في `updateRoomNumbers()`:**
```dart
BookingPriceAdjustmentsCompanion(
  roomNumber: Value(newRoomNumber),
  updatedAt: Value(now),
  lastModified: Value(now),
  version: Value(adj.version + 1),  // ✅ إضافة
),
```

---

## 9. إصلاح مزامنة booking_price_adjustments

**الملف:** `mobile/lib/services/appwrite_sync_manager.dart`
**الدالة:** `_syncBookingPriceAdjustments()`

**قبل (المرحلة الأولى):**
```dart
if (!await _ensureParentBookingExists(data, doc.$id)) {
  processed++;     // ← يحتسب السجل كـ "معالج" رغم أنه لم يُدرج!
  continue;        // ← يتخطاه للأبد
}
```

**بعد (المرحلة الأولى):**
```dart
if (!await _ensureParentBookingExists(data, doc.$id)) {
  deferred.add(doc);  // ← يؤجل السجل للمرحلة الثانية
  continue;
}
```

**بعد (المرحلة الثانية):**
```dart
if (!await _ensureParentBookingExists(data, doc.$id)) {
  _logger.warning(
    '⚠️ تعديل سعر $docId: الحجز الأب غير موجود بعد محاولتين — تم التجاهل',
    tag: 'SYNC',
  );
  continue;
}
```

**السبب:** السجلات التي لا تجد الحجز الأب كانت تُتخطى للأبد (processed++ + continue). الآن تُؤجل وتُعاد محاولتها بعد اكتمال سحب كل الحجوزات.

---

## الموجودة مسبقاً (تم التأكيد لا تحتاج تعديل)

| المكون | الملف | الوصف |
|--------|-------|-------|
| Outbox Pattern | `local_db.dart` + `outbox_dao.dart` | جدول كامل بـ 14 عمود و 6 فهارس، دوال merge/takeBatch/markFailed |
| Type Adapters | `appwrite_sync_utils.dart` | `_intAmountFields` لـ 5 جداول مع `.round()` |
| Conflict Resolution | `sync_conflict_resolver.dart` | `detectAndResolve()` - مقارنة lastModified و version (LWW) |
| Soft Delete | جميع DAOs | `SyncFields.deletedAt` في كل جدول |

## روابط
- **الفرع:** `https://github.com/NassarAlshabi1/marina-hotel-wit-app/tree/yy`
- **الالتزام:** `b678214`

---

## 10. Adaptive Batch Size (حجم الدفعة التكيفي)

**الملف:** `mobile/lib/services/appwrite_sync_manager.dart`
**المتغير:** `_adaptiveBatchSize`
**الدوال:** `_adjustBatchSize()`، `_pushAllEntities()`

```dart
if (كل السجلات نجحت) {
  _adaptiveBatchSize = (_adaptiveBatchSize * 1.3).clamp(10, 200);
} else if (فشل أو لم تكتمل) {
  _adaptiveBatchSize = (_adaptiveBatchSize * 0.6).clamp(5, 100);
}
```

**القيم الأولية:** 50 (جوال)، 100 (WiFi) من `SyncPerformanceOptimizer`
**الحد الأقصى:** 200 | **الحد الأدنى:** 5

---

## 11. Timeout لكل عملية رفع

**الملف:** `mobile/lib/services/appwrite_sync_manager.dart`
**الدالة:** `_pushAllEntities()`

```dart
final success = await _processOutboxEntry(entry)
    .timeout(Duration(seconds: timeoutSeconds));
```

**القيمة:** 30 ثانية (قابلة للتعديل من `SyncPerformanceOptimizer`)
**عند timeout:** لا تتعطل الدفعة — يُحتسب فشلاً ويُعاد المحاولة لاحقاً

---

## 12. إيقاف المزامنة بعد 3 دفعات فاشلة

**الملف:** `mobile/lib/services/appwrite_sync_manager.dart`
**الدالة:** `_pushAllEntities()`

```dart
int consecutiveFailures = 0;

if (batchSuccess) consecutiveFailures = 0;
else consecutiveFailures++;

if (consecutiveFailures >= 3) {
  // إيقاف المزامنة — المشكلة في الشبكة أو السيرفر
  break;
}
```

---

## 13. Vector Clock في حل التعارضات

**الملف:** `mobile/lib/services/sync_conflict_resolver.dart`
**الدالة:** `detectAndResolve()`

**قبل:**
```
تعارض → مباشرة إلى الـ strategy (serverWins/localWins/manualReview)
```

**بعد:**
```
تعارض → فحص Vector Clock:
  - remote أحدث في كل الأجهزة → remote wins
  - local أحدث في كل الأجهزة → local wins
  - متعارض → العودة لمقارنة lastModified + strategy
```

**الدالة المساعدة `_parseVectorClock()`:**
```dart
Map<String, int> _parseVectorClock(String raw) {
  // تحويل '{"device1":3,"device2":5}' → {'device1': 3, 'device2': 5}
}
```

---

## 14. تنظيف Outbox تلقائي كل 24 ساعة

**الملف:** `mobile/lib/services/appwrite_sync_manager.dart`
**الدالة:** `_startFailedRetryTimer()` (أُضيف في نهايتها)

```dart
_cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) async {
  await outboxDao.cleanupCompleted();      // أقدم من 7 أيام
  await outboxDao.cleanupOrphanedEntries(); // يتيمة + قديمة
});
```

**في `dispose()`:**
```dart
_cleanupTimer?.cancel();
```

---

## 15. شاشة حل التعارضات اليدوي

**الملف الجديد:** `mobile/lib/screens/settings/sync_conflicts_screen.dart` (221 سطر)

**الميزات:**
- عرض جميع التعارضات المعلقة من جدول `sync_conflicts`
- زرين لكل تعارض: `الاحتفاظ بالمحلي` / `استخدام البعيد`
- عرض تفاصيل البيانات المحلية والبعيدة
- تحديث (Refresh) بسحب الشاشة للأسفل
- حالة عدم وجود تعارضات (Empty State)

**طريقة الاستخدام:**
```dart
import '../../screens/settings/sync_conflicts_screen.dart';

// التنقل إلى الشاشة
Navigator.push(context, MaterialPageRoute(
  builder: (_) => const SyncConflictsScreen(),
));
```

---

## الالتزامات في GitHub

| الالتزام | الوصف | الملفات |
|----------|-------|---------|
| `b678214` | إصلاحات المزامنة الشاملة | 14 ملف |
| `3cd570c` | `memory.md` مع كود الإصلاحات | 1 ملف |
| `330aaca` | Adaptive Batch, Timeout, Vector Clock, شاشة التعارضات | 3 ملفات |

## إجمالي التعديلات
**17 ملفاً، +442 إضافة، -34 حذف**
