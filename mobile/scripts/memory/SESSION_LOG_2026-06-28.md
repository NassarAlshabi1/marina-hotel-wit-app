# 📒 سجل جلسة العمل الشاملة - Marina Hotel Mobile

**تاريخ الجلسة:** 2026-06-28
**الفرع:** `marina`
**المستودع:** `https://github.com/NassarAlshabi1/marina-hotel-wit-app`
**عدد الالتزامات (commits):** 7
**إجمالي الأسطر المُعدَّلة:** ~2,500+ إضافة، ~1,800+ حذف

---

## 📋 فهرس الالتزامات

| # | Hash | النوع | العنوان |
|---|------|------|---------|
| 1 | `0d1877e6` | 🔒 fix | SQL injection + hardened upsert against document_already_exists race |
| 2 | `4053fe55` | ✨ feat | Wire Vector Clock + SmartConflictResolver into production sync |
| 3 | `e6cb67f1` | 🔧 refactor | Unify VectorClock, hash passwords, expand entity policies |
| 4 | `f3c8d19c` | 🐛 fix | booking_checkout_screen — transactions, VC bumping, debt amount |
| 5 | `2cbadd68` | ⚡ perf | Dashboard + GDrive backup integrity |

---

## 1. تثبيت البيئة

### Flutter SDK 3.35.7
- **المسار:** `/home/z/my-project/sdks/flutter/`
- **الإصدار:** Flutter 3.35.7 (stable) / Dart 3.9.2 / DevTools 2.48.0
- **التفعيل:** `export PATH="/home/z/my-project/sdks/flutter/bin:$PATH"`

### استنساخ المستودع
- **الفرع:** `marina`
- **عدد الملفات:** 593 ملف في `mobile/`
- **الالتزام الأخير قبل الجلسة:** `6f3a6743` (smart conflict resolution system)

---

## 2. الإصلاحات الأمنية (Commit 1: `0d1877e6`)

### 2.1 ثغرة SQL Injection في `outbox_dao.dart`

**الموقع:** `lib/services/daos/outbox_dao.dart` — دالة `takeBatch`

**المشكلة:**
```dart
// قبل الإصلاح — string concatenation:
final sourceCondition = (sources != null && sources.isNotEmpty)
    ? ' AND source IN (${sources.map((s) => "'$s'").join(',')})'
    : '';
```

**الإصلاح:** parameterized query + 4 طبقات دفاع:
1. Allowlist regex: `^[a-zA-Z0-9_-]+$`
2. Length validation (max 50)
3. `?` placeholders بدلاً من string interpolation
4. `safeSources` local variable

**الفحص الشامل:** فُحصت 227 موقع `customSelect`/`customStatement` في 24 ملف — الموقع الوحيد الحقيقي للخطر كان `outbox_dao.dart`.

### 2.2 خطأ `document_already_exists` (409) في upsert

**الموقع:** `lib/services/appwrite_service.dart` — `_upsertDocumentInternal`

**المشكلة:** Step 3 و Step 5 في منطق upsert كانا بدون retry/timeout/try-catch.

**الإصلاح:**
- استخراج `doUpdate()` و `doCreate()` كدوال مساعدة مُلفوفة بـ `withRetryAndTimeout`
- Steps 3 و 5 مُغلَّفة بـ try-catch + تسجيل مفصّل (tag='UPSERT')

---

## 3. نظام Vector Clock الكامل (Commit 2: `4053fe55`)

### 3.1 ملخص العيوب المُكتشفة

| المستوى | الحالة قبل الإصلاح | الحالة بعد الإصلاح |
|---------|-------------------|-------------------|
| Level 0: LWW | يعمل | يعمل (fallback) |
| Level 1: VC Detection | متصل بـ 2/17 كيان | متصل بـ 17/17 كيان |
| Level 2: Field-Level 3-Way Merge | dead code | متصل عبر SmartConflictResolver |
| Level 3: Semantic Resolution | dead code | متصل (18 سياسة كيان) |

### 3.2 الإصلاحات P0 (عاجلة)

#### P0-1: VC bumping قبل كل push
**الملف:** `lib/services/sync_core/sync_push_service.dart`
- دالة جديدة: `_bumpVectorClockBeforePush(entity, localUuid)`
- تُستدعى في `_processOutboxEntry` dispatcher قبل كل push غير حذف
- تقرأ VC الحالي، تزيد عداد الجهاز، تكتبه في DB
- خريطة 20 كيان → اسم جدول

