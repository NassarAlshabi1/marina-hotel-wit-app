# تقرير الإصلاحات الكامل — مزامنة Appwrite + خطوط CI

**الفرع:** `arena/20569ff5-marina-hotel-wit-app`
**نقطة الأساس:** `8dda3d7` (2026‑11‑02) — آخر حالة على `refactor/performance-fixes-v2`
**رأس الفرع:** `9d24b71`
**حالة Actions على رأس الفرع:** كل التشغيلات ✅ ناجحة (التفاصيل في §7)

---

## 1) الملخص التنفيذي

| المجال | ما كان معطلاً | ما صار |
|---|---|---|
| سحب Appwrite | **9 مجموعات** كانت **تُبتلع** فيها أخطاء المستند الواحد ثم يتقدّم المؤشر فوقها ⇒ فقدان صامت دائم | **24 من 25** دالة تُسجّل الفشل فلا يتقدّم مؤشرها (المتبقية `_syncEmployeesWithRetry` غلاف إعادة محاولة لا تطبيق سحب) |
| مجموعة متعثرة | مستند تالف واحد يحجب مجموعته **إلى الأبد** (إعادة سحب نافذة متضخمة كل دورة) | تراجع تدريجي `0, 0, 15د, 30د, 1س … ≤6س` **بلا أي مساس بدلالات المؤشر** |
| تغيير مشروع Appwrite | مؤشرات SQLite لا تحمل هوية الهدف ⇒ بعد الانتقال `6a4408f3 → 6ae118bc` تُتخطّى مستندات بصمت | بصمة `endpoint\|project\|database` ⇒ تصفير لمرة واحدة وسحب كامل |
| المراجع الأب | `upsertFromJson` يعيد `-1` عند أب غير محلول وكان يُحسب نجاحاً | `-1` يُضاف إلى `failed` في 8 مجموعات |
| CI (`Dart Format`) | فشل دائم في كل الفروع ⇒ `Run tests` لا يُنفَّذ أبداً | ✅ ينجح، والاختبارات تُنفَّذ فعلاً |
| Security (`Trivy`) | فشل تثبيت Trivy على Ubuntu 24.04 ⇒ سقوط الـ workflow كله | ✅ التثبيت + كل الفحوص تمر |
| بوابة الجوال | فحص التنسيق كان **بلا أثر** (ينجح دائماً) | فحص حقيقي بـ `--set-exit-if-changed` |

---

## 2) منهجية التشخيص

لم يُعتمد أي تخمين: كل سبب جذري أدناه مُثبت بمقارنة الكود مع نقطة الأساس `b1d29fa` (2026‑10‑22) وقياس فعلي على الشجرة، وكل إصلاح أُرفق باختبار وحدة أو أُثبت عبر CI الحقيقي (runner فيه Flutter 3.44.6).

الفرق بين نقطة الأساس و`8dda3d7`: **32 كوميت، 79 ملفاً، +7116/−1368**.

---

## 3) أعطال المزامنة — التشخيص والإصلاح بالتفصيل

### 3.1 الفقدان الصامت (Silent loss) — السبب الجذري الأول

**العرض:** مستند يفشل تطبيقه محلياً (قيد NOT NULL، أب غير موجود، …) لا يظهر في أي مكان، ثم تتقدّم المزامنة التالية فوقه فلا يُسحب مرة أخرى.

**السبب (بالقياس على الكود نفسه):**

| | نقطة الأساس `b1d29fa` | `8dda3d7` | بعد الإصلاح `9d24b71` |
|---|---|---|---|
| دوال `_sync*/_apply*` الكلية | 25 | 25 | 25 |
| التي تُسجّل فشلاً (`failed.add`) | **0** | **14** | **24** |
| التي تبتلع الخطأ فعلياً (ثغرة) | 23 | **9** | **0** |

المجموعات التسع التي كانت تبتلع أخطاء المستند الواحد على مستوى المستند (فتُعيد `recordsPulled` بلا فشل ⇒ `failedCollections.isEmpty` ⇒ يتقدّم المؤشر الشرعي والعالمي `last_pull_ts` فوق المستندات المفقودة):

`expenses · guest_infos · inventory_items · shift_notes · cash_transactions · price_adjustments · audit_logs · payment_voids · blacklist`

**الإصلاح:** كل خطأ مستند يُضاف إلى `failed` (الذي يمنع `commit` للمؤشر). الغطاء الآن **24 من 25** دالة، والمتبقية الوحيدة ليست ثغرة:
- `_syncEmployeesWithRetry` — ليست تطبيق سحب أصلاً، بل غلاف إعادة محاولة حول `_syncEmployees` (التي تُسجّل الفشل).

(`_syncAppSettings` كانت في الدفعة الأولى استثناءً مقصوداً لأنها غير حرجة؛ في الدفعة الثانية صارت تُسجّل الفشل وتُرميه أيضاً — انظر §12.)

قائمة الدوال التي تُسجّل الفشل الآن:
`_applyNightBatchEntries, _syncAuditLogs, _syncBlacklist, _syncBookingNights, _syncBookingNotes, _syncBookingPriceAdjustments, _syncBookings, _syncCashTransactions, _syncDebts, _syncEmployees, _syncExpenses, _syncGuestInfos, _syncInventoryItems, _syncInventoryTransactions, _syncPaymentVoids, _syncPayments, _syncPriceAdjustments, _syncRooms, _syncSalaryCarryOverLogs, _syncSalaryCycles, _syncSalaryPayments, _syncSalaryWithdrawals, _syncShiftNotes`.

---

### 3.2 التعليق غير المحدود (Unbounded stall) — السبب الجذري الثاني

**العرض:** بعد إصلاح 3.1 ظهر العطل المعاكس: عقد «لا يتقدّم المؤشر فوق الفشل» بلا صمام. مستند واحد يفشل دائماً ⇒ المجموعة تبقى محجوبة أبداً، وكل دورة تعيد سحب نفس نافذة الدلتا وتتضخّم (قراءات Appwrite متناهية ومتنامية — مؤثر فعلي على جهاز 1GB)، وسجل الأخطاء يتكرر كل دورة بلا فائدة.

**الإصلاح — `mobile/lib/services/sync_core/sync_checkpoint_store.dart`:**

عمودان جديدان في جدول `sync_checkpoints` بنفس نمط الترحيل الموجود (`_ensureTable` + `_tryAlter`، بلا أي تعديل على جداول Drift المولّدة):

```sql
consecutive_failures INTEGER NOT NULL DEFAULT 0
retry_after_ts       INTEGER NOT NULL DEFAULT 0
```

وجدول التراجع (نقي وقابل للاختبار وحده):

```dart
static const int directRetryCycles  = 2;
static const int maxBackoffSeconds  = 6 * 60 * 60;   // 6 ساعات

static int backoffSecondsFor(int consecutiveFailures) {
  if (consecutiveFailures <= directRetryCycles) return 0;
  final step = consecutiveFailures - directRetryCycles - 1; // 0, 1, 2, …
  const baseSeconds = 15 * 60;
  if (step >= 16) return maxBackoffSeconds;
  final seconds = baseSeconds << step;
  return seconds > maxBackoffSeconds ? maxBackoffSeconds : seconds;
}
```

⇒ الدورتان الأولى والثانية: **تأخير صفر** (نفس السلوك السابق تماماً: الشفاء العابر — أب يصل في الدورة التالية — يُعالج فوراً). من الثالثة: 15د, 30د, 1س, 2س … حتى 6 ساعات.

**الواجهة الجديدة في المخزن:**
`getConsecutiveFailures`, `getRetryAfterTs`, `isRetryDue`, `registerFailure` (upsert ذرّي), `registerSuccess` (تصفير), `hasAnyCheckpoint`, ومعامل `clock` قابل للاستبدال في الاختبارات فقط (الإنتاج = ساعة النظام).

