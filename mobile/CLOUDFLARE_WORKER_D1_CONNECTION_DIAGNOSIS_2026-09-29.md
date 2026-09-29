# مسودة تشخيص: فشل اتصال التطبيق مع Cloudflare Worker / D1

> **الحالة:** مسودة للمراجعة، وليست قراراً نهائياً.
> **الفرع:** `feat/cloudflare-sync-execution` @ `9c76df83` (يشمل جسر pages.dev من `ee07d5c3`).
> **تاريخ الفحص:** 2026-09-29 UTC.
> **المنهج:** قراءة الكود الفعلي مع أرقام الأسطر، وفحص شبكة حي للسلسلة كاملة (DNS ← TLS ← `/health` ← login ← D1)، وحساب زمني لميزانيات المهلات.
> **الحدود:** لم يتوفر هنا Flutter/Dart لتشغيل اختبارات العميل، ولم تصلنا سجلات من جهاز المستخدم. أي ادعاء خاص بشبكة المستخدم موسوم بـ«فرضية» أو «مرجح»، ولا يُعرض كحقيقة.

---

## 0. تصحيحات على المسودة السابقة

| ادعاء المسودة السابقة | الواقع عند الفحص (2026-09-29) | الأثر |
|---|---|---|
| «`*.workers.dev` لا يُحل في بيئة التشخيص (NXDOMAIN)، مؤكد» | **غير قابل للتكرار الآن:** `getent` يحل `marina-hotel-api.adenmarina2.workers.dev → 172.67.165.5`، و`/health` يعيد 200 خلال 0.09 ث. | تلك النتيجة لقطة من بيئة أو وقت آخر، ولا تصلح دليلاً ثابتاً. |
| «الإصلاح الجذري الوحيد هو نطاق مخصّص» | الفرع يحوي أصلاً **جسر `marina-hotel-api-relay.pages.dev`** مرشحاً ثالثاً دائماً، وهو يعمل حالياً (انظر §1). | النطاق المخصّص صار احتياطاً لحالة حجب `pages.dev` أيضاً، وليس الخطوة الأولى. |
| «D1 binding غير مؤكد السلامة» | **مؤكد سليم:** دخول حقيقي ثم `/api/health/d1` أعاد `200 {"d1":"ok","latency_ms":~240}` عبر المسارين. | D1 والـ Worker خارج دائرة الاتهام. |
| «الواجهة تجمع كل فشل D1 تحت عبارة واحدة بلا تفريق» | صحيح جزئياً: العنوان موحّد، لكن `d1Error` يُلحق بين قوسين (`cloudflare_auto_connection_card.dart:112-116`)، فرسالة 401 ورمز HTTP يظهران فعلاً. | المشكلة في **العنوان المضلل** (401 يُعرض كـ«D1 لا تستجيب»)، وليست في غياب المعلومة. |
| «pure DNS block يفسر الفشل» | الكود الحالي يتجاوز حجب DNS وحده: DoH ثم نفق CONNECT بالـ IP مع SNI حقيقي (`resilient_http_client.dart:255-290`). | الفشل **المستمر** على شبكة يمنية يعني حجب SNI أو حجب `pages.dev` أيضاً أو خللاً في العميل، وليس حجب DNS وحده. |

---

## 1. الأدلة الحية (مسجّلة في `/tmp/logs/net_probe.log` و`/tmp/logs/chain_probe.log`)

```text
DNS (resolver النظام):
  marina-hotel-api.adenmarina2.workers.dev → 172.67.165.5
  marina-hotel-api-relay.pages.dev         → 172.66.47.73
DNS (dns.google): كلاهما Status 0 مع سجلَي A لكل اسم.

GET /health
  workers.dev → 200  dns=0.030s connect=0.031s tls=0.057s total=0.093s
  pages.dev   → 200  dns=0.019s connect=0.021s tls=0.045s total=0.156s

POST /api/auth/login  ثم  GET /api/health/d1 (Bearer)
  pages.dev   → login 200 (1.06s) → d1 200 {"d1":"ok","latency_ms":241}
  workers.dev → login 200 (0.92s) → d1 200 {"d1":"ok","latency_ms":239}
```

**الحكم المؤكد:** الخادم سليم كاملاً على مستوى Worker والجسر والمصادقة وbinding ‏`DB`. بيانات `wrangler.toml` (`database_id = 607f1090-…`) مطابقة للنشر الفعلي، لأن استعلام `SELECT 1` نجح عبر الـ binding. **لا تغيّر `database_id` ولا `JWT_SECRET` ولا تُعِد نشر الـ Worker لإصلاح هذا العطل.**

