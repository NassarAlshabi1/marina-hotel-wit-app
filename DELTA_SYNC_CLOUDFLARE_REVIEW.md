# مراجعة دقيقة عميقة — Delta Sync × Cloudflare

> **الحالة:** ✅ تم تنفيذ الإصلاحات (البنود 1–3 + حارس دفاعي للبند 5) ودفعها إلى
> `agent/lunar-maple-mq0y`. البند 5 (تلف بيانات الإنتاج نفسه) لم يُلمَس — أُضيف
> حارس كودي للتعافي التدريجي فقط، دون أي تعديل SQL مباشر على قاعدة الإنتاج.
> **النطاق:** مسار الـ Delta Sync الكامل بين تطبيق الموبايل و Cloudflare Worker/D1.
> **الملفات المفحوصة الرئيسية:**
> - `mobile/lib/services/delta_sync_service.dart`
> - `mobile/lib/services/sync_service.dart`
> - `mobile/lib/services/cloudflare_sync_manager.dart`
> - `mobile/lib/services/daos/outbox_dao.dart`
> - `mobile/lib/providers/appwrite_providers.dart` / `core_providers.dart`
> - `worker/src/index.ts`, `worker/src/sync.ts`, `worker/src/database.ts`
> - `mobile/test/services/sync/delta_sync_service_test.dart`, `mobile/test/unit/delta_sync_service_test.dart`

---

## ملخص تنفيذي

| # | الخطورة | الموضوع | الأثر | الحالة |
|---|---|---|---|---|
| 1 | 🔴 عالية | `DeltaSyncService`/`SyncService` (مسار PHP قديم) مربوط بأزرار مزامنة رئيسية في الواجهة، **منفصل تماماً** عن Cloudflare | أزرار "مزامنة" في عدة شاشات لا تُزامن مع Cloudflare D1 إطلاقاً، وتفشل بصمت | ✅ **تم الإصلاح** |
| 2 | 🟠 متوسطة-عالية | مفتاح idempotency في `outbox_dao.dart` بدقة الثانية فقط | خطر إسقاط تحديثات صامتة عند تعديلين متتاليين لنفس السجل ضمن نفس الثانية بعد نجاح دفع سابق | ✅ **تم الإصلاح** |
| 3 | 🟡 منخفضة | تعليق توثيقي قديم متضارب مع الاختبار الفعلي + ملف اختبار مكرر فارغ | تضليل محتمل للمطوّرين/الأدوات المستقبلية | ✅ **تم الإصلاح** |
| 4/5 | 🔴 عالية (مؤكَّدة في الإنتاج) | تلف حقيقي في حقل `version` — **100% من جدول `rooms`** + صفوف متفرقة في `payments`/`bookings` تحمل قيماً اصطناعية (`9999`, `10000`, `1,000,000,000+n`) | يلوّث "معيار الفوز" في حسم تعارضات LWW الحقيقي على قاعدة الإنتاج | ⚠️ **حارس كودي مُضاف** (تعافٍ تدريجي)، **البيانات الحالية لم تُصحَّح** — بانتظار قرارك |

---

## 1) 🔴 انفصال كامل بين "Delta Sync" الحقيقي (Cloudflare) والكلاس المسمّى فعلياً `DeltaSyncService`

### المشكلة

الكلاس الوحيد في المستودع الذي يحمل اسم "Delta Sync" حرفياً — `mobile/lib/services/delta_sync_service.dart` — **لا يُستخدم من قِبل `CloudflareSyncManager` إطلاقاً**. تحققتُ بالبحث الكامل في الشجرة:

```bash
grep -n "DeltaSync\|delta_sync" mobile/lib/services/cloudflare_sync_manager.dart \
    mobile/lib/services/unified_sync_orchestrator.dart \
    mobile/lib/services/sync_orchestrator.dart
# → صفر نتائج
```

المستخدم الوحيد لـ `DeltaSyncService` هو `mobile/lib/services/sync_service.dart`:

```dart
// sync_service.dart:36, 111, 160
deltaSyncService = DeltaSyncService(db), ...
final computation = await deltaSyncService.compute();
...
final response = await ApiService.I.syncPush(payload).timeout(timeout);
```

وهذا يستدعي `ApiService` وهو عميل **REST/PHP قديم** (وليس Cloudflare Worker):

- `ApiService` يبني `baseUrl` من `ApiConfigService` ← `Env.baseApiUrl`:
  ```dart
  // mobile/lib/utils/env.dart:25
  static String baseApiUrl = const String.fromEnvironment('BASE_API_URL');
  ```
  وهذه القيمة **فارغة افتراضياً** ما لم تُمرَّر عبر `--dart-define=BASE_API_URL=...` وقت البناء.
