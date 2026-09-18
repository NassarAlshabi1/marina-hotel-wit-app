# 🏗️ مسار Realtime → Delta المعماري — 2026-09-01

**الفرع:** `perf/appwrite-sync-pull-reduction`
**النطاق:** إعادة توحيد مسار Remote → Local وإزالة fast-apply نهائياً

---

## 1. المسار الوحيد المقبول (مُنفَّذ ومُختبر)

```
Appwrite Cloud
      ↓
Appwrite Realtime (WebSocket)
      ↓
AppwriteRealtimeSync          ← اشتراكات + تصفية self-events + طابور + إعادة اتصال
      ↓
طابور الأحداث (دور RemoteChangeQueue)   ← debounce 500ms + cooldown 15s
      │                                   + in-flight guard + trailing queue
      ↓
AppwriteSyncManager.sync(push, pull, realtimePriority, deltaOnly:true)
      ↓
SyncPullService (Delta Pull — metadata-first + tombstone-aware)
      ↓
Field-Level merge (checkAndResolveConflict / SmartConflictResolver)
      ↓
Drift
      ↓
Riverpod (StreamProviders)
      ↓
UI
```

**المسارات الممنوعة — مُثبتة إزالتها:**

| المسار الممنوع | الإثبات |
|---|---|
| `Realtime → Drift` مباشر | `setFastApplyHandler`/`applyRemoteRecordFast` حُذفا من الكود؛ اختبار A1 يثبت عدم وجود أي كتابة قبل الديبونس |
| `Realtime → Fast Apply → Drift` | كتلة fast-apply في `handleRemoteDataChange` أُزيلت (سابقاً L397-433) + typedef `FastRecordApply` حُذف |
| `Realtime → Full Sync` | trigger يمرر `deltaOnly: true` — في bootstrap يُتخطى السحب كلياً (اختبار D2: صفر قراءات شبكة) |
| `Realtime → Sync Engine جديد` | لم يُنشأ أي محرك جديد — نفس `AppwriteSyncManager`/`SyncPullService` |
| `Remote Pull → Outbox` | مسار التطبيق يكتب بـ `enqueueOutbox: false` (manager L~3244/3270) + اختبار B يفحص outbox |

## 2. Realtime instances في المشروع (نقطة 9)

| Instance | الموضع | الحالة | القرار |
|---|---|---|---|
| `AppwriteRealtimeSync` | `appwrite_realtime_sync.dart` | **الوحيد النشط** — WebSocket واحد لكل الكولكشنات | هو المسار المعتمد |
| `AppwriteRealtimeService` | `appwrite_realtime_service.dart` | `@Deprecated` — لا يُستدعى من أي مسار إنتاجي (لا initialize ولا subscribe)؛ فقط `disposeInstance()` عند logout (main.dart:1078) | لا حذف — موثق كغير مستخدم؛ لا يُشارك في المزامنة |
| Messaging Realtime | `appwrite_messaging_service.dart:285` | معطّل بثابت `_useRealtimeNotificationFallback = false` (L84) — FCM هو مسار الإشعارات | **ليس جزءاً من Remote → Local** — لا حذف تلقائي (المواصفة) |

إثبات التوحيد: instance نشط واحد فقط للمزامنة، والاشتراك عبر قنوات متعددة في **اتصال WS واحد**.

## 3. طابور الأحداث — دور RemoteChangeQueue (نقطة 4)

لا توجد class باسم `RemoteChangeQueue` في المشروع — ولم تُنشأ (المواصفة: لا طبقات جديدة؛ استخدم الآلية الحالية إن كانت كافية). **الآلية الحالية داخل `AppwriteRealtimeSync` تؤدي الوظيفة كاملة:**

| متطلب الطابور | التنفيذ الحالي |
|---|---|
| Queue | `handleRemoteDataChange` → debounce timer 500ms (`debugEventDebounce` للاختبار) |
| Deduplicate | مؤقت الديبونس يُلغى ويُعاد مع كل حدث — دفعة أحداث = إطلاق واحد |
| Coalesce/Debounce | `realtimeEventPullCooldown` (15s) + `_pullQueued` (trailing) |
| Controlled pull | `_triggerInFlight` guard — يستحيل سحبان متزامنان |

**إثبات:** اختبار C — 10 أحداث متتالية → ≤ 2 سحبة متتالية (1 جارية + 1 متابعة) وأقصى تزامن = 1.

## 4. جدول الكيانات (نقطة 10) — Remote / Realtime / Delta