إذن فشل الاتصال الذي يراه المستخدم يقع في أحد ثلاثة مواضع: **الشبكة بين الجهاز وحافة Cloudflare**، أو **منطق العميل**، أو **نسخة APK لا تحوي الإصلاحات**.

---

## 2. خريطة المسار الفعلية (من الكود)

```
الجهاز ──► WorkerEndpoints.active  (worker_endpoints.dart:128)
            ترتيب المرشحين: custom → relay(pages.dev) → builtin(workers.dev)   (:239-243)
            │
            ├─ فحص البطاقة: ConnectionStatusNotifier.checkConnection
            │    http.Client عادي، مهلة 8ث، بلا DoH/نفق/تدوير      (appwrite_providers.dart:207-254)
            │    يستدعي reportSuccess/reportFailure ← يغيّر sticky للمزامنة أيضاً!
            │
            ├─ المزامنة/الدخول: CloudflareSyncManager
            │    ResilientHttpClient: مسار سريع 6ث → DoH ≤8ث → نفق (30ث/IP) → المرشح التالي
            │    login مغلف بـ .timeout(15ث) × 3 محاولات      (cloudflare_sync_manager.dart:855-930)
            │
            ├─ Realtime WS: يدور على candidatesFor بنفسه، بلا DoH/نفق  (cloudflare_realtime_sync.dart:320-345)
            └─ Finance/AI: http.Client عادي على active فقط، بلا تدوير  (cloudflare_finance_service.dart:173، cloudflare_ai_service.dart:147)

Pages relay (_worker.js) ──► fetch(workers.dev) داخل شبكة Cloudflare
Worker: /health (بلا D1 وبلا rate limit) | rate limit عبر D1 | /api/auth/login (دلو 20/دقيقة لكل clientIp) | /api/health/d1 (SELECT 1)
```

---

## 3. العيوب المثبتة في الكود (مع السطر والسيناريو)

### C1 — [P0 أمني] بيانات الدخول الافتراضية `admin/admin` مدمجة في التطبيق وتعمل على الإنتاج
- `mobile/lib/utils/env.dart:226-240`: `cloudflareUsername/Password` افتراضياً `admin`/`admin`.
- **تحقق حي:** `POST /api/auth/login {"admin","admin"}` أعاد **200 وتوكن admin**.
- `JWT_EXPIRY_HOURS = "0"` في `wrangler.toml`، أي أن التوكن **بلا انتهاء**.
- **السيناريو:** أي شخص يفك APK أو يقرأ README يحصل على توكن admin دائم، فيقرأ ويكتب D1 كاملة عبر `/api/sync/*`.
- هذا لا يسبب فشل الاتصال، لكنه أخطر ما ظهر في الفحص، ويجب أن يُعالج قبل أي تحسين آخر.

### C2 — [P1] فحص البطاقة ينزّل الجسر العامل إلى workers.dev المحجوب
- `appwrite_providers.dart:224-252`: أي استثناء أو رد غير 200 خلال **8 ثوانٍ عبر `http.Client` عادي** يستدعي `WorkerEndpoints.reportFailure(healthUri)`.
- `worker_endpoints.dart:208`: بلا نطاق مخصّص تكون المرشحات `[relay, builtin]`، وفشل relay (idx 0) يجعل `_activeOverride = builtin`.
- **السيناريو (اليمن، شبكة بطيئة):** رد الجسر تأخر 8.1 ث مرة واحدة، فيُنزَّل الجسر ويصبح `active = workers.dev` المحجوب بـ SNI. كل طلب مزامنة بعدها يبدأ بالمرشح المحجوب (`candidatesFor` يضع عنوان الطلب أولاً، `:165`). يتعافى الوضع فقط بعد أن يفشل فحص البطاقة التالي (30-60 ث) على workers.dev فيعود للجسر. النتيجة **رفرفة**: متصل ← غير متصل ← متصل.
- يزيد الأمر سوءاً أن فحص البطاقة لا يملك DoH ولا نفقاً ولا تدويراً، فهو **أضعف** من المسار الذي يتحكم في اختيار نقطته.

