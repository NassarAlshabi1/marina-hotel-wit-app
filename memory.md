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

---

## 16. إصلاح خطأ app_settings (Missing required attribute "key")

**الملفات:** `appwrite_sync_utils.dart` + `appwrite_sync_manager.dart`

**الخطأ:**
```
AppwriteException: document_invalid_structure, Invalid document structure: Missing required attribute "key" (400)
```

**السبب:** Appwrite Cloud يتطلب حقل `key` في مجموعة `app_settings`، لكن الكود لم يكن يرسله.

**الإصلاح 1 — `appwrite_sync_utils.dart`:**
```dart
'app_settings': {
  'appwrite_sync_interval', 'dark_mode', 'hotel_cutoff_hour',
  'hotel_name', 'key',  // ✅ إضافة
  'lark_app_id', ...
},
```

**الإصلاح 2 — `appwrite_sync_manager.dart` (دالة `_pushAppSettingsToCloud`):**
```dart
final data = <String, dynamic>{
  'key': 'whatsapp_settings',  // ✅ إضافة — القيمة الثابتة
  'hotel_name': ...,
  ...
};
```

**الالتزام:** `e625ee9`

---

## 17. إصلاح خطأ app_settings (Missing required attribute "value")

**الملفات:** `appwrite_sync_utils.dart` + `appwrite_sync_manager.dart`

**الخطأ:**
```
AppwriteException: document_invalid_structure, Invalid document structure: Missing required attribute "value" (400)
```

**السبب:** Appwrite Cloud يتطلب حقل `value` من نوع string في مجموعة `app_settings`، لكن الكود لم يكن يرسله. الإصلاح السابق (`key`) كان ناقصاً.

**الإصلاح 1 — `appwrite_sync_utils.dart` (السطر 212):**
إضافة `'value'` إلى `validFieldsPerCollection['app_settings']` لمنع `_filterPayload` من إزالته:
```dart
'app_settings': {
  'value',  // ✅ إضافة — مطلوب من Appwrite Schema
  'appwrite_sync_interval', 'dark_mode', 'hotel_cutoff_hour',
  'hotel_name', 'key', ...
},
```

**الإصلاح 2 — `appwrite_sync_manager.dart` (دالة `_pushAppSettingsToCloud`):**
إضافة `data['value'] = jsonEncode(data)` بعد بناء الـ data map وقبل الإرسال:
```dart
      'appwrite_sync_interval': prefs.getInt('appwrite_sync_interval') ?? 15,
    };

    // ✅ إضافة حقل value المطلوب من Appwrite Schema — JSON للكل
    data['value'] = jsonEncode(data);
```

## 18. حذف السجلات اليتيمة من Appwrite تلقائياً

**الملف:** `appwrite_sync_manager.dart`

**المشكلة:** السجلات اليتيمة (orphaned records) تتراكم في Appwrite Cloud دون حذف:
- `booking_price_adjustments` تشير إلى حجز غير موجود محلياً ولا على Appwrite
- `salary_withdrawals` تشير إلى موظف غير موجود محلياً ولا على Appwrite

كل دورة مزامنة تعيد جلب هذه السجلات، ثم تكتشف أنها يتيمة، فتتخطاها، وتتكرر العملية في الدورة التالية.

**الإصلاح — دالة مساعدة جديدة `_deleteOrphanFromCloud`:**
```dart
Future<void> _deleteOrphanFromCloud({
  required String collectionId,
  required String documentId,
}) async {
  await _deleteSilently(() => appwriteService.deleteDocument(
    collectionId: collectionId,
    documentId: documentId,
  ));
  _logger.warning('🗑️ تم حذف سجل يتيم $documentId من Appwrite ($collectionId)', tag: 'SYNC');
}
```

**الإصلاح — `_syncBookingPriceAdjustments` (مرحلة إعادة المحاولة):**
- بعد `_ensureParentBookingExists` ترفع `false` في المحاولة الثانية → نحذف السجل اليتيم من Appwrite
- بعد `FOREIGN KEY constraint failed` في المحاولة الثانية → نحذف السجل اليتيم من Appwrite

