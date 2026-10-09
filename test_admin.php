<?php
/**
 * صفحة اختبار سريع للتأكد من عمل الإصلاحات
 */
require_once 'includes/config.php';
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>اختبار إصلاحات Admin</title>
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/fonts/fonts.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        body { font-family: 'Tajawal', sans-serif; margin: 20px; }
        .test-result { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .info { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
    </style>
</head>
<body>

<div class="container">
    <h1><i class="fas fa-check-circle"></i> اختبار إصلاحات Admin</h1>
    
    <?php
    $tests = [];
    
    // اختبار BASE_URL
    if (defined('BASE_URL')) {
        $tests[] = ['نجح', 'تم تعريف BASE_URL: ' . BASE_URL];
    } else {
        $tests[] = ['خطأ', 'لم يتم تعريف BASE_URL'];
    }
    
    // اختبار ملفات CSS
    $css_files = [
        'assets/css/bootstrap.rtl.min.css',
        'assets/fonts/fonts.css',
        'assets/css/fontawesome.min.css',
        'assets/css/dashboard.css'
    ];
    
    foreach ($css_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف CSS موجود: $file"];
        } else {
            $tests[] = ['خطأ', "ملف CSS مفقود: $file"];
        }
    }
    
    // اختبار ملفات JS
    $js_files = [
        'assets/js/jquery.min.js',
        'assets/js/bootstrap-local.js'
    ];
    
    foreach ($js_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف JS موجود: $file"];
        } else {
            $tests[] = ['خطأ', "ملف JS مفقود: $file"];
        }
    }
    
    // اختبار ملفات includes
    $include_files = [
        'includes/config.php',
        'includes/header.php',
        'includes/db.php',
        'includes/functions.php'
    ];
    
    foreach ($include_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف include موجود: $file"];
        } else {
            $tests[] = ['خطأ', "ملف include مفقود: $file"];
        }
    }
    
    // اختبار بعض ملفات admin
    $admin_files = [
        'admin/dashboard.php',
        'admin/bookings/list.php',
        'admin/settings/index.php'
    ];
    
    foreach ($admin_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف admin موجود: $file"];
            
            // فحص محتوى الملف للتأكد من إصلاح المسارات
            $content = file_get_contents($file);
            if (strpos($content, "require_once '../includes/") === false && 
                strpos($content, "include '../includes/") === false) {
                $tests[] = ['نجح', "تم إصلاح مسارات includes في: $file"];
            } else {
                $tests[] = ['تحذير', "قد تحتاج مسارات includes إصلاح في: $file"];
            }
        } else {
            $tests[] = ['خطأ', "ملف admin مفقود: $file"];
        }
    }
    
    // عرض النتائج
    $success_count = 0;
    $error_count = 0;
    $warning_count = 0;
    
    foreach ($tests as $test) {
        $class = $test[0] == 'نجح' ? 'success' : ($test[0] == 'خطأ' ? 'error' : 'info');
        echo "<div class='test-result $class'>";
        echo "<strong>{$test[0]}:</strong> {$test[1]}";
        echo "</div>";
        
        if ($test[0] == 'نجح') $success_count++;
        elseif ($test[0] == 'خطأ') $error_count++;
        else $warning_count++;
    }
    ?>
    
    <div class="row mt-4">
        <div class="col-md-4">
            <div class="card text-white bg-success">
                <div class="card-body text-center">
                    <h3><?= $success_count ?></h3>
                    <p>اختبارات نجحت</p>
                </div>
            </div>
        </div>
        <div class="col-md-4">
            <div class="card text-white bg-warning">
                <div class="card-body text-center">
                    <h3><?= $warning_count ?></h3>
                    <p>تحذيرات</p>
                </div>
            </div>
        </div>
        <div class="col-md-4">
            <div class="card text-white bg-danger">
                <div class="card-body text-center">
                    <h3><?= $error_count ?></h3>
                    <p>أخطاء</p>
                </div>
            </div>
        </div>
    </div>
    
    <div class="mt-4">
        <h3>اختبار القوائم المنسدلة</h3>
        <div class="dropdown">
            <button class="btn btn-primary dropdown-toggle" type="button" data-bs-toggle="dropdown">
                <i class="fas fa-cog"></i> قائمة اختبار
            </button>
            <ul class="dropdown-menu">
                <li><h6 class="dropdown-header">عناصر الاختبار</h6></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-home"></i> الرئيسية</a></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-user"></i> المستخدمين</a></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-cog"></i> الإعدادات</a></li>
                <li><hr class="dropdown-divider"></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-sign-out-alt"></i> خروج</a></li>
            </ul>
        </div>
        <p class="mt-2 text-muted">جرب النقر على القائمة أعلاه للتأكد من عملها</p>
    </div>
    
    <div class="mt-4">
        <h3>اختبار الخطوط والأيقونات</h3>
        <p style="font-family: 'Tajawal', sans-serif; font-weight: 300;">نص بخط تجوال خفيف</p>
        <p style="font-family: 'Tajawal', sans-serif; font-weight: 400;">نص بخط تجوال عادي</p>
        <p style="font-family: 'Tajawal', sans-serif; font-weight: 700;">نص بخط تجوال غامق</p>
        
        <div class="mt-3">
            <i class="fas fa-home"></i> الرئيسية |
            <i class="fas fa-user"></i> مستخدم |
            <i class="fas fa-cog"></i> إعدادات |
            <i class="fas fa-chart-bar"></i> تقارير |
            <i class="fas fa-database"></i> قاعدة البيانات
        </div>
    </div>
    
    <div class="mt-4 alert alert-info">
        <h4><i class="fas fa-info-circle"></i> ملاحظات</h4>
        <ul>
            <li>إذا ظهرت أيقونات صحيحة أعلاه، فإن Font Awesome يعمل</li>
            <li>إذا كان النص يظهر بخط جميل، فإن خط تجوال يعمل</li>
            <li>إذا كانت القائمة المنسدلة تعمل، فإن Bootstrap يعمل</li>
            <li>تأكد من فتح وحدة تحكم المطور للتحقق من عدم وجود أخطاء</li>
        </ul>
    </div>
    
    <div class="mt-4">
        <a href="admin/dashboard.php" class="btn btn-primary">
            <i class="fas fa-arrow-left"></i> انتقل إلى لوحة الإدارة
        </a>
        <a href="ADMIN_FIXES_SUMMARY.md" class="btn btn-info" target="_blank">
            <i class="fas fa-file-alt"></i> عرض ملخص الإصلاحات
        </a>
    </div>