- بحسب `mobile/CLAUDE.md` نفسه: *"Legacy Sync: `sync_service.dart` (PHP REST API)"* — أي أنه موصوف رسمياً كمسار قديم.
- تاريخ الالتزامات الأخيرة (`90cd584b feat(purge): remove Appwrite & Google Drive sync entirely`) يقول صراحة: **"Cloudflare D1 is now the only sync backend"**.

بالمقابل، محرك المزامنة الفعلي مع Cloudflare يعمل عبر آلية outbox مختلفة تماماً:

```
CloudflareSyncManager → OutboxDao (outbox table) → POST /api/sync/push
                                                   → GET  /api/sync/pull
```

### أين يظهر الخلل في الواجهة؟

عدّة شاشات تستدعي `syncServiceProvider`/`syncProvider` (المسار الميت) بدلاً من `appwriteSyncManagerProvider` (وهو typedef حقيقي لـ `CloudflareSyncManager`، انظر `mobile/lib/providers/appwrite_providers.dart:21`):

| الشاشة | السطر | الفعل |
|---|---|---|
| `rooms_dashboard.dart` | 47 | زر أيقونة المزامنة |
| `rooms_main.dart` | 39 | زر أيقونة المزامنة |
| `employees_list.dart` | 50, 95 | زر + إجراء إضافي |
| `settings_employees.dart` | 48 | زر المزامنة |
| `settings_guests.dart` | 47 | زر المزامنة |
| `bookings_list.dart` | 134 | Pull-to-refresh |
| `payment_history_screen.dart` | 119, 216 | زر + Pull-to-refresh |
| `blacklist_screen.dart` | 135, 428 | زر المزامنة |
| `reports_screen.dart` | 217 | زر المزامنة |

بينما **الزر الحقيقي الوحيد** المتصل فعلياً بـ Cloudflare هو `DashboardSyncButton` (`mobile/lib/widgets/dashboard_sync_button.dart:261, 554, 762`) عبر `appwriteSyncManagerProvider`.

### لماذا هذا خطير عملياً

معظم استدعاءات `runSync()` أعلاه **غير منتظرة (`unawaited`) وغير ملتقطة بـ try/catch**، مثال حرفي:

```dart
// rooms_dashboard.dart:47
onPressed: () => ref.read(syncServiceProvider).runSync(),
```

و`runSync()` تُعيد رمي الاستثناء عند الفشل:

```dart
// sync_service.dart:98-102
} catch (e) {
  _performanceOptimizer.recordSyncAttempt(success: false);
  _status.add(SyncStatus.error);
  dlog(() => '❌ فشل في المزامنة: $e');
  rethrow;
}
```

بما أن `Env.baseApiUrl` فارغ افتراضياً، فإن أي طلب HTTP سيفشل فوراً — والاستثناء يضيع في `Future` غير منتظر، فلا يرى المستخدم أي رسالة خطأ. **النتيجة: ضغط زر "مزامنة" في هذه الشاشات يُعطي وهم النجاح دون أي مزامنة فعلية مع Cloudflare D1.**

### التوصية

- الخيار الأنظف: حذف `SyncService`/`DeltaSyncService`/`ApiService.syncPush/syncPull` بالكامل (كود ميت فعلياً بعد إزالة الـ PHP backend)، وربط كل الشاشات أعلاه بـ `appwriteSyncManagerProvider` (أو دالة موحّدة في `UnifiedSyncOrchestrator`).
- إن كان هناك سبب لإبقاء هذا المسار (مثلاً عميل PHP قديم قيد الاستخدام في بيئة معينة)، فيجب على الأقل معالجة الاستثناء وإظهار Snackbar واضح للمستخدم بدل الفشل الصامت.

### ✅ الإصلاح المُطبَّق

اختير المسار الأقل مخاطرة: **إعادة توجيه كل نقاط الاستدعاء دون حذف `SyncService`/`DeltaSyncService`** (تبقى `syncStatusProvider`/`syncStatusStream` مستخدَمة في عدة اختبارات أداء/تكامل — حذفها الآن مخاطرة غير ضرورية لحل هذا الخلل تحديداً).

