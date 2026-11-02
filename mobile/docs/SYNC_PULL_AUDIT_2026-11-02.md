# تقرير مراجعة المزامنة — سحب الحجوزات وكل كيانات السحب (2026-11-02)

**النطاق:** الفرع `refactor/performance-fixes-v2`، آخر التزامين في مجلد `mobile`:

| الالتزام | العنوان |
|---|---|
| `724610cf` | fix: stop silent bookings loss in delta pull and false success on dashboard |
| `b04d9d50` | fix: stop expenses and salary-expense conflict ping-pong over device-local FK ids |

**المنهج:** قراءة الكود سطراً بسطر لمسار السحب كله: زر لوحة التحكم ← `AppwriteSyncManager.sync()` ← `UnifiedPullEngine.run()` ← دوال `_syncX` ← المحوّلات (Adapters) ← `BaseRepository.upsertFromJson`.
لم تُشغَّل الاختبارات، لأن Flutter/Dart غير مثبتين في البيئة. أرقام الأسطر تخص `lib/services/appwrite_sync_manager.dart` ما لم يُذكر ملف آخر.

---

## 0. الخلاصة التنفيذية

1. **إصلاح الحجوزات في `724610cf` صحيح في اتجاهه لكنه ناقص.** السبب الجذري الذي حدّده صحيح: المحرك يثبّت المؤشر على أقصى `$updatedAt` للمستندات **المجلوبة** لا **المطبّقة**، فيضيع أي مستند فشل تطبيقه إلى الأبد. لكن:
   - زر السحب ما زال يعرض **«✅ تم سحب التغييرات بنجاح»** عندما تكون النتيجة `failed`. أمثلة: «Sync already in progress»، انقطاع الإنترنت، مهلة القفل (§1.1).
   - الحجوزات تعتمد على الغرف، و`_syncRooms` ما زالت **تبتلع الأخطاء**. إذا ضاعت غرفة، تفشل حجوزاتها في كل دورة إلى الأبد، ولا يتحقق «الشفاء عند وصول الأب» (§1.2).
   - حجز واحد معطوب بشكل دائم يكفي لإيقاف مؤشر `bookings` نهائياً. لا توجد آلية حجر (quarantine)، ويُرسَل إلى Crashlytics تقرير **Fatal** في كل دورة (§1.3).
2. **العيب نفسه موجود في كل الكيانات الأخرى تقريباً.** لا توجد دالة سحب غير `_syncBookings` ترمي استثناءً عند بقاء مستندات غير مطبّقة. في بعضها يُعدّ المستند «مطبَّقاً» وهو لم يُكتب أصلاً، لأن `upsertFromJson` يعيد `-1` بصمت عند غياب الأب (§2).
3. **فرع تأجيل FK بالشرط `e.resultCode == 787` لا يُنفَّذ أبداً.** في `sqlite3` 3.5.0 تُعرَّف `resultCode` كـ `extendedResultCode & 0xFF`، فقيمتها 19 لا 787. التأجيل في `salary_withdrawals` و`salary_cycles` و`salary_payments` غير موجود فعلياً (§2.2).
4. **ست مهام سحب تمرّ عبر كاش مدته 6 ساعات** لأن `listDocuments` تستخدم `useCache: true` افتراضياً. «سحب التغييرات» قد لا يرى تعديلات هذه المجموعات لساعات (§3).
5. **الالتزام `b04d9d50`:** أُزيل `employeeId` من حمولة `salary_withdrawals`، بينما مخطط المشروع يعلن هذا الحقل `required`. قد يفشل إنشاء أي سحبة جديدة على السحابة إذا كان المخطط الحي مطابقاً. كذلك حارس «لا تغييرات فعلية» نادراً ما يعمل في البيانات الحقيقية (§4).

---

## 1. مسار «سحب التغييرات» في لوحة التحكم — الحجوزات

### المسار الفعلي
```
DashboardSyncButton._pullChanges  (SyncGate)
  └─ _pullChangesInner: يرفض إن كان Outbox غير فارغ (_pendingChangesCount > 0)
      └─ appwriteSyncManager.sync(push:false, pull:true)
          ├─ OutboxPullPolicy: إن وُجد Outbox غير مُسلَّم → SyncResult(idle, errorMessage)
          ├─ _currentStatus == syncing → SyncResult(failed, 'Sync already in progress')
          └─ _unifiedPull.run(_buildPullTasks())
               rooms → employees → inventory_* → bookings → cash_transactions → expenses
               → booking_nights → booking_notes → payments → debts → salary_* → ...
               لكل مهمة: plan → fetch (ترقيم كامل بالمؤشر) → apply → commit(max $updatedAt)
```

