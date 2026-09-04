# كتيّب التبديل الإنتاجي إلى Cloudflare (Runbook)

**المرجع:** خطة الانتقال إلى Cloudflare Worker — القسمان 10 و11
**الفرع:** `feat/cloudflare-sync-execution`
**القاعدة الذهبية:** لا يُحذف أي كود Appwrite قبل يوم 30 + تصدير أرشيفي موثّق.

---

## التسلسل التنفيذي (المراحل 5–7)

```
[اليوم 0]  ترحيل تجريبي على staging + قائمة فحص E2E كاملة (الخطة 9.2)
[اليوم 1]  Dual-Run: Cloudflare حي + Appwrite قراءة ظل (مقارنة فروق يومية)
[اليوم 7]  مراجعة الفروق: صفر فقد → تعطيل الظل، Cloudflare هو المصدر الوحيد
[اليوم 30] أرشفة Appwrite (تصدير نهائي JSON + .db) ثم إزالة كود المسار
```

---

## 1) إعداد staging (المرحلة 5.1)

```bash
scripts/cloudflare/staging_setup.sh marina-hotel-db-staging
# ثم: انسخ database_id إلى wrangler.toml (أو config منفصل لـ staging)
npx wrangler secret put JWT_SECRET          # ≥64 بايت عشوائية — تدوير دوري
npx wrangler versions upload                # معاينة بلا ترويج (الخطة 10.3)
```

## 2) الترحيل التجريبي والتحقق (المرحلة 5.2–5.3)

1. اسحب نسخة `.db` خام حقيقية من جهاز إنتاج (ميزة Task 21 — ملف واحد مضمون
   السلامة مع `integrity_check` بعد النسخ).
2. شغّل الترحيل عبر `CloudflareMigrationService` (وضع تجريبي، دفعات تكيفية
   مع استئناف تلقائي بعد الانقطاع).
3. بوابة العدّادات:

```bash
scripts/cloudflare/verify_migration_counts.sh <worker_url> <jwt> <local.db>
# ✅ تطابق كامل مطلوب قبل أي تقدم — فروق = توقف وتشخيص
```

4. عينات عشوائية صف-بصف لكل كيان + قائمة E2E كاملة (الخطة 9.2):
   جهازان realtime <3s، قطع شبكة أثناء push/pull، تعارض حقيقي، tombstone
   يفوز، استئناف migration، احترام 429/Retry-After، انتهاء JWT → دخول صامت،
   ودورة مخزون كاملة (الفجوة المغلقة D7).

## 3) Dual-Run (المرحلة 6 — أسبوع مراقبة)

- التطبيق يدفع ويقرأ من **Cloudflare فقط**.
- **المقارنة الظلّية مدمجة في التطبيق**: `CloudflareDualRunService`
  يشغّل جولة مقارنة عدّادات (D1 `/api/stats` مقابل Appwrite — قراءة-فقط)
  بعد 5 دقائق من الإقلاع ثم كل 12 ساعة؛ الفروق تُسجَّل في السجل وتُحفظ
  آخر جولة في `SharedPreferences` (`cloudflare_shadow_last_compare`).
- **مفتاح الإيقاف عن بُعد**: Remote Config `cloudflare_sync_enabled=false`
  → تعطيل فوري لمسار Cloudflare (sync + realtime) بلا نشر تحديث — رجوع
  في دقائق. تجاوز محلي للتشغيل: `CloudflareDualRunService.setLocalOverride`.
- **مراجعة يومية**: صفر فروق ظل متتالية لمدة 7 أيام = بوابة اليوم 7.

## 4) التبديل النهائي (المرحلة 7 — بعد اليوم 7)

1. عطّل قراءة الظل (`cloudflare_shadow_enabled=false` لاحقاً أو أزل الجدولة).
2. Cloudflare = المصدر الوحيد. Appwrite يبقى **متاحاً للقراءة/الرجوع** حتى
   اليوم 30 (قرار D10).
3. بعد اليوم 30: تصدير نهائي (`wrangler d1 export` + تصدير Appwrite JSON)
   ثم إزالة كود مسار Appwrite في إصدار لاحق (يبقى مقروءاً لإصدارين).

## 5) خطة الرجوع (Rollback)

| السيناريو | الإجراء | الزمن |
|---|---|---|
| فشل وظيفي مبكر (أيام 1–7) | `cloudflare_sync_enabled=false` → العودة لـ Appwrite (لم يُمس) | دقائق |
| فقد بيانات بعد التبديل | نسخ `.db` اليومية (Task 21) + `wrangler d1 export` → مقارنة → إعادة إدخال الفرق عبر `/api/sync/migrate` | ساعات |
| كارثة D1 | `wrangler d1 export` يومي مجدول (cron Worker → R2) — يُفعّل في المرحلة 6 | ساعات |

## 6) الأسرار والتشغيل

| العنصر | القناة | ملاحظة |
|---|---|---|
| `JWT_SECRET` | `wrangler secret put` | ≥64 بايت، تدوير دوري 🔴 |
| `JWT_EXPIRY_HOURS=24` | `[vars]` | بلا نشر جديد |
| `CORS_ORIGIN` | `[vars]` | يُضيّق عند إضافة لوحة ويب |
| عميل Flutter | `--dart-define` (`CLOUDFLARE_WORKER_URL/USERNAME/PASSWORD`) | كلمة مرور لكل جهاز — أفضل من مفتاح مدمج |

تصدير احتياطي يومي:

```bash
npx wrangler d1 export marina-hotel-db --remote --output=backup_$(date +%F).sql
```