- أُضيفت دالة موحّدة `triggerManualCloudflareSync(context, ref, {showSuccessSnackbar})` في `mobile/lib/utils/manual_sync_trigger.dart` — تستدعي `CloudflareSyncManager.sync(forcePull: true)` الحقيقي (دفع + سحب) وتُظهر نجاحاً/فشلاً حقيقياً عبر `SnackBarHelper` بدل الفشل الصامت.
- استُبدلت كل استدعاءات `ref.read(syncServiceProvider).runSync()` / `ref.read(syncProvider).runSync()` بهذه الدالة في:
  `rooms_dashboard.dart`, `rooms_main.dart`, `employees_list.dart` (زر + إعادة محاولة الخطأ)، `settings_employees.dart`, `settings_guests.dart`, `bookings_list.dart` (pull-to-refresh)، `payment_history_screen.dart` (زر + pull-to-refresh)، `reports_screen.dart`.
- `blacklist_screen.dart`: أُعيدت كتابة `_performSync()` لتستخدم `appwriteSyncManagerProvider.sync(forcePull: true)` مباشرة (كانت أصلاً تحتوي بنية try/catch + `_isSyncing` + snackbar جيدة — فقط تستدعي المدير الخطأ) بدل تمرير `SyncService` كمعامل.
- تحقّقتُ بعد التعديل: **صفر استدعاءات إنتاجية متبقية** لـ `syncServiceProvider`/`syncProvider` في `mobile/lib` (تبقى تعريفاتها فقط في `sync_service.dart`/`core_providers.dart`، غير مُستخدَمة إنتاجياً بعد الآن).

---

## 2) 🟠 مفتاح Idempotency بدقة الثانية — خطر إسقاط تحديثات صامتة في مسار Cloudflare الحقيقي

### الموقع

```dart
// mobile/lib/services/daos/outbox_dao.dart:219  (merge)
// mobile/lib/services/daos/outbox_dao.dart:1163 (_mergeSingle، لعمليات الدفعة/الاستعادة)
final idempKey = '$entity:$op:$localUuid:$clientTs';
```

حيث `clientTs = Time.nowEpoch()`:

```dart
// mobile/lib/utils/time.dart:8
static int nowEpoch() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
```

أي **دقة ثانية واحدة فقط**. هذا المفتاح يُرسَل إلى Worker ويُخزَّن بشكل دائم:

```ts
// worker/src/database.ts:1003-1011 (saveIdempotency)
'INSERT OR IGNORE INTO idempotency_log (key, entity, operation, entity_id, processed_at, response) ...'
```

ويُتحقق منه أولاً في كل Push:

```ts
// worker/src/sync.ts:338-348 (handlePush)
const idempResult = await db.checkIdempotency(op.idempotencyKey);
if (idempResult.exists) {
  results.push({ idempotencyKey: op.idempotencyKey, success: true, skipped: true, ... });
  continue; // ← لا تُطبَّق البيانات الجديدة إطلاقاً
}
```

### آلية الحماية الموجودة ولماذا هي غير كافية

طالما بقي صف الـ outbox بحالة `pending`/`processing`، فإن `merge()` يدمج التعديلات المتتالية في نفس الصف ويُحدّث `idempKey` معه (`outbox_dao.dart:236-244`) — وهذا يمنع التصادم أثناء الانتظار. **لكن هذه الحماية تختفي بعد نجاح الدفع وحذف الصف**:

```dart
// cloudflare_sync_manager.dart:1678-1682
if (success) {
  await (outboxDao.delete(outboxDao.outbox)..where((t) => t.id.equals(outboxItem.id))).go();
  successCount++;
}
```

### سيناريو الفشل الملموس

1. تعديل 1 على `bookings/<uuid>` (op=`update`) يُسجَّل بـ `clientTs = T`.
2. دورة دفع تُنفَّذ وتنجح **ضمن نفس الثانية T** → الصف يُحذف من outbox، والمفتاح `bookings:update:<uuid>:T` يُخزَّن نهائياً في `idempotency_log`.
3. تعديل 2 مختلف تماماً (بيانات جديدة) على **نفس** `bookings/<uuid>` يحدث — أيضاً ضمن نفس الثانية T (وارد في عمليات تصحيح/إعادة حساب سريعة متتالية).
4. `merge()` لا يجد صفاً `pending` سابقاً (حُذف في الخطوة 2) فيُنشئ صفاً جديداً بنفس المفتاح تماماً `bookings:update:<uuid>:T`.
5. عند الدفع، `checkIdempotency` يجد المفتاح موجوداً مسبقاً → يُعيد `success:true, skipped:true` **دون تطبيق بيانات التعديل 2 على D1**.
6. العميل لا يميّز بين `success` و`success+skipped` (`cloudflare_sync_manager.dart:1678-1682`) → يحذف الصف ظانّاً أن الرفع تم بنجاح.

