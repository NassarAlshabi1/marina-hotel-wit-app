# مراجعة شاملة لكود نظام المزامنة — Appwrite Sync (v2)

**تاريخ المراجعة:** 2026-06-28  
**النطاق:** جميع ملفات المزامنة — `sync_core/` + `daos/` + `delta_sync` + `appwrite_sync_manager`

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
| عدد المشاكل الحرجة (P0) | 8 |
| عدد المشاكل المهمة (P1) | 5 |
| عدد المشاكل التحسينية (P2) | 7 |

---

## 🏗️ البنية المعمارية

```
┌──────────────────────────────────────────────┐
│       AppwriteSyncManager (6300 سطر)         │ ← المنسق الرئيسي
├──────────────────────────────────────────────┤
│  SyncPullService  │  SyncPushService         │ ← خدمات السحب والدفع
├──────────────────────────────────────────────┤
│  AppwriteDeltaSync │  DeltaSyncService       │ ← مزامنة تفاضلية
├──────────────────────────────────────────────┤
│  ConflictDetector │ SmartConflictResolver    │ ← كشف وحل التعارضات
├──────────────────────────────────────────────┤
│  VectorClock      │ OptimisticLockHelper     │ ← السببية والقفل التفاؤلي
├──────────────────────────────────────────────┤
│  CircuitBreaker   │ RetryStrategy            │ ← المرونة والاستشفاء
├──────────────────────────────────────────────┤
│  OutboxDao        │ AncestorCacheDao         │ ← التخزين المؤقت
├──────────────────────────────────────────────┤
│  SyncLocks        │ SyncConstants            │ ← الأقفال والإعدادات
└──────────────────────────────────────────────┘
```

---

## 🔴 P0 — مشاكل حرجة (يجب إصلاحها فوراً)

### 1. `serverId` يستخدم `hashCode` — انتهاك لسلامة البيانات
```
الملف: appwrite_sync_manager.dart:2958 و sync_push_service.dart:827
المشكلة: serverId: drift.Value(remoteDoc.$id.hashCode)
التأثير: Object.hashCode غير ثابت عبر العمليات — قيم مختلفة لنفس المستند
         على أجهزة مختلفة، مما يسبب فشل حل FK عبر الأجهزة.
الحل: تخزين الـ $id النصي مباشرة (String) بدلاً من hashCode
```

### 2. `_RemoteNewerResult.mergedData` لا يُستهلك أبداً
```
الملف: appwrite_sync_manager.dart:80-96 و sync loop
المشكلة: SmartConflictResolver يُنتج بيانات مدمجة عبر 3-way merge
         لكن الكود لا يطبق mergedData على قاعدة البيانات المحلية.
         يتحقق فقط من shouldApplyRemote ويطبق remoteData الأصلي.
التأثير: نتائج الدمج التلقائي تُفقد — التعارضات تُحل في الذاكرة فقط ولا تُحفظ.
الحل: إذا hasMerge == true، طبق mergedData بدلاً من remoteData.
```

### 3. تكرار كود بنسبة ~80% بين ملفين ضخمين
```
الملف: sync_pull_service.dart (2524 سطر) و appwrite_sync_manager.dart (6307 سطر)
المشكلة: 
  - _syncRooms, _syncBookings, _syncEmployees... موجودة في الملفين
  - _getXxxByLocalUuid و _getLocalXxxLastModified (+30 دالة) مكررة
  - _asInt, _asIntNullable, _asIntSafe مكررة في 4 ملفات
  - _performPostSyncIntegrityCheck مكرر
التأثير: أي إصلاح bug يجب تطبيقه في مكانين — خطأ بشري محتمل
الحل: دمج SyncPullService ككائن موحد يُستخدم من AppwriteSyncManager
```