| Entity | Remote | Realtime | Delta | Local-only | Reason |
|---|---|---|---|---|---|
| rooms | ✅ | ✅ | ✅ | — | تُعدَّل من أي جهاز |
| bookings | ✅ | ✅ | ✅ | — | تُعدَّل من أي جهاز |
| booking_notes | ✅ | ✅ | ✅ | — | ملاحظات الحجوزات |
| booking_nights | ✅ | ✅ | ✅ | — | ليالٍ الحجوزات (2018 صف) |
| payments | ✅ | ✅ | ✅ | — | مالية حرجة |
| expenses | ✅ | ✅ | ✅ | — | مالية حرجة |
| cash_transactions | ✅ | ✅ | ✅ | — | مالية |
| debts | ✅ | ✅ | ✅ | — | مالية |
| employees | ✅ | ✅ | ✅ | — | تُدار مركزياً |
| salary_cycles | ✅ | ✅ | ✅ | — | رواتب |
| salary_payments | ✅ | ✅ | ✅ | — | رواتب |
| salary_withdrawals | ✅ | ✅ | ✅ | — | رواتب (601 صف) |
| salary_carry_over_logs | ✅ | ✅ **(جديد)** | ✅ | — | كانت تُسحب بلا اشتراك — تغييرها من جهاز آخر يتأخر 15د/ساعة |
| shift_notes | ✅ | ✅ | ✅ | — | ملاحظات الورديات |
| guest_infos | ✅ | ✅ | ✅ | — | بيانات النزلاء |
| price_adjustments | ✅ | ✅ | ✅ | — | تعديلات أسعار |
| booking_price_adjustments | ✅ | ✅ | ✅ | — | تعديلات أسعار الحجوزات |
| blacklist | ✅ | ✅ **(جديد)** | ✅ | — | قائمة سوداء تُدار من أي جهاز |
| inventory_items | ✅ | ✅ **(جديد)** | ✅ | — | حركة مخزون من أجهزة متعددة |
| inventory_transactions | ✅ | ✅ **(جديد)** | ✅ | — | حركة مخزون من أجهزة متعددة |
| app_settings | ✅ | ✅ **(جديد)** | ✅ | — | إعدادات تُعدَّل مركزياً |
| payment_voids | ✅ | ✅ | ✅ | — | إلغاءات مدفوعات |
| audit_logs | ❌ | ❌ | ❌ | — | مستبعدة من المزامنة كلياً (e1975be) |
| hotel_day_ledger | ❌ | ❌ | ❌ | ✅ | محلي فقط (appwrite_config L59-60) — No Realtime / No Pull |
| devices / sync_logs / sync_state / app_users | بنية تحتية | ❌ | — | — | ليست بيانات عمل تُسحب |

**الإضافة (2026-09-01):** 5 كيانات Remote كانت تُسحب دلتا لكن **بلا اشتراك Realtime** — أُضيفت لقائمة الاشتراكات (الآن 22 قناة على WS واحد). Delta-only في السحب يبقى هو الأسلوب لكل الكيانات (وثّق أعلاه).

## 5. Recovery بعد إعادة الاتصال (نقطة 6 — إلزامي)

- فقدان الاتصال (`onDone`/`onError`/استسلام) → `_pendingRecoveryPull = true`.
- عودة التطبيق (`ensureStarted`) → تعليم الاسترداد.
- نجاح الاشتراك (`onSubscriptionEstablished`) → إن وُجد تعليم: **Delta Pull واحد** عبر نقطة الدخول الحالية + `[DeltaSync] recovery pull started`.
- في bootstrap يُتخطى السحب (D2) — لا Full من الخلفية أبداً.
- الاشتراك الأول عند الإقلاع لا يُطلق استرداداً (فحص فتح التطبيق مسؤول).

## 6. Full Sync وBootstrap (نقطة 7)

- Realtime/fallback/staleness-guard: كلها `deltaOnly: true` — يستحيل Full من الخلفية.
- Bootstrap الصريح الوحيد: "المتابعة بدون مزامنة Google Drive" → `pullAllDataWithDisabledFK()` (تُرجع `Future<bool>` الآن):
  - SUCCESS (`true`) → العلم `appwrite_pull_after_drive_skip_done = 1` **يُضبط بعد الاكتمال فقط** (إصلاح: كان يُضبط قبل السحب — فشل يترك العلم مرفوعاً بلا سحب!).
  - FAILURE (`false`) → العلم يبقى فارغاً → إعادة المحاولة ممكنة (اختبار H2/H3).
- دلالات العلم نفسها لم تتغير (علامة اكتمال الـ bootstrap الصريح) — توقيت الضبط صُحح فقط.
- شاشة الصيانة تزيل العلم عند تصفير البيانات المحلية — دون تغيير.

## 7. Self-events وMetadata (نقطة 12) — بلا تغيير

- التصفية الحالية: `payload['device_id'] ?? payload['lastModifiedBy'] == _currentDeviceId → تجاهل` — echo الرفع لا يعود كدورة سحب.
- الحقول الحالية كما هي: `deviceId / lastModifiedBy / origin / lastModified / version / vectorClock` — **لم تُضف حقول** (نقطة 18).
- حلقة Local Push → Realtime → Delta → Push مستحيلة: echo مُصفّى + push-echo immunization (تطابق الطوابع في `computeChangedIds`).

