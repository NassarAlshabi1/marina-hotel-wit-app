# مراجعة شاملة لكود نظام المزامنة — Appwrite Sync

**تاريخ المراجعة:** 2026-06-28  
**النطاق:** جميع ملفات المزامنة في `mobile/lib/services/sync_core/` + الملفات المرتبطة

---

## 📊 ملخص تنفيذي

| المقياس | القيمة |
|---------|--------|
| إجمالي ملفات المزامنة | +80 ملف |
| ملفات sync_core | 14 ملف |
| الكيانات المتزامنة | 17 كيان |
| حجم appwrite_sync_manager.dart | ~6300 سطر |
| حجم sync_pull_service.dart | ~2524 سطر |
| حجم sync_push_service.dart | ~1495 سطر |

---

## 🏗️ البنية المعمارية (Architecture)

### الطبقات

```
┌─────────────────────────────────────────────┐
│         AppwriteSyncManager (6300 سطر)      │  ← المنسق الرئيسي
├─────────────────────────────────────────────┤
│  SyncPullService  │  SyncPushService        │  ← خدمات السحب والدفع
├─────────────────────────────────────────────┤
│  ConflictDetector │ SmartConflictResolver   │  ← كشف وحل التعارضات
├─────────────────────────────────────────────┤
│  VectorClock      │ OptimisticLockHelper    │  ← السببية والقفل التفاؤلي
├─────────────────────────────────────────────┤
│  CircuitBreaker   │ RetryStrategy           │  ← المرونة والהתאוששות
├─────────────────────────────────────────────┤
│  OutboxDao        │ AncestorCacheDao        │  ← التخزين المؤقت
├─────────────────────────────────────────────┤
│  AdapterRegistry  │ AppwriteService         │  ← المحولات والتواصل
└─────────────────────────────────────────────┘
```

### أنماط التصميم المستخدمة

| النمط | التطبيق | التقييم |
|-------|---------|---------|
| **Outbox Pattern** | `OutboxDao` — تغييرات محلية تُكتب أولاً ثم تُدفع للسحابة | ✅ ممتاز |
| **Delta Sync** | `AppwriteDeltaSync` — سحب التغييرات فقط عبر `lastPullTs` | ✅ جيد |
| **Vector Clocks** | `VectorClockService` — تحديد السببية بدلاً من LWW | ✅ ممتاز |
| **3-Way Merge** | `SmartConflictResolver` + `AncestorCacheDao` | ✅ ممتاز |
| **Circuit Breaker** | `CircuitBreaker` — حماية من انهيار الخدمة | ✅ جيد |
| **Optimistic Locking** | `OptimisticLockDaoMixin` — منع الكتابة المتزامنة | ✅ جيد |
| **Adapter Pattern** | `AdapterRegistry` — محولات لكل كيان | ✅ ممتاز |

---

## ✅ نقاط القوة

### 1. نظام كشف التعارضات المتطور (`conflict_detector.dart`)
- **7 أنواع تعارض** مُعرّفة بدلاً من الثنائي البسيط
- استخدام `VectorClock` لتحديد السببية بدلاً من الاعتماد على timestamps
- كشف على مستوى الحقل (field-level) وليس السجل فقط
- فصل الحقول المالية الحرجة (`amount`, `price`, `isVoided`) التي لا تُدمج تلقائياً

### 2. حل التعارضات الذكي (`smart_conflict_resolver.dart`)
- **17 سياسة كيان** مُعرّفة (كل كيان له قواعد خاصة)
- **7 استراتيجيات حل**: `newerWins`, `localWins`, `remoteWins`, `maxValue`, `minValue`, `sum`, `concat`, `manual`
- دمج نصي مع **deduplication** (`_concatWithDedup`) لمنع تضخم الملاحظات
- استخدام `max(localTs, remoteTs)` بدلاً من `DateTime.now()` في الدمج (إصلاح idempotency)
- تصعيد يدوي للحقول المالية الحرجة

### 3. حماية البيانات المالية
- الحقول المالية (`amount`, `paidAmount`, `totalAmount`) تُصعد دائماً للمراجعة اليدوية
- `Financial immutability` في Pull: إذا كان السجل المحلي أحدث، لا يُكتب فوقه
- منع إحياء السجلات المحذوفة softly من السحابة

