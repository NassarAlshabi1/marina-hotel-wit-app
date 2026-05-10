<?php
// تحديث الموقع ليصبح PWA - فندق مارينا
?>
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تثبيت تطبيق فندق مارينا</title>
    
    <!-- PWA Meta Tags -->
    <link rel="manifest" href="manifest.json">
    <meta name="theme-color" content="#2196f3">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <meta name="apple-mobile-web-app-title" content="فندق مارينا">
    <link rel="apple-touch-icon" href="assets/icons/icon-192x192.png">
    
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
            margin-bottom: 10px;
        }
        
        .status {
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            font-size: 18px;
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
        
        .install-btn {
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 50px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            margin: 10px;
            min-width: 200px;
            transition: all 0.3s;
        }
        
        .install-btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 25px rgba(40, 167, 69, 0.4);
        }
        
        .install-btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .steps {
            text-align: right;
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        
        .steps ol {
            margin: 0;
            padding-right: 20px;
        }
        
        .steps li {
            margin: 10px 0;
            line-height: 1.6;
        }
        
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🏨</div>
        <h1>تطبيق فندق مارينا</h1>
        <p>يمكنك الآن تثبيت التطبيق على هاتفك!</p>
        
        <!-- حالة التثبيت -->
        <div id="installStatus" class="status info">
            🔍 جاري فحص إمكانية التثبيت...
        </div>
        
        <!-- زر التثبيت -->
        <button id="installBtn" class="install-btn hidden">
            📱 تثبيت التطبيق
        </button>
        
        <!-- تعليمات يدوية -->
        <div id="manualInstructions" class="steps hidden">
            <h3>📋 طريقة التثبيت اليدوي:</h3>
            <ol>
                <li>افتح هذا الموقع في <strong>Chrome</strong> أو <strong>Edge</strong></li>
                <li>اضغط على قائمة المتصفح (⋮)</li>
                <li>اختر <strong>"تثبيت التطبيق"</strong> أو <strong>"Add to Home Screen"</strong></li>
                <li>اضغط <strong>"تثبيت"</strong></li>
            </ol>
        </div>
        
        <!-- معلومات التطبيق -->
        <div class="steps">
            <h3>✨ مميزات التطبيق:</h3>
            <ul style="text-align: right; list-style: none; padding: 0;">
                <li>📱 يعمل كتطبيق حقيقي</li>
                <li>⚡ سرعة فائقة</li>
                <li>🔄 يعمل بدون إنترنت</li>
                <li>🔔 إشعارات تلقائية</li>
                <li>🎯 واجهة محسنة للهواتف</li>
            </ul>
        </div>
        
        <p><a href="admin/dashboard.php" style="color: #007bff;">🚀 فتح نظام الإدارة</a></p>
    </div>

    <script>
        let deferredPrompt;
        const installBtn = document.getElementById('installBtn');
        const installStatus = document.getElementById('installStatus');
        const manualInstructions = document.getElementById('manualInstructions');
        
        // تسجيل Service Worker
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('sw.js')
                    .then(registration => {
                        console.log('SW registered: ', registration);
                        updateInstallStatus('success', '✅ التطبيق جاهز للتثبيت!');
                    })
                    .catch(registrationError => {
                        console.log('SW registration failed: ', registrationError);
                        updateInstallStatus('warning', '⚠️ تثبيت يدوي مطلوب');
                        showManualInstructions();
                    });
            });
        }
        
        // التحقق من إمكانية التثبيت
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            installBtn.classList.remove('hidden');
            updateInstallStatus('success', '✅ يمكن تثبيت التطبيق!');
        });
        
        // زر التثبيت
        installBtn.addEventListener('click', async () => {
            if (!deferredPrompt) {
                showManualInstructions();
                return;
            }
            
            installBtn.disabled = true;
            updateInstallStatus('info', '⏳ جاري التثبيت...');
            
            const result = await deferredPrompt.prompt();
            console.log('Install result:', result);
            
            if (result.outcome === 'accepted') {
                updateInstallStatus('success', '🎉 تم تثبيت التطبيق بنجاح!');
                setTimeout(() => {
                    window.location.href = 'admin/dashboard.php';
                }, 2000);
            } else {
                updateInstallStatus('warning', '❌ تم إلغاء التثبيت');
                installBtn.disabled = false;
            }
            
            deferredPrompt = null;
        });
        
        // بعد التثبيت
        window.addEventListener('appinstalled', () => {
            updateInstallStatus('success', '🎉 تم تثبيت التطبيق بنجاح!');
            deferredPrompt = null;
        });
        
        // دوال مساعدة
        function updateInstallStatus(type, message) {
            installStatus.className = `status ${type}`;
            installStatus.innerHTML = message;
        }
        
        function showManualInstructions() {
            manualInstructions.classList.remove('hidden');
        }
        
        // التحقق إذا كان التطبيق مثبت بالفعل
        if (window.matchMedia('(display-mode: standalone)').matches) {
            updateInstallStatus('success', '✅ التطبيق مثبت بالفعل!');
            setTimeout(() => {
                window.location.href = 'admin/dashboard.php';
            }, 2000);
        }
        
        // إظهار التعليمات اليدوية بعد 10 ثوان
        setTimeout(() => {
            if (installBtn.classList.contains('hidden')) {
                showManualInstructions();
                updateInstallStatus('info', '💡 اتبع التعليمات أدناه للتثبيت');
            }
        }, 10000);
    </script>