### ما يصلحه `724610cf` (تم التحقق)
- `_syncBookings` (الأسطر 2221–2486) يؤجّل أخطاء `FOREIGN KEY` و`NOT NULL` ويعيد محاولتها، ثم يرمي `StateError` إن بقيت إخفاقات (2423). عندها يُسجَّل `bookings` في `failedCollections` ولا يتقدّم مؤشرها (`unified_pull_engine.dart:233-234`).
- `BookingsAdapter` لا يستخدم `shouldSkip`. غياب الغرفة يصل كخطأ FK حقيقي لا كـ `-1` صامت، فالإصلاح فعّال لحالة الغرفة المفقودة.
- `SyncResult` أصبح يحمل `failedCollections` والحالة `partial`، والزر والسحب التلقائي يعرضان تحذيراً برتقالياً في حالة السحب الجزئي.
- جلب `listBookings` يمرّ على كل الصفحات (`_listAllDocumentsInternal`، مؤشر `$id`)، ويستخدم `useCache:false`. لا سقف ولا كاش.

### 1.1 🔴 عالٍ — الزر يعرض «نجاح» عند `SyncStatus.failed`
`dashboard_sync_button.dart:272-371`: يميّز الزر بين `wasBlocked` (أي `idle` مع رسالة) و`wasPartial` فقط، وكل ما عداهما يقع في فرع النجاح الأخضر. لكن `sync()` لا ترمي استثناءً بل **تعيد** `failed` في الحالات التالية:
- `_currentStatus == syncing` (السطر 921) تعيد «Sync already in progress». يحدث هذا عندما تكون دورة دفع/سحب من مصدر آخر جارية: `AutoOutboxSyncWatcher`، أو مؤقت الإعادة، أو realtime، إذ لا تمر كلها عبر `SyncGate`.
- مهلة القفل (السطر 1511).
- أي استثناء داخل الدورة مثل `No internet connection` (السطر 966)، فيلتقطه الـ catch ويضبط `finalStatus = failed`.

**النتيجة:** يضغط المستخدم الزر، فلا يُسحب شيء، ويظهر «✅ تم سحب التغييرات بنجاح — استُلم 0 سجل». هذا تفسير محتمل جداً لبلاغ «الحجوزات لا تُسحب» حتى بعد الالتزام، لأن الإصلاح عالج الجزئي فقط.

**الإصلاح:** أضف فرعاً لـ `pullResult.status == SyncStatus.failed` برسالة حمراء تعرض `errorMessage`، وسجّله في `sync_logs` بحالة `failed`. ويُفضَّل أيضاً اعتبار `idle` بلا رسالة (المزامنة معطّلة) حالة غير ناجحة.

### 1.2 🔴 عالٍ — اعتماد الحجوزات على `_syncRooms` التي تبتلع الأخطاء
`_syncRooms` (2158–2219): كل خطأ يُسجَّل كتحذير ثم `continue`، ولا ترمي الدالة شيئاً، فيتقدّم مؤشر `rooms`. أي غرفة فشل تطبيقها تضيع إلى الأبد. من الأمثلة الواقعية: `rooms.roomNumber` معرَّف `unique`، فإذا أنشأ جهازان رقم الغرفة نفسه بـ UUID مختلف، أو أُعيدت تسمية غرفة، يحدث تعارض UNIQUE أو FK.
بعد `724610cf` تفشل كل حجوزات تلك الغرفة بخطأ FK في **كل** دورة. لن تصل الغرفة أبداً لأن مؤشرها تجاوزها، فيبقى `bookings` في حالة `partial` دائمة ولا يتحقق «الشفاء» المذكور في رسالة الالتزام.

**الإصلاح:** طبّق النمط نفسه (تأجيل ثم رمي) في `_syncRooms`. وعند فشل FK في الحجز بسبب غرفة مفقودة، يمكن أيضاً إعادة جلب الغرفة المحددة بالمعرّف (على غرار `tombstone_parents_repull.dart`).

