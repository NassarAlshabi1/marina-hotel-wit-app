<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>اختبار PWA - فندق مارينا</title>
    
    <!-- PWA Configuration -->
    <link rel="manifest" href="manifest.json">
    <meta name="theme-color" content="#2196f3">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <meta name="apple-mobile-web-app-title" content="فندق مارينا">
    
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 20px;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.2);
            max-width: 500px;
            width: 100%;
            text-align: center;
        }
        
        .logo {
            font-size: 80px;
            margin-bottom: 20px;
        }
        
        h1 {
            color: #2c3e50;
            margin-bottom: 20px;
        }
        
        .status {
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            font-size: 16px;
            font-weight: 600;
        }
        
        .success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        
        .info {
            background: #d1ecf1;
            color: #0c5460;
            border: 1px solid #bee5eb;
        }
        
        .warning {
            background: #fff3cd;
            color: #856404;
            border: 1px solid #ffeaa7;
        }
        
        .btn {
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 50px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            margin: 10px;
            min-width: 200px;
            transition: all 0.3s;
        }
        
        .btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 25px rgba(40, 167, 69, 0.4);
        }
        
        .btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .features {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            text-align: right;
        }
        
        .features ul {
            list-style: none;
            padding: 0;
            margin: 0;
        }
        
        .features li {
            padding: 8px 0;
            border-bottom: 1px solid #dee2e6;
        }
        
        .features li:last-child {
            border-bottom: none;
        }
        
        .test-results {
            background: #e3f2fd;
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            text-align: right;
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🏨</div>
        <h1>فندق مارينا PWA</h1>
        <p>Progressive Web App - اختبار وتثبيت</p>
        
        <!-- حالة PWA -->
        <div id="pwaStatus" class="status info">
            🔍 جاري فحص حالة PWA...
        </div>
        
        <!-- أزرار التحكم -->
        <button id="installBtn" class="btn" style="display: none;">
            📱 تثبيت التطبيق
        </button>
        
        <button id="testBtn" class="btn">
            🧪 اختبار PWA
        </button>
        
        <a href="admin/dashboard.php" class="btn" style="text-decoration: none; display: inline-block;">
            🚀 دخول النظام
        </a>
        
        <!-- نتائج الاختبار -->
        <div id="testResults" class="test-results">
            <h3>📊 نتائج الاختبار:</h3>
            <ul id="testList"></ul>
        </div>
        
        <!-- الميزات -->
        <div class="features">
            <h3>✨ مميزات PWA:</h3>
            <ul>
                <li>📱 يعمل كتطبيق حقيقي</li>
                <li>⚡ تحميل سريع</li>
                <li>🔄 يعمل بدون إنترنت</li>
                <li>🔔 إشعارات push</li>
                <li>📲 تثبيت بنقرة واحدة</li>
                <li>🔄 تحديثات تلقائية</li>
            </ul>
        </div>
        
        <!-- التعليمات -->
        <div class="features">
            <h3>📋 طريقة التثبيت:</h3>
            <ol style="text-align: right;">
                <li>افتح الموقع في Chrome أو Edge</li>
                <li>اضغط على زر "تثبيت التطبيق"</li>
                <li>أو من قائمة المتصفح اختر "تثبيت التطبيق"</li>
                <li>اضغط "تثبيت" في النافذة المنبثقة</li>
            </ol>
        </div>
    </div>

    <script>
        let deferredPrompt;
        const installBtn = document.getElementById('installBtn');
        const pwaStatus = document.getElementById('pwaStatus');
        const testBtn = document.getElementById('testBtn');
        const testResults = document.getElementById('testResults');
        const testList = document.getElementById('testList');
        
        // تسجيل Service Worker
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('./sw.js')
                    .then(registration => {
                        console.log('SW registered: ', registration);
                        updateStatus('success', '✅ PWA جاهز للتثبيت!');
                        checkPWAFeatures();
                        
                        // التحقق من حالة SW
                        if (registration.active) {
                            console.log('Service Worker is active');
                        }
                    })
                    .catch(registrationError => {
                        console.log('SW registration failed: ', registrationError);
                        updateStatus('warning', '⚠️ خطأ في تسجيل Service Worker: ' + registrationError.message);
                    });
            });
        } else {
            updateStatus('warning', '❌ المتصفح لا يدعم Service Worker');
        }
        
        // التحقق من إمكانية التثبيت
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            installBtn.style.display = 'inline-block';
            updateStatus('success', '🎉 يمكن تثبيت التطبيق الآن!');
        });
        
        // زر التثبيت
        installBtn.addEventListener('click', async () => {
            if (!deferredPrompt) {
                alert('غير متاح للتثبيت حالياً. جرب:\n1. استخدم Chrome أو Edge\n2. افتح الموقع عبر HTTPS\n3. انتظر تحميل PWA كاملاً');
                return;
            }
            
            installBtn.disabled = true;
            updateStatus('info', '⏳ جاري التثبيت...');
            
            const result = await deferredPrompt.prompt();
            console.log('Install result:', result);
            
            if (result.outcome === 'accepted') {
                updateStatus('success', '🎉 تم تثبيت التطبيق بنجاح!');
                setTimeout(() => {
                    window.location.href = 'admin/dashboard.php';
                }, 2000);
            } else {
                updateStatus('warning', '❌ تم إلغاء التثبيت');
                installBtn.disabled = false;
            }
            
            deferredPrompt = null;
        });
        
        // بعد التثبيت
        window.addEventListener('appinstalled', () => {
            updateStatus('success', '🎉 تم تثبيت التطبيق!');
            installBtn.style.display = 'none';
            deferredPrompt = null;
        });
        
        // اختبار PWA
        testBtn.addEventListener('click', () => {
            testPWAFeatures();
        });
        
        function updateStatus(type, message) {
            pwaStatus.className = `status ${type}`;
            pwaStatus.innerHTML = message;
        }
        
        function checkPWAFeatures() {
            const features = [
                {
                    name: 'Service Worker',
                    supported: 'serviceWorker' in navigator,
                    required: true
                },
                {
                    name: 'Web App Manifest',
                    supported: 'onbeforeinstallprompt' in window,
                    required: true
                },
                {
                    name: 'Push Notifications',
                    supported: 'Notification' in window,
                    required: false
                },
                {
                    name: 'Background Sync',
                    supported: 'serviceWorker' in navigator && 'sync' in window.ServiceWorkerRegistration.prototype,
                    required: false
                },
                {
                    name: 'Offline Support',
                    supported: 'caches' in window,
                    required: true
                }
            ];
            
            console.log('PWA Features Check:', features);
        }
        
        function testPWAFeatures() {
            testResults.style.display = 'block';
            testList.innerHTML = '';
            
            const tests = [
                {
                    name: 'Service Worker مسجل',
                    test: () => 'serviceWorker' in navigator && navigator.serviceWorker.controller,
                    async: false
                },
                {
                    name: 'Manifest موجود',
                    test: () => document.querySelector('link[rel="manifest"]') !== null,
                    async: false
                },
                {
                    name: 'HTTPS أو localhost',
                    test: () => location.protocol === 'https:' || location.hostname === 'localhost',
                    async: false
                },
                {
                    name: 'Cache API متاح',
                    test: () => 'caches' in window,
                    async: false
                },
                {
                    name: 'اتصال الشبكة',
                    test: () => navigator.onLine,
                    async: false
                }
            ];
            
            tests.forEach(test => {
                const result = test.test();
                const li = document.createElement('li');
                li.innerHTML = `
                    ${result ? '✅' : '❌'} ${test.name}: 
                    <strong>${result ? 'متاح' : 'غير متاح'}</strong>
                `;
                li.style.color = result ? '#155724' : '#721c24';
                testList.appendChild(li);
            });
            
            // اختبار إضافي - تحميل Manifest
            fetch('manifest.json')
                .then(response => response.json())
                .then(manifest => {
                    const li = document.createElement('li');
                    li.innerHTML = `✅ Manifest JSON: <strong>صالح (${manifest.name})</strong>`;
                    li.style.color = '#155724';
                    testList.appendChild(li);
                })
                .catch(error => {
                    const li = document.createElement('li');
                    li.innerHTML = `❌ Manifest JSON: <strong>خطأ في التحميل</strong>`;
                    li.style.color = '#721c24';
                    testList.appendChild(li);
                });
        }
        
        // التحقق إذا كان التطبيق مثبت بالفعل
        if (window.matchMedia('(display-mode: standalone)').matches) {
            updateStatus('success', '✅ التطبيق مثبت ويعمل في وضع standalone!');
        }
        
        // مراقبة حالة الاتصال
        window.addEventListener('online', () => {
            console.log('Back online');
        });
        
        window.addEventListener('offline', () => {
            console.log('Gone offline');
        });
    </script>
</body>
</html>