</body>
</html><?php
// تحديث الموقع ليصبح PWA - فندق مارينا
?>
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تثبيت تطبيق فندق مارينا</title>
    
    <!-- PWA Meta Tags -->
    <link rel="manifest" href="manifest.json">
    <meta name="theme-color" content="#2196f3">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <meta name="apple-mobile-web-app-title" content="فندق مارينا">
    <link rel="apple-touch-icon" href="assets/icons/icon-192x192.png">
    
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
            margin-bottom: 10px;
        }
        
        .status {
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            font-size: 18px;
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
        
        .install-btn {
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 50px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            margin: 10px;
            min-width: 200px;
            transition: all 0.3s;
        }
        
        .install-btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 25px rgba(40, 167, 69, 0.4);
        }
        
        .install-btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .steps {
            text-align: right;
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        
        .steps ol {
            margin: 0;
            padding-right: 20px;
        }
        
        .steps li {
            margin: 10px 0;
            line-height: 1.6;
        }
        
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🏨</div>
        <h1>تطبيق فندق مارينا</h1>
        <p>يمكنك الآن تثبيت التطبيق على هاتفك!</p>
        
        <!-- حالة التثبيت -->
        <div id="installStatus" class="status info">
            🔍 جاري فحص إمكانية التثبيت...
        </div>
        
        <!-- زر التثبيت -->
        <button id="installBtn" class="install-btn hidden">
            📱 تثبيت التطبيق
        </button>
        
        <!-- تعليمات يدوية -->
        <div id="manualInstructions" class="steps hidden">
            <h3>📋 طريقة التثبيت اليدوي:</h3>
            <ol>
                <li>افتح هذا الموقع في <strong>Chrome</strong> أو <strong>Edge</strong></li>
                <li>اضغط على قائمة المتصفح (⋮)</li>
                <li>اختر <strong>"تثبيت التطبيق"</strong> أو <strong>"Add to Home Screen"</strong></li>
                <li>اضغط <strong>"تثبيت"</strong></li>
            </ol>
        </div>
        
        <!-- معلومات التطبيق -->
        <div class="steps">
            <h3>✨ مميزات التطبيق:</h3>
            <ul style="text-align: right; list-style: none; padding: 0;">
                <li>📱 يعمل كتطبيق حقيقي</li>
                <li>⚡ سرعة فائقة</li>
                <li>🔄 يعمل بدون إنترنت</li>
                <li>🔔 إشعارات تلقائية</li>
                <li>🎯 واجهة محسنة للهواتف</li>
            </ul>
        </div>
        
        <p><a href="admin/dashboard.php" style="color: #007bff;">🚀 فتح نظام الإدارة</a></p>
    </div>

    <script>
        let deferredPrompt;
        const installBtn = document.getElementById('installBtn');
        const installStatus = document.getElementById('installStatus');
        const manualInstructions = document.getElementById('manualInstructions');
        
        // تسجيل Service Worker
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('sw.js')
                    .then(registration => {
                        console.log('SW registered: ', registration);
                        updateInstallStatus('success', '✅ التطبيق جاهز للتثبيت!');
                    })
                    .catch(registrationError => {
                        console.log('SW registration failed: ', registrationError);
                        updateInstallStatus('warning', '⚠️ تثبيت يدوي مطلوب');
                        showManualInstructions();
                    });
            });
        }
        
        // التحقق من إمكانية التثبيت
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            installBtn.classList.remove('hidden');
            updateInstallStatus('success', '✅ يمكن تثبيت التطبيق!');
        });
        
        // زر التثبيت
        installBtn.addEventListener('click', async () => {
            if (!deferredPrompt) {
                showManualInstructions();
                return;
            }
            
            installBtn.disabled = true;
            updateInstallStatus('info', '⏳ جاري التثبيت...');
            
            const result = await deferredPrompt.prompt();
            console.log('Install result:', result);
            
            if (result.outcome === 'accepted') {
                updateInstallStatus('success', '🎉 تم تثبيت التطبيق بنجاح!');
                setTimeout(() => {
                    window.location.href = 'admin/dashboard.php';
                }, 2000);
            } else {
                updateInstallStatus('warning', '❌ تم إلغاء التثبيت');
                installBtn.disabled = false;
            }
            
            deferredPrompt = null;
        });
        
        // بعد التثبيت
        window.addEventListener('appinstalled', () => {
            updateInstallStatus('success', '🎉 تم تثبيت التطبيق بنجاح!');
            deferredPrompt = null;
        });
        
        // دوال مساعدة
        function updateInstallStatus(type, message) {
            installStatus.className = `status ${type}`;
            installStatus.innerHTML = message;
        }
        
        function showManualInstructions() {
            manualInstructions.classList.remove('hidden');
        }
        
        // التحقق إذا كان التطبيق مثبت بالفعل
        if (window.matchMedia('(display-mode: standalone)').matches) {
            updateInstallStatus('success', '✅ التطبيق مثبت بالفعل!');
            setTimeout(() => {
                window.location.href = 'admin/dashboard.php';
            }, 2000);
        }
        
        // إظهار التعليمات اليدوية بعد 10 ثوان
        setTimeout(() => {
            if (installBtn.classList.contains('hidden')) {
                showManualInstructions();
                updateInstallStatus('info', '💡 اتبع التعليمات أدناه للتثبيت');
            }
        }, 10000);
    </script>