## 8. Outbox وGoogle Drive وRiverpod (نقاط 13-16) — إثباتات

- **Outbox:** LOCAL CHANGE → Drift → Outbox → Appwrite. مسار السحب يكتب بـ `enqueueOutbox: false` — Remote Pull لا ينشئ Outbox أبداً. `OutboxPullPolicy` يمنع السحب فوق Outbox غير مفروغ.
- **Google Drive:** `appwrite_realtime_sync.dart` لا يستورد أي Drive service؛ لا استدعاء Drive في pull/realtime. الفصل كامل.
- **Riverpod/UI:** لا `setState` خاص بـ Realtime — البيانات تصل عبر Drift → StreamProviders. `hasRemoteChanges`/`pendingRemoteChangesCount` شارات UI فقط (وليست مسار بيانات).
- **Manual Sync:** `DashboardSyncButton` → `sync(forcePull: true)` — بلا أي تعديل.

## 9. SDK وAPI (نقاط 8 و20)

- `appwrite: ^21.0.0` — دون تغيير؛ `databases → collections → documents` كما هي؛ لا TablesDB/Rows.
- لا ترقية SDK، لا تعديل schema، لا حقول جديدة.

## 10. Logging (نقطة 19)

الصيغة الموحدة المضافة/الموثقة:
```
[Realtime] connected — subscribed: 22 collections (delta pull enabled)
[Realtime] event: …payments.update — queued (merged by debounce), triggering delta pull
[Realtime] triggering delta pull
[DeltaSync] pull started / pull completed
[Realtime] disconnected — stream error / stream done / intentional stop
[Realtime] reconnecting (attempt n/6)
[Realtime] reconnected — recovery pull scheduled
[DeltaSync] recovery pull started
```
لا يُسجل أبداً: API keys/tokens/passwords/session secrets (الحمولات لا تُطبع محتواها أصلاً — dlog فقط رسائل).

## 11. الاختبارات الإلزامية (نقطة 17)

`test/services/realtime_pipeline_architecture_test.dart` — ملف جديد يغطي:

| # | الاختبار | ما يثبته |
|---|---|---|
| A1 | حدث تعديل من جهاز آخر | لا كتابة قبل الديبونس (لا fast-apply) → Delta Pull يجلب من الخادم → merge → Drift |
| A2 | بلا trigger | صفر كتابة في Drift — لا مسار بديل |
| B | تعديل بعيد (field-level) | receive → queue → delta → merge (اسم محدّث من جهاز B) → Drift |
| C | عاصفة 10 أحداث | ≤ 2 سحبة متتالية + أقصى تزامن = 1 (لا pull storm) |
| D1 | disconnect → reconnect | Delta Pull واحد يستدراك الفاقد بالكامل |
| D2 | استرداد في bootstrap | صفر قراءات — لا Full Sync من Realtime |
| E | Remote delete | Queue → Delta → tombstone → local delete (لا حذف مباشر من الحدث) |
| F | Logout/Login | إغلاق + إفراغ الطابور؛ لا أحداث متأخرة بعد stop؛ اشتراك جديد نظيف |
| G | Realtime غير متاح | المزامنة اليدوية تعمل كالمعتاد |
| H1-H3 | Bootstrap flag | success → flag بعد الاكتمال؛ failure → flag فارغ + retry؛ idempotent |

+ تحديث `realtime_full_enable_test.dart` و`realtime_priority_sync_integration_test.dart` و`sync_metadata_first_integration_test.dart` (DT5) للتواقيع الجديدة، وحذف `realtime_record_level_fast_path_test.dart` (موضوعه أُزيل).

## 12. الملفات المتغيرة

| الملف | ما تغيّر | لماذا |
|---|---|---|
| `lib/services/appwrite_realtime_sync.dart` | إزالة fast-apply كلياً؛ `RemoteChangePull` بلا وسائط؛ `onSubscriptionEstablished` + استرداد reconnect؛ +5 اشتراكات؛ logging موحد؛ خطافات اختبار | النقطة الأهم: لا مسار Realtime → Drift |
| `lib/main.dart` | trigger بلا وسائط + `deltaOnly: true`؛ حذف `setFastApplyHandler` | لا Full من Realtime؛ المسار الوحيد |
| `lib/services/appwrite_sync_manager.dart` | حذف `fastAppliedEntities`/`_activeFastAppliedEntities`/`applyRemoteRecordFast`/كتلة fast-path؛ `pullAllDataWithDisabledFK` → `Future<bool>` | إزالة كل بنية fast-apply؛ علم bootstrap بعد النجاح |
| `lib/screens/auth/google_drive_login_screen.dart` | العلم يُضبط فقط إذا أعاد السحب `true` | FAILURE → retry ممكن (نقطة 7) |
| `mobile/scripts/APPWRITE_INDEX_AUDIT…` (سابق) + هذا الملف | توثيق | نقطة 10/21 |
