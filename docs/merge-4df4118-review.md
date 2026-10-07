# فحص الالتزام `4df41185` (دمج PR #619 — `chore/branch3-parity-unification`)

**تاريخ الفحص:** 2026-10-07 · **المُفحوص:** `4df41185de931686ba5a215cdba4c7904a82721a`
= `Merge pull request #619 from NassarAlshabi1/chore/branch3-parity-unification`
(= رأس `arena/be8302d7-marina-hotel-wit-app` وقت الفحص).
**الكاتب:** `Parity Bridge <parity-bridge@users.noreply.github.com>` (الطرف الآخر)،
والمدمَج فيه طرفي هذه الجلسة (`a430a628`, `3e71420f`).

## 0) الخلاصة

- **الدمج سليم**: لا فقدان لأي تغيير من أي طرف، ولا ملف مشترك بين الطرفين ⇒ لا
  تعارض دلالي لحلّه. (الأدلة في البند 1).
- **CI على الدمج أخضر** لاختبارات الوحدة والـ worker، و**الـAPK قيد البناء** وقت
  كتابة هذا التقرير. (البند 2).
- **إضافتهم الأساسية** (توحيد مخطط: ترحيل D1 0008/0009 + ترحيل Room 76→77 +
  `finance_snapshots` محلياً) صحيحة من ناحية المخطط والتحقق، لكنها **جاءت بجدول
  Room بلا أي مسار بيانات**: لا كاتب ولا قارئ محلياً، وليس في نطاق السحب.
  وقد كانت تعليقات الملفات ووثيقة التكافؤ تدّعي أنه «يُملأ عبر السحب» — صُحّحت
  التعليقات (البند 3، F-1).

## 1) سلامة الدمج (لا فقدان ولا تعارض)

| الفحص | النتيجة |
| --- | --- |
| أبوا الدمج | `a430a628` (طرفنا) + `f23eb8db` (طرفهم) |
| ملفات الطرفين المتقاطعة | **صفر** — `comm -12` بين قائمتي الملفات المعدّلة عند الطرفين = فارغ |
| ما جلبه طرفهم إلى الدمج (`git diff a430a628 4df41185`) | 11 ملفاً: `worker/migrations/0008`، `0009`، `worker/schema.sql`، `worker/package.json`، `AppDatabase.kt`، `DatabaseModule.kt`، `FinanceSnapshotEntity.kt`، `FinanceSnapshotsDao.kt`، `FinancialMigrationTest.kt`، `schemas/77.json`، `docs/CLOUDFLARE_BRANCH2_3_PARITY_REPORT_AR.md` |
| ما جلبه طرفنا إلى الدمج (`git diff f23eb8db 4df41185`) | 9 ملفات: `SyncEpochs.kt`، `SyncIngestorRegistry.kt`، `RoomsDao.kt`، `RoomsRepositoryImpl.kt`، `BookingsRepositoryImpl.kt`، `PushWireContract.kt`، `SyncEpochParityTest.kt`، ووثيقتان |
| تعديلات جانبية (تغيير نص خارج نطاق الطرفين) | **لا شيء** — كل سطر في الدمج يخصّ أحد الأبوين |

⇒ إصلاح وحدة الطوابع (العطل المطلوب في الرسالة السابقة) باقٍ كاملاً في الدمج.

## 2) أدلة CI على الدمج

| البند | النتيجة |
| --- | --- |
| `Sync Unit Tests (Android + Worker)` — تشغيل `37569814669` | **success** |
| `:app:testDebugUnitTest` | **383 حالة • فشل 0 • أخطاء 0 • متخطّاة 0** (كان 377 قبل `SyncEpochParityTest`) |
| `worker: vitest + typecheck` | success |
| `android-sync-detekt` | success — 320 ملاحظة على ملفات الدفعة (1616 بالمستودع)، إعلامي غير حاجب |
| `Android APK Build (session branch)` — تشغيل `37569814531` | قيد التنفيذ وقت الفحص (النتيجة تُذكر في نهاية المهمة) |
| `Code scanning AI findings on PR #617` | failure (بنية تحتية متكرر، لا علاقة بالدمج) |

ملاحظتان دقيقتان:

1. **383 = 377 + 6**: أصناف `SyncEpochParityTest` الستة هي الفرق بالضبط. وجدول
   الأصناف التفصيلي في ملخص الـcheck-run **لا يذكرها لأن القائمة مبرمجة على ثلاثة
   أصناف** فقط (`.github/workflows/android-sync-unit-tests.yml:202`)، فالعدد
   الإجمالي هو الشاهد، لا الجدول.
2. تشغيلا الالتزام `a430a628` (37569372028 / 37569372108) **أُلغيَا** (cancelled)
   بعد دفع الدمج ⇒ لم يُقيَّما منفصلين، والتحقق الفعلي جاء من تشغيل الدمج.

## 3) مراجعة تقنية لمحتوى طرفهم

### ما تحقّق فعلاً

1. **رفع إصدار المخطط**: `AppDatabase.SCHEMA_VERSION = 77` والملف المُصدَّر
   `app/schemas/…/77.json` موجود (39 كياناً، `identityHash = 6c96e9a3…`).
2. **`MIGRATION_76_77`** ينشئ `finance_snapshots` + فهرسين، ومطابق للمخطط
   المُصدَّر: الأعمدة/الأنواع/`NOT NULL` والافتراضيات (`'base'`, `'{}'`, `0`,
   `''`) وأسماء الفهارس وأعمدتها (بلا `DESC` — Room لا يدعم ترتيباً في `@Index`).
   **التحقق ليس بالورق:** كل اختبار في `FinancialMigrationTest` يفتح القاعدة بعد
   الترحيل، و`RoomOpenHelper.onUpgrade` يشغّل `onValidateSchema` بعد كل ترحيل
   ويرمي `Migration didn't properly handle…` عند أي انحراف — وكلها خضراء في CI.