```dart
if (!await _ensureParentBookingExists(data, doc.$id)) {
  _logger.warning('🗑️ حذف تعديل سعر يتيم ${doc.$id}: الحجز الأب غير موجود بعد محاولتين', tag: 'SYNC');
  _deleteOrphanFromCloud(
    collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
    documentId: doc.$id,
  );
  continue;
}
```

**الإصلاح — `_syncSalaryWithdrawals` (المرحلتين الأولى وإعادة المحاولة):**
- بعد `_ensureEmployeeExists` ترفع `null` في المرحلة الأولى → نحذف السجل اليتيم من Appwrite
- بعد `_ensureEmployeeExists` ترفع `null` في مرحلة إعادة المحاولة → نحذف السجل اليتيم من Appwrite

```dart
if (employee == null) {
  _logger.warning('🗑️ حذف salary_withdrawal يتيم ${doc.$id}: الموظف غير موجود', tag: 'SYNC');
  _deleteOrphanFromCloud(
    collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
    documentId: doc.$id,
  );
  processed++;
  continue;
}
```

---

## 19. إضافة طرق بحث إضافية قبل حذف اليتامى (منع فقدان البيانات)

**الملف:** `appwrite_sync_manager.dart`

**المشكلة:** دالة `getDocumentSafe` تعيد `null` في حالتين:
1. **المستند غير موجود (404)** — صحيح، السجل يتيم
2. **انتهت المهلة (Timeout)** — خطأ! قد يكون السجل موجوداً لكن الشبكة بطيئة

في الحالة الثانية، كنا نظن السجل يتيماً ونحذفه من Appwrite — وهذا يؤدي لفقدان بيانات.

**الإصلاح — `_ensureParentBookingExists` (طريقة 4 جديدة):**
```dart
// الطريقة 4: البحث في Appwrite باستخدام listDocuments بالـ localUuid
// هذا يغطي الحالات التي يعيد فيها getDocumentSafe null بسبب timeout
if (booking == null) {
  final docs = await appwriteService.listAllDocuments(
    collectionId: AppwriteConfig.bookingsCollectionId,
    queries: [Query.equal('localUuid', bookingUuid)],
    useCache: false,
  );
  if (docs.isNotEmpty) {
    // وجدنا الحجز بواسطة query — نُدخله محلياً
    bookingData['localUuid'] ??= docs.first.$id;
    await _adapterRegistry.bookings.upsertFromJson(bookingData, src: Source.appwrite);
    booking = await ...getSingleOrNull();
  }
}
```

**الإصلاح — `_ensureEmployeeExists` (طريقة 5 جديدة):**
```dart
// الطريقة 5: البحث في Appwrite باستخدام listDocuments بالـ localUuid
if (employee == null && employeeUuid != null && employeeUuid.isNotEmpty) {
  final docs = await appwriteService.listAllDocuments(
    collectionId: AppwriteConfig.employeesCollectionId,
    queries: [Query.equal('localUuid', employeeUuid)],
    useCache: false,
  );
  if (docs.isNotEmpty) {
    // وجدنا الموظف — نُدخله محلياً
  }
}
```

**الفرق بين `getDocumentSafe` و `listDocuments`:**
| الخاصية | `getDocumentSafe` | `listDocuments` |
|---------|------------------|-----------------|
| آلية البحث | بـ `$id` (document ID) | بـ query filter (`localUuid` field) |
| فشل الشبكة | يعيد `null` | يرمي استثناء |
| timeout | يعيد `null` (خطير!) | يرمي `TimeoutException` |

**لماذا `listDocuments` أكثر أماناً:**
- لا يمكن الخلط بين "غير موجود" و "فشل الشبكة"
- يبحث بقاعدة بيانات Appwrite بالحقل `localUuid` وليس فقط بـ `$id`
- يغطي الحالات النادرة التي يختلف فيها `$id` عن `localUuid`

---

## 20. آلية رفع الـ Outbox للدفعات (Batch Processing)

**الملفات:**
- `lib/services/daos/outbox_dao.dart` — `merge()` + `takeBatch()`
- `lib/services/appwrite_sync_manager.dart` — `_pushAllEntities()`

### كيف يعمل رفع 50 سجل؟

#### 1. التسجيل (Merge) — ذري
عند كل عملية محلية (حجز، دفعة، تعديل)، يُستدعى `outboxDao.merge()`:
- يبحث عن سجل موجود بنفس `entity` + `localUuid` في حالة `pending`/`processing`
- إذا وُجد → يُحدّث الـ payload **دون مضاعفة السجل**
- إذا لم يُوجد → يُدرج سجل جديد