### 4. التعامل مع Foreign Keys
- **حل FK بثلاث مستويات**: UUID → id → serverId
- تأجيل السجلات ذات FK المفقودة (`deferred` list) وإعادة المحاولة لاحقاً
- رفع الكيانات الأب قبل الأبناء (employees قبل salary_withdrawals)
- فحص سلامة البيانات بعد المزامنة (`_performPostSyncIntegrityCheck`)

### 5. نظام Vector Clock
- تنظيف `vectorClock` من حساب الحقول المتغيرة (منع التعارضات الوهمية)
- **bump VC قبل كل push** (`_bumpVectorClockBeforePush`) — إصلاح P0-1
- دمج VC بعد كل عملية merge

### 6. المرونة والاستشفاء
- `CircuitBreaker` مع 3 حالات (closed/open/halfOpen)
- `RetryStrategy` مع 3 أنماط (linear/exponential/fibonacci) + jitter
- Adaptive batch size في Push (يزيد/ينقص بناءً على نسبة النجاح)
- تنظيف stuck entries في Outbox عند التهيئة

---

## ⚠️ مشاكل وتحذيرات

### P0 — حرج

#### 1. `appwrite_sync_manager.dart` ضخم جداً (~6300 سطر)
```
المشكلة: ملف واحد يحتوي على معظم منطق المزامنة
التأثير: صعوبة الصيانة والاختبار والتعاون
الحل: تقسيم إلى:
  - sync_orchestrator.dart (التنسيق)
  - sync_device_manager.dart (إدارة الأجهزة)
  - sync_entity_handlers.dart (معالجات الكيانات)
```

#### 2. تكرار كود `_asInt` / `_asIntNullable` / `_asIntSafe`
```
المشكلة: نفس الدوال مكررة في 4+ ملفات
الملفات: sync_pull_service.dart, sync_push_service.dart, appwrite_sync_manager.dart, appwrite_delta_sync.dart
الحل: نقل إلى ملف مشترك مثل sync_helpers.dart
```

#### 3. تكرار lookup functions (`_getXxxByLocalUuid`)
```
المشكلة: كل ملف يُعرّف نسخته الخاصة
الحل: إنشاء SyncLookupService موحد أو استخدام AdapterRegistry
```

### P1 — مهم

#### 4. `_syncBlacklist` يكتب في `shiftNotes` table
```
المشكلة: blacklist يُخزّن في جدول shift_notes مع createdBy='blacklist'
التأثير: ازدواجية في البيانات، صعوبة الاستعلام
الحل: إنشاء جدول blacklist منفصل أو توضيح السبب بالتعليقات
```

#### 5. `appwrite_delta_sync.dart` يحتوي على `insertOnConflictUpdate` مباشرة
```
المشكلة: Pull في DeltaSync لا يستخدم AdapterRegistry (يكتب Companion مباشرة)
بينما Pull في SyncPullService يستخدم AdapterRegistry
التأثير: تكرار منطق التحويل وصعوبة الحفاظ على اتساق
```

#### 6. `sync_push_service.dart` لا يتحقق من نجاح الرفع
```
المشكلة: بعد upsertRoom/upsertBooking لا يتم التحقق من حفظ البيانات
(ملاحظة: تم إضافة _verifyPushedBooking للحجوزات فقط)
الحل: إضافة تحقق مشابه للكيانات المالية الحرجة
```

### P2 — تحسين

#### 7. `_cleanupOutboxAfterPull` يفحص كل كيان بشكل منفصل
```
المشكلة: N استعلامات DB لكل كيان (17 كيان × M عناصر)
التحسين: دمج الاستعلامات أو استخدام batch query
```

#### 8. `ConflictDetector._findChangedFields` لا يتعامل مع القيم المعقدة
```
المشكلة: المقارنة تستخدم `!=` مباشرة — لا تدعم Map/List嵌套
التحسين: استخدام deep equality للمقارنة
```

#### 9. `SmartConflictResolver._applyRule` لـ `newerWins` يقارن timestamps فقط
```
المشكلة: لا يستخدم VectorClock لتحديد "الأحدث"
يستخدم lastModified (الذي قد يكون متأثراً بـ clock skew)
التحسين: دمج VectorClock في القرار
```

