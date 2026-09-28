# worker/relay — جسر Pages المجاني (marina-hotel-api-relay.pages.dev)

جسر Cloudflare Pages (advanced mode `_worker.js`) يعيد توجيه كل طلب نحو
الـ Worker الإنتاجي `marina-hotel-api.adenmarina2.workers.dev` من داخل
شبكة Cloudflare.

## لماذا؟
شبكات اليمن تحجب `*.workers.dev` (فلترة SNI على اسم النطاق). `*.pages.dev`
اسم مختلف كلياً في TLS ClientHello ينهي على نفس حافة Cloudflare، فالتطبيق
يتصل بالجسر والقفزة نحو workers.dev تحدث داخل الشبكة حيث لا رقيب.

## ماذا يمرر؟
- كل المسارات/الاستعلامات/الترويسات/الأجسام (gzip بايت-ببايت).
- ترقية WebSocket `/api/realtime` نصاً (passthrough بلمس Request الأصلي).
- هوية العميل الحقيقية تحت `x-mh-client-ip` / `x-mh-client-country`
  (لأن CF- تُقتطع في subrequest) — الـ Worker يقبلها فقط عند مطابقة
  `x-mh-relay-key` مع سر `RELAY_SECRET` (worker/src/index.ts:242-257).

## النشر
```bash
cd worker
CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=81a73bba9acc1de5693ff929d0a372ce \
  npx wrangler pages project create marina-hotel-api-relay --production-branch main
CLOUDFLARE_API_TOKEN=... npx wrangler pages deploy relay \
  --project-name marina-hotel-api-relay --branch main --commit-dirty=true
```

العنوان النهائي: `https://marina-hotel-api-relay.pages.dev`
(مدمج في التطبيق كمرشح ثالث في `WorkerEndpoints` — قبل workers.dev
المحجوب وبعد أي نطاق مخصص يضبطه المستخدم).

## سر الجسر (RELAY_SECRET) — إلزامي لهوية العميل
بدونه تُهمل ترويسات x-mh-* ويُحدد المعدل بعنوان خروج CF المشترك:
```bash
# نفس القيمة 64-hex على الطرفين (خارج المستودع، مثلاً .relay_secret)
CLOUDFLARE_API_TOKEN=... npx wrangler secret put RELAY_SECRET \
  --name marina-hotel-api          # طرف الـ Worker
cd relay && CLOUDFLARE_API_TOKEN=... npx wrangler pages secret put RELAY_SECRET \
  --project-name marina-hotel-api-relay   # طرف الجسر
# ثم إعادة نشر الجسر لالتقاط السر:
CLOUDFLARE_API_TOKEN=... npx wrangler pages deploy relay \
  --project-name marina-hotel-api-relay --branch main --commit-dirty=true
```

## التحقق بعد النشر
```bash
curl -sS https://marina-hotel-api-relay.pages.dev/health          # 200
curl -sS -X POST https://marina-hotel-api-relay.pages.dev/api/auth/login \
  -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin"}'
npx wrangler tail marina-hotel-api --format pretty   # راقب client_id عبر الجسر
```