**النتيجة: فقدان صامت لتعديل حقيقي دون أي أثر في outbox أو في سجل الأخطاء.**

### التوصية

أضِف عنصراً غير قابل للتصادم إلى المفتاح بدلاً من الاعتماد فقط على ثانية wall-clock — مثلاً حقل `payloadVersion` الموجود أصلاً في جدول outbox، أو UUID عشوائي يُولَّد عند الإدراج الأول ويُحافَظ عليه عبر الدمج.

### ✅ الإصلاح المُطبَّق

أُضيفت دالة خاصة موحّدة `_buildIdempotencyKey(entity, op, localUuid, clientTs)` في `outbox_dao.dart` تُلحق UUID v4 عشوائياً بالمفتاح: `'$entity:$op:$localUuid:$clientTs:${_uuid.v4()}'` (الحزمة `uuid` مستوردة أصلاً في الملف). استُخدمت في كلا موقعي التوليد (`merge()` و`_mergeSingle()` — مسار الاستعادة/الدفعات).

- **لماذا هذا آمن لدلالة "إعادة المحاولة"**: العشوائية تُضاف فقط عند استدعاء `merge()` فعلياً (إدراج جديد أو تعديل محتوى). القيمة تُخزَّن في عمود `idempotency_key` بالصف — إعادة محاولة دفع نفس الصف (بلا `merge()` جديد بينهما، أي بلا تعديل محتوى) تقرأ نفس القيمة المخزَّنة كما هي، فتبقى دلالة idempotency الحقيقية (نفس المحاولة → نفس المفتاح) سليمة تماماً؛ فقط تعديل محتوى جديد فعلي يُنتج مفتاحاً جديداً — وهو بالضبط ما يمنع الآن أي تصادم مع مفاتيح سابقة استُهلكت على الخادم.
- تحقّقتُ أن لا اختبار في `mobile/test` يفترض الصيغة الحرفية القديمة للمفتاح (`entity:op:uuid:ts` بأربعة أجزاء فقط) — الاختبارات الموجودة تتحقق من السلوك (عدد الصفوف، الدمج) لا من شكل السلسلة النصية.

---

## 3) 🟡 توثيق اختبار قديم متضارب مع الحالة الفعلية للكود

في `mobile/test/services/sync/delta_sync_service_test.dart:11-13` (تعليق أعلى الملف):

```
6. ⚠️ Known bug: hard-deleted row keeps emitting 'update' forever
   (missing-row path always emits with nowTs). This test documents
   the behavior; a fix must change this test.
```

بينما الاختبار الفعلي في نفس الملف معنون:

```dart
// السطر 186
test('6. ✅ FIX: hard-deleted row emits delete only once (not forever)', ...)
```

والمصدر يحتوي فعلاً على الإصلاح الموثَّق بتعليق عربي مفصّل (`delta_sync_service.dart:705-723`، "إصلاح bug 'missing forever'"). أي أن **الإصلاح تمّ فعلاً وعنوان الاختبار حُدِّث، لكن ملخّص رأس الملف بقي قديماً** — ما قد يُضلّل أي مطوّر (أو Agent) يقرأ رأس الملف فقط ويظن أن الخلل ما يزال قائماً.

بالإضافة إلى ذلك، يوجد ملف مكرّر بنفس الاسم تماماً: `mobile/test/unit/delta_sync_service_test.dart` وهو مجرد placeholder فارغ:

```dart
test('placeholder test', () {
  expect(true, isTrue);
});
```

### التوصية

- تحديث تعليق الرأس في `mobile/test/services/sync/delta_sync_service_test.dart` ليعكس أن البند 6 مُصلَح فعلاً (لا "known bug").
- حذف ملف الـ placeholder المكرر `mobile/test/unit/delta_sync_service_test.dart` أو استبداله باختبارات حقيقية إن أُريد الإبقاء عليه.

### ✅ الإصلاح المُطبَّق

- حُدِّث تعليق الرأس ليقول "✅ FIXED" بدل "⚠️ Known bug"، ويشرح آلية الإصلاح الفعلية (حلقة الـ missing-uuid في `delta_sync_service.dart`) بدل وصف السلوك القديم.
- حُذف ملف الـ placeholder المكرر `mobile/test/unit/delta_sync_service_test.dart` (لم يكن مرجَّعاً من أي إعداد تشغيل اختبارات).

---

## 4) 🔴 تحقّق حي على قاعدة الإنتاج — سحب فعلي للأحداث من D1 (`marina-hotel-db`)