### 1.3 🟠 متوسط — «حبة سامة» (poison pill) بلا حجر
بعد الالتزام، أي حجز يفشل لسبب **دائم** (بيانات تالفة، UNIQUE، خطأ في `refreshForBookingId` أو `syncLegacyDiscountToAdjustments`) يسبّب ما يلي:
- يبقى مؤشر `bookings` ثابتاً للأبد. في كل دورة يُعاد جلب **كل** الحجوزات المعدّلة منذ ذلك المؤشر، فيكبر الحجم مع الوقت، وهذا مكلف على أجهزة 1GB وفق `docs/PERFORMANCE.md`.
- على جهاز جديد لا تكتمل أبداً `isFullSyncComplete('bookings')`، فيُجرى **سحب كامل** للحجوزات في كل دورة.
- يبقى `failedCollections` غير فارغ، فلا يتحدّث `lastPullTs` العام ولا `markFullSyncComplete()` (السطر 1143).
- `onTaskError` يرسل `CrashlyticsSeverity.fatal` لكل فشل في `bookings` (السطر 1132)، أي تقرير Fatal كل دورة (كل 15 دقيقة أو عند كل فتح).

**الإصلاح:** عدّاد محاولات لكل مستند (مثل جدول أو مفتاح `sync_quarantine` بالـ `$id`). بعد N محاولات يُنقل المستند إلى الحجر ويُسمح للمؤشر بالتقدم، مع ظهوره في شاشة صحة المزامنة. ويُخفَّض Crashlytics إلى non-fatal عند تكرار الخطأ نفسه.

### 1.4 🟡 منخفض/متوسط — تطبيق جزئي يُخفي المعالجة اللاحقة
داخل `applyBookingDoc` يُكتب الحجز (`upsertFromJson`) **قبل** المعالجة اللاحقة (الخصومات، `refreshForBookingId`، الإشعار). إذا نجحت الكتابة وفشل ما بعدها، تجري المحاولة الثانية (التأجيل أو الدورة التالية) كما يلي: يرى `_isRemoteDataNewer` أن المحتوى مطابق، فيعيد `return` مبكراً ويُعدّ الحجز ناجحاً. **الحقول المشتقة لا تُحسب أبداً**، والسبب أن الحقول المحسوبة لا تأتي من Appwrite وتبدأ صفراً، فيظهر الحجز «مدفوعاً بالكامل».
**الإصلاح:** نفّذ الكتابة والمعالجة اللاحقة في معاملة واحدة لكل حجز، أو نفّذ المعالجة اللاحقة دائماً عندما تكون الحقول المشتقة صفرية أو قديمة.

### 1.5 🟡 منخفض — ملاحظات أخرى على مسار الحجوزات
- **`_currentStatus` ينحرف عن النتيجة:** يُضبط على `finalStatus` في `finally` (السطر 1442) **قبل** تحويله إلى `partial` (السطر 1455). المستمعون لـ `_syncController` يرون `success` بينما النتيجة المعادة `partial`.
- **السحب التلقائي يكتم المحاولة التالية:** `dashboard_screen.dart:152` يكتب `lastAppOpenPullKey` حتى عند الفشل أو الحجب أو السحب الجزئي، فلا يحاول السحب التلقائي مرة أخرى قبل ساعة (`appOpenSyncInterval`).
- **عدم توحيد وحدات الزمن:** فرع LWW للتعارض المتزامن في `sync_pull_service.dart:290-293` يقارن `normalizedRemoteTs` بـ `localLastModified` **غير المُطبَّع**. إن كان المحلي بالميلي ثانية فلن يفوز البعيد أبداً.
- **عدّ غير دقيق:** حالات التخطي (المحتوى مطابق) تُحسب ضمن `processed`، فالعدد «استُلم N سجل» يشمل سجلات لم تتغير.
- **أثر جانبي على المنسّق:** `unified_sync_orchestrator.dart:512` أصبح يعتبر `partial` فشلاً (`isSuccess == false`). هذا مقصود، لكن يجب التأكد من أنه لا يطلق إعادة محاولة أو backoff عنيفاً.

---

## 2. مراجعة كل كيانات السحب