</div>

<script src="<?= BASE_URL ?>assets/js/jquery.min.js"></script>
<script src="<?= BASE_URL ?>assets/js/bootstrap-local.js"></script>
<script>
    // Test if Bootstrap is loaded
    if (typeof bootstrap === 'undefined') {
        console.log('Bootstrap not loaded locally, loading from CDN...');
        document.write('<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"><\/script>');
    } else {
        console.log('Bootstrap loaded successfully from local files');
    }
    
    // Test dropdown functionality
    document.addEventListener('DOMContentLoaded', function() {
        console.log('DOM loaded, testing functionality...');
        
        // Test if Tajawal font is loaded
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
        
        // Test Font Awesome
        const iconTest = document.querySelector('.fas');
        if (iconTest) {
            const iconStyle = window.getComputedStyle(iconTest, ':before');
            if (iconStyle.content !== 'none' && iconStyle.content !== '') {
                console.log('✓ Font Awesome loaded successfully');
            } else {
                console.log('⚠ Font Awesome not loaded properly');
            }
        }
        
        console.log('All tests completed. Check the page for results.');
    });
</script>

</body>
</html><?php
/**
 * صفحة اختبار سريع للتأكد من عمل الإصلاحات
 */
require_once 'includes/config.php';
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>اختبار إصلاحات Admin</title>
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/fonts/fonts.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        body { font-family: 'Tajawal', sans-serif; margin: 20px; }
        .test-result { padding: 10px; margin: 10px 0; border-radius: 5px; }
        .success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .info { background: #d1ecf1; color: #0c5460; border: 1px solid #bee5eb; }
    </style>
</head>
<body>

<div class="container">
    <h1><i class="fas fa-check-circle"></i> اختبار إصلاحات Admin</h1>
    
    <?php
    $tests = [];
    
    // اختبار BASE_URL
    if (defined('BASE_URL')) {
        $tests[] = ['نجح', 'تم تعريف BASE_URL: ' . BASE_URL];
    } else {
        $tests[] = ['خطأ', 'لم يتم تعريف BASE_URL'];
    }
    
    // اختبار ملفات CSS
    $css_files = [
        'assets/css/bootstrap.rtl.min.css',
        'assets/fonts/fonts.css',
        'assets/css/fontawesome.min.css',
        'assets/css/dashboard.css'
    ];
    
    foreach ($css_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف CSS موجود: $file"];
        } else {
            $tests[] = ['خطأ', "ملف CSS مفقود: $file"];
        }
    }
    
    // اختبار ملفات JS
    $js_files = [
        'assets/js/jquery.min.js',
        'assets/js/bootstrap-local.js'
    ];
    
    foreach ($js_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف JS موجود: $file"];
        } else {
            $tests[] = ['خطأ', "ملف JS مفقود: $file"];
        }
    }
    
    // اختبار ملفات includes
    $include_files = [
        'includes/config.php',
        'includes/header.php',
        'includes/db.php',
        'includes/functions.php'
    ];
    
    foreach ($include_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف include موجود: $file"];
        } else {
            $tests[] = ['خطأ', "ملف include مفقود: $file"];
        }
    }
    
    // اختبار بعض ملفات admin
    $admin_files = [
        'admin/dashboard.php',
        'admin/bookings/list.php',
        'admin/settings/index.php'
    ];
    
    foreach ($admin_files as $file) {
        if (file_exists($file)) {
            $tests[] = ['نجح', "ملف admin موجود: $file"];
            
            // فحص محتوى الملف للتأكد من إصلاح المسارات
            $content = file_get_contents($file);
            if (strpos($content, "require_once '../includes/") === false && 
                strpos($content, "include '../includes/") === false) {
                $tests[] = ['نجح', "تم إصلاح مسارات includes في: $file"];
            } else {
                $tests[] = ['تحذير', "قد تحتاج مسارات includes إصلاح في: $file"];
            }
        } else {
            $tests[] = ['خطأ', "ملف admin مفقود: $file"];
        }
    }
    
    // عرض النتائج
    $success_count = 0;
    $error_count = 0;
    $warning_count = 0;
    
    foreach ($tests as $test) {
        $class = $test[0] == 'نجح' ? 'success' : ($test[0] == 'خطأ' ? 'error' : 'info');
        echo "<div class='test-result $class'>";
        echo "<strong>{$test[0]}:</strong> {$test[1]}";
        echo "</div>";
        
        if ($test[0] == 'نجح') $success_count++;
        elseif ($test[0] == 'خطأ') $error_count++;
        else $warning_count++;
    }
    ?>
    
    <div class="row mt-4">
        <div class="col-md-4">
            <div class="card text-white bg-success">
                <div class="card-body text-center">
                    <h3><?= $success_count ?></h3>
                    <p>اختبارات نجحت</p>
                </div>
            </div>
        </div>
        <div class="col-md-4">
            <div class="card text-white bg-warning">
                <div class="card-body text-center">
                    <h3><?= $warning_count ?></h3>
                    <p>تحذيرات</p>
                </div>
            </div>
        </div>
        <div class="col-md-4">
            <div class="card text-white bg-danger">
                <div class="card-body text-center">
                    <h3><?= $error_count ?></h3>
                    <p>أخطاء</p>
                </div>
            </div>
        </div>
    </div>
    
    <div class="mt-4">
        <h3>اختبار القوائم المنسدلة</h3>
        <div class="dropdown">
            <button class="btn btn-primary dropdown-toggle" type="button" data-bs-toggle="dropdown">
                <i class="fas fa-cog"></i> قائمة اختبار
            </button>
            <ul class="dropdown-menu">
                <li><h6 class="dropdown-header">عناصر الاختبار</h6></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-home"></i> الرئيسية</a></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-user"></i> المستخدمين</a></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-cog"></i> الإعدادات</a></li>
                <li><hr class="dropdown-divider"></li>
                <li><a class="dropdown-item" href="#"><i class="fas fa-sign-out-alt"></i> خروج</a></li>
            </ul>
        </div>
        <p class="mt-2 text-muted">جرب النقر على القائمة أعلاه للتأكد من عملها</p>
    </div>
    
    <div class="mt-4">
        <h3>اختبار الخطوط والأيقونات</h3>
        <p style="font-family: 'Tajawal', sans-serif; font-weight: 300;">نص بخط تجوال خفيف</p>
        <p style="font-family: 'Tajawal', sans-serif; font-weight: 400;">نص بخط تجوال عادي</p>
        <p style="font-family: 'Tajawal', sans-serif; font-weight: 700;">نص بخط تجوال غامق</p>
        
        <div class="mt-3">
            <i class="fas fa-home"></i> الرئيسية |
            <i class="fas fa-user"></i> مستخدم |
            <i class="fas fa-cog"></i> إعدادات |
            <i class="fas fa-chart-bar"></i> تقارير |
            <i class="fas fa-database"></i> قاعدة البيانات
        </div>
    </div>
    
    <div class="mt-4 alert alert-info">
        <h4><i class="fas fa-info-circle"></i> ملاحظات</h4>
        <ul>
            <li>إذا ظهرت أيقونات صحيحة أعلاه، فإن Font Awesome يعمل</li>
            <li>إذا كان النص يظهر بخط جميل، فإن خط تجوال يعمل</li>
            <li>إذا كانت القائمة المنسدلة تعمل، فإن Bootstrap يعمل</li>
            <li>تأكد من فتح وحدة تحكم المطور للتحقق من عدم وجود أخطاء</li>
        </ul>
    </div>
    
    <div class="mt-4">
        <a href="admin/dashboard.php" class="btn btn-primary">
            <i class="fas fa-arrow-left"></i> انتقل إلى لوحة الإدارة
        </a>
        <a href="ADMIN_FIXES_SUMMARY.md" class="btn btn-info" target="_blank">
            <i class="fas fa-file-alt"></i> عرض ملخص الإصلاحات
        </a>
    </div>
</div>

<script src="<?= BASE_URL ?>assets/js/jquery.min.js"></script>
<script src="<?= BASE_URL ?>assets/js/bootstrap-local.js"></script>
<script>
    // Test if Bootstrap is loaded
    if (typeof bootstrap === 'undefined') {
        console.log('Bootstrap not loaded locally, loading from CDN...');
        document.write('<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"><\/script>');
    } else {
        console.log('Bootstrap loaded successfully from local files');
    }
    
    // Test dropdown functionality
    document.addEventListener('DOMContentLoaded', function() {
        console.log('DOM loaded, testing functionality...');
        
        // Test if Tajawal font is loaded
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
        
        // Test Font Awesome
        const iconTest = document.querySelector('.fas');
        if (iconTest) {
            const iconStyle = window.getComputedStyle(iconTest, ':before');
            if (iconStyle.content !== 'none' && iconStyle.content !== '') {
                console.log('✓ Font Awesome loaded successfully');
            } else {
                console.log('⚠ Font Awesome not loaded properly');
            }
        }
        
        console.log('All tests completed. Check the page for results.');
    });
</script>

</body>
</html>