### C3 — [P1] ميزانية مهلة الدخول (15ث) أقصر من أسوأ زمن للمرشح الأول، فلا يُبلغ الجسر
- `cloudflare_sync_manager.dart:868`: `.timeout(15s)` يلف **كامل** `ResilientHttpClient.send` بما فيه التدوير.
- أسوأ زمن للمرشح المحجوب قبل الانتقال للتالي (`resilient_http_client.dart`):
  - مسار سريع: 6 ث (`:218-226`)
  - DoH: حتى 8 ث (`:~647`)
  - نفق لكل IP: حتى 30 ث (`_timeout`، `:283-289`)، ويصل إلى 6 IPs
  - المجموع: **≥ 14 ث قبل أول بايت عبر النفق**، أي أن 15 ث تنتهي قبل الوصول إلى `relay`.
- **السيناريو:** `active = workers.dev` (بعد C2 أو C4)، والشبكة تُسقط ClientHello بصمت (blackhole لا RST). تنتهي المحاولة 1 بـ Timeout عند 15 ث، والمحاولتان 2 و3 مبنيتان على `CloudflareConfig.workerUrl`، الذي يبقى workers.dev ما لم يُنزّله أحد. قاطع المسار السريع (10 د) يرسلهما مباشرة للنفق فتنتهيان بمهلة أيضاً. الحصيلة ≈ 49 ث ثم رسالة `TimeoutException … workers.dev`. أما مستقبل المحاولة 1 فيبقى يعمل في الخلفية ويصل لاحقاً إلى الجسر وينجح ويثبّته، لكن **التوكن الناتج يُهمل**. التعافي يحدث في دورة الدخول الكسول التالية بعد 60 ث (`lazyInitCooldown`).
- إذا كانت الشبكة ترسل RST بدل الإسقاط الصامت فالفشل سريع ويصل التدوير إلى الجسر ضمن الميزانية. **لذلك الأثر مشروط بنمط الحجب**، ويُحسم بسجل جهاز واحد (§6).

### C4 — [P2] التركيبات المُحدَّثة (لا الجديدة) تبدأ على workers.dev
- `worker_endpoints.dart:113-115`: `load()` يرقّي sticky القديم إلى **المخصّص** فقط، ولا يرقّيه إلى **الجسر**.
- جهاز شغّل نسخة سابقة للجسر ونجح مرة على workers.dev (عبر نفق أو شبكة أخرى) فحُفظ `cf_worker_active_url = workers.dev`. عند الترقية يكون `active = workers.dev` (`:130-131`)، فيدخل مباشرة في سيناريو C3.
- الاختبارات تغطي «تركيبة جديدة ← الجسر أولاً» (`worker_endpoint_failover_test.dart:190`) و«sticky مدمج + مخصّص» (`:167`)، **ولا تغطي sticky مدمج + جسر بلا مخصّص**.
- يتعافى ذاتياً بعد أول فشل ونجاح، لكن الجلسة الأولى بعد الترقية تفشل.

### C5 — [P2] الدخول لا يعيد المحاولة على 429/5xx ولا يحترم `Retry-After`
- `cloudflare_sync_manager.dart:875-887`: أي رد غير 200 يؤدي إلى `return` فوراً. فمثلاً 429 من دلو الدخول (`index.ts:284-305`، 20/دقيقة) أو 502 عابر من الجسر يُبقي `_token = null` لمدة 60 ث، والبطاقة تعرض D1 «لم يُفحص».

### C6 — [P2، مشروط] دلو الدخول مشترك بين كل عملاء الجسر إذا غاب `RELAY_SECRET`
- `index.ts:242-250`: بلا سر مطابق يكون `clientIp = CF-Connecting-IP`، وهو عبر الجسر **عنوان خروج Cloudflare المشترك**.
- النتيجة: 20 دخولاً/دقيقة و1000 طلب/دقيقة **لكل المستخدمين معاً**، فتظهر 429 تبدو كأنها «فشل اتصال».
- رسالة الـ commit تذكر أن `wrangler tail` أظهر العنوان الحقيقي، أي أن السر مُفعَّل على الأرجح. **لم يُتحقق منه هنا** (يحتاج `wrangler secret list`).

### C7 — [P3] عنوان رسالة 401 مضلل
- `cloudflare_auto_connection_card.dart:115` و`sync_indicator.dart:146`: الرسالة 401 تُعرض تحت «قاعدة D1 لا تستجيب». و`_probeD1` لا يبطل `Env.cloudflareAuthToken` عند 401 (`appwrite_providers.dart:284-289`) بعكس مسار الدفع (`cloudflare_sync_manager.dart:1630-1636`).

