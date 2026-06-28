# 🔬 مراجعة هندسية دقيقة — سيناريو Secondary Appwrite

**التاريخ:** 2026-06-28
**المراجِع:** مهندس برمجيات محترف
**المنهجية:** تتبع كل مسار كود سطراً بسطر، فحص الحالات الحدية (edge cases)

---

## 📋 فهرس المسارات المُراجَعة

1. [المسار A: إضافة حجز عند Secondary مُفعّل + Push مُفعّل](#a)
2. [المسار B: إضافة حجز عند Secondary معطّل](#b)
3. [المسار C: إضافة حجز عند Secondary مُفعّل + Push معطّل](#c)
4. [المسار D: تفعيل/تعطيل Push](#d)
5. [المسار E: تفعيل/تعطيل Secondary بالكامل](#e)
6. [المسار F: حذف سجل](#f)
7. [المسار G: SecondarysyncManager.sync() الدورية](#g)
8. [المشاكل المُكتشفة](#problems)

---

## <a id="a"></a>المسار A: Secondary مُفعّل + Push مُفعّل — إضافة حجز

### التدفق المتوقع
```
bookingsRepo.create() → outbox.merge() → markDataChanged()
  → syncNow() → SmartSyncManager.pushLocalChanges() [Google Drive]
  → _pushToSecondary() → SecondarySyncManager.sync()
```

### التحليل الدقيق

**الخطوة 1:** `bookingsRepo.create()` يكتب الحجز في DB محلي + يستدعي `outbox.merge()`

**الخطوة 2:** `outbox.merge()` يُدرج سجلاً جديداً في outbox:
- `delivered_to_primary = false` (افتراضي)
- `delivered_to_secondary = true` (افتراضي — من local_db.dart:697-698)
- `processing_status = 'pending'`
- `source = 'local'`

⚠️ **ملاحظة:** `delivered_to_secondary = true` افتراضياً! هذا يعني أن السجل "مُسلّم للثانوي" قبل أن يُسلّم فعلاً!

**الخطوة 3:** `markDataChanged()` يبدأ مؤقت 15 ثانية

**الخطوة 4:** `syncNow()` يستدعي `SmartSyncManager.instance.pushLocalChanges()`

⚠️ **مشكلة حرجة #1:** `SmartSyncManager.pushLocalChanges()` يرفع إلى **Google Drive فقط**! لا يرفع إلى Appwrite Primary!

```dart
// screen_sync_controller.dart:126
return SmartSyncManager.instance.pushLocalChanges();  // ← Google Drive!
```

`SmartSyncManager.pushLocalChanges()` (smart_sync_manager.dart:770-842) يستدعي `GoogleDriveDeltaSync.instance.pushDeltaChanges()` — لا يستدعي `AppwriteSyncManager` إطلاقاً!

**الخطوة 5:** `_pushToSecondary()` يستدعي `SecondarySyncManager.instance.pushLocalChanges()`

هذا يرفع السجلات إلى Secondary Appwrite. لكن:
- `SecondarySyncManager._takeUndeliveredBatch()` يفحص `delivered_to_secondary = 0`
- لكن السجل الجديد له `delivered_to_secondary = true` (افتراضي)!
- **لن يأخذه Secondary!**

### 🔴 النتيجة: Secondary لا يرفع السجلات الجديدة!

السجل له `delivered_to_secondary = true` افتراضياً، لكن `SecondarySyncManager` يبحث عن `delivered_to_secondary = 0`. السجل لن يُرفع للثانوي!

### من يضبط `delivered_to_secondary = false`؟

من local_db.dart:693-694:
```
delivered_to_secondary = true (افتراضياً مُسلّم: تجنّب حجب السجلات
عندما Secondary غير مُفعّل — فقط SecondarySyncManager يضبطها على false)
```

لكن `SecondarySyncManager` لا يضبطها على `false` عند الإدراج! يضبطها على `false` فقط في `markAllLocalAsUndeliveredToSecondary()` الذي يُستدعى عند **تفعيل** Secondary.

### متى يُضبط `delivered_to_secondary = false` للسجلات الجديدة؟

**إجابة: فقط عند تفعيل Secondary من الإعدادات** — `markAllLocalAsUndeliveredToSecondary()` يُعلّم كل السجلات الموجودة كـ `false`.

لكن السجلات الجديدة المُضافة **بعد** التفعيل؟
- `outbox.merge()` يُدرجها بـ `delivered_to_secondary = true` (افتراضي)
- `SecondarySyncManager._takeUndeliveredBatch()` لن يأخذها (يفحص `= 0`)
- **السجل لا يُرفع للثانوي!**

### 🔴 هذا عيب تصميمي جوهري!

---

## <a id="b"></a>المسار B: Secondary معطّل — إضافة حجز

### التدفق
```
bookingsRepo.create() → outbox.merge()
  → delivered_to_secondary = true (افتراضي) ✅
  → syncNow() → SmartSyncManager.pushLocalChanges() [Google Drive]
  → _pushToSecondary() → يعود فوراً (isEnabled = false) ✅
```

### النتيجة: ✅ صحيح
- السجل يُكتب بـ `delivered_to_secondary = true`
- Primary (لو كان يُستدعى) يرفعه ويضبط `delivered_to_primary = true`
- كلاهما `true` → السجل يُحذف من outbox

⚠️ لكن Primary لا يُستدعى من `syncNow()`! (مشكلة #1 أعلاه)

---

## <a id="c"></a>المسار C: Secondary مُفعّل + Push معطّل — إضافة حجز

### التدفق
```
bookingsRepo.create() → outbox.merge()
  → delivered_to_secondary = true (افتراضي) ✅
  → _pushToSecondary() → يعود فوراً (isPushEnabled = false) ✅
```

### النتيجة: ✅ صحيح (للسجلات الجديدة)
- السجل يُكتب بـ `delivered_to_secondary = true`
- لا ينتظر في outbox

⚠️ لكن السجلات القديمة (قبل التعطيل) التي كانت `false` — تم إصلاحها في `_togglePush(false)` بـ `markAllLocalAsDeliveredToSecondary()`.

---

## <a id="d"></a>المسار D: تفعيل/تعطيل Push

### تفعيل Push
```
_togglePush(true)
  → saveConfig(pushEnabled: true)
  → startAutoSync()
  → sync() فوري (خلفية) ← ✅ إصلاح 96c87186
```

⚠️ لكن `sync()` يستدعي `_takeUndeliveredBatch()` التي تبحث عن `delivered_to_secondary = 0`!
السجلات الجديدة لها `delivered_to_secondary = true` (افتراضي) — **لن تُؤخذ!**

### تعطيل Push
```
_togglePush(false)
  → saveConfig(pushEnabled: false)
  → stopAutoSync()
  → markAllLocalAsDeliveredToSecondary() ← ✅ إصلاح 8ca9e0fb
```

### النتيجة: ⚠️ تفعيل Push لا يعمل للسجلات الجديدة!

---

## <a id="e"></a>المسار E: تفعيل/تعطيل Secondary بالكامل

### تفعيل Secondary
```
_toggleSync(true)
  → markAllLocalAsUndeliveredToSecondary() ← يضبط كل السجلات false ✅
  → startAutoSync()
  → sync() فوري ← ✅
```

هذا يعمل للسجلات الموجودة وقت التفعيل. لكن السجلات الجديدة بعدها لها `delivered_to_secondary = true`!

### تعطيل Secondary
```
_toggleSync(false)
  → markAllLocalAsDeliveredToSecondary() ← يضبط كل السجلات true ✅
  → stopAutoSync()
```

### النتيجة: ⚠️ التفعيل يعمل مرة واحدة فقط (للسجلات الموجودة). السجلات الجديدة لا تُرفع!

---

## <a id="f"></a>المسار F: حذف سجل

نفس مشكلة المسار A — `outbox.merge()` يُدرج بـ `delivered_to_secondary = true` افتراضياً.

---

## <a id="g"></a>المسار G: SecondarySyncManager.sync() الدورية

كل 15 دقيقة:
```
sync() → _takeUndeliveredBatch()
  → SELECT ... WHERE delivered_to_secondary = 0 AND processing_status IN ('pending', 'failed')
```

السجلات الجديدة لها `delivered_to_secondary = true` → **لا تُؤخذ أبداً!**

---

## <a id="problems"></a>🔴 المشاكل المُكتشفة

### 🔴 عيب #1 (حرج): `syncNow()` لا يرفع إلى Appwrite Primary

`ScreenSyncController.syncNow()` يستدعي `SmartSyncManager.pushLocalChanges()` الذي يرفع إلى **Google Drive فقط**، لا Appwrite!

```dart
// screen_sync_controller.dart:126
return SmartSyncManager.instance.pushLocalChanges();  // Google Drive!
// يجب أن يستدعي AppwriteSyncManager.pushLocalChanges() أيضاً!
```

### 🔴 عيب #2 (حرج): `delivered_to_secondary` افتراضي `true` يمنع رفع السجلات الجديدة

```dart
// local_db.dart:697-698
BoolColumn get deliveredToSecondary =>
    boolean().withDefault(const Constant(true))();  // ← true!
```

السجلات الجديدة تُكتب بـ `delivered_to_secondary = true`، لكن `SecondarySyncManager` يبحث عن `= 0`. السجلات لا تُرفع!

### 🔴 عيب #3 (حرج): `_pushToSecondary()` لا يعمل للسجلات الجديدة

```dart
// screen_sync_controller.dart:201-208
if (!SecondaryAppwriteConfig.isEnabled) return;
if (!SecondaryAppwriteConfig.isPushEnabled) return;
// ← لا يفحص delivered_to_secondary!
final result = await SecondarySyncManager.instance.pushLocalChanges();
```

`pushLocalChanges()` يستدعي `sync()` التي تستدعي `_takeUndeliveredBatch()` التي تبحث عن `delivered_to_secondary = 0`. لكن السجل له `true`!

---

## 🎯 الإصلاح المطلوب

### إصلاح #1: `outbox.merge()` يجب أن يضبط `delivered_to_secondary` بناءً على حالة Secondary

```dart
// outbox_dao.dart merge() — يجب أن يفحص SecondaryAppwriteConfig
final deliveredToSecondary = !SecondaryAppwriteConfig.isEnabled || 
    !SecondaryAppwriteConfig.isPushEnabled;
// true إذا Secondary معطّل أو Push معطّل (لا حاجة للانتظار)
// false إذا Secondary مُفعّل + Push مُفعّل (يجب الرفع)
```

### إصلاح #2: `syncNow()` يجب أن يرفع إلى Appwrite Primary أيضاً

```dart
// screen_sync_controller.dart syncNow()
// قبل _pushToSecondary():
await AppwriteSyncManager(appwriteService: ..., database: ...).pushLocalChanges();
```

أو دمج AppwriteSyncManager.pushLocalChanges() في SmartSyncManager.pushLocalChanges().

### إصلاح #3: `_pushToSecondary()` يجب أن يضبط `delivered_to_secondary = false` للسجلات الجديدة

أو الأفضل: إصلاح #1 يحل هذا تلقائياً.

---

## 📊 ملخص الحالات

| السيناريو | Primary يُرفع؟ | Secondary يُرفع؟ | السجل يُحذف؟ |
|-----------|---------------|-----------------|-------------|
| Secondary مُفعّل + Push مُفعّل | ❌ لا (عيب #1) | ❌ لا (عيب #2) | ❌ لا |
| Secondary معطّل | ❌ لا (عيب #1) | ✅ لا حاجة | ❌ لا (عيب #1) |
| Secondary مُفعّل + Push معطّل | ❌ لا (عيب #1) | ✅ لا حاجة | ❌ لا (عيب #1) |
| زر مزامنة Dashboard | ✅ نعم | ✅ نعم | ✅ نعم |

**الخلاصة:** زر المزامنة اليدوي في Dashboard يعمل بشكل صحيح (يستدعي `AppwriteSyncManager.pushLocalChanges()` + `SecondarySyncManager.pushLocalChanges()`). لكن `markDataChanged() → syncNow()` **لا يعمل** لأنه يستدعي `SmartSyncManager` فقط (Google Drive) ولا يستدعي Appwrite Primary!

---

## ⚠️ خلاصة هندسية

النظام الحالي به **3 عيوب حرجة** تجعل Secondary غير فعال للسجلات الجديدة:

1. `syncNow()` لا يرفع إلى Appwrite Primary (يفقد المسار الرئيسي)
2. `delivered_to_secondary = true` افتراضياً يمنع Secondary من أخذ السجلات
3. `_pushToSecondary()` لا يعمل لأن السجلات ليست `delivered_to_secondary = 0`

الإصلاح الثلاثي المطلوب:
1. `outbox.merge()`: ضبط `delivered_to_secondary` ديناميكياً
2. `syncNow()`: استدعاء AppwriteSyncManager.pushLocalChanges()
3. تأكيد `_pushToSecondary()` يعمل بعد الإصلاح #1

---

**آخر تحديث:** 2026-06-28
**الحالة:** 3 عيوب حرجة مُكتشفة — تحتاج إصلاح فوري