> نُفِّذ هذا القسم عبر اتصال مباشر بقاعدة D1 الإنتاجية (Cloudflare MCP)، بتشغيل استعلامات SQL تُطابق منطق `pullChanges()` في `worker/src/database.ts` — أي "سحب دلتا" فعلي، بدل تشغيل تطبيق الموبايل نفسه (لا توجد جلسة جهاز في هذه البيئة).

### مؤشر المزامنة الحالي
`sync_clock.last_ts = 1789592943` (آخر حدث في كامل النظام، ≈ 2026-09-16 21:09:03 UTC).

### آخر الأحداث المسجَّلة في `sync_log` (13 حدثاً فقط منذ التأسيس)

| الوقت (UTC) | الكيان | العملية | النسخة | الجهاز |
|---|---|---|---|---|
| 2026-09-16 21:09:04 | bookings | update | 4 | cf_dev_mu07yt34 |
| 2026-09-16 19:59:03 | rooms | update | **1000000000071** ⚠️ | cf_dev_mu07yt34 |
| 2026-09-16 19:59:02 | debts | create | 1 | cf_dev_mu07yt34 |
| 2026-09-16 19:59:01 | bookings | update | 2 | cf_dev_mu07yt34 |
| 2026-09-15 01:24:53 | app_users | create | 1 | cf_dev_mu07yt34 |
| 2026-09-15 01:24:50 | app_users | update | 2 | cf_dev_mu07yt34 |
| 2026-09-14 17:40:40 | salary_withdrawals | update | 2 | cf_dev_mu07yt34 |
| (+6 أحداث أقدم: expenses, salary_withdrawals) | | | | |

### آخر التغييرات الفعلية بالقراءة المباشرة من الجداول (أدق من `sync_log`)

- **bookings**: أحدث تحديث `2026-09-16 21:09:03 UTC` — حجز الغرفة 103 (الحالة: "مكتمل").
- **guest_infos**: 5 ضيوف حُدِّثوا خلال ثانيتين فقط حول `21:08:50–21:09:03 UTC` (دفعة تسجيل نزلاء مرتبطة على الأرجح بنفس الحجز).
- **payments**: أحدث دفعة `2026-09-16 21:08:38 UTC` (من إجمالي 1368).
- **debts**: أحدث دين مُنشأ `2026-09-16 19:59:02 UTC` (من إجمالي 9 فقط).

### حجم البيانات الحالي في D1

| الجدول | عدد الصفوف |
|---|---|
| rooms | 20 |
| bookings | 250 |
| payments | 1368 |
| expenses | 1318 |
| guest_infos | 71 |
| employees | 16 |
| debts | 9 |
| cash_transactions | 0 (فارغ تماماً) |

---

## 5) 🔴 تلف بيانات مؤكَّد في الإنتاج — حقل `version` ملوَّث في `rooms` (100%) وصفوف متفرقة أخرى

اكتُشف أثناء سحب الأحداث أعلاه (البند رقم 12 في `sync_log` لفت الانتباه بقيمة `version: 1000000000071`). فحص الجدول بالكامل أكّد أن الأمر **ليس عرضياً**:

```sql
SELECT local_uuid, room_number, version, updated_at, created_at FROM rooms ORDER BY version DESC;
```

| room_number | version | ملاحظة |
|---|---|---|
| 101 | 1,000,000,000,070 | |
| 103 | 1,000,000,000,064 | |
| 201 | 1,000,000,000,047 | |
| 204 | 1,000,000,000,036 | |
| ... | ... | 18 غرفة أخرى بنفس النمط (قاعدة ~1e9 أو ~1e12) |
| 402, 203 | 1,000,000,000,000 | القيمة الأساسية بالضبط (بلا أي زيادة) |
| 104 | 1,000,077 | قاعدة مختلفة (~1e6) |

**النتيجة: 20 من 20 صفاً في `rooms` (100%) مصابة.** فحص جداول أخرى:

| الجدول | صفوف بـ version > 1000 | القيم |
|---|---|---|
| `rooms` | 20 / 20 (100%) | 1,000,077 → 1,000,000,000,070 |
| `payments` | 12 / 1368 | القيمة `9999` بالضبط لكل الصفوف الـ12 |
| `bookings` | 1 / 250 | القيمة `10000` بالضبط |
| `employees`, `debts`, `expenses`, `guest_infos`, `salary_withdrawals` | 0 | سليمة تماماً |

### لماذا هذا مهم لخوارزمية الـ Delta Sync تحديداً