**الآلية المشتركة للفقدان:** `UnifiedPullEngine.commit` يثبّت `max($updatedAt)` لكل المستندات المجلوبة. أي دالة `apply` تعود بشكل طبيعي رغم فشل مستند تعني **فقداناً دائماً** لذلك المستند في كل سحب دلتا لاحق. وفي `booking_nights` يتقدّم أيضاً مؤشر صفحة السحب الكامل.

**آلية `-1` الصامتة:** `base_repository.dart:92-98` يعيد `-1` بلا استثناء عندما يضع المحوّل `shouldSkip`، أي عند عدم وجود الأب. لا أحد من المستدعين يفحص `-1`: يُعدّ المستند `processed++` ويُرسَل إشعار «تغيير بعيد» وكأنه طُبِّق.

### 2.1 جدول الكيانات

| الكيان | الدالة (سطر) | معالجة الفشل | يرمي في النهاية؟ | تخطٍّ مؤقت = فقدان | الخطورة |
|---|---|---|---|---|---|
| rooms | `_syncRooms` 2158 | يُسجَّل ثم يتابع | ❌ | لا يوجد، لكن UNIQUE/FK على `roomNumber` يُبتلع | 🔴 (أب الحجوزات) |
| employees | `_syncEmployees` 2496 + `_syncEmployeesWithRetry` 10125 | يُسجَّل لكل مستند ثم يتابع، و**غلاف الإعادة يعيد `lastCount ?? 0` بلا إعادة رمي** (10166) | ❌ | فشل الدفعة كاملة يُقدّم مؤشر **كل** الموظفين | 🔴 (أب الرواتب والمصروفات) |
| inventory_items | 8031 | يُسجَّل ثم يتابع | ❌ | — | 🟠 |
| inventory_transactions | 8078 | يُسجَّل ثم يتابع | ❌ | الصنف غير موجود ← `shouldSkip` ← `-1` يُعدّ نجاحاً (`inventory_adapter.dart:191-196`) | 🔴 |
| bookings | `_syncBookings` 2221 | تأجيل FK/NOT NULL ثم رمي ✅ | ✅ | — (انظر §1) | ✅ مع ملاحظات |
| cash_transactions | 8584 | يُسجَّل ثم يتابع | ❌ | — | 🟠 (أب `payments.cashTransactionLocalId`) |
| expenses | `_syncExpenses` 2570 | يُسجَّل ثم يتابع | ❌ | `cashTransactionId` يُكتب `null` إن لم تصل الحركة النقدية بعد، ولا توجد إعادة ربط لاحقة عبر `cashFlowUuid` | 🟠 |
| booking_nights | 8272 | تأجيل FK/`shouldSkip`، لكن الإعادة **فورية في الاستدعاء نفسه** فلا تنجح عادة، وتُعدّ `-1` نجاحاً (8441)، والأخطاء الأخرى تُبتلع (8389، 8572) | ❌ (ومؤشر الصفحة يتقدّم) | ليلة وصلت قبل حجزها تضيع | 🔴 |
| booking_notes | 8186 | يُسجَّل ثم يتابع | ❌ | الحجز غير موجود ← `-1` يُعدّ نجاحاً (`booking_notes_adapter.dart:44`) | 🔴 |
| payments | `_syncPayments` 2673 | تأجيل نصّي FK/NOT NULL، والإعادة فورية، والفشل النهائي يُبتلع (2776-2799) | ❌ | + **`cashTransactionLocalId` يُرفع ويُخزَّن كمعرّف محلي خام** لجهاز المصدر (`payments_adapter.dart:133-138`، `payload_mapper.dart:247-251`)، فتُربط الدفعة بحركة نقدية خاطئة أو يفشل FK. إصلاح `b04d9d50` لم يشمل الدفعات | 🔴 |
| debts | `_syncDebts` 2805 | مثل payments | ❌ | المسار الأول لا يرسل `onRemoteRecordApplied` (المؤجَّل يرسله) | 🟠 |
| salary_cycles | 8636 | `resultCode == 787` (فرع ميت، انظر §2.2)، والباقي يُبتلع | ❌ | **الموظف غير موجود ← `continue` إلى قائمة `orphans` تُسجَّل فقط** (8702-8708) | 🔴 |
| salary_payments | 8794 | `resultCode == 787` (ميت) | ❌ | الدورة غير موجودة ← `shouldSkip` ← `-1` يُعدّ نجاحاً. التعليق في 8825 يقول إنها تؤجَّل، وهذا غير صحيح | 🔴 |
| salary_withdrawals | `_syncSalaryWithdrawals` 4148 | طابور أيتام دائم في SharedPreferences ✅، لكن `787` ميت، والفشل المؤجَّل النهائي لا يُعاد إلى طابور الأيتام، **والطابور يُسقط بصمت بعد 500** (4454-4463)، وفشل قراءته يعيد `[]` ثم يُكتب فوقه (4412، 4448) | ❌ | المسار المؤجَّل يعيد بناء `data` من `doc.data` الخام فيُفقد ربط الموظف **ونتيجة الدمج الثلاثي** | 🔴 |
| guest_infos | 4016 | يُسجَّل ثم يتابع | ❌ | — | 🟠 |
| booking_price_adjustments | 8901 | تأجيل نصّي غير قابل للوصول عملياً، و`-1` يُعدّ نجاحاً | ❌ | الحجز غير موجود ← `-1` (`booking_price_adjustments_adapter.dart:37-60`). التسجيل «after all bookings synced» في 8986 غير صحيح لأن الإعادة فورية | 🔴 (سعر الحجز خاطئ على الجهاز الآخر) |
| shift_notes | 8127 | يُسجَّل ثم يتابع | ❌ | فحص «الأحدث» يقرأ بـ `createdBy='user'` بينما الكتابة على `local_uuid` فقط، فقد يُكتب فوق صف blacklist يشترك في الـ UUID | 🟠 |
| blacklist | 7308 | يُسجَّل ثم يتابع | ❌ | `deletedAtVal as String?` يرمي إذا كانت القيمة رقمية (7357)، والإصدار المحلي `existing.version + 1` بدل البعيد (7425) | 🟡 |
| price_adjustments | 9035 | يُسجَّل ثم يتابع | ❌ | **يكتب `rooms.price = newValue` لأي تعديل مطبَّق** (9074-9094) دون فحص `isReversed` أو `deletedAt` أو الأحدث. tombstone لتعديل قديم يعيد سعر الغرفة إلى قيمة قديمة | 🟠 |
| audit_logs | 9139 | يُسجَّل ثم يتابع | ❌ | — | 🟡 |
| payment_voids | 9428 | يُسجَّل ثم يتابع | ❌ | `originalPaymentUuid` فريد، فإلغاء ثانٍ من جهاز آخر يضيع بخطأ UNIQUE | 🟠 |
| salary_carry_over_logs | 9484 | يُسجَّل ثم يتابع | ❌ | الموظف غير موجود ← `-1` يُعدّ نجاحاً (`salary_carry_over_logs_adapter.dart:52-70`)، ولا يوجد طابور أيتام مثل السحبات | 🔴 |
| app_settings | 9342 (معطّل: `appSettingsSyncEnabled = false`) | يُسجَّل ثم يتابع | ❌ | **كامن:** الدفع يشفّر `wa_api_token`/`telegram_bot_token`، والسحب يكتب النص المشفّر كما هو، ولا يُستدعى `decryptValue` في أي مكان. عند تفعيل المزامنة ستتلف الرموز | 🟠 كامن |

