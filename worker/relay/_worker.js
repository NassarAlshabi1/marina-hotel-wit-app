// ═══════════════════════════════════════════════════════════════
//  _worker.js — Cloudflare Pages Relay (advanced mode)
//  جسر مجاني 100%: *.pages.dev → *.workers.dev
// ═══════════════════════════════════════════════════════════════
//
//  السياق (2026-09-28): شبكات اليمن تحجب *.workers.dev بفلترة SNI
//  على اسم النطاق نفسه. *.pages.dev نطاق مختلف كلياً في ترويسة
//  ClientHello ينهي عليه نفس حافة Cloudflare — فالجسر يعطي التطبيق
//  مدخلاً بنفس البنية والشهادة لكن باسم غير محجوب، وإعادة التوجيه
//  نحو workers.dev تجري داخل شبكة Cloudflare (الرقيب لا يراها).
//
//  العقود:
//  1. كل مسار/استعلام/ترويسات/جسم يمرّ كما هو (gzip يعبر بايت-ببايت).
//  2. ترقية WebSocket (/api/realtime → RealtimeHubDO) تُمرَّر نصاً:
//     fetch() بعنوان مختلف مع Request الأصلي يبقي Upgrade و101
//     يمرّ عبر الـ runtime (الجسور النصية هي الطريقة الموثقة).
//  3. هوية العميل الحقيقية تُعاد تحت أسماء محايدة (x-mh-client-ip /
//     x-mh-client-country) لأن Cloudflare يقتطع ترويسات CF-* في
//     الـsubrequest — على HTTP وWebSocket معاً، موقّعة بـ
//     x-mh-relay-key = RELAY_SECRET (الـ Worker يهملها بلا توقيع مطابق).
// ═══════════════════════════════════════════════════════════════

const UPSTREAM = 'https://marina-hotel-api.adenmarina2.workers.dev';

/**
 * إرفاق هوية العميل الحقيقية + توقيع الجسر على ترويسات الطلب الصاعد.
 * ✅ (2026-09-29) مشتركة بين HTTP وWebSocket — كان مسار WebSocket يمرر
 * الطلب بلا x-mh-* فتُحسب كل ترقيات /api/realtime عبر الجسر على دلو
 * عنوان خروج Cloudflare المشترك (مثبت في rate_limits: 2a06:98c0:…).
 */
function attachIdentity(request, env, headers) {
  const clientIp = request.headers.get('cf-connecting-ip');
  const country = (request.cf && request.cf.country) || '';
  if (clientIp) headers.set('x-mh-client-ip', clientIp);
  if (country) headers.set('x-mh-client-country', country);
  headers.set('x-mh-relayed', '1');
  // RELAY_SECRET (Pages env var) يوقّع الطلب — بدونه يهمل الـ Worker x-mh-*.
  if (env && env.RELAY_SECRET) headers.set('x-mh-relay-key', env.RELAY_SECRET);
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const upstreamUrl = UPSTREAM + url.pathname + url.search;

    // ── WebSocket passthrough: Request جديد مبني على الأصلي (يحفظ
    //    Upgrade والجسم والطريقة كما هي ويعطي ترويسات قابلة للتعديل)،
    //    ثم إرفاق الهوية قبل المصافحة 101.
    const upgrade = (request.headers.get('upgrade') || '').toLowerCase();
    if (upgrade === 'websocket') {
      const wsRequest = new Request(upstreamUrl, request);
      attachIdentity(request, env, wsRequest.headers);
      return fetch(wsRequest);
    }

    // ── HTTP عادي: نسخ الترويسات + إعادة إرفاق هوية العميل.
    const headers = new Headers(request.headers);
    headers.delete('host'); // يُشتق من الـ URL في الـ subrequest
    attachIdentity(request, env, headers);

    const init = {
      method: request.method,
      headers,
      redirect: 'manual',
    };
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      init.body = await request.arrayBuffer();
    }

    return fetch(upstreamUrl, init);
  },
};