`version` هو **كاسر التعادل (tie-breaker)** الوحيد في حسم تعارضات LWW عند تساوي `updated_at`:

```ts
// worker/src/database.ts:1112-1118
private incomingVersionWins(existingVersion: number, incomingVersion: unknown): boolean {
  const v = Number(incomingVersion);
  return Number.isFinite(v) && v > existingVersion;
}
```

القيم المستديرة تماماً (`9999`, `10000`, `1000000000+n`) لا يمكن أن تنتج من الزيادة الطبيعية (`existing.version + 1` في `updateRecord`، `database.ts:905`) — كل جدول `rooms` مصاب بالكامل بينما بقية الجداول سليمة، وبعض صفوف `payments`/`bookings` تحمل قيماً اصطناعية مطابقة تماماً لبعضها البعض (`9999` في كل الاثني عشر صفاً). هذا نمط توقيع كلاسيكي لسكربت **ترحيل/استيراد** (على الأرجح من مرحلة الانتقال من Appwrite إلى Cloudflare، أو أداة استعادة نسخة احتياطية) ضخّ قيمة `version` اصطناعية عالية عمداً أو بالخطأ — ربما لضمان "فوز" هذه الصفوف في أي تعارض LWW مستقبلي مقابل outbox محلي لم يُفرَّغ بعد وقت الترحيل.

**الأثر العملي:** غير مدمِّر فورياً (الأرقام ضمن مدى JS الآمن `Number.MAX_SAFE_INTEGER`)، لكنه:
- يلوّث بيانات إنتاج حقيقية بشكل دائم (`version` لم يعد يعكس "عدد التعديلات الحقيقي" لهذه الصفوف).
- يجعل أي عملية Ops/تدقيق مستقبلية تعتمد على `version` (Debug/Analytics/تنظيف بيانات) مضلَّلة.
- يكشف أن مسار ترحيل واحد على الأقل تجاوز خط أنابيب `updateRecord`/`allocateUpdatedAt` العادي (أو استخدم `/api/sync/migrate` بقيم `version` حرفية من العميل، انظر `worker/src/sync.ts:495-638`) دون تعقيم.

### التوصية

1. تحديد سكربت/عملية الترحيل المسؤولة (فحص تاريخ Git لأي أداة migrate/restore تدمج حقل `version` بقيمة ثابتة أو مُشتقة من epoch).
2. كتابة استعلام تصحيح آمن (مرة واحدة) يعيد ضبط `version` في الصفوف المتأثرة إلى قيمة صغيرة معقولة مع الحفاظ على ترتيبها النسبي، **بعد** التأكد أن لا outbox محلي معلّق يعتمد على القيمة القديمة.
3. إضافة تحقّق دفاعي في `createRecord`/`updateRecord` (الخادم) يرفض/يُطبّع أي `version` واردة من العميل تتجاوز حداً معقولاً (مثلاً 100,000)، تماماً كما تُعالَج الطوابع الزمنية المسمومة حالياً (`Database.FUTURE_TIMESTAMP_THRESHOLD`).

### ✅ الإصلاح المُطبَّق جزئياً (حارس كودي فقط — لا لمس للبيانات)

تحقّقتُ أولاً من نقطة الحقن الفعلية: `createRecord`/`updateRecord` في `database.ts` يفرضان `version` الخادم دائماً (`version: 1` / `version: newVersion` تُكتب **بعد** `...data` في الـ object literal فتتجاوز أي قيمة عميل) — أي أن المسار العادي `/api/sync/push` **محصَّن أصلاً**. الحقن الفعلي جاء إذاً من `handleMigrate` (`worker/src/sync.ts`) الذي ينفّذ عبارات `INSERT` الخام من العميل حرفياً (مسار ترحيل سريع مقصود، بلا تحقق من قيم الأعمدة) — تعديل هذا المسار لفرض قواعد على قيم أعمدة عشوائية داخل SQL خام يتطلب Parsing SQL حقيقي وهو تغيير أكبر وأخطر من نطاق هذا الإصلاح.

بدلاً من ذلك طُبِّق تعافٍ ذاتي تدريجي (بنفس روح `FUTURE_TIMESTAMP_THRESHOLD` الموجود مسبقاً للطوابع الزمنية المسمومة):

