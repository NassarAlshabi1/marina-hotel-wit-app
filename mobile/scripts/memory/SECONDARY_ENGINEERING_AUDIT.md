# 🔬 التدقيق الهندسي الدقيق — Secondary Appwrite Sync

**التاريخ:** 2026-06-28
**المراجِع:** Software Engineering Deep Audit
**الفرع:** `marina`
**الحكم:** 🔴 **FAIL** — 3 مشاكل حرجة (فقدان بيانات)، 2 عالية، 3 متوسطة

---

## 📊 ملخص النتائج

| # | السيناريو | الحكم | السبب |
|---|----------|------|-------|
| 1 | Secondary معطّل + إضافة حجز | ✅ PASS | افتراضي `true` صحيح هنا |
| 2 | Secondary + Push مُفعّل + إضافة حجز | 🔴 **FAIL** | Bug #1: افتراضي `true` → حذف قبل وصول Secondary |
| 3 | Secondary + Push معطّل + إضافة حجز | ⚠️ PARTIAL | يعمل للسجلات الجديدة؛ سجلات قديمة تتراكم |
| 4 | إعادة تفعيل Push بعد التعطيل | 🔴 **FAIL** | Bug #2: `_togglePush(true)` لا يعيد تعليم السجلات |
| 5 | تعطيل ثم تفعيل Secondary | ✅ PASS | `_toggleSync` يعيد تعليم كل السجلات |
| 6 | عملية حذف | ⚠️ PARTIAL | Soft-delete يعمل؛ فرع `op:'delete'` ميت |
| 7 | إعادة تشغيل التطبيق | ⚠️ PARTIAL | يعتمد على Primary لاستعادة السجلات العالقة |
| 8 | مزامنة متزامنة (Primary + Secondary) | ✅ PASS | Atomic claim يمنع التضارب |

---

## 🔴 المشاكل الحرجة (P0) — فقدان بيانات

### P0-1: `delivered_to_secondary` افتراضي `true` — Secondary لا يرى السجلات أبداً

**الموقع:** `local_db.dart:697-698` + `outbox_dao.dart:140-149`

```dart
// local_db.dart — القيمة الافتراضية
BoolColumn get deliveredToSecondary =>
    boolean().withDefault(const Constant(true))();  // ← المشكلة الجذرية
```

```dart
// outbox_dao.dart merge() — لا يضبط القيمة
return into(outbox).insert(OutboxCompanion.insert(
  entity, op, localUuid, serverId, payload, clientTs, idempotencyKey, source
  // ← deliveredToSecondary absent → يستخدم الافتراضي = true
));
```

**التأثير الكارثي:**
1. مستخدم يُفعّل Secondary + Push
2. `_toggleSync(true)` يعلم السجلات **الموجودة** كـ `false` ✅
3. مستخدم يضيف حجز جديد → `merge()` يكتب `delivered_to_secondary=true` ❌
4. Primary يرفع → `markDeliveredToPrimary` → كلا العلمين `true` → **حذف السجل**
5. Secondary لا يجد السجل → **فقدان بيانات دائم**

**الإصلاح:**
```dart
// في merge() — احسب القيمة ديناميكياً
final shouldDeliverToSecondary = SecondaryAppwriteConfig.isEnabled &&
    SecondaryAppwriteConfig.isPushEnabled;
// مرر: deliveredToSecondary: Value(!shouldDeliverToSecondary)
```

---

### P0-2: `_togglePush(true)` لا يعيد تعليم السجلات

**الموقع:** `secondary_appwrite_settings_screen.dart:155-204`

```dart
if (value && SecondaryAppwriteConfig.isEnabled) {
  SecondarySyncManager.instance.startAutoSync();
  SecondarySyncManager.instance.sync().then(...);
  // ❌ لا يوجد markAllLocalAsUndeliveredToSecondary()!
}
```

**التأثير:**
- سجلات فشلت أثناء تعطيل Push لها `delivered_to_secondary=true`
- إعادة تفعيل Push لا يغيرها → Secondary لا يراها أبداً