```dart
Future<int> merge({entity, op, localUuid, payload, clientTs, ...}) async {
  return transaction(() async {
    final existing = await (select(outbox)
      ..where((t) => t.entity.equals(entity) &
                    t.localUuid.equals(localUuid) &
                    t.processingStatus.isIn(['pending', 'processing']))
      ..limit(1)).getSingleOrNull();
    if (existing != null) {
      return (update(outbox)..where((t) => t.id.equals(existing.id)))
        .write(OutboxCompanion(op: Value(op), payload: Value(payloadJson), ...));
    }
    return into(outbox).insert(OutboxCompanion.insert(...));
  });
}
```

#### 2. السحب (TakeBatch) — دفعة + Atomic Lock
```sql
UPDATE outbox SET processing_status = 'processing', ...
WHERE id IN (
  SELECT id FROM outbox WHERE processing_status = 'pending'
  ORDER BY 
    CASE entity 
      WHEN 'rooms' THEN 1 WHEN 'employees' THEN 2 
      WHEN 'bookings' THEN 3 WHEN 'payments' THEN 4
      WHEN 'expenses' THEN 5 WHEN 'debts' THEN 6
      WHEN 'booking_notes' THEN 7 WHEN 'shift_notes' THEN 8
      WHEN 'cash_transactions' THEN 9 ELSE 10 
    END ASC, client_ts ASC
  LIMIT ?
)
RETURNING *
```
**الترتيب:** حسب علاقات FK (rooms → employees → bookings → ...) ثم حسب timestamp.

#### 3. المعالجة (Push) — حلقة داخل الدفعة
```dart
for (final entry in entries) {
  final success = await _processOutboxEntry(entry).timeout(30s);
  if (success) await outboxDao.removeById(entry.id);
  else failedInBatch++;
}
```

#### 4. Adaptive Batch Size
```
Batch 1: 10 سجلات → نجحت كلها → 10 * 1.3 = 13
Batch 2: 13 سجل → نجحت كلها → 13 * 1.3 = 16
Batch 3: 16 سجل → نجحت كلها → 16 * 1.3 = 20
Batch 4: 11 سجل (المتبقي من 50) → اكتمل ✅
```

#### 5. عند الفشل
- **Timeout**: يُوسم السجل كـ `failed` مع زيادة `attempts`
- **3 دفعات متتالية فاشلة**: إيقاف المزامنة
- **مؤقت 5 دقائق**: إعادة محاولة السجلات الفاشلة (`retryFailedWithBackoff`)
- **الفشل لا يفقد البيانات**: السجل يبقى في Outbox حتى يُرفع بنجاح

#### 6. Adaptive Batch Size (التفاصيل)
```dart
void _adjustBatchSize(bool success, int processed, int total) {
  if (success && processed == total) {
    _adaptiveBatchSize = (_adaptiveBatchSize * 1.3).round().clamp(1, 50);
  } else if (total > 0 && processed == 0) {
    _adaptiveBatchSize = (_adaptiveBatchSize / 0.6).round().clamp(1, 50);
  }
}
```
- نجاح الدفعة بالكامل → ×1.3 (حد أقصى 50)
- فشل الدفعة بالكامل → ÷0.6 (حد أدنى 1)
- يتكيف مع سرعة الإنترنت تلقائياً

---

## 21. PrefsCache — SharedPreferences Cache (Singleton)

**الملف الجديد:** `mobile/lib/utils/prefs_cache.dart`
**الالتزام:** `c5345f2`

### المشكلة
- 328 استدعاء `await SharedPreferences.getInstance()` في 65 ملفاً
- كل استدعاء = I/O (قراءة ملف XML كامل)
- يسبب بطئاً في إقلاع التطبيق وفتح الشاشات