**`mobile/lib/services/sync_core/unified_pull_engine.dart`:**

```dart
if (task.critical && !await checkpoints.isRetryDue(task.name)) {
  failed.add(task.name);              // يبقى ظاهراً في SyncResult
  _logger.warning('⏸️ تخطي سحب ${task.name}: … المؤشر لم يتقدّم فوق الفشل (لا فقدان بيانات).');
  onTaskDone?.call(task.name, 0, false);
  continue;                            // بلا طلب شبكة ولا إعادة سحب
}
```

- فشل المهمة ⇒ `registerFailure` (بعد استنفاد الاستثناء).
- نجاح المهمة الحرجة ⇒ `registerSuccess` (داخل `try/catch`: كتابة العدّاد ليست حرجة ولا تُفشل مهمة ناجحة).

**الضمانة:** لم تُلمس دلالات المؤشر إطلاقاً. الفشل ما زال يمنع التقدّم (لا فقدان)، والمتغيّر الوحيد هو **تكرار المحاولة**.

---

### 3.3 غياب هوية هدف المزامنة — السبب الجذري الثالث

**العرض المؤكد:** في 2026‑10‑31 انتقل المشروع من `6a4408f300217885fd7b` إلى `6ae118bc00263ddb1cd5`. مؤشرات السحب في `sync_checkpoints` (SQLite محلي) لا تحمل أي بُعد يحدّد *أي* مشروع/قاعدة حُسبت عليها. النتيجة: المجموعات تبقى `full_sync_complete = 1` بمؤشر من المشروع القديم، فأي مستند في المشروع الجديد يحمل `$updatedAt` أقدم من ذلك المؤشر **لا يُسحب أبداً** — نقص صامت لا تشتكي منه أي شاشة.

**الإصلاح — `mobile/lib/services/appwrite_sync_manager.dart`:**

```dart
static const String _syncTargetIdentityKey = 'appwrite_sync_target_identity';

Future<void> _ensureSyncTargetIdentity() async {
  final identity = '${AppwriteConfigManager.endpoint}|'
                   '${AppwriteConfigManager.projectId}|'
                   '${AppwriteConfigManager.databaseId}';
  final stored = prefs.getString(_syncTargetIdentityKey);
  if (stored == identity) return;
  if (stored != null) {
    await _resetPullStateForNewTarget(previous: stored, current: identity);
  } else if (await _checkpointStore.hasAnyCheckpoint()) {
    await _resetPullStateForNewTarget(previous: 'غير معروفة (تثبيت سابق لهذا الحرس)', current: identity);
  }
  await prefs.setString(_syncTargetIdentityKey, identity);
}
```

- يُستدعى في بداية `sync()` **وقبل** `pullRemoteChanges()`.
- `_resetPullStateForNewTarget` يصفّر: كل مؤشرات المجموعات (`checkpoints.resetAll()`)، المؤشر العالمي (صف `sync_state` id=1 ⇒ `lastPullTs=0`, `fullSyncComplete=0`)، خريطة مؤشرات الكيانات في `SyncPullService`، و`_maxUpdatedAtInPull`.
- **قرار تصميمي صريح:** عند غياب البصمة مع وجود مؤشرات (ترقية إلى أول نسخة تحمل الحرس) يُنفَّذ السحب الكامل **دائماً**. المبرر: عمليات upsert عند المُهايئات idempotent، فسحب كامل واحد صحيح دائماً، بينما الفجوة الصامتة الدائمة أسوأ بكثير.
- الحرس نفسه لا يُفشل التهيئة: أي خطأ في التخزين يُسجَّل تحذيراً ويُعاد الفحص في التشغيل التالي.

---

### 3.4 `upsertFromJson == -1` يُحسب نجاحاً — السبب الجذري الرابع

**السبب:** `BaseRepository.upsertFromJson` يعيد `-1` عندما يقرّر `shouldSkip` تخطّي المستند (أب/مرجع غير محلول بعد). الكود كان يعتبر أي قيمة غير استثناء = نجاح ⇒ المستند يُفقد والمؤشر يتقدّم.

**الإصلاح:** 8 حراس صريحة، كل واحد يُضيف إلى `failed`:

| الدالة | السطر | المجموعة |
|---|---|---|
| `_syncExpenses` | 2811 | `expenses` |
| `_syncGuestInfos` | 4268 | `guest_infos` |
| `_syncInventoryItems` | 8321 | `inventory_items` |
| `_syncShiftNotes` | 8514 | `shift_notes` |
| `_syncCashTransactions` | 9079 | `cash_transactions` |
| `_syncPriceAdjustments` | 9639 | `price_adjustments` |
| `_syncAuditLogs` | 9760 | `audit_logs` |
| `_syncPaymentVoids` | 10068 | `payment_voids` |

```dart
if (upserted == -1) {
  failed.add('${doc.$id}: unresolved parent reference (adapter skip)');
  continue;
}
```

وكل هذه المجموعات كانت ضمن المجموعات التي تبتلع الأخطاء (§3.1) ⇒ كان الخللان يتضافران.

---

## 4) إصلاحات CI/CD

### 4.1 `CI` → `Dart Format` (كان يمنع تشغيل الاختبارات)

**التشخيص بدليل:** الـ run `41504784575` على كوميت الأساس `8dda3d7` (قبل أي تعديل):
`Flutter Analyze=success | Dart Format=failure | Run tests=skipped`.

السبب الجذري: عدد صغير من ملفات Dart لم يكن منسّقاً وفق 80 عموداً (المعيار الفعلي للشجرة)، و`--set-exit-if-changed` يُسقط الـ build قبل الاختبارات. القياس الأولي: 371 من 604 ملف فيه أسطر > 80 — أي أن الفشل بنيوي وليس عابراً.

**الطريقة الآمنة (بلا تخمين):** لا يوجد Dart SDK في بيئة العمل المحلية، لذا أضفت workflow يشغّل **الأداة الرسمية** على runner ثم يدفع الناتج إلى الفرع نفسه:

- **`.github/workflows/auto-format.yml`** — يعمل بـ `workflow_dispatch` أو بأي push يلمس `.github/format-request`، يحسب `git ls-files '*.dart'` مستثنياً الملفات المولّدة، ينفّذ `dart format --line-length 80`، ويدفع فقط إن كان هناك تغيير (بلا حلقات، وبلا لمس `*.g.dart`).
- **نتيجة التشغيل الفعلي:** 3 ملفات فقط احتاجت تنسيقاً (`appwrite_sync_manager.dart`, `silent_loss_checkpoint_regression_test.dart`, `sync_backoff_test.dart`) — 85 إضافة / 94 حذفاً.
- **محاولة مرفوضة وموثّقة:** شغّلت أولاً بعرض **120** (لأن بوابة الجوال تذكر 120) ⇒ أنتج **544 ملفاً، −35,779 سطراً** ⇒ تراجعت عنها فوراً (`a749e8e`) لأن دِفّاً بهذا الحجم غير مقبول، ثم ثبّت المعيار الحقيقي **80**.
- **`.github/workflows/ci.yml`** (خطوة `Dart Format`): 80 صريحاً + استثناء `*.g.dart/*.freezed.dart/*.gr.dart/*.mocks.dart` (لأن build_runner يعيد توليدها بخطوة سابقة) + إظهار المخالفات كـ **annotations** قابلة للنقر + ملخص في `$GITHUB_STEP_SUMMARY`. لم تُضَف `continue-on-error` في أي مكان: الفحص ما زال حاجزاً.

### 4.2 `Security & Malware Scan` → تثبيت Trivy

**التشخيص بدليل:** الـ run `41513813034`:
`Trivy Filesystem & Secrets :: Install Trivy=failure` ثم كل خطوات Trivy `skipped` ⇒ `Security Summary :: Aggregate job results=failure`. و**نفس الخطوة فشلت على `8dda3d7`** في الـ run `41504784476` ⇒ عطل سابق مستقل عن الكود.