### 4. `outbox_dao.dart` — واجهة حل التعارضات اليدوية معطلة
```
الملف: outbox_dao.dart:604-615
المشكلة: getConflicts() تعيد remotePayload = localPayload
         مع تعليق // TODO: Fetch actual remote data
التأثير: شاشة حل التعارضات اليدوية تظهر بيانات متطابقة للجهتين
         — لا يمكن للمستخدم اتخاذ قرار صحيح.
```

### 5. `_bumpVectorClockBeforePush` يزيد العداد حتى لو فشل الرفع
```
الملف: sync_push_service.dart:153-161
المشكلة: يتم bump VC قبل الرفع. إذا فشل الرفع، العداد ارتفع محلياً
         لكن السحابة لم تستلم البيانات.
         المحاولة التالية تزيد مرة أخرى → فجوات في الساعة المنطقية.
الحل: زيادة VC بعد نجاح الرفع، أو حفظ قيمة VC الأصلية للتراجع عند الفشل.
```

### 6. `_blacklistToRemote` يبتلع أخطاء JSON بصمت
```
الملف: sync_push_service.dart:473
المشكلة: jsonDecode(item.content) as Map<String, dynamic> + catch (_) {}
         إذا كان item.content يحتوي JSON تالف، ينتج {} فارغ
         ويفقد جميع بيانات القائمة السوداء دون أي تحذير.
الحل: تسجيل الخطأ مع LOG warning وعدم رفع بيانات فارغة.
```

### 7. إرسال كلمات المرور كنص صريح إلى Appwrite
```
الملف: sync_push_service.dart:1182-1241
المشكلة: wa_api_token, telegram_bot_token, lark_app_secret
         تُرسل مباشرة في _pushAppSettingsToCloud بدون تشفير.
         مخزنة في Appwrite Cloud كنص صريح مقروء.
التأثير: خرق أمني — أي شخص لديه وصول لقاعدة Appwrite
         يمكنه قراءة جميع كلمات المرور والرموز.
الحل: تشفير القيم الحساسة قبل الإرسال والتخزين.
```

### 8. `sync_pull_service.dart` — خطأ محتمل في `rowid` vs `id`
```
الملف: sync_pull_service.dart:1966-2024
المشكلة: _performPostSyncIntegrityCheck يستخدم rowid من PRAGMA
         ثم يبحث بـ t.id.equals(rowId as int). إذا كان الجدول
         يستخدم WITHOUT ROWID أو id ليس alias لـ rowid،
         فسيتم حذف السجل الخطأ.
الحل: استخدام اسم العمود الصحيح من PRAGMA output أو البحث بـ localUuid.
```

---

## 🟡 P1 — مشاكل مهمة

### 9. `ConflictDetector._findChangedFields` — مقارنة سطحية
```
الملف: conflict_detector.dart:231-250
المشكلة: ancestor[key] != current[key] لا تدعم Map/List المتداخلة
         مثلاً content = {"a": 1} vs {"a": 1} قد تُعتبر مختلفة
         بسبب اختلاف مراجع الكائنات.
الحل: استخدام DeepCollectionEquality من package:collection للمقارنة.
```

### 10. `sync_push_service.dart` — حلقة لا نهائية محتملة
```
الملف: sync_push_service.dart:92-150
المشكلة: while(true) في _pushAllEntities ليس له حد أعلى صارم.
         إذا استمرت إضافة عناصر outbox أثناء الدفع، قد تستمر للأبد.
الحل: إضافة maxIterations أو maxDuration إجباري.
```

### 11. `appwrite_delta_sync.dart` — تكرار منطق Pull
```
الملف: appwrite_delta_sync.dart
المشكلة: AppwriteDeltaSync يكتب Companions مباشرة (insertOnConflictUpdate)
         بينما SyncPullService يستخدم AdapterRegistry.upsertFromJson.
         منطقان مختلفان لنفس العملية — صعوبة الصيانة.
الحل: توحيد Pull logic لاستخدام AdapterRegistry في كل الحالات.
```