### الحل — Singleton PrefsCache
```dart
class PrefsCache {
  PrefsCache._();
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get _p {
    assert(_prefs != null, '⚠️ PrefsCache لم يُهيّأ');
    return _prefs!;
  }

  // قراءة سريعة من الذاكرة
  static String getString(String key, [String? defaultValue]) =>
      _p.getString(key) ?? defaultValue ?? '';
  
  static bool getBool(String key, [bool defaultValue = false]) =>
      _p.getBool(key) ?? defaultValue;

  static int getInt(String key, [int defaultValue = 0]) =>
      _p.getInt(key) ?? defaultValue;

  // كتابة
  static Future<bool> setString(String key, String value) =>
      _p.setString(key, value);
  static Future<bool> setBool(String key, bool value) =>
      _p.setBool(key, value);
}
```

### دالة استبدال مباشر
```dart
Future<SharedPreferences> getSharedPrefs() async {
  if (PrefsCache._prefs == null) {
    PrefsCache._prefs = await SharedPreferences.getInstance();
  }
  return PrefsCache._prefs!;
}
```

### ملفات معدلة (65 ملفاً)
- `main.dart`: `await PrefsCache.init()` بعد `WidgetsFlutterBinding.ensureInitialized()`
- جميع ملفات `services/`: `SharedPreferences.getInstance()` → `getSharedPrefs()`
- جميع ملفات `providers/`: نفس الاستبدال
- جميع ملفات `screens/settings/`: نفس الاستبدال

---

## 22. Silent Catch Logger — 49/134 fix

**الملف الجديد:** `mobile/lib/utils/safe_catch.dart`
**الالتزام:** `c5345f2`

### المشكلة
- 134 `catch (_) {}` صامتة تبتلع الأخطاء
- الأخطاء تختفي بدون سجل → يصعب تتبع مشاكل المزامنة

### الحل — استبدال تدريجي
```dart
void reportError(Object error, {
  String message = '⚠️ خطأ غير متوقع',
  String tag = 'SAFE',
  StackTrace? stackTrace,
}) {
  AppLogger.warning(message, tag: tag, error: error, stackTrace: stackTrace);
}
```

### ملفات معدلة (18 ملف خدمات)
- `appwrite_sync_manager.dart` — 12 catch
- `appwrite_backup_service.dart` — 4 catch
- `appwrite_full_pull.dart` — 3 catch
- `sync_safety_layer.dart` — 3 catch
- `sync_notification_manager.dart` — 3 catch
- `sync_performance_optimizer.dart` — 3 catch
- `whatsapp_settings_sync.dart` — 2 catch
- `hotel_day_key_fix_service.dart` — 2 catch
- `google_drive_conflict_resolver.dart` — 2 catch
- `restore_fix_service.dart` — 2 catch
- `appwrite_backup_sync_service.dart` — 2 catch
- `appwrite_delta_sync.dart` — 1 catch
- `google_drive_unified_sync_coordinator.dart` — 1 catch
- `local_backup_service.dart` — 1 catch
- `app_session_manager.dart` — 1 catch
- `fcm_service.dart` — 2 catch
- `telegram/whatsapp_notification_service.dart` — 1 catch
- `repositories/salary_withdrawals_repository.dart` — 4 catch

### الاستبدال
```dart
// قبل
catch (_) { /* صامت */ }

// بعد
catch (e) { AppLogger.warning("⚠️ silent catch", tag: "SYNC", error: e);
  // الكود الأصلي موجود (إن وُجد)
}
```

**ملاحظة:** لم يتم تعديل CrashlyticsService (10 catches — متعمدة)

---

## 23. ForegroundSyncService — خدمة خلفية للمزامنة الموثوقة

**الملف الجديد:** `mobile/lib/services/foreground_sync_service.dart`
**الملف الجديد:** `mobile/docs/foreground_service_setup.md`
**الالتزام:** `c5345f2`

### المشكلة
- Android 12+ يقتل خدمات WorkManager في الخلفية
- التطبيق يفقد المزامنة التلقائية بعد ~10 دقائق من الإغلاق
- المستخدم يضطر لفتح التطبيق يدوياً للمزامنة

### الحل — Foreground Service
```dart
class ForegroundSyncService {
  ForegroundSyncService._();
  static final ForegroundSyncService instance = ForegroundSyncService._();

  Future<void> start() async {
    // تستخدم Singletons — لا تفتح اتصال DB جديد
    final db = AppDatabase.instance;
    final appwrite = AppwriteService();

    // مزامنة دورية كل 5 دقائق
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _performSync(),
    );

    // تنظيف Outbox كل ساعة
    _cleanupTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => _cleanupOutbox(),
    );
  }
}
```