### 2.2 🔴 فرع `e.resultCode == 787` ميت (تم التحقق من مصدر الحزمة)
`sqlite3` 3.5.0 (`pubspec.lock`) تعرّف الحقلين كما يلي (`lib/src/exception.dart`):
```dart
final int extendedResultCode;
int get resultCode => extendedResultCode & 0xFF;   // 787 & 0xFF = 19
```
لذلك الشرط في الأسطر 4310 و8729 و8846 لا يتحقق أبداً، وكل أخطاء FK في `salary_withdrawals` و`salary_cycles` و`salary_payments` تُعامل كفشل نهائي وتُبتلع.
**الإصلاح:** استخدم `e.extendedResultCode == 787`، أو `e.resultCode == 19` مع فحص النص، أو المطابقة النصية كما في `_syncBookings`.

### 2.3 🟠 التأجيل «داخل الاستدعاء نفسه» لا يشفي أباً من مجموعة أخرى
في `payments` و`debts` و`booking_nights` و`booking_price_adjustments` و`salary_*` تجري الإعادة فوراً داخل الدالة نفسها، ولم يتغير شيء بين المحاولتين لأن الأب (الحجز أو الموظف) من مجموعة سحبت قبلها. هذا التأجيل لا يفيد إلا عندما يكون الأب في الدفعة نفسها، أي في حالة `bookings` فقط. **الشفاء الحقيقي يتطلب عدم تقدّم المؤشر** (الرمي) حتى تعيد الدورة التالية الجلب.

