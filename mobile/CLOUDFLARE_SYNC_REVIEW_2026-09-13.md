# تقرير مراجعة مسار Cloudflare Sync — 2026-09-13

> مراجعة هندسية معمّقة لمجلد `mobile` (مسار Cloudflare) وعقد الـ `worker` مقابل
> معايير مزامنة إنتاجية: Outbox + Idempotency، LWW مع Version، Cursor رتيب،
> Tombstones، إعادة محاولة بـ Backoff، ولا وصول مباشر لـ D1 من العميل.

## نتيجة الفحص الآلي للخادم قبل الدمج

- `tsc --noEmit`: نظيف.
- `npm test`: **117/117 ناجح** (بعد الإصلاحات أدناه).

## ما تم إصلاحه في هذا الالتزام

| # | الخطورة | الملف | المشكلة والإصلاح |
|---|---------|-------|-------------------|
| M3 | 🔴 MAJOR | `mobile/lib/services/cloudflare_sync_manager.dart` | **إسقاط دائم لتحديثات الأجهزة الأخرى عند انزياح ساعة الجهاز**: كان `localUpdatedAt > remoteUpdatedAt` يُسقط الوارد فوراً بينما المؤشر يتقدم فوقه فلا يعود الصف أبداً. الآن: إن كان `version` الوارد أعلى (دليل مستقل عن الساعات) يُطبَّق/يُدمج عبر المسار الموجود. |
| M4 | 🟠 MAJOR | `cloudflare_sync_manager.dart` + `worker/src/sync.ts` | **الرفض الدائم كان يُعاد حتى عتبة dead-letter بلا فائدة**: العميل يقرأ `status` والخادم لا يرسله. الآن الخادم يرسل `status: 'validation_error'` صراحةً، والعميل يصنّف أيضاً أنماط الرسائل الدائمة (`is required`, `Invalid operation`, ...) كخطأ دائم فوراً. |
| M5 | 🟠 MAJOR | `mobile/lib/tasks/auto_sync_task.dart` | **مهمة الخلفية كانت معطلة لأجهزة Cloudflare-only**: البوابة تشترط `google_drive_sync_enabled`. الآن أي مسار سحابي مفعّل (`appwrite_sync_enabled` يشمل Cloudflare) يكفي، مع بقاء مفتاح الإيقاف الداخلي هو القرار النهائي. |
| M2 | 🟠 MAJOR | `mobile/lib/services/cloudflare_config.dart` | **كلمة مرور المزامنة كانت نصاً صريحاً في SharedPreferences** (تُسرَّب مع Android Auto Backup). الآن: `flutter_secure_storage` (Keystore/Keychain/DPAPI) أساساً، مع ترحيل لمرة واحدة من القيمة القديمة، وfallback لـ prefs فقط في البيئات بلا Keystore (يبقي الاختبارات العقدية hermetic خضراء دون تعديلها). |
| R1 | 🟡 MINOR | `cloudflare_sync_manager.dart` | **تجاهل Retry-After عند 429**: كان الخادم يخنق والدفع يعاود فوراً. الآن تُقرأ المدة (هيدر بالثواني أو epoch في الجسم) وتُبرمَج تهدئة حتى 600ث تُفحص قبل أي reclaim. |
| R-min5 | 🟡 MINOR | `cloudflare_sync_manager.dart` + `cloudflare_migration_service.dart` | حذف `Content-Length` اليدوي مع gzip (حزمة http تحسبه، والتكرار يربك البروكسيات). |
| W-M1 | 🟠 MAJOR | `worker/src/database.ts` | **تسمّم ساعة المزامنة بنطاق الميلي ثانية**: طابع `1.7e12` متسلل من ترحيل قديم كان يقفز بـ `sync_clock` فيعيد `normalizeTimestamps` ختم 500 صف/سحب بلا تقارب أبدي. الآن `advanceSyncClock` تتجاهل أي قيمة فوق عتبة `1e11` الموثقة. |
| W-min2 | 🟡 MINOR | `worker/src/sync.ts` + `database.ts` | **LIMIT سالب في SQLite = بلا حدّ**: تقييد `[1, N]` إجباري في `sync/log` و`conflicts` ودوال القراءة. |

## ما يحتاج قراراً منك (لم يُغيَّر عمداً)

1. **🔴 اعتمادات admin مدمجة في التطبيق** (`lib/utils/env.dart` — `CLOUDFLARE_PASSWORD` الافتراضي `admin`، بطلبك الموثق للدخول التلقائي): أي شخص يفكك الـ APK يمتلك حساب admin كامل الصلاحيات على الـ Worker الإنتاجي. التوصية بالترتيب:
   - غيّر كلمة مرور admin على الـ Worker فوراً وأبقِها قوية، ثم مرّرها عبر `--dart-define` عند البناء بدل الافتراضي المدمج، أو
   - أنشئ حساب خدمة `sync_service` محدود الصلاحيات خادمياً (Worker يفرض role-scoped authorization على push/pull) واستخدمه افتراضياً بدل admin.
2. **🔴 عميل D1 HTTP مباشر في التطبيق** (`cloudflare_d1_service.dart` يستدعي `api.cloudflare.com` بـ SQL خام لتوكن بصلاحية Edit — يُستخدم لزر النسخ الاحتياطي في `cloudflare_d1_tab.dart`): هذا يتجاوز كل validation/rate-limit خادمية. التوصية: إعادة توجيه رفع النسخة إلى `POST /api/sync/migrate` الموجود أصلاً في الـ Worker (نفس مسار `cloudflare_migration_service.dart`)، ونقل فحوص الاتصال إلى نقطة `/api/diagnostics` خادمية، ثم سحب صلاحية D1 Edit من أي توكن يوزَّع على الأجهزة.
3. **اقرأ تعارضات الخادم**: الـ Worker يسجل تعارضات LWW ويكشفها عبر `GET /api/sync/conflicts` لكن لا يقرأها أي كود في `lib/` — يستحق ربطاً بشاشة التعارضات في تكرار قادم.
4. **ملاحظة توثيق**: README الـ worker يقول سقف السحب 200 بينما الكود 500 — يُحدَّث لاحقاً.

## ما ثبتت سلامته في المراجعة (بلا تغيير)

- حلقة السحب: مؤشر رتيب لا يتراجع، حفظ بعد دورة نظيفة فقط، تراجع كامل عند الفشل، حجر صحي للصفوف اليتيمة، تطبيق tombstones حذفاً ناعماً.
- مسار الدفع: `idempotencyKey` لكل عملية، لا حذف من الـ outbox قبل تأكيد الخادم، مطابقة النتائج بالمفتاح بلا orElse خطير.
- عقد السلك: `payload_normalizer.dart` مطابق تماماً لـ `PushOperation` الخادمي، الأوقات بالثواني على الطرفين.
- `worker_endpoints.dart`: تعدد نقاط + sticky + دعم custom domain (جاهز لتجاوز حجب workers.dev).
- اختبارات الـ worker (11 ملفاً/117 اختباراً): تغطية استثنائية للحدود والـ idempotency وLWW وSQLi — كلها خضراء بعد الإصلاحات.