</body>
</html><?php
// تحديث الموقع ليصبح PWA - فندق مارينا
?>
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تثبيت تطبيق فندق مارينا</title>
    
    <!-- PWA Meta Tags -->
    <link rel="manifest" href="manifest.json">
    <meta name="theme-color" content="#2196f3">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <meta name="apple-mobile-web-app-title" content="فندق مارينا">
    <link rel="apple-touch-icon" href="assets/icons/icon-192x192.png">
    
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
            margin-bottom: 10px;
        }
        
        .status {
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
            font-size: 18px;
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
        
        .install-btn {
            background: linear-gradient(135deg, #28a745, #20c997);
            color: white;
            border: none;
            padding: 15px 30px;
            border-radius: 50px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            margin: 10px;
            min-width: 200px;
            transition: all 0.3s;
        }
        
        .install-btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 10px 25px rgba(40, 167, 69, 0.4);
        }
        
        .install-btn:disabled {
            opacity: 0.6;
            cursor: not-allowed;
        }
        
        .steps {
            text-align: right;
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            margin: 20px 0;
        }
        
        .steps ol {
            margin: 0;
            padding-right: 20px;
        }
        
        .steps li {
            margin: 10px 0;
            line-height: 1.6;
        }
        
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">🏨</div>
        <h1>تطبيق فندق مارينا</h1>
        <p>يمكنك الآن تثبيت التطبيق على هاتفك!</p>
        
        <!-- حالة التثبيت -->
        <div id="installStatus" class="status info">
            🔍 جاري فحص إمكانية التثبيت...
        </div>
        
        <!-- زر التثبيت -->
        <button id="installBtn" class="install-btn hidden">
            📱 تثبيت التطبيق
        </button>
        
        <!-- تعليمات يدوية -->
        <div id="manualInstructions" class="steps hidden">
            <h3>📋 طريقة التثبيت اليدوي:</h3>
            <ol>
                <li>افتح هذا الموقع في <strong>Chrome</strong> أو <strong>Edge</strong></li>
                <li>اضغط على قائمة المتصفح (⋮)</li>
                <li>اختر <strong>"تثبيت التطبيق"</strong> أو <strong>"Add to Home Screen"</strong></li>
                <li>اضغط <strong>"تثبيت"</strong></li>
            </ol>
        </div>
        
        <!-- معلومات التطبيق -->
        <div class="steps">
            <h3>✨ مميزات التطبيق:</h3>
            <ul style="text-align: right; list-style: none; padding: 0;">
                <li>📱 يعمل كتطبيق حقيقي</li>
                <li>⚡ سرعة فائقة</li>
                <li>🔄 يعمل بدون إنترنت</li>
                <li>🔔 إشعارات تلقائية</li>
                <li>🎯 واجهة محسنة للهواتف</li>
            </ul>
        </div>
        
        <p><a href="admin/dashboard.php" style="color: #007bff;">🚀 فتح نظام الإدارة</a></p>
    </div>

    <script>
        let deferredPrompt;
        const installBtn = document.getElementById('installBtn');
        const installStatus = document.getElementById('installStatus');
        const manualInstructions = document.getElementById('manualInstructions');
        
        // تسجيل Service Worker
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('sw.js')
                    .then(registration => {
                        console.log('SW registered: ', registration);
                        updateInstallStatus('success', '✅ التطبيق جاهز للتثبيت!');
                    })
                    .catch(registrationError => {
                        console.log('SW registration failed: ', registrationError);
                        updateInstallStatus('warning', '⚠️ تثبيت يدوي مطلوب');
                        showManualInstructions();
                    });
            });
        }
        
        // التحقق من إمكانية التثبيت
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            installBtn.classList.remove('hidden');
            updateInstallStatus('success', '✅ يمكن تثبيت التطبيق!');
        });
        
        // زر التثبيت
        installBtn.addEventListener('click', async () => {
            if (!deferredPrompt) {
                showManualInstructions();
                return;
            }
            
            installBtn.disabled = true;
            updateInstallStatus('info', '⏳ جاري التثبيت...');
            
            const result = await deferredPrompt.prompt();
            console.log('Install result:', result);
            
            if (result.outcome === 'accepted') {
                updateInstallStatus('success', '🎉 تم تثبيت التطبيق بنجاح!');
                setTimeout(() => {
                    window.location.href = 'admin/dashboard.php';
                }, 2000);
            } else {
                updateInstallStatus('warning', '❌ تم إلغاء التثبيت');
                installBtn.disabled = false;
            }
            
            deferredPrompt = null;
        });
        
        // بعد التثبيت
        window.addEventListener('appinstalled', () => {
            updateInstallStatus('success', '🎉 تم تثبيت التطبيق بنجاح!');
            deferredPrompt = null;
        });
        
        // دوال مساعدة
        function updateInstallStatus(type, message) {
            installStatus.className = `status ${type}`;
            installStatus.innerHTML = message;
        }
        
        function showManualInstructions() {
            manualInstructions.classList.remove('hidden');
        }
        
        // التحقق إذا كان التطبيق مثبت بالفعل
        if (window.matchMedia('(display-mode: standalone)').matches) {
            updateInstallStatus('success', '✅ التطبيق مثبت بالفعل!');
            setTimeout(() => {
                window.location.href = 'admin/dashboard.php';
            }, 2000);
        }
        
        // إظهار التعليمات اليدوية بعد 10 ثوان
        setTimeout(() => {
            if (installBtn.classList.contains('hidden')) {
                showManualInstructions();
                updateInstallStatus('info', '💡 اتبع التعليمات أدناه للتثبيت');
            }
        }, 10000);
    </script>
</body>
</html>