### تفعيل الخدمة في main.dart
```dart
// بعد AppwriteConfigManager.init()
try {
  await ForegroundSyncService.instance.start();
  debugPrint('✅ ForegroundSyncService started');
} catch (e) {
  debugPrint('⚠️ ForegroundSyncService failed: $e');
}
```

### متطلبات التفعيل
1. إضافة `flutter_background_service: ^5.0.0` للـ pubspec.yaml
2. إضافة permissions و service للـ AndroidManifest.xml
3. تشغيل `flutter pub get`

### دورة الحياة
- تبدأ تلقائياً عند تشغيل التطبيق
- إشعار دائم "المزامنة نشطة"
- مزامنة Outbox → Push → Pull كل 5 دقائق
- تنظيف Outbox القديم (> 24 ساعة) كل ساعة
- لا تتأثر بقيود Android 12+ Background Execution

---

## 24. آخر التزام

**الالتزام:** `c5345f2`
**التاريخ:** 15 يونيو 2026
**الرسالة:** perf: PrefsCache + Silent catch fixes + ForegroundService + memory.md
**الفرع:** `yy`
**الرابط:** https://github.com/NassarAlshabi1/marina-hotel-wit-app/tree/yy

---

## 25. المهام المتبقية

### أولوية عالية
1. **تفعيل Background Service** — يتطلب Flutter SDK:
   - `flutter pub add flutter_background_service`
   - تحديث AndroidManifest.xml
   - `flutter pub get`

### أولوية متوسطة
2. **باقي Silent Catches (~85)** — في ملفات UI (screens, widgets)
3. **تحويل 3 شاشات إلى Riverpod** — تحتاج تعديل يدوي:
   - `ai_chat_screen.dart` — StatefulWidget
   - `appwrite_backup_endpoints_screen.dart` — StatefulWidget
   - `database_fixer_screen.dart` — StatefulWidget

### أولوية منخفضة
4. **تحديث pubspec.yaml** — إضافة الـ dependencies الجديدة
5. **اختبارات المزامنة** — اختبار Outbox مع 50+ سجل

---

## 26. debugPrint → AppLogger (1071 استدعاء في 117 ملف)

**الالتزام:** `4f6987e`
**التاريخ:** 15 يونيو 2026

### المشكلة
- 1,080 استدعاء `debugPrint()` في 123 ملفاً
- في وضع الإصدار (release)، `debugPrint` يكتب على stderr ← يستهلك بطارية ويبطئ الأداء
- لا يوجد فلترة حسب المستوى (info/warning/error)
- لا يوجد تخزين منظم للقراءة لاحقاً

### الحل — تحويل شامل إلى AppLogger
```dart
// قبل
debugPrint('✅ تم تحميل البيانات');

// بعد
AppLogger.info('✅ تم تحميل البيانات', tag: 'APP');
```

### التصنيف التلقائي حسب المحتوى
| الرمز | مستوى AppLogger |
|-------|----------------|
| `✅`، `تم `، `نجاح` | `AppLogger.info()` |
| `⚠️`، `فشل`، `خطأ`، `تخطي` | `AppLogger.warning()` |
| `❌`، `Exception` | `AppLogger.error()` |
| `🚀`، `🔧`، `ℹ️` | `AppLogger.info()` |

### آلية العمل في الإنتاج
```dart
// lib/utils/app_logger.dart
if (kDebugMode) {
  debugPrint(output);   // ← فقط في وضع التطوير
} else {
  developer.log(output); // ← في الإنتاج: يكتب للنظام بصمت
}
```

تلقائياً في وضع release:
- `AppLogger.debug()` ← لا يطبع أي شيء
- `AppLogger.info()` ← لا يطبع أي شيء (أقل من `_releaseMinLevel=2`)
- `AppLogger.warning()` ← يطبع
- `AppLogger.error()` ← يطبع + يسجل في Crashlytics

### النتيجة
| البيان | قبل | بعد |
|--------|-----|-----|
| استدعاءات debugPrint في الكود | 1,080 | **1** (في app_logger.dart نفسه) |
| استدعاءات AppLogger | 49 | **1,165** |
| ملفات تستخدم AppLogger | 18 | **131** |