---

## 3. 🔴 كاش 6 ساعات على ست مهام سحب
`_buildPullTasks` (السطور 6032–6101) تستدعي `appwriteService.listDocuments(...)` **بدون** `useCache: false` للمجموعات التالية:
`booking_price_adjustments`، `price_adjustments`، `audit_logs`، `payment_voids`، `salary_carry_over_logs`، `app_settings`.

`listDocuments` ← `listRows(useCache: true)` ← `_listAllDocumentsInternal` تبني مفتاح كاش من نص الاستعلامات (`appwrite_service.dart:176`) بمدة `AppwriteConfig.cacheExpiry = 6h`.
في وضع الدلتا يبقى الاستعلام `greaterThan($updatedAt, checkpoint-300)` ثابتاً ما دام المؤشر لم يتغير، أي في الحالة المعتادة «لا جديد». فتعيد الدورات التالية القائمة المخزّنة (غالباً فارغة) لمدة تصل إلى 6 ساعات، و**لا يرى زر السحب تعديلات الأسعار أو إلغاءات الدفعات الجديدة**. لا يوجد في مسار السحب أي `clear()` للكاش.
**الإصلاح:** أضف `useCache: false` للمهام الست. ويُفضَّل أن يمنع `_listAllDocumentsInternal` الكاش عند وجود فلتر `$updatedAt`.

---

## 4. مراجعة `b04d9d50` (معرّفات FK المحلية في المصروفات والرواتب)

| # | الخطورة | الملاحظة |
|---|---|---|
| 4.1 | 🔴 عالٍ (يحتاج تأكيداً على المخطط الحي) | `payload_mapper.dart:797-806` أزال `employeeId` من حمولة `salary_withdrawals`، بينما `appwrite_schema_verifier.dart:622` و`scripts/appwrite/schema/Final_setup_all_collections.js:420` يعرّفانه `integer, required: true`. إن طابق المخطط الحي ذلك، فإن **إنشاء أي سحبة جديدة يفشل بخطأ 400 «Missing required attribute»**، ويعلق في Outbox، ثم يحجب Outbox السحب كله على ذلك الجهاز (`OutboxPullPolicy`). التحديثات لا تتأثر. **الإجراء:** افحص المخطط الحي، فإما أن تجعل الحقل اختيارياً أو تعيده إلى الحمولة. |
| 4.2 | 🟠 | `employeeId` لم يكن بلا معنى تماماً: بعد دفع الموظف يُضبط `employees.serverId = employee.id` (≈4615)، والسحب يحلّ بـ `serverId: remoteEmployeeId` (4242-4248، `id_resolver.dart:274-299`). إزالته تُسقط مسار الحل الاحتياطي، و**الإصدارات الأقدم من التطبيق** على أجهزة أخرى تعتمد عليه، فتتيتّم سحبات الأجهزة المحدّثة عندها. كما أن الدفع الجماعي (≈6762-6776) يأخذ `employeeUuid` من الموظف المرتبط فقط ويتجاهل عمود `employeeUuid` في السحبة نفسها. |
| 4.3 | 🟠 | حارس «لا تغييرات فعلية» في `smart_conflict_resolver.dart:409-420` لا يعمل إلا إذا كانت مجموعتا الحقول المتغيرة فارغتين. لكن `_findChangedFields` في `conflict_detector.dart` ما زال يعدّ `syncTimestamp` (يتغير في كل دفع) و`sync_origin` و`deviceId` و`origin` و`lastModifiedEpoch`، فلا يعمل الحارس في البيانات الحقيقية تقريباً. الاختبار ينجح لأن بياناته الوهمية لا تحتوي هذه الحقول. وعندما يعمل، يُهمَل ناتجه `localWins` لأن `checkAndResolveConflict` لا يستخدم إلا `fieldLevelMerge` (`sync_pull_service.dart:246`) ثم يرجع إلى LWW. **حلقة ping-pong قد لا تكون أُغلقت فعلياً.** |
| 4.4 | 🟡 | قائمة الاستبعاد تضم `booking_id` (`conflict_detector.dart:304`، `sync_pull_service.dart:364`)، وهو الاسم snake_case للرابط المحمول `serverBookingId` في محوّلات الحجوزات والدفعات والديون والليالي. Appwrite يرسل camelCase حالياً فلا أثر حيّ، لكنه فخ مستقبلي. |
| 4.5 | 🟡 | `booking_notes` ترفع `bookingId` الرقمي فقط بلا UUID (`payload_mapper.dart:418`)، فلا رابط محمول لها أصلاً. الفجوة سابقة للالتزام، لكن الاستبعاد الجديد يخفي أي اختلاف فيها. |
| 4.6 | 🟡 | `ExpensesAdapter` يكتب الآن `relatedId = null` للمصروفات غير المتعلقة بالرواتب، و`cashTransactionId = null` عند غياب `cashFlowUuid`، حتى على الجهاز المنشئ نفسه عند سحب نسخته. الأثر محدود حالياً لأن الحقلين لا يُقرآن في منطق الأعمال. |
| 4.7 | ✅ | `_expenseToRemoteWithEmployeeLink` (≈4947-4964) سليم ومستخدم في مساري الدفع (Outbox والدفع الجماعي). |