#### 10. `_pushAppSettingsToCloud` يرسل كلمات مرور كنص صريح
```
المشكلة: wa_api_token, telegram_bot_token, lark_app_secret تُرسل كما هي
التحسين: تشفير القيم الحساسة قبل الإرسال
```

---

## 📋 تقييم كل ملف

| الملف | الأسطر | التقييم | ملاحظات |
|-------|--------|---------|---------|
| `sync_pull_service.dart` | 2524 | ⭐⭐⭐⭐ | قوي، لكن يحتاج تقسيم |
| `sync_push_service.dart` | 1495 | ⭐⭐⭐⭐ | جيد، VC bump ممتاز |
| `conflict_detector.dart` | 260 | ⭐⭐⭐⭐⭐ | ممتاز ومُنظّم |
| `smart_conflict_resolver.dart` | 611 | ⭐⭐⭐⭐⭐ | تصميم احترافي |
| `vector_clock_service.dart` | 217 | ⭐⭐⭐⭐⭐ | نظيف ومكتمل |
| `circuit_breaker.dart` | 203 | ⭐⭐⭐⭐ | جيد |
| `retry_strategy.dart` | 159 | ⭐⭐⭐⭐ | جيد، fibonacci مبتكر |
| `sync_metrics.dart` | 268 | ⭐⭐⭐⭐ | مفيد للمراقبة |
| `sync_validator.dart` | 148 | ⭐⭐⭐ | بسيط، يحتاج توسيع |
| `sync_error_handler.dart` | 231 | ⭐⭐⭐⭐ | تصنيف أخطاء جيد |
| `sync_error_service.dart` | 110 | ⭐⭐⭐⭐ | توحيد ممتاز |
| `optimistic_lock_helper.dart` | 70 | ⭐⭐⭐⭐ | نظيف |
| `conflict_resolver.dart` | 204 | ⭐⭐⭐ | بسيط مقارنة بـ SmartConflictResolver |
| `appwrite_delta_sync.dart` | 1200+ | ⭐⭐⭐⭐ | جيد لكن يكرر منطق Pull |
| `appwrite_sync_manager.dart` | 6307 | ⭐⭐⭐ | يشتغل لكن ضخم جداً |

---

## 🔧 توصيات التحسين

### عاجل (قبل الإنتاج)
1. ✅ **تم بالفعل** — Vector Clock bumping قبل Push (P0-1)
2. ✅ **تم بالفعل** — منع إحياء السجلات المحذوفة softly
3. ✅ **تم بالفعل** — فحص سلامة البيانات بعد المزامنة
4. ✅ **تم بالفعل** — حل FK بثلاث مستويات

### مهم (المرحلة 2)
5. تقسيم `appwrite_sync_manager.dart` إلى ملفات أصغر
6. نقل `_asInt` و `_getXxxByLocalUuid` إلى ملف مشترك
7. توحيد Pull logic بين DeltaSync و SyncPullService
8. إضافة تحقق بعد الرفع للكيانات المالية

### تحسينات (المرحلة 3)
9. تحسين `_cleanupOutboxAfterPull` بأداء أفضل
10. دمج VectorClock في قرارات newerWins
11. تشفير البيانات الحساسة في app_settings
12. إضافة اختبارات unit test للكشف والحل

---

## 🎯 الخلاصة

نظام المزامنة **قوي واحترافي** بشكل عام. البنية المعمارية سليمة وتتبع أفضل الممارسات:
- Outbox Pattern للدفع
- Delta Sync للسحب
- Vector Clocks للسببية
- 3-Way Merge للتعارضات
- Circuit Breaker للمرونة

**أبرز الإصلاحات التي تمت مؤخراً** (2026-06-28):
- P0-1: Vector Clock bumping قبل Push
- P0-2: منع إحياء السجلات المحذوفة
- P0-3: فحص _isRemoteDataNewer مع SmartConflictResolver
- P0-4: AncestorCacheDao لتخزين الـ ancestor
- P0-5: إزالة `status` من الحقول الحرجة (للسماح بـ newerWins)

**أكبر تحدٍ**: حجم الملفات — `appwrite_sync_manager.dart` بـ 6300 سطر يحتاج تقسيم عاجل.