السبب: الخطوة كانت تستخدم مستودع apt القديم `aquasecurity.github.io/trivy-repo` + `apt-key` (مهجور)، ولا ينشر ذلك المستودع حزمة لـ Ubuntu 24.04 (noble) الذي يعمل عليه `ubuntu-latest` ⇒ فشل التثبيت.

**الإصلاح — `.github/workflows/security-scan.yml`:**

```yaml
env:
  TRIVY_VERSION: 'v0.76.1'
run: |
  URL="https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${VER}_Linux-64bit.deb"
  sudo wget -q --tries=3 --timeout=60 -O /tmp/trivy.deb "$URL"
  sudo dpkg -i /tmp/trivy.deb || sudo apt-get install -fy -qq
  trivy --version
```

تم التحقق من وجود الـ asset (`.deb` بحجم 52 MB، وإعادة توجيه 302 صحيحة). **بقية المهام السبع في نفس الـ workflow كانت ناجحة أصلاً**: Semgrep SAST، npm audit ×3، CodeQL، Psalm/taint، pub.dev advisories، Syft+Grype، Socket + pip-audit + heuristics.

### 4.3 بوابة الجوال: فحص تنسيق كان «بلا أثر»

**الاكتشاف:** `.github/workflows/mobile-quality-gate.yml` كان ينفّذ:
`dart format --output=none --line-length 120 lib test` **بدون** `--set-exit-if-changed` ⇒ يخرج دائماً بـ 0، ثم `grep -c "Formatting"` يبحث عن كلمة لا تظهر في مخرجات الأداة أبداً ⇒ الفحص ينجح ولو كانت الملفات غير منسّقة تماماً. وكان يقيس 120 بينما معيار الشجرة 80.

**الإصلاح:** فحص حقيقي عند 80 على الملفات المكتوبة يدوياً مع `--set-exit-if-changed`، وannotations، وملخص يصف المخالفات. أصبحت الحالة تُقرأ من علامة `❌` في السجل بدل الكلمة الوهمية.

---

## 5) إصلاحات ثانوية

| الملف | المشكلة | الإصلاح |
|---|---|---|
| `scripts/appwrite/add_guest_entrydate_attribute.py` | الافتراضيات تشير إلى مشروع ميت `6a4408f300217885fd7b` / قاعدة `6a4409b50019dd39dde5`؛ تشغيله بلا متغيرات بيئة يضيف العمود في مشروع لا يستخدمه التطبيق ⇒ `entryDate` يبقى مفقوداً بلا أي خطأ ظاهر | الافتراضيات صارت `6ae118bc00263ddb1cd5` / `6ae119d7001046bbdb3e` (مطابقة `AppwriteConfig`) |
| `.github/format-request` | لا وسيلة لتشغيل المُنسّق قبل وجود الـ workflow على الفرع الافتراضي، و`gh workflow run` ممنوع (403) | ملف مُشغِّل: أي push يلمسه يشغّل Auto Format |
| `.github/workflows/auto-format.yml` | — | عرض السطر قابل للتحديد (`workflow_dispatch.inputs.line_length`, الافتراضي 80) |

---

## 6) الاختبارات المضافة

### `mobile/test/unit/sync_backoff_test.dart` (جديد — 308 أسطر)

**أ. `SyncCheckpointStore.backoffSecondsFor` (نقي):**
1. الدورتان الأولى والثانية بلا تأخير (سلوك ما قبل التراجع).
2. من الثالثة تتصاعد ثم تُقيَّد بسقف 6 ساعات.
3. رتيب غير متناقص.

**ب. حالة الفشل/التراجع في المخزن (بساعة وهمية):**
4. الحالة الابتدائية: لا فشل والمحاولة مستحقة فوراً.
5. أول فشلين: العدّاد يرتفع والمحاولة تبقى مستحقة (تأخير صفر).
6. الفشل الثالث: تراجع 15 دقيقة ثم يستحق بعد انقضائها.
7. النجاح يُصفّر العدّاد وموعد المحاولة.
8. `reset()` يصفّر العدّاد والتراجع مع المؤشر.
9. `hasAnyCheckpoint`: يفرّق بين قاعدة جديدة وقاعدة سُحب منها.

**ج. `UnifiedPullEngine` مع مخزن حقيقي:**
10. أول فشلين يُعاد سحبهما في الدورة التالية.
11. الفشل الثالث يفتح فترة تراجع: **لا طلب شبكة ولا إعادة سحب**.
12. بعد انقضاء التراجع تُعاد المحاولة وتنجح ⇒ تُصفَّر الحالة.
13. مجموعة متعثرة لا تمنع بقية المجموعات من العمل.

### `mobile/test/unit/pull_contract_expenses_test.dart` (جديد — 145 أسطر)

14. مصروف تالف لا يُسجَّل «نجاحاً»: الدفعة ترمي `StateError` والمصروف السليم يُطبَّق — يعتمد على قيد `amount NOT NULL` (المسار الوحيد القابل للاستفزاز: `upsertFromJson` لا يُعيد `-1` لغياب `localUuid` لأنه يولّد واحداً).
15. دفعة سليمة كاملة لا ترمي (لا إيجابيات كاذبة).

**لماذا هذان الملفان تحديداً:** الأول يثبت أن التراجع لا يكسر عقد «لا فقدان» ولا يُغيّر إيقاع الدورتين الأوليين؛ والثاني يثبت سلوك ما قبل الإصلاح (كان يمرّ أخضر) ⇒ فهو اختبار انحدار حقيقي.

---

## 7) التحقق — نتائج Actions الفعلية

| Workflow | الكوميت | النتيجة | Run |
|---|---|---|---|
| **CI** | `9d24b71` (HEAD) | ✅ | `41521468997` — `Dart Format` ✅ · `Flutter Analyze` ✅ · `Run tests` ✅ · Coverage gate ✅ |
| **Mobile Quality Gate - Enhanced** | `9d24b71` | ✅ | `41521468992` — التنسيق ✅ · التحليل ✅ · الاختبارات ✅ |
| **Enterprise Quality Gate** | `9d24b71` | ✅ | `41521469025` |
| **Security & Malware Scan** | `59e19be` | ✅ | `41519447678` — Trivy ✅ وSecurity Summary ✅ |
| **Auto Format (dart)** | `59e19be` | ✅ | `41519447984` |
| **Build Flutter Release APK** | `169e00d` | ✅ | `41520680378` — APK لكل ABI + R8 + Release ✅ |

ملاحظات على الجدول:
- `Security & Malware Scan` آخر تشغيلٍ له على `59e19be` لا على HEAD، لأن شروط `paths` لديه لا تشمل تعديلات ملفات الـ workflows فقط؛ وهو أخضر ومعه إصلاح Trivy.
- دفعات البوت (`github-actions[bot]`) لا تُشغِّل workflows (حماية GitHub من الحلقات)، لذلك دُفعت كوميتات عادية بعدها لتشغيل الفحوص على الشجرة المنسّقة.
- تشغيلات حمراء بقيت في السجل هي اللحظات الانتقالية فقط (`83ea334` قبل الإصلاح، `c1f8a07` بعرض 120 قبل تصحيحه إلى 80، و`59e19be` الذي أُلغي تلقائياً بسبب `concurrency`). آخر تشغيل لكل workflow على الفرع **أخضر**.

---

## 8) ما لم يُغيَّر — وقصداً

