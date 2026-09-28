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
//     الـsubrequest — الـ Worker يتجاهلها حالياً؛ متاحة لتحديد
//     المعدل لكل عميل حقيقي عبر الجسر متى لزمت (مع RELAY_SECRET).
// ═══════════════════════════════════════════════════════════════

const UPSTREAM = 'https://marina-hotel-api.adenmarina2.workers.dev';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const upstreamUrl = UPSTREAM + url.pathname + url.search;

    // ── WebSocket passthrough: Request الأصلي كما هو — لا جسم يُستهلك
    //    ولا ترويسة تُمسّ حتى يكتمل المصافحة 101.
    const upgrade = (request.headers.get('upgrade') || '').toLowerCase();
    if (upgrade === 'websocket') {
      return fetch(upstreamUrl, request);
    }

    // ── HTTP عادي: نسخ الترويسات + إعادة إرفاق هوية العميل.
    const headers = new Headers(request.headers);
    headers.delete('host'); // يُشتق من الـ URL في الـ subrequest

    const clientIp = request.headers.get('cf-connecting-ip');
    const country = (request.cf && request.cf.country) || '';
    if (clientIp) headers.set('x-mh-client-ip', clientIp);
    if (country) headers.set('x-mh-client-country', country);
    headers.set('x-mh-relayed', '1');
    // RELAY_SECRET (Pages env var) يُضاف عند تفعيل التحقق خلف الجسر.
    if (env && env.RELAY_SECRET) headers.set('x-mh-relay-key', env.RELAY_SECRET);

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