- دالة خاصة جديدة `sanitizeVersion(v)` في `database.ts` تُعيد القيمة كما هي إن كانت ≤ `MAX_SANE_VERSION` (1,000,000)، وإلا تُعيد `1`.
- طُبِّقت في 3 مواضع: حساب `newVersion` في `updateRecord` و`deleteRecord` (كلاهما كان `existing.version + 1` مباشرة)، وفي مقارنة `incomingVersionWins` داخل حساب `timestampLoss` (تكسير تعادل LWW) — بحيث لا تفوز نسخة الخادم في أي تعارض مستقبلي **فقط** بسبب رقم `version` ملوَّث تاريخياً.
- **لماذا لم أُصحِّح البيانات الحالية مباشرة**: تصحيح صفوف `rooms`/`payments`/`bookings` الحالية عبر `UPDATE` مباشر على D1 الإنتاجية عملية لا رجعة فيها على بيانات حية — تنفَّذ فقط بتأكيد صريح منك (سؤالي الأصلي عند الاكتشاف). الحارس الحالي يضمن أن أي **تعديل مستقبلي** على هذه الصفوف عبر المسار الطبيعي يُصحِّح رقمها تلقائياً دون أي تدخل يدوي، بلا أي مخاطرة إضافية على بيانات لم تُعدَّل بعد.
- تحقّق: `npx tsc --noEmit` نظيف، و**137/137 اختباراً** في `worker` (`npx vitest run`) ما زالت تنجح بعد التعديل.

⚠️ **لم يتم تنفيذه بعد** (بانتظار تأكيدك الصريح، لأنه يمسّ بيانات إنتاج حية):
- تصحيح صفوف `version` الملوَّثة الحالية فعلياً عبر استعلام SQL تصحيحي لمرة واحدة.
- تحديد سكربت الترحيل التاريخي المسؤول عن الحقن الأصلي (بحث في تاريخ Git/سكربتات الاستيراد).

---

## خلاصة

المشكلة الجوهرية في هذه المراجعة ليست خللاً في خوارزمية الـ delta نفسها (منطق `compute()` في `delta_sync_service.dart` سليم إلى حد بعيد ومُختبر جيداً)، بل في **البنية**: يوجد نظاما مزامنة منفصلان تماماً في نفس التطبيق — واحد ميت (PHP/legacy) مربوط بواجهات حيّة، وواحد حي (Cloudflare/outbox) مربوط بواجهة واحدة فقط. هذا النوع من الانفصال الصامت هو أخطر من أي علة منطقية موضعية لأنه يُعطي ثقة زائفة بأن "زر المزامنة يعمل" في معظم شاشات التطبيق.

كما أن التحقّق الحي المباشر على قاعدة الإنتاج (البندان 4 و5) أثبت أن الفحص النظري للكود لا يكفي وحده: تلف حقل `version` في جدول `rooms` بالكامل كان موجوداً فعلياً في بيانات حقيقية ولم يكن ليُكتشف بمراجعة الكود المصدري وحدها.

## حالة التنفيذ النهائية

تم تنفيذ إصلاحات البنود 1، 2، 3 كاملةً، وحارس دفاعي كودي للبند 5 — كلها مدفوعة إلى فرع `agent/lunar-maple-mq0y`:

- **الملفات المعدَّلة**: 9 شاشات Flutter (إعادة توجيه زر المزامنة)، `outbox_dao.dart` (مفتاح idempotency)، `worker/src/database.ts` (حارس `version`)، ملف اختبار (تحديث توثيق) + حذف ملف اختبار placeholder مكرر.
- **ملف جديد**: `mobile/lib/utils/manual_sync_trigger.dart`.
- **التحقق**: `npx tsc --noEmit` نظيف على الـ Worker، و**137/137** اختباراً في `worker` (`vitest`) ناجحة بعد التعديل. لا Flutter SDK متاح في هذه البيئة لتشغيل `flutter analyze`/اختبارات الموبايل — رُوجعت التعديلات يدوياً بعناية (ترتيب الـ imports، عدم وجود استخدامات متبقية لِـ `syncServiceProvider`/`syncProvider`، توافق الأنواع مع `SyncResult`/`CloudflareSyncManager.sync()`).
- **لم يُلمَس**: بيانات الإنتاج الفعلية (صفوف `version` الملوَّثة في `rooms`/`payments`/`bookings` — بحاجة تأكيدك الصريح لتصحيح SQL مباشر)، وكذلك تحديد سكربت الترحيل التاريخي المسؤول عن الحقن الأصلي.

---

## ملحق (2026-09-17): الدمج + النشر + تصحيح البيانات

> أُضيف عند دمج فرع `agent/lunar-maple-mq0y` في `feat/cloudflare-sync-execution`،
> لسدّ ثلاث فجوات في «حالة التنفيذ النهائية» أعلاه.

### 1. Commit ثالث على الفرع لم يكن موثقاً هنا