#### P0-2: تمرير `localVectorClock` في جميع 17 موقع
**الملف:** `lib/services/appwrite_sync_manager.dart`
- كان: 2/17 موقع يمرر VC (rooms, bookings)
- الآن: 17/17 موقع يمرر `localVectorClock`, `entityName`, `localUuid`

#### P0-3: تكامل SmartConflictResolver في فرع concurrent
**الملف:** `lib/services/appwrite_sync_manager.dart`
- `_isRemoteDataNewer` أصبحت `Future<_RemoteNewerResult>`
- `_RemoteNewerResult` يحمل `shouldApplyRemote` + `mergedData` + `pushedToRemote`
- في فرع `concurrent`: يستدعي `SmartConflictResolver.resolve()` مع ancestor من `AncestorCacheDao`
- إذا `fieldLevelMerge` → يُرجع البيانات المدمجة
- إذا `manualEscalation` → يُسجّل في `sync_conflicts` ويحتفظ بالمحلي

#### P0-4: AncestorCacheDao متصل
- حقل جديد: `_ancestorCacheDao` في `AppwriteSyncManager`
- `getAncestor()` يُستدعى في فرع concurrent لـ 3-way merge

### 3.3 الإصلاحات P1 (عالية)

#### P1-5: إزالة `'status'` من `_criticalFields`
**الملف:** `lib/services/sync_core/conflict_detector.dart`
- كان `'status'` في القائمة الحرجة → تصعيد كل تعارض status إلى manual
- لكن سياسة `bookings` تقول `status=newerWins` → تناقض
- أُزيل `'status'`، أُبقيت الحقول المالية فقط

#### P1-6: استثناء `vectorClock` من `_findChangedFields`
- أضيفت `vectorClock`, `vector_clock`, `last_modified`, `updated_at` لقائمة الاستثناءات
- منع التعارضات الوهمية بعد كل merge

#### P1-7: `max(localTs, remoteTs)` بدلاً من `DateTime.now()`
**الملف:** `lib/services/sync_core/smart_conflict_resolver.dart`
- `_autoMerge` كان يكسر idempotency عبر timestamp جديد
- الآن يستخدم `max(localTs, remoteTs)` — يحافظ على الترتيب السبكي

#### P1-8: 49 اختبار وحدة جديد
- `test/unit/conflict_detector_test.dart` — 29 اختبار
- `test/unit/smart_conflict_resolver_test.dart` — 20 اختبار

#### P1-9: التسجيل الفعلي في `sync_conflicts`
- `_logConcurrentConflict` أصبحت `async`
- تنشئ سجل `SyncLog` أولاً (للـ FK)، ثم `SyncConflicts` مع full conflict data
- audit trail دائم في SQLite

### 3.4 الإصلاح P2-12: Deduplication في `concat`
- دالة جديدة: `_concatWithDedup(local, remote)`
- تقسيم على `\n---\n`، دمج الأجزاء، إزالة التكرارات
- منع تضخم النصوص بعد عدة عمليات دمج

---

## 4. توحيد VectorClock + تشفير كلمات المرور (Commit 3: `e6cb67f1`)

### 4.1 P2-10: توحيد تنفيذَي VectorClock

| الإجراء | الملف | الأسطر |
|---------|------|--------|
| 🗑️ حذف | `lib/services/vector_clock.dart` | 124 سطر (dead code) |
| 🗑️ حذف | `lib/services/conflict_resolver.dart` | 360 سطر (dead code) |
| 🗑️ حذف | `lib/services/sync_manager.dart` | 1041 سطر (dead code) |
| 🗑️ حذف | `test/vector_clock_test.dart` | 46 سطر |
| 🗑️ حذف | `test/conflict_resolver_test.dart` | 174 سطر |
| ✏️ تحديث | `lib/sync/vector_clock.dart` | +19 سطر (deprecation header) |

**النتيجة:** حذف **1753 سطر كود ميت**. التنفيذ الكنزي: `lib/services/vector_clock_service.dart`.

### 4.2 P2: تشفير كلمات المرور (PBKDF2)

**ملف جديد:** `lib/services/password_hasher.dart`
- **الخوارزمية:** PBKDF2-HMAC-SHA-256
- **التكرارات:** 100,000
- **Salt:** 16 بايت عشوائي (Fortuna PRNG)
- **الصيغة:** `pbkdf2_sha256$<iter>$<salt_b64>$<hash_b64>`
- **مقاومة timing attacks:** مقارنة ثابتة الزمن

