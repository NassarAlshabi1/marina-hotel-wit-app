/* MarinaHotel Service Worker */
const VERSION = 'v2';
const STATIC_CACHE = `marinahotel-static-${VERSION}`;
const RUNTIME_CACHE = `marinahotel-runtime-${VERSION}`;
const API_CACHE = `marinahotel-api-${VERSION}`;

const PRECACHE_URLS = [
  'offline.html',
  'assets/css/bootstrap-complete.css',
  'assets/css/fontawesome.min.css',
  'assets/css/arabic-enhanced.css',
  'assets/css/dashboard.css',
  'assets/css/style.css',
  'assets/js/bootstrap-local.js',
  'assets/js/jquery.min.js',
  'assets/js/enhanced-ui.js',
  'assets/js/pwa.js',
  'assets/fonts/fonts.css'
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(STATIC_CACHE);
    try { 
      await cache.addAll(PRECACHE_URLS); 
    } catch (e) {
      console.error('Precache failed:', e);
    }
    self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map(k => {
      if (!k.includes(VERSION)) return caches.delete(k);
    }));
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

function isAsset(req) {
  return /\.(?:css|js|png|jpg|jpeg|gif|svg|ico|woff2?|ttf|eot)$/i.test(new URL(req.url).pathname);
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  const url = new URL(req.url);

  // Only handle same-origin requests
  if (url.origin !== location.origin) return;

  // HTML navigations: Network-first, fallback to offline page
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        // Do not cache HTML responses for security
        return fresh;
      } catch (err) {
        const cache = await caches.open(STATIC_CACHE);
        const offline = await cache.match('offline.html');
        return offline || new Response('<h1>Offline</h1>', { headers: { 'Content-Type': 'text/html; charset=utf-8' } });
      }
    })());
    return;
  }

  // Static assets: Cache-first
  if (isAsset(req)) {
    event.respondWith((async () => {
      const cache = await caches.open(RUNTIME_CACHE);
      const cached = await cache.match(req);
      if (cached) return cached;
      try {
        const fresh = await fetch(req, { credentials: 'same-origin' });
        if (fresh && fresh.ok) cache.put(req, fresh.clone());
        return fresh;
      } catch (e) {
        return cached || Response.error();
      }
    })());
    return;
  }

  // API GET: Network-first with cache fallback
  if (url.pathname.startsWith('/api/') && req.method === 'GET') {
    event.respondWith((async () => {
      const cache = await caches.open(API_CACHE);
      try {
        const fresh = await fetch(req, { credentials: 'include' });
        if (fresh && fresh.ok) cache.put(req, fresh.clone());
        return fresh;
      } catch (e) {
        const cached = await cache.match(req);
        return cached || new Response(JSON.stringify({ error: 'offline' }), { headers: { 'Content-Type': 'application/json' }, status: 503 });
      }
    })());
    return;
  }

  // Default: just fetch
  // Avoid caching POST/PUT/DELETE or sensitive endpoints
});