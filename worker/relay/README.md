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
  (لأن CF- تُقتطع في subrequest) — الـ Worker يتجاهلها حالياً.

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
المحمي وبعد أي نطاق مخصص يضبطه المستخدم).