**تحديثات `auth_local_store.dart`:**
| العملية | قبل | بعد |
|---------|------|------|
| `validateCredentials` | `storedPassword != password` | `PasswordHasher.verify(password, stored)` |
| `addUser` | يخزّن plaintext | يخزّن PBKDF2 hash |
| `_pushUserToCloud` | يرفع plaintext | يرفع PBKDF2 hash |
| `updateCloudUser` | يحدّث plaintext | يحدّث PBKDF2 hash |
| `_migratePasswordToHashed` (جديد) | ❌ | ✅ ترحيل تلقائي عند تسجيل الدخول |

**اختبارات:** 21 اختبار في `test/unit/password_hasher_test.dart`

### 4.3 توسيع سياسات SmartConflictResolver (7 → 18 كيان)

الكيانات الجديدة الـ 11:
- `salary_withdrawals`, `salary_payments`, `cash_transactions`
- `shift_notes`, `guest_infos`, `booking_nights`
- `salary_cycles`, `booking_price_adjustments`
- `blacklist`, `price_adjustments`, `payment_voids`
- `audit_logs`

---

## 5. إصلاحات booking_checkout_screen (Commit 4: `f3c8d19c`)

### 5.1 P0-1: Transaction موحد
- `_completeCheckoutNow`: 4 عمليات DB مُغلَّفة في `db.transaction()`
- `_completeCheckout`: 3 عمليات DB مُغلَّفة في `db.transaction()`
- atomicity: فشل أي عملية يُلغي الكل

### 5.2 P0-2: `markDataChanged()` بعد حذف الليالي
- تحويل من `hard-delete` إلى `soft-delete` (deletedAt=epoch)
- `markDataChanged()` فوراً بعد الحذف
- الليالي المحذوفة تُرفع للسحابة ولا تعود

### 5.3 P0-3: تصحيح `totalAmount` في الدين
- قبل: `totalAmount=totalDue, paidAmount=totalPaid` (مبالغ مزدوجة)
- بعد: `totalAmount=remainingAmount, paidAmount=0` (المتبقي فقط)

### 5.4 P1-4, P1-5: VC bumping بعد الكتابة
**ملف جديد:** `lib/services/vector_clock_helper.dart`
- `VectorClockHelper.bump(db, entity, localUuid)` — أداة عامة
- خريطة 18 كيان → اسم جدول
- تُستدعى بعد `bookingsRepo.update`, `paymentsRepo.create`, `debtsRepo.create`

### 5.5 إصلاحات أخرى
- P1-6: `_countNightsWithDiscount` — منطق أوضح
- P2-7: إزالة فحص الكسور المكرر
- P2-9: `_showSuspiciousNightsDialog` — `Future<void>` بدلاً من `Future<bool>`

---

## 6. تحسينات Dashboard + GDrive Backup (Commit 5: `2cbadd68`)

### 6.1 Dashboard Performance

| الإصلاح | التأثير |
|---------|---------|
| توحيد `ref.watch` في `Consumer` واحد | تقليل إعادة البناء للنصف |
| `RepaintBoundary` حول بطاقات الإحصائيات | عزل إعادة الرسم |
| `RepaintBoundary` حول شبكة الغرف | عزل رسوم `flutter_animate` |

### 6.2 GDrive Backup Integrity

| # | الإصلاح | التفاصيل |
|---|---------|---------|
| 1 | استدعاء `verifyBackupChecksum` قبل الاستعادة | كشف البيانات التالفة قبل حذف الجداول |
| 2 | SHA-256 checksum لنسخ `.db` | `appProperties.data_hash` + `file_size` |
| 3 | التحقق من checksum عند استعادة `.db` | فحص الحجم + SHA-256 بعد التنزيل |
| 4 | `listDbBackups` pagination | `do-while` loop على `nextPageToken` |

---

## 7. الإحصائيات النهائية

### 7.1 الاختبارات
- **`flutter analyze`:** No issues found! (في كل التزام)
- **`flutter test`:** 99/99 اختبار ناجح
  - 29 conflict_detector tests
  - 20 smart_conflict_resolver tests
  - 21 password_hasher tests
  - 29 vector_clock tests (موجودة)