### 12. `_syncBlacklist` — ازدواجية تخزين
```
الملف: sync_pull_service.dart:1069-1184 و sync_push_service.dart:471-503
المشكلة: blacklist يُخزّن في جدول shift_notes مع createdBy='blacklist'
         بدلاً من جدول منفصل. 
التأثير: ازدواجية، استعلامات معقدة، صعوبة فصل المنطق.
الحل: إنشاء جدول blacklist منفصل أو استخدام حقل type بدلاً من createdBy.
```

### 13. `_syncPriceAdjustments` — إنشاء service جديد لكل حلقة
```
الملف: sync_pull_service.dart:1681-1744
المشكلة: BookingDerivedFieldsService(database) يُنشأ جديداً
         لكل حجز نشط داخل الحلقة (~1717).
الحل: إنشاء instance واحد وإعادة استخدامه.
```

---

## 🟢 P2 — تحسينات مقترحة

### 14. `_cleanupOutboxAfterPull` — أداء
```
المشكلة: فحص كل كيان باستعلامات منفصلة (17 كيان × M عناصر)
الحل: دمج الاستعلامات أو استخدام batch operations.
```

### 15. `SmartConflictResolver._applyRule` — newerWins لا يستخدم VectorClock
```
المشكلة: newerWins يقارن lastModified timestamps فقط
         التي قد تتأثر بـ clock skew بين الأجهزة.
الحل: استخدام VectorClock لتحديد "الأحدث" سببياً.
```

### 16. `outbox_dao.dart` — خطأ صامت في secondary delivery
```
الملف: outbox_dao.dart:110-115
المشكلة: merge() يحاول الوصول لـ SharedPreferences في try-catch
         وإذا فشل (مثلاً SharedPreferences not ready)،
         يُعلم deliveredToSecondary = true خطأً.
```

### 17. `sync_enums.dart` و `sync_constants.dart` — أرقام سحرية
```
المشكلة: tableOrder في sync_constants لا يتحقق تلقائياً من اتساقه
         مع مخطط قاعدة البيانات الفعلي.
الحل: إضافة فحص في وقت التهيئة أو إنشاء الترتيب تلقائياً من Drift schema.
```

### 18. `central_sync_coordinator.dart` — نمط Singleton غير مكتمل
```
المشكلة: factory constructor يأخذ معاملات لكن يتجاهلها بعد أول إنشاء.
         المتصل الثاني يحصل على instance الأول بدون تحذير.
```

### 19. `AppwriteSyncManager.sync()` — دالة ضخمة جداً
```
المشكلة: sync() بطول ~680 سطر مع try/catch متداخلة عميقاً.
         صعوبة الاختبار والتصحيح.
الحل: استخراج كل _doSyncXxx إلى كلاس منفصل أو استخدام Chain of Responsibility.
```

### 20. `appwrite_sync_manager.dart:1284` — TimeoutException لا يمكن حدوثه
```
المشكلة: catch على TimeoutException حول SyncLocks.appwriteSyncLock.synchronized()
         لكن synchronized() من package:synchronized لا يرمي TimeoutException.
         كتلة catch هذه لا يمكن الوصول إليها أبداً.
```

---

## ✅ نقاط القوة المعمارية