| العنصر | السبب |
|---|---|
| `app_settings` | غير حرجة بالتصميم (`critical: false`): فشلها لا يجوز أن يوقف المزامنة |
| `appwrite/appwrite.json` (`projectId = 690ff0da0025518570c1`) | مشروع ثالث قديم؛ لم أمسّه لأنه ملف نشر لا يعرف عنه إلا مالكه، والإصلاح المؤكد كان في سكربت `entryDate`. **يُنصح بمراجعته** |
| مخطط Drift (جداول/أعمدة) | حالة التراجع محفوظة في raw‑SQL داخل `sync_checkpoints` حتى لا يتعارض `local_db.g.dart` المولّد |
| `continue-on-error` | لم تُضَف في أي خطوة: كل الفحوص ما زالت حاجزة |
| `dart format` على الملفات المولّدة | مستثناة عمداً لأن build_runner يعيد توليدها |

---

## 9) ما يلزم التحقق محلياً

```bash
cd mobile
flutter pub get
flutter analyze
flutter test test/unit/sync_backoff_test.dart test/unit/pull_contract_expenses_test.dart
dart format --line-length 80 lib test   # اختياري: يؤكد خلو الملفات من فروق
```

**سيناريو يدوي للسبب الجذري الثالث:**
1. سجّل الدخول بمشروع `A`، اضغط مزامنة حتى تكتمل (لتُحفظ المؤشرات).
2. غيّر `projectId/databaseId` من الإعدادات إلى مشروع `B`.
3. اضغط مزامنة ⇒ يجب أن يظهر تحذير `🔄 تغيّر هدف مزامنة Appwrite … تصفير كل مؤشرات السحب` ثم سحب كامل من `B`، بدل تخطّي صامت.

**سيناريو يدوي للسبب الجذري الثاني:**
- أنشئ مستنداً في Appwrite يفشل تطبيقه محلياً (مثلاً `expenses` بـ `amount = null`) وكرّر المزامنة: تظهر المجموعة فاشلة في `SyncResult` مع تحذير `⏸️ تخطي سحب …` تدريجياً، وبقية المجموعات تستمر بالعمل.

---

## 10) سجل الكوميتات والملفات

```
b841fa5  fix(sync): guard Appwrite target change, bound stuck checkpoints, close last silent-loss gaps
83ea334  docs(sync): comparison b1d29fa vs 8dda3d7 (Appwrite push/pull, delta/full)
c1f8a07  ci: إصلاح فشلَي Dart Format وتثبيت Trivy
6a6e2d0  style(dart): تنسيق 120 عموداً            ← تجربة مرفوضة
a749e8e  Revert «تنسيق 120 عموداً»                  ← تراجع موثّق
59e19be  ci(format): عرض السطر قابلاً للتحديد (الافتراضي 80)
5d4314c  style(dart): dart format --line-length 80  ← 3 ملفات فقط
169e00d  ci(format): تثبيت العرض على 80 + استثناء المولّد
9d24b71  ci(gate): فحص تنسيق حقيقي في بوابة الجوال
```

**صافي الفرق مقابل `8dda3d7`:** 13 ملفاً، **+1505 / −106**

| الملف | +/− | ماذا فيه |
|---|---|---|
| `mobile/lib/services/appwrite_sync_manager.dart` | +304 / −29 | حرس هوية الهدف، 8 حراس `-1`، تسجيل فشل 9 مجموعات |
| `mobile/lib/services/sync_core/sync_checkpoint_store.dart` | +148 / −4 | عمودان جديدان، `backoffSecondsFor`، 7 واجهات، ساعة قابلة للحقن |
| `mobile/lib/services/sync_core/unified_pull_engine.dart` | +57 / −1 | تخطي فترة التراجع، تسجيل النجاح/الفشل، تحذيرات |
| `mobile/test/unit/sync_backoff_test.dart` | +308 / −0 | جديد — 13 حالة |
| `mobile/test/unit/pull_contract_expenses_test.dart` | +145 / −0 | جديد — حالتان |
| `mobile/test/unit/silent_loss_checkpoint_regression_test.dart` | +44 / −45 | تنسيق 80 فقط، بلا أي تغيير منطقي |
| `.github/workflows/ci.yml` | +46 / −3 | خطوة `Dart Format` (80 + استثناء المولّد + annotations) |
| `.github/workflows/mobile-quality-gate.yml` | +35 / −14 | فحص تنسيق حقيقي بدل فحص بلا أثر |
| `.github/workflows/security-scan.yml` | +17 / −8 | تثبيت Trivy من GitHub Releases |
| `.github/workflows/auto-format.yml` · `.github/format-request` | +96 / +12 | المُنسّق التلقائي ومُشغِّله |
| `scripts/appwrite/add_guest_entrydate_attribute.py` | +6 / −2 | تصحيح مشروع/قاعدة `entryDate` |
| `docs/reports/appwrite-sync-comparison-b1d29fa-vs-8dda3d7.md` | +287 / −0 | تقرير المقارنة (Delta vs Full) |

---

## 11) المخاطر والتراجع

| المخاطرة | التخفيف |
|---|---|
| سحب كامل إضافي مرة واحدة عند أول تشغيل بعد الترقية (غياب البصمة) | مقصود: upsert idempotent، وتكلفة قراءة واحدة أفضل من فجوة صامتة دائمة |
| تراجع طويل (حتى 6 ساعات) قد يؤجّل بيانات مجموعة متعثرة | الدورتان الأولى والثانية بلا تأخير ⇒ الأعطال العابرة تُشفى كما كان؛ والتأجيل يخص فقط فشلاً متكرراً مثبتاً |
| تغيير ملفات `.github` | لا يمسّ منطق التطبيق؛ كل الخطوات ما زالت حاجزة |
| الرجوع عن كل ما سبق | `git revert b841fa5 c1f8a07 59e19be 169e00d 9d24b71` (وإبقاء `5d4314c` للتنسيق أو تراجعه أيضاً) |

**ملاحظة:** كوميتا `6a6e2d0` و`a749e8e` (تنسيق 120 ثم تراجعه) أُبقيا في التاريخ كأثر شفاف للتجربة — أثرهما الصافي على الشجرة = صفر.

---

## 12) الدفعة الثانية (2026‑11‑03): آخر مواضع ابتلاع الفشل

بعد تعميم العقد على الكيانات، أُجري تدقيق بنيوي آلي على **كل** `catch` داخل حلقات المستندات في `appwrite_sync_manager.dart` (وليس بحثاً نصياً فقط): استُخرجت كتل `catch` عبر مطابقة الأقواس وصُنّفت إلى «تُسجّل فشلاً / تؤجّل / ترمي / تبتلع». النتيجة: ثلاث ثغرات حقيقية + موضعان دفاعيان موثّقان.

### 12.1 `app_settings` — إعداد يُفقد بصمت

**قبل:** فشل تطبيق مستند الإعدادات كان `_logger.warning` فقط، وكذلك تعذّر فكّ `config_json` (مصدر الحقيقة الجديد) — ثم يتقدّم مؤشر المجموعة ⇒ إعداد لا يُطبَّق على الجهاز إلى الأبد (رمز واتساب/تلجرام قديم، تقرير يومي خاطئ) بلا أي إشارة.

**بعد:**
```dart
final failed = <String>[];
...
} catch (e) {                     // داخل حلقة المستندات
  failed.add('${doc.$id}: $e');
}
if (failed.isNotEmpty) {
  throw StateError('app_settings: ${failed.length} document(s) failed to apply — ...');
}
```
وتعذّر فكّ `config_json` يُسجَّل أيضاً: `failed.add('${doc.$id}: config_json parse failed: $e')`.

**لماذا هذا آمن:** المهمة `critical: false`، والمحرك لا يضيف غير الحرجة إلى `failedCollections` ولا يوقف بقية المهام — لكن `commit` لا يُنفَّذ ⇒ مؤشر المجموعة لا يتقدّم ⇒ تُعاد المحاولة في الدورة التالية (و`plan()` يقرأ مؤشر كل مجموعة على حدة، فلا فجوة من المؤشر العالمي).