### 7.2 الملفات الجديدة
1. `lib/services/password_hasher.dart` — تشفير PBKDF2
2. `lib/services/vector_clock_helper.dart` — أداة زيادة VC
3. `test/unit/conflict_detector_test.dart` — 29 اختبار
4. `test/unit/smart_conflict_resolver_test.dart` — 20 اختبار
5. `test/unit/password_hasher_test.dart` — 21 اختبار

### 7.3 الملفات المحذوفة (dead code)
1. `lib/services/vector_clock.dart` (124 سطر)
2. `lib/services/conflict_resolver.dart` (360 سطر)
3. `lib/services/sync_manager.dart` (1041 سطر)
4. `test/vector_clock_test.dart` (46 سطر)
5. `test/conflict_resolver_test.dart` (174 سطر)

**إجمالي الكود الميت المُحذوف:** 1,745 سطر

### 7.4 الملفات المُعدَّلة الرئيسية
1. `lib/services/appwrite_sync_manager.dart` — 6302 سطر (VC integration + sync_conflicts logging)
2. `lib/services/appwrite_service.dart` — upsert retry/timeout
3. `lib/services/daos/outbox_dao.dart` — parameterized query
4. `lib/services/sync_core/conflict_detector.dart` — criticalFields + vectorClock exclusion
5. `lib/services/sync_core/smart_conflict_resolver.dart` — max ts + concat dedup + 11 policies
6. `lib/services/sync_core/sync_push_service.dart` — VC bumping
7. `lib/services/auth_local_store.dart` — password hashing
8. `lib/services/google_drive_backup_service.dart` — checksum + pagination
9. `lib/screens/payments/booking_checkout_screen.dart` — transactions + VC + debt fix
10. `lib/screens/dashboard_screen.dart` — performance

---

## 8. القواعد الذهبية المُكتسبة

### 8.1 Vector Clock
- ✅ `increment()` يجب أن يُستدعى قبل كل push (ليس فقط عند المعالجة)
- ✅ كل `repository.update` يجب أن يزيد VC فوراً عبر `VectorClockHelper.bump`
- ✅ `_findChangedFields` يجب أن يستثني `vectorClock` (يتغير بعد كل merge)
- ✅ `lastModified` في الدمج يجب أن يكون `max(local, remote)` وليس `DateTime.now()`

### 8.2 الأمان
- ✅ لا string concatenation في SQL — parameterized queries دائماً
- ✅ كلمات المرور بـ PBKDF2 (100K تكرار) + salt عشوائي + constant-time comparison
- ✅ ترحيل تلقائي للأنظمة القديمة (plaintext → PBKDF2 عند تسجيل الدخول)

### 8.3 المزامنة
- ✅ عمليات DB متعددة في transaction موحد (atomicity)
- ✅ `markDataChanged()` فوراً بعد كل كتابة محلية
- ✅ soft-delete بدلاً من hard-delete (لرفع الحذف للسحابة)
- ✅ 18 سياسة كيان صريحة في SmartConflictResolver

### 8.4 النسخ الاحتياطي
- ✅ SHA-256 checksum لكل نسخة (JSON + .db)
- ✅ التحقق من checksum قبل الاستعادة
- ✅ pagination في listBackups (do-while loop)

### 8.5 الأداء
- ✅ `RepaintBoundary` حول الأقسام المستقلة
- ✅ توحيد `ref.watch` في `Consumer` واحد
- ✅ `const` widgets حيثما أمكن

---

## 9. تحذيرات أمنية

⚠️ **GitHub Token:** ظهر token (`ghp_...`) في محادثة سابقة — يجب إبطاله فوراً من إعدادات GitHub.

⚠️ **Dependabot:** 7 ثغرات في الفرع الافتراضي (4 high, 3 moderate) — يجب مراجعتها على https://github.com/NassarAlshabi1/marina-hotel-wit-app/security/dependabot

---

## 10. الخطوات التالية المقترحة

1. **اختبار على جهازين حقيقيين** للتحقق من كشف التعارضات المتزامنة
2. **مراجعة تنبيهات Dependabot** (7 ثغرات)
3. **اختبار تسجيل الدخول** بمستخدم موجود (سيتم ترحيل كلمة مروره تلقائياً)
4. **اختبار استعادة نسخة `.db`** قديمة وجديدة
5. **فتح PR** من `marina` للفرع الرئيسي لمراجعة كل التحسينات

---

**آخر تحديث:** 2026-06-28
**الحالة:** جميع الإصلاحات مُلتزمة ومرفوعة لفرع `marina` ✅