**الإصلاح:** إضافة `await outboxDao.markAllLocalAsUndeliveredToSecondary();`

---

### P0-3: `_processEntry` خطأ دائم يعود `false` بدلاً من معالجة صحيحة

**الموقع:** `secondary_sync_manager.dart:291-301`

```dart
} on AppwriteException catch (e) {
  if (e.code == 400 || e.code == 401 || e.code == 403) {
    // التعليق يقول "نضع علامة مُسلّم" لكن الكود return false!
    return false;  // ← لا يضع أي علامة!
  }
  rethrow;
}
```

**التأثير:**
- السجل يبقى `processing_status='processing'` (من الـ claim)
- لا `markDeliveredToSecondary` ولا `setError`
- حلقة لا نهائية: stuck → recover → fail → stuck

**الإصلاح:**
```dart
if (e.code == 400 || e.code == 401 || e.code == 403) {
  await outboxDao.setError(entry.id, 'Permanent: ${e.message}', 999);
  failed++;
  continue;  // تخطي بدلاً من return false
}
```

---

## 🟠 مشاكل عالية (P1)

### P1-1: لا تنظيف للسجلات العالقة في Secondary

**الموقع:** `secondary_sync_manager.dart` (الملف كامل — لا `cleanupStuckEntries`)

**التأثير:** إذا كان Primary معطّل، السجلات العالقة لا تُستعادة أبداً.

**الإصلاح:** إضافة مؤقت تنظيف كل 1-2 دقيقة.

### P1-2: سجلات تالفة تتراكم بعد bulk flag operations

**الموقع:** `outbox_dao.dart:403-419`

`markAllLocalAsDeliveredToSecondary` و `markAllLocalAsUndeliveredToSecondary` يحدّثان العلم دون فحص الحذف.

**الإصلاح:** إضافة `DELETE FROM outbox WHERE delivered_to_primary=1 AND delivered_to_secondary=1` بعد الـ bulk update.

---

## 🟡 مشاكل متوسطة (P2)

| # | المشكلة | الإصلاح |
|---|---------|---------|
| P2-1 | `op:'delete'` فرع ميت | إزالة أو توثيق |
| P2-2 | `_pushToSecondary` يعمل فقط بعد نجاح Primary | استدعاء مستقل |
| P2-3 | bulk operations لا تحدّث `processing_status` | إضافة تحديث |

---

## ✅ ما يعمل بشكل صحيح

1. **Atomic claim** — يمنع التضارب بين Primary و Secondary
2. **تصفية payload** — مُصلَّحة
3. **كتم 404** — مُصلَّح
4. **معالجة 409** — recursive retry
5. **TimeoutException** — يُعاد المحاولة ثم `setError`
6. **`_toggleSync` enable/disable** — يعيد تعليم كل السجلات
7. **`_markDelivered` transactional delete** — منطق صحيح
8. **إعادة تشغيل التطبيق** — يبدأ Secondary auto-sync

---

## 🎯 خطة الإصلاح (بالترتيب)

| الأولوية | الإصلاح | الجهد | الأثر |
|---------|---------|------|------|
| **P0-1** | `merge()` يحسب `delivered_to_secondary` ديناميكياً | 5 دقائق | يُصلح السيناريو 2 + 6 |
| **P0-2** | `_togglePush(true)` يضيف `markAllLocalAsUndeliveredToSecondary` | 1 دقيقة | يُصلح السيناريو 4 |
| **P0-3** | `_processEntry` يستدعي `setError` بدلاً من `return false` | 10 دقائق | يُصلح السجلات العالقة |
| **P1-1** | Secondary stuck-recovery timer | 30 دقيقة | استقلالية عن Primary |
| **P1-2** | cleanup DELETE بعد bulk operations | 10 دقائق | منع التراكم |

**بعد إصلاح P0-1 و P0-2، السيناريوهات 2 و 4 و 6 ستعمل بشكل صحيح.**

---

**آخر تحديث:** 2026-06-28
