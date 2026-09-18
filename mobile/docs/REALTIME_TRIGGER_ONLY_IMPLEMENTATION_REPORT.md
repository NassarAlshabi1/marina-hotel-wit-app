# تقرير تنفيذ Appwrite Realtime Trigger-Only

## نطاق التنفيذ

تم تنفيذ التعديلات على الفرع `refactor/performance-fixes-v2` داخل مجلد `mobile`، مع الإبقاء على `appwrite: ^21.0.0` وواجهة `databases → collections → documents`. لم يُنشأ `AppwriteDeltaSync` أو `RealtimeSyncEngine`.

## الملفات المعدلة

| الملف | ما الذي تغير | السبب |
|---|---|---|
| `lib/services/appwrite_realtime_sync.dart` | إضافة `RemoteChangeQueue`، إزالة أي تطبيق مباشر للـ payload، إضافة deduplication وdebounce وsingle-flight Delta Pull، وإضافة recovery pull عند إعادة الاتصال، مع تنظيف queue عند `stop()` وإعادة التهيئة | جعل Realtime طبقة إدخال وإشارة فقط، ومنع مسار `Realtime → Drift` وعرقلة عواصف السحب |
| `lib/main.dart` | تمرير `syncManager.pullRemoteChanges` إلى `AppwriteRealtimeSync.initialize` | استخدام نقطة الدخول الحالية للسحب التزايدي بدلاً من إنشاء محرك جديد أو تشغيل `sync()` العام |
| `lib/services/fcm_service.dart` | تغيير trigger الإشعار البعيد من `sync(push: false)` إلى `pullRemoteChanges()` | توحيد الإشارات البعيدة مع مسار Delta Pull وعدم إدخال عملية رفع ضمن trigger بعيد |
| `lib/services/appwrite_realtime_service.dart` | إزالة تحديث cache المباشر من الخدمة القديمة المهملة | ضمان عدم وجود تطبيق محلي مباشر في مسار Realtime حتى في الخدمة غير الإنتاجية |
| `lib/screens/auth/google_drive_login_screen.dart` | حفظ `appwrite_pull_after_drive_skip_done` بعد نجاح Full Sync فقط | إبقاء إعادة المحاولة متاحة عند الفشل والحفاظ على دلالة علامة Bootstrap |
| `test/unit/appwrite_realtime_trigger_only_test.dart` | اختبارات deduplication، coalescing لعشرة أحداث، والحفاظ على queue عند فشل Delta Pull | تغطية سلوك Trigger-only الأساسي ومنع concurrent pull storm |

## المسار النهائي

```text
Appwrite Cloud
  → Appwrite Realtime
  → AppwriteRealtimeSync
  → RemoteChangeQueue
  → AppwriteSyncManager.pullRemoteChanges()
  → UnifiedPullEngine / Field-Level Delta
  → Drift
  → Riverpod
  → UI
```

`AppwriteRealtimeSync` لا يعدّل Drift، ولا يحل التعارضات، ولا يكتب إلى Outbox، ولا يستدعي Google Drive، ولا يشغّل Full Sync. عمليات DELETE تصل كإشارة queue فقط، ثم تعتمد إزالة السجل على tombstone والمنطق الموجود داخل مسار Delta الحالي.

## Realtime instances

| الموضع | الوظيفة | التصنيف |
|---|---|---|
| `appwrite_realtime_sync.dart` | اشتراك واحد على collections الخاصة بمزامنة البيانات وإرسال trigger إلى Delta Pull | جزء من Remote → Local data sync |
| `appwrite_realtime_service.dart` | خدمة قديمة معلّمة Deprecated، ولا توجد لها استدعاءات إنتاجية وفق تدقيق الفرع | غير مستخدمة لمسار المزامنة الحالي |
| `appwrite_messaging_service.dart` | Realtime مستقل لخدمة الرسائل/الإشعارات | ليس جزءاً من Remote → Local data sync؛ لم يُحذف تلقائياً |

`hotel_day_ledger` بقي مستبعداً من collections الخاصة بـ Realtime كما هو موثق في الكود، لأنه Local-only.

## Reconnect وLogin/Logout

عند انقطاع الاشتراك، تتم إعادة المحاولة بتأخير متزايد. عند نجاح اتصال بعد اتصال سابق، يُسجل Reconnect وتُطلق Recovery Delta Pull من خلال `pullRemoteChanges()`، وليس Full Sync. عند `stop()` تُغلق subscription وتُلغى timers وتُفرغ `RemoteChangeQueue`، وعند `initialize()` لحساب جديد يُعاد ضبط دورة الحياة.

## Full Sync وGoogle Drive وOutbox

يبقى Full Sync محصوراً في Bootstrap الصريح من شاشة المتابعة دون Google Drive، وتُكتب علامة النجاح بعد اكتمال العملية فقط. لا يستدعي Realtime Google Drive ولا Full Sync. كما أن Remote Pull يستمر عبر `pullRemoteChanges()`، بينما يبقى Outbox لمسار التغييرات المحلية إلى Appwrite.

## التحقق الفعلي

تم اجتياز `git diff --check` دون أخطاء، وبقي إصدار Appwrite دون تغيير. كما تحقق التدقيق الساكن من عدم وجود `_updateCacheOnEvent` أو cache mutation داخل ملفات Realtime الحالية، وعدم وجود استدعاء Full Sync داخل `AppwriteRealtimeSync`.

لم يمكن تشغيل `flutter analyze` أو `flutter test` في بيئة التنفيذ الحالية لأن الأمرين `flutter` و`dart` غير مثبتين أو غير موجودين في `PATH`. لذلك لا تُعرض نتيجة نجاح مصطنعة لهذين الاختبارين؛ يلزم تشغيلهما في بيئة Flutter فعلية قبل الدمج النهائي.