3. **مخطط الـ Worker**: `0008` فهرس TTL لـ`idempotency_log`، و`0009` جدول
   `finance_snapshots`، وكلاهما منسوخ في `worker/schema.sql`، واثنا السكربتين
   مضافان إلى `worker/package.json` كأوامر `db:migrate:*`.
4. **أثر على مزامنة الدلتا: صفر** — `finance_snapshots` **ليس** في
   `ENTITY_TABLES` في الـ Worker، لا في فرعنا ولا في الفرع المرجعي (تحقّق آلي:
   القائمتان 24 عنصراً في الفرعين، والجدول غائب عنهما) ⇒ لا تُسحب صفوفه ولن
   تُعزل عند أي جهاز.

### Findings

**F-1 (متوسط — تعليقات ووثيقة مضلّلة، صُحّحت)**
`FinanceSnapshotEntity` كان يقول: «The local copy is a mirror pulled during sync
so the Android app can read the latest snapshot offline… Inserted locally only via
the sync ingestor on pull»، و`FinanceSnapshotsDao` يقول: «INSERT is called only by
the sync ingestor when pulling a new snapshot from D1»، ووثيقة التكافؤ (سطر 189)
تقول «DAO للقراءة + upsert على الـ pull». **كل هذا غير صحيح اليوم بالقياس:**

- `finance_snapshots` ليس في `ENTITY_TABLES` (نطاق السحب) ولا في فرعنا ولا في الفرع
  المرجعي ⇒ لا يصل منه صف واحد عبر الدلتا.
- `SyncIngestorRegistry` لا يعرف الكيان: لا `entityClass` ولا `store` ولا
  `fetchExisting` ⇒ لو وصل صفّ منه لكان رُفض `unsupported_entity` وعُزل.
- `financeSnapshotsDao()` مُعلَن في `AppDatabase` لكن **لا مستدعي له في كل
  المصدر** ⇒ لا كتابة ولا قراءة محلياً.

النتيجة: الجدول موجود ومُتحقَّق منه لكنه **معطَّل بلا مسار بيانات** — وهو نفس
الحال على D1 في فرعنا: كاتب الجدول هو مسارات
`/api/finance/*` (`worker/src/finance-data.ts:178/244/264`) وهي **غير موجودة في
فرعنا** (موجودة في الفرع المرجعي فقط). صُحّحت تعليقات الملفين لتقول الحقيقة
بدل الادّعاء.

**F-2 (منخفض — افتراق ترتيب الفهارس بين D1 وRoom، مُوثَّق لا مُصلَّح)**
D1 ينشئ `idx_finance_snapshots_approved` و`idx_finance_snapshots_scenario` بـ
`approved_at DESC`، وRoom بالترتيب الافتراضي ASC. لا أثر وظيفي (SQLite يمسح
الفهرس تصاعدياً أو تنازلياً بالكفاءة نفسها تقريباً)، لكن ادّعاء «المخطط نفسه»
حرفياً غير صحيح — والسبب هو أن `@Index` في Room لا يقبل ترتيباً. الحل المستقبلي
إن أُريد تطابق حرفي: إنشاء الفهارس بـ ASC على D1 أيضاً (تغيير ترحيل منشور ⇒
لا يُعاد، وتُضاف تهيئة لاحقة عند الحاجة).

**F-3 (منخفض — تقرير قديم)**
`docs/CLOUDFLARE_BRANCH2_3_PARITY_REPORT_AR.md` سطر 264 يقول إن اختبار ترحيل
Room 76→77 «موصى به لكن لم يُكتب»، والصحيح أن `f23eb8db` أضاف الترحيل إلى
قوائم `addMigrations` في أربعة اختبارات ومعه تصحيح التوقعات إلى 77. أي أن
التقرير يسبق الالتزام `f23eb8db`؛ يُقرأ معه لا وحده. (سطر 35 «اختبارات
Kotlin/Room… لم تُشغّل» صار كذلك قديماً — تشغيل CI يشغّلها.)

**F-4 (معلومة — قرار مطلوب من صاحب المنتج)**
لا وجود لجدول `finance_snapshots` في أي مسار عمل على فرعنا (لا كاتب على D1، ولا
مسار سحب/REST). فإضافته إلى Room = **مرآة مخطط بلا بيانات**. ثلاثة خيارات:
(أ) إبقاؤه كما هو بعد تصحيح التوثيق — وهو ما فعلته (لا تغيير سلوكي)،
(ب) تنفيذ مسار بيانات حقيقي: نقل مسارات `/api/finance/*` من الفرع المرجعي +
إضافة الكيان إلى نطاق السحب (سياسة جديدة تُدخل بيانات مالية إلى الدلتا — تحتاج
قراراً صريحاً)، (ج) إزالة الجدول (يقتضي ترحيلاً جديداً ورفع الإصدار 77→78 —
غير مُستحسن الآن لأن الفرع المرجعي يحمل الجدول نفسه).

## 4) ما لم يُتحقق (بصراحة)

- لم أشغّل Gradle محلياً (لا toolchain في بيئة الجلسة) — الأدلة من CI.
- بناء الـAPK للدمج **قيد التنفيذ** وقت كتابة التقرير؛ نتيجته تُلحق عند اكتماله.
- لم أفحص سلوك الجدول على قاعدة إنتاج (لا وصول لـD1 من هنا)؛ الادعاءات
  المتعلقة بـD1 مسنودة إلى `worker/schema.sql` + الترحيلات + الشيفرة.