### 12.2 `price_adjustments` — إجماليات مالية مغلوطة

**قبل:** إعادة حساب الحجوزات المتأثرة بعد تطبيق تعديل سعر الغرفة كان فشلها تحذيراً فقط (كتلة `try/catch` مستقلة داخل الحلقة) ⇒ سعر الغرفة تغيّر والشتقاقات لم تُبنَ، ولا مسار يعيد بناءها.

**بعد:** `failed.add('${doc.$id}: room price recalculation failed: $e'); continue;` ⇒ الكتلة النهائية `if (failed.isNotEmpty) throw StateError(...)` تمنع تقدّم المؤشر وتعيد المحاولة.

### 12.3 `bookings` — حالة إشغال الغرف (حالة مشتقة)

**قبل:** تحديث حالة الإشغال بعد تطبيق الحجوزات كان فشله تحذيراً فقط ⇒ غرفة تُعرض متاحة وهي محجوزة (قرار حجز خاطئ على الاستقبال)، ولا مسار محلي آخر يعيد بناءها.

**بعد:**
```dart
failed.add('room_occupancy: $e');
throw StateError(
  'bookings: room occupancy refresh failed for '
  '${affectedRoomNumbers.length} room(s) — checkpoint must not advance ...',
);
```
الرمي هو الطريقة الوحيدة لضمان إعادة المحاولة: لا يتقدّم مؤشر bookings ⇒ تُعاد نفس الدفعة (upsert idempotent) وتُعاد معها إعادة حساب الإشغال.

### 12.4 طابور يتامى مسحوبات الرواتب — تدمير حمولة تالفة

**قبل:** `_loadPendingSalaryWithdrawalOrphans` عند فشل الفكّ يعيد قائمة فارغة، وأول حفظ لاحق يستبدل المفتاح (أو `prefs.remove` إن كانت القائمة فارغة) ⇒ ضياع دائم لسحوبات كانت محفوظة كأمان ضد تقدم مؤشر Delta.

**بعد:** يُحفظ نسخ احتياطي من الحمولة الخام في
`salary_withdrawal_pending_orphans_v1_corrupt_backup` قبل أي استبدال، مع `_logger.error` واضح — لا شيء يُدمَّر، ويمكن استرجاعها يدوياً.

### 12.5 موضعان دفاعيان (ليستا ابتلاعاً) — وُثّقا صراحةً

- `_syncBlacklist`: ثلاثة `catch` لتحويل تواريخ ISO إلى epoch، وقيمتها البديلة `Time.nowEpoch()`/`_asIntNullable`. المستند يُطبَّق بنجاح في الحالتين، وتسجيلها فشلاً كان سيُعطّل مجموعة الحظر إلى الأبد بسبب تاريخ تالف. أُضيف تعليق يوضّح أنها قيم بديلة لا ابتلاع.
- `_syncBookingNights` / `_syncBookings`: إشعار `RemoteChangeNotificationService` غير حرج بالتصميم (لا يؤثر على تطبيق المستند).

### 12.6 اختبار الانحدار الجديد

`mobile/test/unit/sync_no_silent_loss_remaining_test.dart` (4 حالات) — يعمل بالكود الإنتاجي نفسه عبر جسرين جديدين `syncAppSettingsForTesting` و`syncPriceAdjustmentsForTesting`:

1. مستند إعدادات صالح يُطبَّق في `SharedPreferences`.
2. مستند إعدادات تالف (`telegram_enabled: 'yes'`) يرفع `StateError`.
3. تعديل سعر لغرفة موجودة بقيمة `newValue` نصية: الإدراج ينجح (سطر التعديل موجود) ثم تفشل إعادة الحساب ⇒ `StateError` وسعر الغرفة لا يتغيّر — أي أن الفشل من المسار المشتق لا من الإدراج.
4. تعديل بلا هدف غرفة لا يرمي (لا إيجابيات كاذبة).

---

## 13) تدقيق مسار الرفع (outbox / push delta / زر «رفع التغييرات»)

### 13.1 ما جرى التحقق منه — سليم بتصميم صحيح (بالدليل من الكود)

| البند | الدليل |
|---|---|
| الرفع **دلتا فقط** (لا رفع كامل من الزر) | `_pushAllEntities` يستهلك دفعات من `outboxDao.takeBatch(batchSize, sources: ['local'])`. المسار الكامل `pushAllLocalDataToAppwrite` لا يُستدعى من الزر إطلاقاً (مواضعه: البذرة الأولى `_runInitialSeedIfNeeded`، شاشة إعدادات Appwrite، ونسخ Google Drive) |
| الحجز ذرّي وبلا تكرار | `takeBatch` ينفّذ `UPDATE outbox SET processing_status='processing' … WHERE id IN (SELECT …) RETURNING *` في استعلام واحد (لا SELECT ثم UPDATE) |
| ترتيب آمن لقواعد FK | `priorityCase`: rooms(1) ← employees(2) ← bookings(3) ← payments(4) ← expenses(5) ← debts(6) ← booking_notes(7) ← shift_notes(8) ← cash_transactions(9) ← الباقي(10) |
| لا تسليم مزدوج | `delivered_to_primary = 0` شرط إلزامي في `takeBatch`؛ وبعد النجاح `markDeliveredToPrimary` يحذف السجل فوراً (الثانوي no-op ⇒ العلامتان مكتملتان دائماً) فلا يتراكم outbox |
| لا فقدان لتغيير محلي عند فشل الرفع | `_processOutboxEntry` يلتفّ حول كل معالج: يعيد Vector Clock كما كان، ثم `setError(...)` + `markFailed([id])` |
| الشفاء الذاتي من الانقطاع | `cleanupStuckEntries` (مؤقّت كل دقيقة بعتبة 60ث + عند `initialize`) للعالقة في `processing`، `retryFailedWithBackoff` (مؤقّت كل 5 دقائق + في كل طور رفع) للفاشلة، `cleanupCompleted/cleanupOrphanedEntries` كل 24 ساعة، ولا تُستخدم `markDead` في أي مسار (لا سجلات ميتة) |
| لا رفع فوق تعارض معلّق | `OutboxPullPolicy.canPull` يمنع السحب ما دام هناك تغيير محلي غير مُسلَّم |
| إعادة المحاولة آمنة | كل حمولة تحمل `idempotencyKey` والمعرّف = `localUuid` ⇒ upsert idempotent |
| تنظيف outbox بعد السحب لا يحذف تغييراً غير مُرفوع | `_cleanupOutboxAfterPull` لا يحذف إلا بعد `_isEntryDeliveredToServer` (Fix C) |

### 13.2 عيبان مُثبتان أُصلحا

**(أ) زر «رفع التغييرات» كان يرى عدّاداً قديماً فيقول «لا توجد تغييرات جديدة» ويخرج بلا رفع**

- **الكود قبل:** `_pushChangesInner` يبدأ بـ `if (_pendingChangesCount == 0) { … «✅ لا توجد تغييرات جديدة للرفع» … return; }`، والعدّاد يُحدَّث من `initState` ثم بمؤقّت كل **15 ثانية** وبعد كل عملية.
- **الأثر:** تغيير أُنشئ قبل الضغط بأقل من 15 ثانية (أو قبل انتهاء أول تحميل) لا يُرى ⇒ الزر لا يفعل شيئاً ورسالته مضلّلة، والـ outbox ممتلئ فعلاً.
- **الإصلاح:**
```dart
// ✅ تحديث العدّاد قبل الحكم — نفس نطاق takeBatch
await _loadPendingChangesCount();
if (_pendingChangesCount == 0) { ... }
```
والعدّاد نفسه `countUndeliveredToPrimary(sources: ['local'])` (pending + processing عالقة + failed، وغير مُسلَّمة للرئيسي) — أي أنه لا يُخفي السجلات العالقة.

