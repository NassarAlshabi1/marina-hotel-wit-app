<?php
require_once 'auth.php';
require_once __DIR__ . '/config.php';
// تحديد المنطقة الزمنية لعدن (اليمن)
date_default_timezone_set('Asia/Aden');

// تحديد المسار النسبي للأصول حسب موقع الملف
$current_dir = dirname($_SERVER['SCRIPT_NAME']);
$depth = substr_count($current_dir, '/') - 1; // عدد المستويات من الجذر
$assets_path = str_repeat('../', max(0, $depth)) . 'assets/';
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>نظام إدارة الفندق</title>
    
    <!-- PWA Configuration -->
    <link rel="manifest" href="<?= BASE_URL ?>manifest.json">
    <meta name="theme-color" content="#2196f3">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <meta name="apple-mobile-web-app-title" content="فندق مارينا">
    <link rel="apple-touch-icon" href="<?= BASE_URL ?>assets/icons/icon-192x192.png">
    <meta name="msapplication-TileColor" content="#2196f3">
    <meta name="msapplication-TileImage" href="<?= BASE_URL ?>assets/icons/icon-144x144.png">

    <!-- Bootstrap CSS (Local) -->
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <!-- Local Fonts -->
    <link href="<?= BASE_URL ?>assets/fonts/fonts.css" rel="stylesheet">
    <!-- Font Awesome (Local) -->
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <!-- Dashboard CSS -->
    <link href="<?= BASE_URL ?>assets/css/dashboard.css" rel="stylesheet">
    <!-- Arabic Support CSS -->
    <link href="<?= BASE_URL ?>assets/css/arabic-support.css" rel="stylesheet">
    <!-- Google Fonts (Fallback) -->
    <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@200;300;400;500;700;800;900&display=swap" rel="stylesheet" media="print" onload="this.media='all'"  onerror="this.media='all'">

    <style>
        body {
            font-family: 'Tajawal', sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            margin: 0;
            padding-top: 80px;
            direction: rtl;
            text-align: right;
            min-height: 100vh;
        }

        /* تنسيق عام للعناصر */
        * {
            font-family: 'Tajawal', sans-serif;
        }

        /* تنسيق النافبار */
        .navbar {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%) !important;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            padding: 1rem 0;
        }

        .navbar-brand {
            font-weight: 700;
            font-size: 1.4rem;
            color: white !important;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
        }

        .navbar-brand:hover {
            color: #ffc107 !important;
        }

        .navbar-nav .nav-link {
            font-weight: 500;
            font-size: 1rem;
            padding: 0.7rem 1.2rem;
            transition: all 0.3s ease;
            color: rgba(255,255,255,0.9) !important;
            border-radius: 6px;
            margin: 0 2px;
        }

        .navbar-nav .nav-link:hover,
        .navbar-nav .nav-link:focus {
            color: #ffc107 !important;
            background-color: rgba(255,255,255,0.1);
            transform: translateY(-2px);
        }

        .navbar-toggler {
            border-color: rgba(255, 255, 255, 0.3);
            padding: 0.5rem 0.75rem;
        }

        .navbar-toggler:focus {
            box-shadow: 0 0 0 0.25rem rgba(255, 193, 7, 0.25);
        }

        /* تنسيق الجداول */
        .table {
            direction: rtl;
            text-align: right;
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }

        .table th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-weight: 600;
            border: none;
            padding: 15px;
        }

        .table td {
            padding: 12px 15px;
            border-bottom: 1px solid #eee;
            vertical-align: middle;
        }

        /* تنسيق النماذج */
        .form-control, .form-select {
            direction: rtl;
            text-align: right;
            border-radius: 8px;
            border: 1px solid #ced4da;
            transition: all 0.3s ease;
        }

        .form-control:focus, .form-select:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.25rem rgba(102, 126, 234, 0.25);
        }

        input[type="number"], input[type="tel"], .number-input {
            direction: ltr;
            text-align: left;
        }

        /* تنسيق الأزرار */
        .btn {
            border-radius: 8px;
            font-weight: 500;
            transition: all 0.3s ease;
            border: none;
        }

        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }

        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }

        .btn-success {
            background: linear-gradient(135deg, #56ab2f 0%, #a8e6cf 100%);
        }

        .btn-danger {
            background: linear-gradient(135deg, #ff416c 0%, #ff4b2b 100%);
        }

        .btn-warning {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }

        /* تنسيق التنبيهات */
        .alert {
            font-size: 1rem;
            font-weight: 500;
            border-radius: 10px;
            border: none;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }

        /* تنسيق البطاقات */
        .card {
            border: none;
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            transition: all 0.3s ease;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
        }

        .card-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 15px 15px 0 0 !important;
            border: none;
            font-weight: 600;
        }

        /* تنسيق القوائم المنسدلة */
        .dropdown-menu {
            border: none;
            border-radius: 12px;
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
            padding: 10px 0;
            margin-top: 8px;
            min-width: 280px;
            background: white;
        }

        .dropdown-header {
            color: #667eea !important;
            font-weight: 700;
            font-size: 0.85rem;
            padding: 8px 20px 5px;
            margin-bottom: 5px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .dropdown-item {
            padding: 10px 20px;
            font-size: 0.95rem;
            color: #495057;
            transition: all 0.3s ease;
            border-radius: 0;
        }

        .dropdown-item:hover,
        .dropdown-item:focus {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            transform: translateX(-5px);
        }

        .dropdown-item i {
            width: 20px;
            text-align: center;
            opacity: 0.7;
        }

        .dropdown-item:hover i,
        .dropdown-item:focus i {
            opacity: 1;
        }

        .dropdown-divider {
            margin: 8px 0;
            border-color: #e9ecef;
        }

        /* تحسين عرض القائمة المنسدلة */
        .dropdown:hover .dropdown-menu {
            display: block;
            margin-top: 0;
        }

        .dropdown-toggle::after {
            margin-right: 5px;
        }

        /* إصلاحات إضافية للقوائم المنسدلة */
        .dropdown-menu {
            right: 0 !important;
            left: auto !important;
            transform-origin: top right;
            opacity: 0;
            transform: translateY(-10px);
            transition: all 0.3s ease;
            pointer-events: none;
        }

        .dropdown-menu.show {
            opacity: 1;
            transform: translateY(0);
            pointer-events: auto;
        }

        .dropdown-item {
            text-align: right;
            padding-right: 20px;
            padding-left: 20px;
        }

        .dropdown-item:hover {
            background-color: #667eea;
            color: white;
        }

        /* إصلاح للأجهزة المحمولة */
        @media (max-width: 768px) {
            .dropdown-menu {
                position: static !important;
                transform: none !important;
                opacity: 1 !important;
                pointer-events: auto !important;
                box-shadow: none;
                border: 1px solid #dee2e6;
                margin-top: 5px;
            }
        }

        /* تنسيق متجاوب */
        @media (max-width: 768px) {
            body {
                padding-top: 70px;
            }

            .navbar-brand {
                font-size: 1.2rem;
            }

            .navbar-nav .nav-link {
                padding: 0.5rem 1rem;
                font-size: 0.9rem;
            }

            .table {
                font-size: 0.9rem;
            }

            .btn {
                font-size: 0.9rem;
                padding: 0.5rem 1rem;
            }
        }

        @media (max-width: 576px) {
            .table th, .table td {
                padding: 8px 10px;
                font-size: 0.8rem;
            }
        }
    </style>
</head>
<body>
    <!-- شريط التنقل -->
    <nav class="navbar navbar-expand-lg fixed-top" aria-label="Main navigation">
        <div class="container">
            <a class="navbar-brand" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/dash.php" title="الصفحة الرئيسية">
                <i class="fas fa-hotel me-2"></i>نظام إدارة الفندق
            </a>
            <button
                class="navbar-toggler"
                type="button"
                data-bs-toggle="collapse"
                data-bs-target="#navbarNav"
                aria-controls="navbarNav"
                aria-expanded="false"
                aria-label="تبديل التنقل"
            >
                <span class="navbar-toggler-icon"></span>
            </button>

            <div class="collapse navbar-collapse" id="navbarNav">
                <ul class="navbar-nav me-auto">
                    <li class="nav-item">
                        <a class="nav-link" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/dash.php">
                            <i class="fas fa-tachometer-alt me-1"></i>لوحة التحكم
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/bookings/list.php">
                            <i class="fas fa-calendar-alt me-1"></i>الحجوزات
                        </a>
                    </li>
                    <li class="nav-item">
                        <a class="nav-link" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/bookings/add2.php">
                            <i class="fas fa-plus-circle me-1"></i>حجز جديد
                        </a>
                    </li>
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-chart-bar me-1"></i>التقارير
                        </a>
                        <ul class="dropdown-menu">
                            <li><h6 class="dropdown-header"><i class="fas fa-money-bill-wave me-1"></i>التقارير المالية</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/reports/revenue.php">
                                <i class="fas fa-chart-line me-2"></i>تقارير الإيرادات
                            </a></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/reports/report.php">
                                <i class="fas fa-chart-pie me-2"></i>التقارير الشاملة
                            </a></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/reports/comprehensive_reports.php">
                                <i class="fas fa-file-alt me-2"></i>التقارير التفصيلية
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header"><i class="fas fa-users me-1"></i>تقارير الموظفين</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/reports/employee_withdrawals_report.php">
                                <i class="fas fa-hand-holding-usd me-2"></i>سحوبات الموظفين
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header"><i class="fas fa-bed me-1"></i>تقارير الإشغال</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/reports/occupancy.php">
                                <i class="fas fa-chart-area me-2"></i>تقرير الإشغال
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header"><i class="fas fa-print me-1"></i>التصدير</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/reports/export_excel.php">
                                <i class="fas fa-file-excel me-2"></i>تصدير Excel
                            </a></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/reports/export_pdf.php">
                                <i class="fas fa-file-pdf me-2"></i>تصدير PDF
                            </a></li>
                        </ul>
                    </li>
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-file-invoice-dollar me-1"></i>المصروفات
                        </a>
                        <ul class="dropdown-menu">
                            <li><h6 class="dropdown-header"><i class="fas fa-plus me-1"></i>إضافة مصروفات</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/expenses/expenses.php">
                                <i class="fas fa-plus-circle me-2"></i>إضافة مصروف جديد
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header"><i class="fas fa-list me-1"></i>إدارة المصروفات</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/expenses/list.php">
                                <i class="fas fa-list-ul me-2"></i>قائمة المصروفات
                            </a></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/expenses/categories.php">
                                <i class="fas fa-tags me-2"></i>فئات المصروفات
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header"><i class="fas fa-users-cog me-1"></i>مصروفات الموظفين</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/expenses/employee_expenses.php">
                                <i class="fas fa-user-tie me-2"></i>مصروفات الرواتب
                            </a></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/expenses/salary_withdrawals.php">
                                <i class="fas fa-hand-holding-usd me-2"></i>سحوبات الرواتب
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header"><i class="fas fa-chart-bar me-1"></i>تقارير المصروفات</h6></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/expenses/monthly_report.php">
                                <i class="fas fa-calendar-alt me-2"></i>التقرير الشهري
                            </a></li>
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/expenses/yearly_report.php">
                                <i class="fas fa-calendar me-2"></i>التقرير السنوي
                            </a></li>
                        </ul>
                    </li>
                </ul>

                <!-- معلومات المستخدم -->
                <ul class="navbar-nav">
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-user me-1"></i>المستخدم
                        </a>
                        <ul class="dropdown-menu dropdown-menu-end">
                            <li><a class="dropdown-item" href="<?php echo str_repeat('../', max(0, $depth)); ?>logout.php">
                                <i class="fas fa-sign-out-alt me-1"></i>تسجيل الخروج
                            </a></li>
                        </ul>
                    </li>
                </ul>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        <?php if (isset($_SESSION['success'])): ?>
            <div class="alert alert-success alert-dismissible fade show" role="alert">
                <?= htmlspecialchars($_SESSION['success']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['success']); ?>
        <?php endif; ?>

        <?php if (isset($_SESSION['error'])): ?>
            <div class="alert alert-danger alert-dismissible fade show" role="alert">
                <?= htmlspecialchars($_SESSION['error']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['error']); ?>
        <?php endif; ?>

        <!-- باقي محتوى الصفحة -->
    </div>

    <!-- jQuery Local -->
    <script src="<?= BASE_URL ?>assets/js/jquery.min.js"></script>
    <!-- Bootstrap JS Local -->
    <script src="<?= BASE_URL ?>assets/js/bootstrap-local.js"></script>
    <!-- Bootstrap JS Fallback -->
    <script>
        if (typeof bootstrap === 'undefined') {
            document.write('<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"><\/script>');
        }
    </script>

    <script>
        // تحسين تجربة المستخدم
        document.addEventListener('DOMContentLoaded', function() {
            // إصلاح القوائم المنسدلة
            initDropdownFixes();
            
            // إضافة تأثيرات للأزرار
            const buttons = document.querySelectorAll('.btn');
            buttons.forEach(button => {
                button.addEventListener('mouseenter', function() {
                    this.style.transform = 'translateY(-2px)';
                });
                button.addEventListener('mouseleave', function() {
                    this.style.transform = 'translateY(0)';
                });
            });

            // تحسين عرض التنبيهات
            const alerts = document.querySelectorAll('.alert');
            alerts.forEach(alert => {
                setTimeout(() => {
                    if (alert.classList.contains('alert-dismissible')) {
                        const closeBtn = alert.querySelector('.btn-close');
                        if (closeBtn) {
                            closeBtn.click();
                        }
                    }
                }, 5000); // إخفاء التنبيه بعد 5 ثوان
            });
        });

        // إصلاح القوائم المنسدلة
        function initDropdownFixes() {
            const dropdowns = document.querySelectorAll('.dropdown');
            
            dropdowns.forEach(dropdown => {
                const toggle = dropdown.querySelector('.dropdown-toggle');
                const menu = dropdown.querySelector('.dropdown-menu');
                
                if (toggle && menu) {
                    // إصلاح موقع القائمة للعربية
                    menu.style.right = '0';
                    menu.style.left = 'auto';
                    
                    // تحسين التفاعل بالماوس (للشاشات الكبيرة)
                    if (window.innerWidth > 768) {
                        dropdown.addEventListener('mouseenter', function() {
                            menu.classList.add('show');
                            toggle.setAttribute('aria-expanded', 'true');
                        });
                        
                        dropdown.addEventListener('mouseleave', function() {
                            menu.classList.remove('show');
                            toggle.setAttribute('aria-expanded', 'false');
                        });
                    }
                    
                    // تحسين النقر
                    toggle.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                        
                        // إغلاق القوائم الأخرى
                        document.querySelectorAll('.dropdown-menu.show').forEach(otherMenu => {
                            if (otherMenu !== menu) {
                                otherMenu.classList.remove('show');
                                const otherToggle = otherMenu.parentElement.querySelector('.dropdown-toggle');
                                if (otherToggle) otherToggle.setAttribute('aria-expanded', 'false');
                            }
                        });
                        
                        // تبديل القائمة الحالية
                        const isShown = menu.classList.contains('show');
                        if (isShown) {
                            menu.classList.remove('show');
                            toggle.setAttribute('aria-expanded', 'false');
                        } else {
                            menu.classList.add('show');
                            toggle.setAttribute('aria-expanded', 'true');
                        }
                    });
                    
                    // إضافة تأثيرات CSS للقائمة
                    menu.style.transition = 'all 0.3s ease';
                    menu.style.opacity = menu.classList.contains('show') ? '1' : '0';
                    menu.style.transform = menu.classList.contains('show') ? 'translateY(0)' : 'translateY(-10px)';
                    
                    // مراقبة تغيير فئة show
                    const observer = new MutationObserver(function(mutations) {
                        mutations.forEach(function(mutation) {
                            if (mutation.type === 'attributes' && mutation.attributeName === 'class') {
                                if (menu.classList.contains('show')) {
                                    menu.style.opacity = '1';
                                    menu.style.transform = 'translateY(0)';
                                } else {
                                    menu.style.opacity = '0';
                                    menu.style.transform = 'translateY(-10px)';
                                }
                            }
                        });
                    });
                    observer.observe(menu, { attributes: true });
                }
            });
            
            // إغلاق القوائم عند النقر خارجها
            document.addEventListener('click', function(e) {
                if (!e.target.closest('.dropdown')) {
                    document.querySelectorAll('.dropdown-menu.show').forEach(menu => {
                        menu.classList.remove('show');
                        const toggle = menu.parentElement.querySelector('.dropdown-toggle');
                        if (toggle) toggle.setAttribute('aria-expanded', 'false');
                    });
                }
            });
            
            // إغلاق القوائم بمفتاح Escape
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') {
                    document.querySelectorAll('.dropdown-menu.show').forEach(menu => {
                        menu.classList.remove('show');
                        const toggle = menu.parentElement.querySelector('.dropdown-toggle');
                        if (toggle) {
                            toggle.setAttribute('aria-expanded', 'false');
                            toggle.focus();
                        }
                    });
                }
            });
        }

        // دالة لتأكيد الحذف
        function confirmDelete(message = 'هل أنت متأكد من الحذف؟') {
            return confirm(message);
        }

        // دالة لعرض رسائل النجاح
        function showSuccess(message) {
            const alertDiv = document.createElement('div');
            alertDiv.className = 'alert alert-success alert-dismissible fade show';
            alertDiv.innerHTML = `
                ${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            `;

            const container = document.querySelector('.container');
            if (container) {
                container.insertBefore(alertDiv, container.firstChild);
            }
        }

        // دالة لعرض رسائل الخطأ
        function showError(message) {
            const alertDiv = document.createElement('div');
            alertDiv.className = 'alert alert-danger alert-dismissible fade show';
            alertDiv.innerHTML = `
                ${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            `;

            const container = document.querySelector('.container');
            if (container) {
                container.insertBefore(alertDiv, container.firstChild);
            }
        }

        // PWA Service Worker Registration
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', function() {
                navigator.serviceWorker.register('<?= BASE_URL ?>sw.js')
                    .then(function(registration) {
                        console.log('SW registered: ', registration);
                        
                        // إضافة زر التثبيت
                        addInstallButton();
                    })
                    .catch(function(registrationError) {
                        console.log('SW registration failed: ', registrationError);
                    });
            });
        }

        // إضافة زر تثبيت PWA
        let deferredPrompt;
        
        window.addEventListener('beforeinstallprompt', function(e) {
            e.preventDefault();
            deferredPrompt = e;
            showInstallButton();
        });

        function addInstallButton() {
            // إنشاء زر التثبيت
            const installButton = document.createElement('button');
            installButton.id = 'installPWA';
            installButton.innerHTML = '📱 تثبيت التطبيق';
            installButton.className = 'btn btn-primary position-fixed';
            installButton.style.cssText = `
                bottom: 20px;
                left: 20px;
                z-index: 1050;
                border-radius: 25px;
                padding: 10px 20px;
                font-size: 14px;
                box-shadow: 0 4px 15px rgba(0,0,0,0.2);
                display: none;
            `;
            
            installButton.addEventListener('click', function() {
                if (deferredPrompt) {
                    deferredPrompt.prompt();
                    deferredPrompt.userChoice.then(function(choiceResult) {
                        if (choiceResult.outcome === 'accepted') {
                            console.log('User accepted the install prompt');
                            hideInstallButton();
                        } else {
                            console.log('User dismissed the install prompt');
                        }
                        deferredPrompt = null;
                    });
                }
            });
            
            document.body.appendChild(installButton);
        }

        function showInstallButton() {
            const installButton = document.getElementById('installPWA');
            if (installButton) {
                installButton.style.display = 'block';
                
                // إضافة تأثير الظهور
                setTimeout(() => {
                    installButton.style.opacity = '1';
                    installButton.style.transform = 'translateY(0)';
                }, 100);
            }
        }

        function hideInstallButton() {
            const installButton = document.getElementById('installPWA');
            if (installButton) {
                installButton.style.display = 'none';
            }
        }

        // إخفاء زر التثبيت إذا كان التطبيق مثبت بالفعل
        window.addEventListener('appinstalled', function() {
            hideInstallButton();
            console.log('PWA was installed');
        });

        // إضافة مؤشر حالة الاتصال
        window.addEventListener('online', function() {
            showConnectionStatus('🟢 متصل', 'success');
        });

        window.addEventListener('offline', function() {
            showConnectionStatus('🔴 غير متصل', 'warning');
        });

        function showConnectionStatus(message, type) {
            const statusDiv = document.createElement('div');
            statusDiv.className = `alert alert-${type} position-fixed`;
            statusDiv.style.cssText = `
                top: 80px;
                right: 20px;
                z-index: 1051;
                padding: 8px 15px;
                border-radius: 20px;
                font-size: 12px;
                min-width: 120px;
                text-align: center;
            `;
            statusDiv.textContent = message;
            
            document.body.appendChild(statusDiv);
            
            setTimeout(() => {
                statusDiv.remove();
            }, 3000);
        }
    </script>
