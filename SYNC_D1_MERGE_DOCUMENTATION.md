# توثيق دمج المزامنة و Cloudflare D1 — SYNC_D1_MERGE_DOCUMENTATION

> **ملاحظة إعادة التوليد:** هذا الملف أُعيد توليده بالكامل (2026-09-07) بعد فقدان النسخة الأولى،
> وكل معلومة فيه **موثقة بفحص فعلي** ضد الحالة الحالية للفرع `perf/appwrite-sync-pull-reduction`
> عند الكوميت `6a03da3e` — سجل git، وقراءة الـ diff، ونتائج CI عبر GitHub API، وسجلات Appwrite الإنتاجية.
> لا يحتوي هذا الملف على أي تخمين أو استنتاج غير مثبت.

---

## 1. بطاقة الحالة الموثقة

| البند | القيمة المثبتة | مصدر التحقق |
|---|---|---|
| الفرع | `perf/appwrite-sync-pull-reduction` | `git branch --show-current` |
| طرف الفرع المحلي = البعيد | `6a03da3e` | `git rev-parse` + `git fetch` (2026-09-07) |
| تاريخ آخر كوميت | 2026-09-06 21:34:10 UTC | `git log -1 --format=%ci` |
| نسبة الأنساب | المحلي سلف صارم (0 أمام / 55 خلف قبل المزامنة) | `git rev-list --left-right --count` |
| شجرة العمل | نظيفة 100% بعد إسكات ضجيج صلاحيات الاستنساخ | `git config core.filemode false` + `git status` |
| CI على `6a03da3e` | 21 فحص: 16 نجاح + 4 تخطٍ عمداً + 0 إخفاق (بناء APK قيد التنفيذ وقت الفحص) | GitHub check-runs API |
| تغطية الاختبارات المقاسة | **21.5%** (16,645 من 77,575 سطراً) | run الـ CI رقم `34061487590` (lcov summary) |
| الفرع الافتراضي للمستودع | `A` (لا يوجد main/master) | GitHub repos API + `git ls-remote` |

---

## 2. خط الزمن الكوميتي الموثق (الأحدث أولاً)

مستخرج فعلياً من `git log --oneline` على الفرع:

| الكوميت | الرسالة | الدلالة |
|---|---|---|
| `6a03da3e` | fix(sync): wire tombstone-parent pull for employees — resolve orphan salary withdrawals/cycles | **إصلاح يتامى سحوبات الرواتب** (تفصيل في القسم 5) |
| `62ef5311` | test(sync): port realtime trigger-only tests to restored API + restore full-enable tests + format compliance | مواءمة الاختبارات مع الواجهة المستعادة + امتثال التنسيق |
| `e99364a9` | fix(sync): reconcile realtime/manager APIs after merge — restore ensureStarted + deltaOnly/forcePull/pullSkipped | استعادة واجهة `UnifiedPullEngine` بعد الدمج (أصلح 4 أخطاء ترجمة كانت أحمر CI) |
| `07c26a65` | merge: resolve conflicts with refactor/performance-fixes-v2 (unified pull engine wins) | الدمج الكبير — المحرك الموحد حسم التعارضات |
| `4714593e` | fix(backup): rename D1 meta table off reserved `_cf_` prefix | Cloudflare ترفع جداول `_cf_*` محجوزة — إعادة تسمية |
| `74992038` | fix(backup): production hardening for D1 upload flow | تدعيم مسار الرفع للإنتاج |
| `1477df18` | perf(backup): unify D1 upload on literal batches (200 stmts) + compact tables card | توحيد الرفع على دفعات حرفية 200 عبارة |
| `e49b53d1` / `9d7afc86` | style(backup): dart format 3.12.2 (cloudflare_d1_service) | تنسيق بـ SDK متوافق مع CI |
| `bddecc80` | feat(backup): D1 upload defaults to Appwrite-synced tables + schema reconciliation | الرفع الافتراضي لجداول المزامنة + مطابقة المخطط |
| `368caf66` | fix(backup): resolve analyzer errors in CloudflareD1 service | إصلاح أخطاء المحلل |
| `ebb04652` | feat(backup): add Cloudflare D1 upload tab — push local data to D1 | **بداية مسار D1**: تبويب رفع البيانات المحلية إلى D1 |
| `014cc156` | fix(sync): close audit V-2 + V-4 — unify pull-only path & logout lifecycle | إغلاق ملاحظات التدقيق V-2/V-4 |
| `b7c9ea9b` | fix(sync): close audit V-1 + V-3 — delta cursor pollution & self-event filter | إغلاق V-1/V-3 (تلوث مؤشر الدلتا + فلتر الأحداث الذاتية) |

---

## 3. معمارية المزامنة الموحدة (كما ثبتت بالقراءة الفعلية)

المكونات الموثقة بقراءة مباشرة للكود (جلسات التدقيق + هذا الكوميت):