| # | الميزة | التفاصيل |
|---|--------|----------|
| 1 | **7 أنواع تعارض** | `conflict_detector.dart` — يتجاوز ثنائية "تحديث/تجاهل" البسيطة |
| 2 | **17 سياسة كيان × 8 استراتيجيات حل** | `smart_conflict_resolver.dart` — تخصيص كامل لكل جدول |
| 3 | **Vector Clock حقيقي** | `vector_clock_service.dart` — تحديد سبببية بدلاً من LWW |
| 4 | **3-Way Merge مع AncestorCache** | حل التعارضات المتزامنة تلقائياً عبر مقارنة مع ancestor |
| 5 | **Outbox Pattern مزدوج التسليم** | تتبع delivery إلى primary + secondary Appwrite instances |
| 6 | **Delta Sync مع Mirror Snapshots** | SHA-1 hashing للكشف عن التغييرات بكفاءة |
| 7 | **Adaptive Batch Size** | 1.3x عند النجاح، 0.6x عند الفشل (10-200) |
| 8 | **حل FK ثلاثي المستويات** | UUID → localId → serverId |
| 9 | **تأجيل وإعادة محاولة** | Deferred retry للسجلات ذات FK المفقودة |
| 10 | **فحص سلامة البيانات** | `PRAGMA foreign_key_check` + إصلاح تلقائي للسجلات اليتيمة |
| 11 | **Circuit Breaker** | 3 حالات (closed/open/halfOpen) + إعادة تعيين تلقائية |
| 12 | **RetryStrategy متعدد الأنماط** | linear + exponential + fibonacci مع jitter |
| 13 | **Financial Immutability** | منع الكتابة فوق البيانات المالية المحلية الأحدث |
| 14 | **منع إحياء السجلات المحذوفة** | Soft delete له أولوية على التحديثات البعيدة |
| 15 | **Idempotency Keys** | `entity:op:localUuid:outboxId` مع graceful fallback |

---

## 📋 تقييم كل ملف (محدث)

| الملف | الأسطر | التقييم | أهم مشكلة |
|-------|--------|---------|-----------|
| `conflict_detector.dart` | 260 | ⭐⭐⭐⭐⭐ | مقارنة سطحية للقيم المتداخلة |
| `smart_conflict_resolver.dart` | 611 | ⭐⭐⭐⭐⭐ | newerWins لا يستخدم VC |
| `vector_clock_service.dart` | 217 | ⭐⭐⭐⭐⭐ | — |
| `conflict_resolver.dart` | 204 | ⭐⭐⭐ | بسيط، لا يستخدم VC |
| `circuit_breaker.dart` | 203 | ⭐⭐⭐⭐ | — |
| `retry_strategy.dart` | 159 | ⭐⭐⭐⭐ | — |
| `optimistic_lock_helper.dart` | 70 | ⭐⭐⭐⭐ | — |
| `sync_validator.dart` | 148 | ⭐⭐⭐ | بسيط جداً |
| `sync_error_handler.dart` | 231 | ⭐⭐⭐⭐ | — |
| `sync_error_service.dart` | 110 | ⭐⭐⭐⭐ | — |
| `sync_metrics.dart` | 268 | ⭐⭐⭐⭐ | — |
| `sync_push_service.dart` | 1495 | ⭐⭐⭐ | **serverId=hashCode** + VC bump قبل الرفع |
| `sync_pull_service.dart` | 2524 | ⭐⭐⭐ | **تكرار 80%** مع sync_manager |
| `appwrite_delta_sync.dart` | 1200+ | ⭐⭐⭐ | يكرر Pull logic |
| `delta_sync_service.dart` | 600+ | ⭐⭐⭐⭐ | timestamp normalization edge cases |
| `appwrite_sync_manager.dart` | 6307 | ⭐⭐ | **ضخم + mergedData لا يُستهلك + serverId=hashCode** |
| `outbox_dao.dart` | 700+ | ⭐⭐⭐ | **getConflicts() معطل** + secondary delivery صامت |
| `sync_locks.dart` | 12 | ⭐⭐⭐⭐ | بعض الأقفال غير مستخدمة |
| `sync_constants.dart` | 51 | ⭐⭐⭐⭐ | tableOrder لا يتحقق تلقائياً |
| `central_sync_coordinator.dart` | صغير | ⭐⭐⭐ | Singleton تجاهل معاملات |

---

## 📊 إحصاءات كمية