### C8 — [P3] خدمات Finance/AI تتجاوز آليات التحمل
- تبني على `active` بـ `http.Client` عادي. إذا كان `active` محجوباً (C2/C4) فهي تفشل بلا تدوير.

---

## 4. الفرضيات المتنافسة لعطل المستخدم، مرتبة حسب الأدلة

| # | الفرضية | ما يؤيدها | ما يحسمها |
|---|---|---|---|
| H1 | **APK المثبت أقدم من `ee07d5c3`** (بلا جسر)، فيعتمد على workers.dev المحجوب وحده | الجسر أُضيف قبل ساعات من الفحص (2026-09-28 23:09)، و`pubspec` ما زال `1.2.0+3` | رقم البناء/الـ commit في شاشة «حول»، أو وجود `pages.dev` في سجل الأخطاء |
| H2 | الشبكة تحجب `pages.dev` أيضاً (SNI) | `*.pages.dev` نطاق Cloudflare شائع الحجب مثل `workers.dev` | `curl https://marina-hotel-api-relay.pages.dev/health` من شبكة المستخدم |
| H3 | رفرفة C2 وميزانية C3 (العميل يصنع الفشل بنفسه) | مثبت من الكود. يظهر كتقطع لا كانقطاع دائم | سجل: «demoted …pages.dev» ثم `TimeoutException` على workers.dev |
| H4 | 429 مشترك (C6) | مشروط بغياب `RELAY_SECRET` | `wrangler secret list` + `wrangler tail` (client_id) |
| H5 | عطل D1/Worker | **مستبعد:** السلسلة كاملة 200 الآن | — |

---

## 5. خطة الإصلاح المقترحة (بالأولوية)

### P0 — أمني (مستقل عن عطل الاتصال لكنه أخطر منه)
1. تغيير كلمة مرور `admin` في D1 فوراً، وإنشاء حساب خدمة مزامنة بأقل صلاحية.
2. إزالة `defaultValue: 'admin'` من `env.dart`، وتمرير الحساب عبر `--dart-define` أو شاشة الدخول.
3. تدوير `JWT_SECRET` **بعد** توزيع البناء الجديد، لإبطال أي توكن admin دائم مسرّب. (هذا التدوير مبرَّر أمنياً، وليس إصلاحاً للاتصال.)

### P0 — تشغيلي
4. **التحقق من أن APK الموزَّع مبني من `≥ ee07d5c3`** (H1). بلا ذلك لا قيمة لأي تحليل آخر.

### P1 — منطق العميل
5. **(C2)** فحص البطاقة **لا يُنزّل** النقاط: إما حذف `reportFailure` منه، أو تمريره عبر `createResilientHttpClient()` ليحصل على التدوير نفسه. الأبسط والأسلم أن يبقى **مراقباً لا حَكَماً**: يستدعي `reportSuccess` فقط.
6. **(C3)** جعل مهلة الدخول الخارجية ≥ مجموع ميزانيات المرشحين، أو (الأفضل) تمرير ميزانية لكل مرشح داخل `_sendWithEndpointRotation` (مثلاً 6 ث للمرشح غير الأخير، والباقي للأخير)، حتى يصل التدوير دائماً إلى الجسر ضمن 15 ث.
7. **(C4)** في `load()`: عندما يكون `hasRelay && !hasCustom && sticky == builtin`، ابدأ الجلسة على الجسر (بنفس منطق المخصّص في `:113-115`)، وأضف الاختبار الناقص.

### P2
8. **(C5)** إعادة محاولة الدخول على 429 (بعد `Retry-After`، بسقف) وعلى 502/503/504 (backoff قصير)، ضمن حد محاولات ثابت.
9. **(C6)** التحقق من `RELAY_SECRET` على الطرفين: `npx wrangler secret list --name marina-hotel-api`، ثم `wrangler tail` والتأكد أن `client_id` ليس `2a06:98c0:…`.
10. **(C7)** عنوان مستقل لكل نوع: 401 ← «الجلسة مرفوضة»، 429 ← «كثرة طلبات»، 503 ← «D1 لا تستجيب». وإبطال التوكن عند 401 في `_probeD1`.

### P3
11. **(C8)** توحيد Finance/AI على `createResilientHttpClient()`.
12. نطاق مخصّص يبقى **احتياطاً** إذا ثبت H2 (حجب `pages.dev`).