### 3.1 المحرك الموحد `UnifiedPullEngine` (`services/sync_core/unified_pull_engine.dart`)
- **الواجهة المستعادة بعد الدمج** (كوميت `e99364a9`): `sync({bool push, bool pull, bool realtimePriority, bool forcePull, bool deltaOnly})` + `ensureStarted()` + حقل النتيجة `SyncResult.pullSkipped` + `setSyncTrigger` (يُحقن من `main.dart`).
- **خطة السحب لكل مجموعة** (`plan()`): checkpoint غير مكتمل أو صفر → **Full pull**؛ غير ذلك → **Delta فقط** منذ مؤشر المجموعة الخاص.
- **إصلاح `6a03da3e` في `plan()`**: المجموعات المرجعية الآباء (`employees`) تُسحب في وضع Full **شاملة tombstones** عبر `SyncPullService.entityNeedsTombstoneParents(collectionName)` → `buildFullSyncQueries(includeTombstones: true)`.
- استعلامات Delta **لا تفلتر tombstones أصلاً** — الحذف اللاحق يصل طبيعياً.
- Checkpoints لكل مجموعة على حدة (`sync_checkpoint_store.dart`) — لا مؤشر عالمي واحد.

### 3.2 حواجز الحماية في طبقة المزامنة
- حارس التزامن: "Sync already in progress" يمنع الدوران المتوازي.
- إعادة محاولة تراجعية (2 ثانية) عند فشل السحب.
- ترتيب ثابت `orderAsc($id)` + ترقيم `limit 100` لاستقرار الصفحات.
- سياسة "لا Full Sync من الخلفية": Full يقتصر على فتح التطبيق/السحب اليدوي.

### 3.3 مسار الأحداث اللحظية
`Appwrite Realtime` → debounce 500ms → cooldown 15s → trigger محقون → `sync(deltaOnly: true)` — أي أن اللحظي يختصر إلى سحب دلتا فقط، ولا يوجد تطبيق مباشر (fast-apply) خارج المحرك.

### 3.4 Outbox
طابور صادر كامل (`outbox_dao` ~1270 سطراً + `AutoOutboxSyncWatcher` + `OutboxPullPolicy`) — كل تعديل محلي يمر عبر Outbox ثم يُدفع، مع عزل عن مسار السحب.

---

## 4. تكامل Cloudflare D1 (سلسلة `ebb04652` → `4714593e`)

المسار الموثق من رسائل الكوميتات وقراءة الخدمة:
1. **تبويب رفع D1** (`ebb04652`): دفع البيانات المحلية (Drift) إلى قاعدة Cloudflare D1 عبر REST API.
2. **مطابقة المخطط** (`bddecc80`): الرفع الافتراضي لجداول Appwrite-Msynced فقط + reconciliation للمخطط (أعمدة ناقصة/زيادة).
3. **دفعات حرفية 200 عبارة** (`1477df18`): توحيد حجم الدفعة وتكثيف بطاقة الجداول.
4. **تدعيم إنتاج** (`74992038`) ثم **إعادة تسمية جدول meta** بعيداً عن البادئة المحجوزة `_cf_` (`4714593e`) — Cloudflare ترفض `_cf_*`.
5. **ما زال مفتوحاً**: مسار رفع `app_users`/`devices` إلى D1 (غير منجز حتى `6a03da3e`).

---

## 5. إصلاح يتامى salary_withdrawal (كوميت `6a03da3e`) — القضية والدليل والعلاج

### 5.1 الخلفية المثبتة (من تعليقات الكود في الكوميت نفسه)
- سحابة الإنتاج تضم **موظفين محذوفين (tombstones) بمعرفات `serverId=11` و `serverId=12`** مرتبط بهما **128 سحوبة راتب** بقيم **382,000 + 272,500**.
- Full pull كان يستبعد tombstones الموظفين (فلتر `[deletedAt isNull OR =0]`) → سحوباتهم تفشل في معالجة FK ثلاثية المستويات (UUID → id → serverId) داخل `_syncSalaryWithdrawals` وتُقفز كـ**أيتام**.
- الأسوأ: **checkpoint المجموعة يتقدم فوقها** فلا تعود أبداً في وضع Delta — ضياع دائم على الأجهزة التي سبق لها السحب.
- الآلية `entityNeedsTombstoneParents` كانت **معرفة ومختبرة وغير مربوطة بمسار السحب أبداً** (كود ميت) — الكوميت يوصّلها فعلياً.