**(ب) سجلات تجاوزت سقف المحاولات كان الزر لا يستطيع رفعها أبداً**

- **الكود قبل:** `_pushAllEntities` ينفّذ `outboxDao.reclaimForPush()` فقط، و`reclaimForPush(maxFailedAttempts: 5)` **يتعمّد** عدم إعادة `failed` التي تجاوزت 5 محاولات (تُترك لمؤقّت `retryFailedWithBackoff` الدوري المرتبط بـ `startAutoSync`).
- **الأثر:** عند تعطيل المزامنة التلقائية (أو قبل انقضاء دورة المؤقّت) يبقى السجل في الشارة كـ«تغيير معلّق» إلى الأبد، ولا يلتقطه `takeBatch` (حالته `failed`) ولا يعيده `reclaimForPush` ⇒ **تغيير محلي لا يمكن رفعه بأي طريقة من الزر**.
- **الإصلاح:** دالة جديدة في `OutboxDao`:
```dart
Future<int> prepareForManualPush({
  Duration stuckAfter = const Duration(seconds: 30),
  int maxFailedAttempts = 5,
  int backoffMinutes = 30,
}) async {
  final reclaimed = await reclaimForPush(...);
  final retried = await retryFailedWithBackoff(...); // يحترم مهلة التراجع
  return reclaimed + retried;
}
```
و`_pushAllEntities` يستخدمها بدل `reclaimForPush` وحده. التراجع الأسّي محفوظ: لا يُعاد سجل فشل قبل `backoffMinutes` من إنشائه، فلا إغراق للخادم.

### 13.3 اختبارات الانحدار

`mobile/test/unit/outbox_manual_push_test.dart` — خمس حالات على قاعدة in-memory:

1. سجل عالق في `processing` ⇒ يعود `pending`.
2. سجل `failed` بثلاث محاولات ⇒ يعود `pending`.
3. سجل `failed` بـ 12 محاولة و`clientTs` قبل ساعتين ⇒ `reclaimForPush` وحده لا يلمسه (توثيق العيب) ثم `prepareForManualPush` يعيده `pending`.
4. سجل `failed` بـ 12 محاولة أُنشئ الآن ⇒ يبقى `failed` (مهلة التراجع غير مخترقة).
5. سجل مُسلَّم للرئيسي ⇒ لا يُلمس ولا يُحتسب في عدّاد الزر.

بالإضافة إلى الحالة الخامسة في `sync_no_silent_loss_remaining_test.dart`: `config_json` تالف يُسجَّل فشلاً مع إبقاء التطبيق الجزئي (الحقول القديمة).

### 13.4 ملاحظات مقصودة (ليست أعطالاً)

- `_processAppUserEntry`: استجابة 404 (الحساب غير موجود سحابياً) ⇒ تُعامَل «مُسلَّمة» لأن التحديث غير ممكن أصلاً. موثّق في الكود.
- عناصر `source = 'restore'` لا يرفعها هذا المسار (تخص استعادة النسخ) — نطاق `takeBatch` هو `['local']` عمداً.
- بطء/فشل الشبكة لا يُسقط السجل: يُعاد إلى `failed` مع `attempts+1` ويبقى مرئياً في الشارة.

---

## 14) قسم «إدارة اتصال Appwrite» في شاشة الإعدادات (2026‑11‑06)

المسار: `الإعدادات ← Appwrite ← إعدادات الاتصال السحابي`
(`mobile/lib/screens/settings/appwrite_connection_settings_screen.dart`، 496 سطراً قبل الإصلاح).

### 14.1 ما كان يعمل بشكل صحيح (تحقّق لا إصلاح)

| البند | النتيجة |
|---|---|
| الوصول إلى الشاشة | ✅ `AppwriteSettingsScreen` ← `ListTile('إعدادات الاتصال السحابي')` ← `AppwriteConnectionSettingsScreen` |
| المفتاح مخفي | ✅ `obscureText` + زر إظهار/إخفاء، والعرض في بطاقة الحالة مقيّد بآخر 4 أحرف |
| «اختبار الاتصال» لا يلوّث الجلسة | ✅ يبني `Client` مؤقتاً داخل `testConnectionWithConfig` ولا يمسّ `AppwriteService` العامل |
| الحفظ لا يمسّ Secondary | ✅ مفاتيح `appwrite_endpoint / _project_id / _database_id / _api_key` فقط |
| «إعادة تعيين» | ✅ يحذف المفاتيح ويعيد `AppwriteConfig.defaultApiKey` (لا يمسحه) |

### 14.2 الأعطال المؤكدة (أربعة) والإصلاحات

**(1) العميل لا يُعاد بناؤه ⇒ «إعادة تشغيل مطلوبة» بعد كل حفظ**

- **الكود قبل:** `AppwriteService` يعلن `late final Client _client; late final Databases _databases;` و`initialize()` يحرسها بـ `_initialized`. لا يوجد أي مسار لإعادة البناء (والإسناد الثاني كان يرمي `LateInitializationError` أصلاً).
- **الأثر:** بعد «تم حفظ الإعدادات بنجاح» تظل **كل** الطلبات (المزامنة التلقائية، الرفع اليدوي، السحب، الـ Realtime) تذهب إلى المشروع القديم حتى إعادة تشغيل التطبيق. أي أن نجاح الحفظ لا يعني نجاح التبديل.
- **الإصلاح:**
```dart
late Client _client;      // بدل late final
late Databases _databases;

Future<void> reinitialize() async {
  _initialized = false;
  invalidateSecondaryClient();  // عميل Secondary المخزَّن مؤقتاً
  _cache.clear();               // وإلا خُدمت مستندات المشروع القديم من الكاش
  await initialize();
}
```
- الشاشة تستدعي `AppwriteService().reinitialize()` فور الحفظ، ثم تُبلغ مدير المزامنة.

**(2) `reinitializeAfterConfigChange()` كانت شيفرة ميتة**

- **قبل:** الدالة معرَّفة في `AppwriteSyncManager` لكن **لا يستدعيها أي موضع**، وفيها حرس هوية الهدف `_ensureSyncTargetIdentity()` (تصفير مؤشرات السحب عند تغيير المشروع/القاعدة).
- **الأثر المزدوج:** (أ) لا إعادة فحص للهوية في الجلسة؛ (ب) بعد إتاحة التطبيق الفوري كان يمكن أن يعمل السحب بهدف جديد بينما المؤشرات محسوبة على القديم ⇒ **نقص صامت** في البيانات.
- **الإصلاح:** `static Future<void> notifyConfigChanged()` تستدعيها الشاشة بعد الحفظ (لا تُنشئ نسخة جديدة إن لم تكن مهيّأة — آمنة في الاختبارات)، وبصمة الهدف صارت مصدراً واحداً للحقيقة:
```dart
// AppwriteConfigManager
static String get targetIdentity => '$_endpoint|$_projectId|$_databaseId';
```

**(3) مفتاح API الفارغ كان يطمس المفتاح المدمج نهائياً**

- **الكود قبل:** `saveConfig` يكتب `prefs.setString(_apiKey, apiKey)` دائماً، و`init()` يقرأ `prefs.getString(_apiKey) ?? AppwriteConfig.defaultApiKey` — و`''` ليست `null` ⇒ **يُلغى** المفتاح المُمرَّر بـ `--dart-define` نهائياً.
- **الأثر:** كل طلبات Appwrite تخرج بلا `X-Appwrite-Key` ⇒ 401، بينما نص الحقل يقول «يُستخدم المفتاح الافتراضي تلقائياً» والشاشة تقول «تم الحفظ بنجاح».
- **الإصلاح:** الحقل الفارغ يعني «استخدم المدمج»:
```dart
if (normalizedApiKey.isEmpty) {
  await prefs.remove(_apiKey);   // لا نخزّن ''
} else {
  await prefs.setString(_apiKey, normalizedApiKey);
}
_apiKeyValue = normalizedApiKey.isEmpty
    ? AppwriteConfig.defaultApiKey
    : normalizedApiKey;
```
و`init()` يشفى من القيم الفارغة المخزَّنة في النسخ السابقة.