### اختبارات عقدية مقترحة (لم تُشغَّل هنا: لا Flutter في البيئة)
- `load()` مع `{activeUrlKey: builtin}` وجسر مفعّل بلا مخصّص ← `active == relay`.
- `checkConnection` بـ MockClient يرمي Timeout على الجسر ← `WorkerEndpoints.active` **لا يتغير** إلى builtin.
- `ResilientHttpClient` مع مرشح أول **يعلّق** (Completer لا يكتمل، وليس SocketException) + مهلة خارجية 15 ث ← الطلب يصل إلى المرشح الثاني وينجح. (الاختبارات الحالية `:409-437` تستخدم فشلاً **فورياً** فقط، لذلك لا تكشف C3.)

---

## 6. بروتوكول تأكيد من جهاز المستخدم (يحسم H1–H4 في دقائق)

من **نفس الشبكة** التي يظهر عليها الفشل (Termux أو حاسوب على نفس الـ Wi-Fi/الباقة):

```bash
for H in marina-hotel-api.adenmarina2.workers.dev marina-hotel-api-relay.pages.dev; do
  echo "== $H"
  getent ahostsv4 "$H" | head -1 || echo "DNS FAIL"
  curl -sS -o /dev/null --connect-timeout 6 --max-time 12 \
    -w "http=%{http_code} dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect}\n" \
    "https://$H/health" || echo "curl exit=$?"
done
```

| النتيجة | التفسير |
|---|---|
| pages.dev = 200 | الشبكة سليمة للجسر، والعطل في التطبيق: H1 (نسخة قديمة) أو H3 (C2/C3). |
| pages.dev: `tls=0` مع `curl exit=35` أو 28 بعد `conn>0` | حجب SNI للجسر (H2)، والحل نطاق مخصّص. |
| كلاهما DNS FAIL وDoH ينجح | حجب DNS فقط. نفق التطبيق يجب أن ينجح، وإن لم ينجح فالعطل في العميل. |
| `exit=28` مع `conn=0` | انقطاع شبكي عام، وليس Cloudflare. |

ومن التطبيق (`sync_debug_logs_screen`) يلزم **سطر واحد** من كل مما يلي:
- رسالة `_initError` الكاملة (تحتوي اسم النطاق ونوع الاستثناء).
- أي سطر `demoted …` أو `endpoint … failed (TimeoutException|HandshakeException|SocketException)`.
- قيمة `cf_worker_active_url` الحالية.

---

## 7. ما لا يُفعل

- لا تغيّر `database_id` أو binding ‏`DB`: D1 تجيب `SELECT 1` بنجاح.
- لا تدوّر `JWT_SECRET` بهدف إصلاح الاتصال. تدويره مبرَّر فقط للبند الأمني P0، وبعد توزيع بناء جديد.
- لا تُعِد نشر الـ Worker ولا الجسر لإصلاح هذا العطل: كلاهما يعيد 200.
- لا تفسّر `Sync already in progress` أو `Not initialized` كفشل شبكة. الثاني نتيجة لفشل الدخول وليس سبباً له.

---

## 8. خريطة الثقة

| الادعاء | الثقة | الدليل |
|---|---|---|
| Worker + relay + login + D1 سليمة الآن | **مؤكد** | فحص حي، 200 في كل المراحل (§1) |
| `admin/admin` يعمل على الإنتاج بتوكن بلا انتهاء | **مؤكد** | login 200 + `JWT_EXPIRY_HOURS="0"` |
| C2 (فحص البطاقة ينزّل الجسر) | **مؤكد من الكود** | `appwrite_providers.dart:229-252`، `worker_endpoints.dart:208` |
| C3 (15ث < زمن المرشح المعلّق) | **مؤكد حسابياً**، وأثره **مشروط** بنمط الحجب | §3-C3 |
| C4 (sticky قديم لا يُرقّى للجسر) | **مؤكد من الكود**، واختبار التغطية غائب | `worker_endpoints.dart:113-115` |
| NXDOMAIN لـ workers.dev في «بيئة التشخيص» | **غير قابل للتكرار** | §0 |
| H1 نسخة APK قديمة | **مرجح**، غير مؤكد | توقيت commit الجسر |
| H2 حجب pages.dev في اليمن | **فرضية** | يحتاج §6 |
| `RELAY_SECRET` مفعّل | **مرجح**، غير متحقق | رسالة commit فقط |