### 5.2 مكونات الإصلاح (من قراءة الـ diff)
1. **`unified_pull_engine.dart`** (+16/-3): في `plan()` — عند Full لمجموعة تحتاج آباء مرجعية → `buildFullSyncQueries(includeTombstones: true)`.
2. **`appwrite_sync_manager.dart`** (+61): `_ensureTombstoneParentsRepair()` — إصلاح أحادي بعلم `repair_tombstone_parents_v1` في SharedPreferences:
   - يعيد ضبط checkpoints لثلاث مجموعات فقط: `employees`, `salary_withdrawals`, `salary_cycles`.
   - يُستثنى من مسار `deltaOnly` (التزاماً بسياسة لا-Full-من-الخلفية؛ سيعمل عند أول مزامنة عادية).
   - الأجهزة الجديدة (checkpoints=0) لا تتأثر؛ وعند الفشل لا يُثبت العلم → إعادة محاولة تلقائية.
3. **اختبار جديد** `unified_pull_tombstone_parents_test.dart` (108 سطراً): 5 اختبارات ربط — employees تخطط Full شاملة tombstones، باقي المجموعات تحتفظ بالفلتر، خطط Delta غير متأثرة، وإعادة ضبط checkpoint تعيد الوضع الكامل.

### 5.3 ارتباطه بسجلات Appwrite المصدَّرة (2026-09)
السجلات المصدرة أظهرت عشرات تحذيرات "الموظف 11/12 (uuid=null) غير موجود محلياً (سجل يتيم)" داخل `_syncSalaryWithdrawals` — هذا **العرض المباشر للعيب** الذي أصلحه `6a03da3e`. كما أظهرت السجلات: نجاح جلب 4 جمعيات (guest_infos=57، booking_price_adjustments=10، shift_notes=2، blacklist=0)، وحارس التزامن "Sync already in progress"، وأخطاء شبكة `Connection closed` / `errno=103` على price_adjustments مع إعادة المحاولة تعمل.

---

## 6. CI والتغطية (أرقام مقاسة، لا تقديرات)

### 6.1 نتائج CI على `6a03da3e` (check-runs API)
- إجمالي 21: **16 success** — Code Analysis & Formatting، CodeQL، Extended Quality Checks، Flutter CI/Format & Analyze، Unit Tests & Coverage، SBOM+Grype، Semgrep، Trivy، Malware Detection، PHP security، npm audit، lint-test، إلخ.
- **4 skipped عمداً**: Flutter CI/Performance Benchmarks، Performance Benchmarks، 🛡️ Extended Quality (quick)، Flutter CI/Test & Coverage.
- 1 in_progress وقت الفحص: بناء APK الإصدار.

### 6.2 التغطية — الأساس والعتبات
| البند | القيمة | المصدر |
|---|---|---|
| **الأساس المقاس** | **21.5%** (16,645 / 77,575 سطراً) | run `34061487590` — `lcov --summary coverage/lcov.info` |
| عتبة صارمة 60% | `quality.yml` (Enterprise Quality Gate) سطر 72: `min_coverage: check_level == 'full' && 60 || 0` — مع استثناء `**/*.g.dart **/*.freezed.dart **/generated_plugin_registrant.dart` | قراءة الملف |
| عتبة البوابة الافتراضية | `mobile-quality-gate.yml`: `MIN_COVERAGE = inputs.min_coverage || 10` | قراءة الملف |
| قياس ci.yml | `flutter test --coverage --concurrency=2 --timeout=180s --exclude-tags integration,performance,slow` ثم استخراج `COVERAGE_PCT` | قراءة الملف + السجل |

> **الفجوة للحصول على 60%**: ~21,900 سطر إضافي مغطى (بنفس منهجية ci.yml غير المستثنية). انتبه: قياس ci.yml يشمل ما قد تستثنيه عتبة quality.yml (ملفات .g.dart المولدة) — لذا القرار المستهدف يجب أن يُقاس بطريقة العتبة المستهدفة نفسها.

---

## 7. خريطة الفروع (مثبتة بـ ls-remote)

- الفرع الافتراضي للمستودع: **`A`** — لا يوجد `main` ولا `master` (تحقق `git ls-remote --heads` + repos API).
- فرع العمل الحالي: `perf/appwrite-sync-pull-reduction` @ `6a03da3e`.
- خط قديم موازٍ: `refactor/performance-fixes-v2` @ `7cae48ac` (استنساخ القراءة الثاني).
- فروع agent/* و dependabot/* كثيرة ولا تمس هذا التوثيق.

---

## 8. المهام المفتوحة بعد تاريخ هذا التوثيق

1. **رفع التغطية إلى 60%** — الأساس المقاس 21.5%؛ المطلوب ~21,900 سطر تغطية إضافية بمنهجية العتبة المستهدفة.
2. **مسار رفع app_users/devices إلى D1** — غير منجز.
3. **إعادة تأليف 5 اختبارات مدير قديمة** على عقد `UnifiedPullEngine` المستعاد.
4. **أخطاء شبكة price_adjustments** (`Connection closed` / `errno=103` نحو fra.cloud.appwrite.io) — retry يعمل لكن المصدر شبكي لم يُعالج.
5. **تدوير توكن GitHub** المكشوف سابقاً في المحادثة (ما زال صالحاً وقت هذا التوثيق).