`58ff9989` — *perf(sync): make the historical tombstone sweep fast and resumable*
(+68 سطراً في `cloudflare_sync_manager.dart`): يعالج شكوى مستخدم حقيقية
(«يتأخر كثيراً أثناء سحب التغييرات») عبر ثلاثة تغييرات: حجم صفحة المسح
100→250 (`deltaPullBatchSize`)، تطبيق دفعة الصفحة داخل معاملة واحدة بدل
صف-بصف، ومؤشر استئناف محفوظ (`cf_tombstone_sweep_v1_cursor`) بحيث لا يعيد
المسح من الصفر بعد كل فشل شبكي جزئي.

### 2. قرار الدمج

جرى تطبيق إصلاحين متوازيين لنفس البند #1: هذا الفرع (إعادة توجيه الشاشات
مع إبقاء `SyncService`) وفرع `feat/cloudflare-sync-execution` commit
`5c1fbc02` (حذف `DeltaSyncService` بالكامل + إعادة كتابة `sync_service.dart`
إلى 88 سطراً مفوّضة إلى `CloudflareSyncManager`). **الدَمج الهجين المعتمد**:
حذف المحرك من فرعنا + شاشاتُ هذا الفرع (استدعاء `triggerManualCloudflareSync`
المباشر بتغذية راجعة حقيقية) + إصلاح idempotency + حارس `version` + إصلاح
tombstone. نتيجة الدمج: `tsc` نظيف و**137/137** اختباراً ناجحة.

### 3. تنبيه تشغيلي مهم

حارس `sanitizeVersion` (البند 5) **لا يصبح فعّالاً إلا بعد `wrangler
deploy`** — دفعه إلى Git وحده لا يحمي الإنتاج. دليل حي قبل النشر: غرفة 104
تحوّلت من `1,000,077` إلى `1,000,078` (تعديل شرعي بنى فوق القيمة الملوَّثة).

### 4. تصحيح البيانات (البند 5 المعلَّق) — نُفِّذ

- نسخة احتياطية كاملة من الصفوف الملوَّثة في جداول
  `version_fix_backup_20260917_{rooms,payments,bookings}` قبل أي تعديل.
- `rooms` (20/20): إعادة ضبط بترتيب نسبي محفوظ — الأعلى تلوثاً (غرفة 101)
  ← 20، والأدنى ← 1.
- `payments`: الصفوف الـ12 ذات `version=9999` ← 1 (تحت عتبة الحارس عمداً،
  فلا يصلحها إلا SQL مباشر).
- `bookings`: الصف ذو `version=10000` ← 1.
- لم يُمسَّ عمود `updated_at` في أي صف — لا عاصفة سحب ولا أثر على LWW.

### 5. تحقيق مصدر الحقن + صمّام أمان جديد لمسار migrate

**التحقيق (مؤكَّد)**: ناقل الحقن هو `cloudflare_migration_service.dart` —
يبني `INSERT OR REPLACE` بأعمدة السجل المحلي **حرفياً** (بما فيها
`version`) ويرسلها إلى `/api/sync/migrate` الذي ينفّذها خاماً بلا
`sync_log` ولا `sync_clock`. دليل حي: 12 دفعة عُيِّنت `version=9999`
بتوقيت 2026-09-17 01:27:06–10 UTC بتسلسل ثانية-بثانية، **دون أي أثر في
sync_log** و`sync_clock` متوقفة عند 01:21:41 — أي أن مسار الترحيل الخام
**نشط ويُعيد الحقن** (إعادة تشغيل جهاز محلي ملوث). القيم الأصلية نفسها
(1e12+n بفوارق متزايدة عبر الغرف، 9999، 10000) لا ينتجها أي كود في
المستودع الحالي — تعود لعملية استيراد/استعادة تاريخية واحدة.

**الإصلاح**: أُضيفت تمريرة `sanitizeMigrateVersions()` في
`worker/src/database.ts` تُستدعى من `handleMigrate` بعد كل دفعة ناجحة —
`UPDATE` واحد لكل جدول ملموس يُعيد أي `version > MAX_SANE_VERSION` إلى 1،
بنفس عتبة الحارس وفلسفته (القيم دون العتبة تبقى). هذا يحمي التصحيح
اليدوي أعلاه من إعادة التلوث عند أي إعادة ترحيل مستقبلية، دون أي SQL
parsing. الاختبارات: 140/140 (3 حالات جديدة: تطبيب فوق العتبة، عدم لمس
دون العتبة، وإعادة التطهيب عند إعادة الاستيراد).
