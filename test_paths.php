<?php
// تحميل config.php
require_once 'includes/config.php';
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>اختبار المسارات المحلية</title>
    
    <!-- اختبار تحميل CSS محلياً -->
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/fonts/fonts.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/dashboard.css" rel="stylesheet">
    
    <style>
        body {
            font-family: 'Tajawal', sans-serif;
            padding: 20px;
            background: #f8f9fa;
        }
        .test-section {
            background: white;
            padding: 20px;
            margin: 20px 0;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        .info { color: #17a2b8; }
    </style>
</head>
<body>

<div class="container">
    <h1><i class="fas fa-check-circle"></i> اختبار المسارات المحلية</h1>
    
    <div class="test-section">
        <h2>🔍 فحص المتغيرات</h2>
        <p><strong>BASE_URL:</strong> <span class="info"><?= BASE_URL ?></span></p>
        <p><strong>ROOT_PATH:</strong> <span class="info"><?= ROOT_PATH ?></span></p>
        <p><strong>Document Root:</strong> <span class="info"><?= $_SERVER['DOCUMENT_ROOT'] ?></span></p>
    </div>
    
    <div class="test-section">
        <h2>📁 فحص الملفات</h2>
        <?php
        $test_files = [
            'assets/css/bootstrap.rtl.min.css',
            'assets/fonts/fonts.css', 
            'assets/css/fontawesome.min.css',
            'assets/css/dashboard.css',
            'assets/js/jquery.min.js',
            'assets/js/bootstrap-local.js'
        ];
        
        foreach ($test_files as $file) {
            $full_path = __DIR__ . '/' . $file;
            if (file_exists($full_path)) {
                $size = round(filesize($full_path) / 1024, 2);
                echo "<p class='success'>✓ $file ($size KB)</p>";
            } else {
                echo "<p class='error'>✗ $file - غير موجود</p>";
            }
        }
        ?>
    </div>
    
    <div class="test-section">
        <h2>🎨 اختبار الخطوط والأيقونات</h2>
        <p style="font-weight: 300;">خط تجوال خفيف (300)</p>
        <p style="font-weight: 400;">خط تجوال عادي (400)</p>
        <p style="font-weight: 700;">خط تجوال غامق (700)</p>
        
        <div class="mt-3">
            <i class="fas fa-home"></i> الرئيسية
            <i class="fas fa-user"></i> المستخدمين
            <i class="fas fa-cog"></i> الإعدادات
            <i class="fas fa-chart-bar"></i> التقارير
        </div>
    </div>
    
    <div class="test-section">
        <h2>🎛️ اختبار القوائم المنسدلة</h2>
        <div class="dropdown">
            <button class="btn btn-primary dropdown-toggle" type="button" id="testDropdown" data-bs-toggle="dropdown">
                <i class="fas fa-cog"></i> قائمة اختبار
            </button>
            <ul class="dropdown-menu" aria-labelledby="testDropdown">
                <li><h6 class="dropdown-header">إدارة النظام</h6></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-tachometer-alt"></i> لوحة الإدارة</a></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-users"></i> المستخدمين</a></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-cogs"></i> الإعدادات</a></li>
                <li><hr class="dropdown-divider"></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-sign-out-alt"></i> تسجيل الخروج</a></li>
            </ul>
        </div>
    </div>
    
    <div class="test-section">
        <h2>🔗 روابط سريعة</h2>
        <div class="row">
            <div class="col-md-6">
                <a href="admin/dashboard.php" class="btn btn-primary btn-lg w-100">
                    <i class="fas fa-tachometer-alt"></i> لوحة الإدارة
                </a>
            </div>
            <div class="col-md-6">
                <a href="index.php" class="btn btn-success btn-lg w-100">
                    <i class="fas fa-home"></i> الصفحة الرئيسية
                </a>
            </div>
        </div>
    </div>
    
    <div class="test-section">
        <h2>⚙️ معلومات الخادم</h2>
        <p><strong>PHP Version:</strong> <?= PHP_VERSION ?></p>
        <p><strong>Server Software:</strong> <?= $_SERVER['SERVER_SOFTWARE'] ?? 'غير محدد' ?></p>
        <p><strong>Current URL:</strong> <?= 'http://' . $_SERVER['HTTP_HOST'] . $_SERVER['REQUEST_URI'] ?></p>
    </div>
</div>

<!-- اختبار تحميل JavaScript محلياً -->
<script src="<?= BASE_URL ?>assets/js/jquery.min.js"></script>
<script src="<?= BASE_URL ?>assets/js/bootstrap-local.js"></script>
<script>
// JavaScript للفحص
document.addEventListener('DOMContentLoaded', function() {
    console.log('✓ DOM loaded successfully');
    
    // فحص jQuery
    if (typeof $ !== 'undefined') {
        console.log('✓ jQuery loaded successfully - Version:', $.fn.jquery);
    } else {
        console.log('✗ jQuery not loaded');
    }
    
    // فحص Bootstrap
    if (typeof bootstrap !== 'undefined') {
        console.log('✓ Bootstrap loaded successfully');
    } else {
        console.log('✗ Bootstrap not loaded, loading from CDN...');
        const script = document.createElement('script');
        script.src = 'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js';
        document.head.appendChild(script);
    }
    
    // فحص الخطوط
    const testElement = document.createElement('span');
    testElement.style.fontFamily = 'Tajawal, sans-serif';
    testElement.textContent = 'Test';
    document.body.appendChild(testElement);
    
    const computedStyle = window.getComputedStyle(testElement);
    if (computedStyle.fontFamily.includes('Tajawal')) {
        console.log('✓ Tajawal font loaded successfully');
    } else {
        console.log('⚠ Tajawal font not loaded, using fallback');
    }
    
    document.body.removeChild(testElement);
    
    // فحص الأيقونات
    const iconTest = document.querySelector('.fas');
    if (iconTest) {
        const iconStyle = window.getComputedStyle(iconTest, ':before');
        if (iconStyle.content && iconStyle.content !== 'none') {
            console.log('✓ Font Awesome icons loaded successfully');
        } else {
            console.log('⚠ Font Awesome icons may not be loaded properly');
        }
    }
    
    // إضافة وظائف القوائم المنسدلة
    const dropdowns = document.querySelectorAll('.dropdown');
    dropdowns.forEach(dropdown => {
        const toggle = dropdown.querySelector('.dropdown-toggle');
        const menu = dropdown.querySelector('.dropdown-menu');
        
        if (toggle && menu) {
            toggle.addEventListener('click', function(e) {
                e.preventDefault();
                menu.classList.toggle('show');
            });
            
            // إغلاق عند النقر خارج القائمة
            document.addEventListener('click', function(e) {
                if (!dropdown.contains(e.target)) {
                    menu.classList.remove('show');
                }
            });
        }
    });
    
    console.log('✓ All tests completed successfully');
});
</script>

<style>
/* إصلاحات إضافية للقوائم المنسدلة */
.dropdown-menu {
    right: 0 !important;
    left: auto !important;
}

.dropdown-menu.show {
    display: block;
}

.dropdown-item {
    text-align: right;
    padding: 8px 16px;
}

.dropdown-item:hover {
    background-color: #f8f9fa;
}

.dropdown-item i {
    width: 20px;
    text-align: center;
    margin-left: 8px;
}
</style>

</body>
</html>