---

## 5. خطة إصلاح مقترحة (حسب الأولوية)

1. **زر لوحة التحكم:** فرع صريح لـ `SyncStatus.failed`، وعدم كتابة `lastAppOpenPullKey` عند الفشل أو الحجب أو السحب الجزئي (§1.1، §1.5).
2. **`useCache: false`** للمهام الست في `_buildPullTasks` (§3). تغيير من سطر واحد لكل مهمة وأثره فوري.
3. **عقد موحّد لكل `_syncX`:** معاملة `-1` من `upsertFromJson` كتأجيل لا كنجاح، ثم `throw StateError` إن بقي أي مستند غير مطبّق (تعميم نمط `724610cf`). الأولوية للآباء: `rooms` و`employees` (وإزالة ابتلاع الخطأ في `_syncEmployeesWithRetry`) و`cash_transactions`، ثم الأبناء: `booking_nights` و`booking_notes` و`booking_price_adjustments` و`payments` و`debts` و`salary_*` و`inventory_transactions` و`salary_carry_over_logs`. في المسار التدفقي لـ `booking_nights` لا يتقدّم `full_sync_cursor` إلا بعد نجاح الصفحة كاملة.
4. **إصلاح `resultCode == 787`** إلى `extendedResultCode` (§2.2).
5. **آلية حجر للحبة السامة** مع حد محاولات لكل `$id`، وخفض Crashlytics إلى non-fatal للتكرار (§1.3). ضرورية **قبل** تعميم البند 3، وإلا قد يتوقف مؤشر مجموعات كثيرة بسبب سجل واحد معطوب.
6. **`payments.cashTransactionLocalId`:** الحل عبر UUID الحركة النقدية بدل المعرّف الخام (§2.1)، استكمالاً لمنطق `b04d9d50`.
7. **التحقق من مخطط `salary_withdrawals.employeeId` الحي** قبل نشر `b04d9d50` (§4.1).
8. **حارس no-op في `SmartConflictResolver`:** استبعاد حقول البيانات الوصفية (`syncTimestamp`/`sync_origin`/`deviceId`/`origin`/`lastModifiedEpoch`) من `_findChangedFields`، واحترام `localWins` في `checkAndResolveConflict` (§4.3).
9. **ملاحظات ثانوية:** ترتيب `_currentStatus` مع `partial`، وتطبيع الزمن في فرع LWW، و`price_adjustments` ← `rooms.price`، وطابور أيتام السحبات (سقف 500 والكتابة فوقه).

## 6. اختبارات مقترحة (درع انحدار)
- زر لوحة التحكم مع `SyncResult(status: failed)` يجب ألا يعرض نص «بنجاح».
- لكل كيان ابن: أب مفقود ثم `apply` يرمي، ولا يتقدّم المؤشر. وصول الأب في الدورة التالية يطبّق الابن.
- `SqliteException` بـ `extendedResultCode = 787` يُصنَّف FK.
- مهمة سحب بفلتر `$updatedAt` لا تقرأ من الكاش.
- حبة سامة: بعد N محاولات يُحجر المستند ويتقدّم المؤشر.