**(4) لا تطبيع لـ Endpoint، وفشل الاختبار بلا تشخيص**

- **قبل:** القيمة تُحفظ كما هي. لوحة تحكم Appwrite تعرض `https://fra.cloud.appwrite.io/v1/`؛ نسخها بشرطة مائلة نهائية ينتج مساراً مزدوجاً (`/v1//databases/...`) ⇒ 404 يظهر كـ«فشل اتصال» مع صحة كل القيم. وعند الفشل كان يُعرض سطر `AppwriteException: ...` واحد لا يفرّق بين Endpoint وProject وDatabase والمفتاح.
- **الإصلاح:** `normalizeEndpoint` (إزالة الفراغات وكل الشرطات النهائية) و`normalizeId` تُطبَّقان في الحفظ وفي `init()` وفي `testConnectionWithConfig` معاً؛ وأُضيف `describeConnectionFailure` يصنّف الفشل إلى: مفتاح (401/403)، قاعدة/مجموعة، مشروع، عنوان/شبكة، أو «غير مصنّف»، ويُعرض في الـ SnackBar.

### 14.3 حمايات أُضيفت مع التطبيق الفوري

- **لا تبديل في منتصف دورة مزامنة:** الصفوف التي رُفعت فعلاً إلى الهدف القديم تُحذف من `outbox` عند النجاح؛ لو بدّلنا الهدف في منتصف الدورة لبقيت نصف التغييرات في مشروع ونصفها في آخر. الشاشة تنتظر انتهاء الدورة (فحص كل 250ms بحد 20 ثانية)، وإن لم تنتهِ تُبقي الإعدادات محفوظة وتُبلّغ بوضوح بدل التطبيق في المنتصف.
- **الـ Realtime:** `AppwriteRealtimeSync.stop()` تُسقط كائن `Realtime` نفسه (كان يُبنى مرة من `AppwriteService().client` ويبقى محفوظاً ⇒ استماع على المشروع القديم).
- **رسائل صادقة:** «تم حفظ الإعدادات وتطبيقها فوراً» عند النجاح، و«تم حفظ الإعدادات، لكن لم تُطبَّق فوراً: <السبب>» عند الفشل — بدل حوار «إعادة تشغيل مطلوبة» في كل الحالات. و«اختبار الاتصال» صار يقول «بالقيم المُدخلة (لم تُحفظ بعد)» بدل «القيم الحالية».

- **اختبار الاتصال صار يقيس المفتاح الفعّال:** ترك حقل API Key فارغاً يعني استخدام المفتاح المدمج عند التشغيل، لكن `_testConnection` كان يرسل بلا مفتاح أصلاً ⇒ يقيس وصولاً «زائراً» لا الإعدادات التي ستُحفظ، فينجح الاختبار ثم تفشل المزامنة بـ 401 (أو العكس). الآن يُمرَّر `effectiveApiKey = الحقل أو المفتاح المدمج`.

### 14.4 اختبارات الانحدار

`mobile/test/services/appwrite_connection_config_test.dart` — 12 حالة:

1. الـ Endpoint يُحفظ مطبَّعاً (شرطة مائلة + فراغات).
2. `normalizeEndpoint` على الحالات الحدّية (`/`, `///`, فراغات، نص فارغ).
3. المفتاح الفارغ **لا** يُخزَّن (المفتاح السابق للعيب: حفظ `''` يطمس المدمج).
4. `init()` يشفى من `appwrite_api_key = ''` وEndpoint قديم بشرطة مائلة.
5. مفتاح غير فارغ يُخزَّن ويُستخدم فعلاً.
6. `resetToDefaults` يحذف المفتاح ويعيد المدمج.
7. صيغة `targetIdentity` مطبَّعة وموحّدة.
8. `reinitialize()` يعيد كائن `Client` جديداً (قبل الإصلاح: `late final` ⇒ استحالة).
9. `initialize()` المتكرر آمن.
10–12. تصنيف الفشل: 401/403 ⇒ مفتاح، `database/collection` ⇒ قاعدة البيانات، `project` ⇒ مشروع، Socket/timeout ⇒ عنوان، غير ذلك ⇒ «غير مصنّف» (لا تصنيف زائف).

> **التنسيق:** الكوميت `5eeed56` (Auto Format الرسمي، `--line-length 80`) أُضيف بعد `a2834c6` لتوافق الشجرة مع بوابة `Dart Format` في CI؛ لم يغيّر أي دلالة — فقط لفّ سطور في `appwrite_service.dart` و`appwrite_connection_config_test.dart`.

---

## 15) تنفيذ «وثيقة الربط والمزامنة الموحدة» — الدفعة الأولى (PR‑1 + PR‑2)

المرجع: `وثيقة_الربط_والمزامنة_Appwrite_الموحدة.md` (900 سطر، 16 قسماً). الدفعة
المنفَّذة هنا تقابل **PR‑1** (UUID backfill والتحقق من الروابط) و**PR‑2**
(`LocalLinkResolver`) من §12، إضافةً إلى فحوص §4.1/§4.2/§5.1/§5.2/§8.1/§11.

### 15.1 تدقيق ما كان مُنفَّذاً بالفعل (لم يُعَد تنفيذه)

| بند PR‑0 | الحالة في الشيفرة | الدليل |
|---|---|---|
| إزالة hard delete من فحص السلامة | ✅ منفَّذ سابقاً | `_performPostSyncIntegrityCheck` — تعليق `المرحلة 0 — P0.1/R1`، لا `DELETE` |
| إزالة «remote employeeId = local id» («الطريقة 2») | ✅ | `appwrite_sync_manager.dart:4488` و`:9215` (`P0.2/R2`) |
| منع raw `relatedId` fallback | ✅ | `P0.3` في `salary_withdrawals_repository` و`expenses_list` |
| إبقاء غير المحلول في outbox | ✅ | `P0.5` |
| حماية `deleteByExpenseId` | ✅ | `P0.5` |
| إضافة «سلفة» إلى المصنّف | ✅ | `local_db.dart:1373/1502` |
| Drive Delta للجداول الناقصة | ✅ | `P0.6` في `google_drive_delta_sync.dart` |
| `employee_uuid` في جداول الرواتب + `expense_uuid`/`withdrawal_uuid` | ✅ | migration 67 و68 |

ما كان **ناقصاً فعلاً** (وهو ما نُفِّذ الآن): `expenses.expense_kind`، جدول
`pending_links`، الفهارس النصّية في §4.1، الفهرس الفريد `ux_sw_expense_uuid_active`،
تعبئة `expense_uuid` بحراس، وخدمة `LocalLinkResolver` المركزية.

### 15.2 Migration 75 — مخطط الربط

`schemaVersion` 74 → **75**. الإنشاء يتم في **`beforeOpen`** عبر
`_ensureUuidLinkSchema()` بمعرّف (idempotent)، لأن `onCreate` (التثبيت الجديد) و
`onUpgrade` (الترقية) لا يمرّان على نفس المسار — وهذا نصّ §4.1: «تُنشأ فعلياً في
`beforeOpen` أو `onCreate` باستخدام `IF NOT EXISTS`».

- `ALTER TABLE expenses ADD COLUMN expense_kind TEXT` — بعد فحص `PRAGMA table_info`
  (SQLite لا يدعم `ADD COLUMN IF NOT EXISTS`).
- `pending_links(id, entity, local_uuid, missing_kind, missing_uuid, payload_json,
  attempts, last_error, created_at, updated_at, UNIQUE(entity,local_uuid,missing_kind,missing_uuid))`
  + فهرسان.