| النوع | العدد |
|-------|-------|
| تكرار دوال `_asInt` | 3 ملفات × 3 دوال = 9 تكرارات |
| تكرار `_getXxxByLocalUuid` | ملفين × 15 دالة = 30 تكراراً |
| تكرار `_syncXxx` methods | ملفين × 20 method = 40 تكراراً |
| تكرار `_getLocalXxxLastModified` | ملفين × 17 دالة = 34 تكراراً |
| كيانات متزامنة | 17 كيان |
| استراتيجيات حل التعارض | 8 استراتيجيات |
| سياسات كيانات للحل | 17 سياسة |
| أنماط retry backoff | 3 أنماط |
| حالات Circuit Breaker | 3 حالات |
| مستويات حل FK | 3 مستويات |
| أنواع التعارضات | 7 أنواع |

---

## 🔧 خارطة طريق الإصلاح

### المرحلة 1 — إصلاح فوري (هذا الأسبوع)

| # | المشكلة | الأولوية | التقدير |
|---|---------|----------|---------|
| 1 | `serverId: hashCode` → تخزين string | P0 🔴 | ساعة |
| 2 | استهلاك `mergedData` في _RemoteNewerResult | P0 🔴 | 3 ساعات |
| 3 | `outbox_dao.getConflicts()` — جلب بيانات بعيدة حقيقية | P0 🔴 | 4 ساعات |
| 4 | تشفير القيم الحساسة في app_settings | P0 🔴 | ساعتين |
| 5 | إصلاح `_blacklistToRemote` — تسجيل خطأ JSON | P0 🔴 | 30 دقيقة |
| 6 | إصلاح `rowid` vs `id` في فحص السلامة | P0 🔴 | ساعة |

### المرحلة 2 — دمج وتنظيف (الأسبوع القادم)

| # | المهمة | التقدير |
|---|--------|---------|
| 7 | دمج `sync_pull_service` + `appwrite_sync_manager` (إزالة التكرار) | 3 أيام |
| 8 | نقل `_asInt` و lookup functions إلى `sync_helpers.dart` | يوم |
| 9 | توحيد Pull logic بين DeltaSync و SyncPullService | يومين |
| 10 | نقل bump VC إلى ما بعد نجاح الرفع | 3 ساعات |
| 11 | إضافة maxIterations لحلقة `_pushAllEntities` | 30 دقيقة |

### المرحلة 3 — تحسينات (لاحقاً)

| # | المهمة | التقدير |
|---|--------|---------|
| 12 | تقسيم `appwrite_sync_manager.dart` إلى 4-5 ملفات | 5 أيام |
| 13 | إضافة deep equality في ConflictDetector | 3 ساعات |
| 14 | دمج VectorClock في newerWins | 4 ساعات |
| 15 | تحسين أداء `_cleanupOutboxAfterPull` | 3 ساعات |
| 16 | فصل جدول blacklist عن shift_notes | يومين |
| 17 | إضافة unit tests للكشف والحل | 3 أيام |

---

## 🎯 الخلاصة النهائية

نظام المزامنة **احترافي وقوي** في تصميمه المعماري:
- Outbox Pattern + Delta Sync + Vector Clocks + 3-Way Merge
- 17 كياناً متزامناً مع سياسات حل مخصصة لكل منها
- Circuit Breaker + Adaptive Batch + Deferred Retry للمرونة

**لكن** حجم الملفات وتكرار الكود يشكلان خطراً على الصيانة. أبرز المشاكل:

1. 🔴 **3 Bugs حرجة في سلامة البيانات** (`serverId=hashCode`, `mergedData` لا يُستهلك, `getConflicts()` معطل)
2. 🔴 **80% تكرار كود** بين ملفين — أي fix يجب تطبيقه مرتين
3. 🔴 **كلمات مرور كنص صريح** في Appwrite Cloud
4. 🔴 **حجم `appwrite_sync_manager.dart`** = 6300 سطر في ملف واحد
