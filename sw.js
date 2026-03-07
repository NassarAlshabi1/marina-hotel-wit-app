// Service Worker للتطبيق PWA - فندق مارينا (مُبسط)
const CACHE_NAME = 'marina-hotel-v1.0.1';
const urlsToCache = [
  './',
  './manifest.json'
];

// تثبيت Service Worker
self.addEventListener('install', event => {
  console.log('[SW] Installing...');
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        console.log('[SW] Caching files');
        return cache.addAll(urlsToCache);
      })
      .catch(err => {
        console.log('[SW] Cache failed:', err);
        // لا نفشل التثبيت حتى لو فشل في cache بعض الملفات
        return Promise.resolve();
      })
  );
  // تفعيل SW فوراً
  self.skipWaiting();
});

// تفعيل Service Worker
self.addEventListener('activate', event => {
  console.log('[SW] Activating...');
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cache => {
          if (cache !== CACHE_NAME) {
            console.log('[SW] Clearing old cache:', cache);
            return caches.delete(cache);
          }
        })
      );
    }).then(() => {
      // تحكم في جميع clients فوراً
      return self.clients.claim();
    })
  );
});

// اعتراض الطلبات
self.addEventListener('fetch', event => {
  console.log('[SW] Fetching:', event.request.url);
  
  // تجاهل الطلبات غير HTTP
  if (!event.request.url.startsWith('http')) {
    return;
  }
  
  event.respondWith(
    caches.match(event.request)
      .then(response => {
        // إرجاع الملف من الكاش إذا وُجد
        if (response) {
          console.log('[SW] From cache:', event.request.url);
          return response;
        }
        
        // أو محاولة جلبه من الشبكة
        return fetch(event.request)
          .then(response => {
            // التحقق من صحة الاستجابة
            if (!response || response.status !== 200 || response.type !== 'basic') {
              return response;
            }
            
            // نسخ الاستجابة للكاش (للملفات المهمة فقط)
            if (shouldCache(event.request.url)) {
              const responseToCache = response.clone();
              caches.open(CACHE_NAME)
                .then(cache => {
                  cache.put(event.request, responseToCache);
                });
            }
            
            return response;
          })
          .catch(() => {
            console.log('[SW] Network failed for:', event.request.url);
            // في حالة فشل الشبكة، إرجاع صفحة offline للصفحات
            if (event.request.destination === 'document') {
              return new Response(`
                <!DOCTYPE html>
                <html dir="rtl" lang="ar">
                <head>
                  <meta charset="UTF-8">
                  <title>غير متصل - فندق مارينا</title>
                  <style>
                    body { font-family: Arial; text-align: center; padding: 50px; background: #f5f5f5; }
                    .container { background: white; padding: 40px; border-radius: 10px; display: inline-block; }
                    .logo { font-size: 64px; margin-bottom: 20px; }
                  </style>
                </head>
                <body>
                  <div class="container">
                    <div class="logo">🏨</div>
                    <h1>فندق مارينا</h1>
                    <p>عذراً، أنت غير متصل بالإنترنت</p>
                    <button onclick="location.reload()">إعادة المحاولة</button>
                  </div>
                </body>
                </html>
              `, {
                headers: { 'Content-Type': 'text/html; charset=utf-8' }
              });
            }
          });
      })
  );
});

// دالة لتحديد ما يجب cache
function shouldCache(url) {
  // cache الملفات الثابتة فقط
  return url.includes('.css') || 
         url.includes('.js') || 
         url.includes('.png') || 
         url.includes('.jpg') || 
         url.includes('.jpeg') ||
         url.includes('manifest.json');
}

// التعامل مع الرسائل
self.addEventListener('message', event => {
  console.log('[SW] Message received:', event.data);
  
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  
  if (event.data && event.data.type === 'GET_VERSION') {
    event.ports[0].postMessage({ version: CACHE_NAME });
  }
});

// إشعار عند تثبيت SW بنجاح
self.addEventListener('install', () => {
  console.log('[SW] ✅ Service Worker installed successfully!');
});

self.addEventListener('activate', () => {
  console.log('[SW] ✅ Service Worker activated successfully!');
});