- الفهارس: `idx_exp_employee_uuid`, `idx_exp_kind_day`, `idx_sw_expense_uuid`,
  `idx_sw_employee_id`, `idx_sc_employee_uuid`, `idx_emp_local_uuid` — كلها
  `IF NOT EXISTS`.
- القيد الفريد للمرآة النشطة: **موجود أصلاً** في المخطط باسم
  `ux_salary_withdrawals_expense_uuid_active` (`@TableIndex.sql` على
  `SalaryWithdrawals` + migration 69/70 التي تُنشئه فقط عندما تخلو البيانات من
  التكرار). لذلك **لم نُضِف قيداً ثانياً** بالاسم الوارد في §4.1: التجربة أثبتت
  أن القيد الإضافي بشرط مختلف (`expense_uuid IS NOT NULL` بلا استثناء السلسلة
  الفارغة) يكسر بيانات مشروعة — `UNIQUE constraint failed:
  salary_withdrawals.expense_uuid` في `operation_identity_semantics_test`.
  المتبقّي في PR‑3 هو منع إنشاء المرآة الثانية **قبل** الكتابة (وليس بعدها)،
  وهو ما يفعله `SalaryExpenseService` الذرية.

لماذا raw SQL لا تعريف Drift للأعمدة الجديدة؟ إعلانها في Drift يوجب إعادة توليد
`local_db.g.dart` (codegen غير متاح في بيئة التنفيذ)، والـ raw SQL هو النمط
المستخدم أصلاً في migrations 42/67/68 للأعمدة الإضافية.

### 15.3 التعبئة الآمنة (§4.2)

`_backfillUuidLinksAfterUpgrade()` — تعمل داخل migration 75، وكلها **محلية وحتمية**:

1. `expense_kind` يُقترح **مرة واحدة** من المصنّف النصي الحالي (نفس قائمة
   migration 67 + «سلفة» + أقساط السلف) ثم لا يُعاد اشتقاقه من النص.
2. `salary_withdrawals.expense_uuid` من `expense_id` المحلي **بشرطين**:
   المصروف موجود و`local_uuid` غير فارغ وغير محذوف، **وأن `employee_uuid`
   متطابق** (أو أحدهما NULL) — فلا يُنسب مصروف موظف لموظف آخر.
3. `expenses.withdrawal_uuid` العكسي يُملأ فقط إذا كانت هناك **مرآة نشطة واحدة**
   تشير إليه (لا تخمين بين مرايا متعددة).
4. **بلا** كتابة إلى outbox، **بلا** رفع `version`، **بلا** تغيير `lastModified` —
   مغطّى باختبار صريح.
5. الأعداد (مسحوبات بلا `employeeUuid`، مسحوبات بلا `expenseUuid`، مصروفات رواتب
   بلا موظف، مرايا مكررة) تُسجَّل في `developer.log` باسم `db.link`.

### 15.4 `LocalLinkResolver` (§5.1/§5.2)

`mobile/lib/services/local_link_resolver.dart` — الخدمة المركزية الوحيدة لتحويل
UUID إلى أرقام محلية:

- `employeeIdForUuid` / `expenseIdForUuid` / `employeeIdsForUuids` (دفعة باستعلام واحد).
- **لا fallback** إلى `employeeId`/`relatedId`/`expenseId` القادمة من Appwrite،
  ولا `serverId` (§1.3/§5.3).
- `recordPendingLink(...)` — `INSERT … ON CONFLICT DO UPDATE` فلا تكرار لنفس العطل،
  وتزداد المحاولات.
- `retryPendingLinks()` — يحل ما وصل أبوه، ويكتب الرقم المحلي **بلا** تعديل هوية
  أو `version`، ويحذف صف `pending_links`؛ وما لم يُحل يبقى بزيادة محاولة وسبب
  واضح، والسجل الأصلي لا يُحذف ولا يُسقط من outbox.
- `pendingLinks()` / `pendingLinksCount()` — أساس تقرير §11.
- نوع ربط غير معروف **لا يكتب شيئاً** (بدل تخمين عمود).

**نقطة الربط:** `AppwriteSyncManager` بعد اكتمال دورة السحب — مباشرةً بعد
`SalaryFixHelper.runOnceAfterFirstPull()`: استدعاء `retryPendingLinks()` داخل
`try/catch` غير حاجب (فشله لا يُفشل المزامنة)، مطابقةً لنصّ §8.1.

### 15.5 تقرير السلامة (§11)

`AppDatabase.uuidLinkHealthCounts()` — قراءة فقط: مسحوبات بلا `employeeUuid`،
مسحوبات بلا `expenseUuid`، مصروفات رواتب بلا موظف، مرايا يتيمة، مرايا مكررة،
`pending_links`، ومصروفات بلا تصنيف. لا حذف ولا تصحيح تلقائي.

### 15.6 الاختبارات

`mobile/test/services/local_link_resolver_test.dart` — 16 حالة:

- المخطط: وجود `expense_kind`، أعمد `pending_links`، ووجود القيد الفريد الفعلي
  `ux_salary_withdrawals_expense_uuid_active` مع **عدم** إضافة قيد مكرر،
  ومنع المرآة الثانية فعلياً، وعدم عدّ السلسلة الفارغة رابطاً.
- التعبئة: تصنيف كل نوع مصروف (سحب/خصم/سلفة/رواتب/عام)، `expense_uuid` للموظف
  الصحيح و**رفض** الربط عبر الموظف الخاطئ، وثبات `version`/`last_modified`/outbox.
- الحل: موظف/مصروف/دفعة، تجاهل المحذوف منطقياً، وقيم فارغة ⇒ `null`.
- `pending_links`: التسجيل، منع التكرار، الحل بعد وصول الأب، البقاء عند غيابه،
  نوع غير معروف لا يكتب، وربط المرآة عبر `expense_uuid`.
- التقرير: المفاتيح المطلوبة، والمرآة اليتيمة تُعدّ ولا تُحذف.

### 15.7 ما تبقّى من الوثيقة (لم يُنفَّذ في هذه الدفعة — عمداً)

| PR | المتبقّي | السبب |
|---|---|---|
| PR‑3 | `SalaryExpenseService` (save/delete/reassign ذرية + منع مرآة ثانية) | يمسّ مسارات إنشاء المصروف والمرآة في الواجهات؛ يحتاج جولة مستقلة مع اختبارات atomicity |
| PR‑4 | Payload UUID-first واستقباله في كل Adapter + Cloud Wins على `revision` | الأجهزة القديمة ما زالت ترسل الأرقام؛ تغييره يحتاج تحققاً من attributes في Appwrite أولاً |
| PR‑5 | Checkpoints دقيقة بعد commit لكل صفحة + إعادة محاولة `pending_links` داخل محرّك السحب | محرّك السحب الحالي يحدّث checkpoint بعد الدفعة؛ يحتاج إعادة هيكلة دقيقة |
| PR‑6 | `EmployeeFinancialReportRepository` ونموذج الحركة الموحّد + منع ازدواج المصروف/المرآة في التقارير | نطاق تقارير كامل (16.2–16.9) |
| PR‑7 | إغلاق التوافق القديم (`reason='exp_N'`، `expense_id`، fallback) | مشروط بتحديث جميع الأجهزة وصفر اعتماد قديم |

حتى تُنفَّذ PR‑3/PR‑4: `expense_kind` **مُعبّأ** للسجلات القائمة ولا يُشتق من النص،
لكن المسارات الجديدة ما زالت تكتب `expense_type` النصي؛ لذلك يُصنَّف عند الحفظ
بمصنّف موحّد لاحقاً في PR‑3.

> **التنسيق:** `131d385` (Auto Format، 80 عموداً) بعد `39c7ebd` — تغييرات تنسيقية فقط في `local_db.dart` و`local_link_resolver.dart` وملفَي الاختبار.
