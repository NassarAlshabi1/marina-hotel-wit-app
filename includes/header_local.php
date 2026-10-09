<?php
require_once 'auth.php';
require_once __DIR__ . '/config.php';

// تحديد المنطقة الزمنية لعدن (اليمن)
date_default_timezone_set('Asia/Aden');

// تحديد المسار النسبي للأصول حسب موقع الملف
$current_dir = dirname($_SERVER['SCRIPT_NAME']);
$depth = substr_count($current_dir, '/') - 1;
$assets_path = str_repeat('../', max(0, $depth)) . 'assets/';

// تحسين الأداء - إعداد output buffering محسن
if (!ob_get_level()) {
    ob_start('ob_gzhandler');
}

// تحسين headers للأمان والأداء
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('X-XSS-Protection: 1; mode=block');
header('X-Powered-By: Marina Hotel System');
header('Cache-Control: no-cache, no-store, must-revalidate');
header('Pragma: no-cache');
header('Expires: 0');
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>نظام إدارة الفندق | فندق مارينا</title>
    <meta name="description" content="نظام إدارة الفندق الذكي لفندق مارينا">
    <meta name="robots" content="noindex, nofollow">
    <meta name="author" content="فندق مارينا">
    
    <!-- Local CSS Assets -->
    <link rel="stylesheet" href="<?= BASE_URL ?>assets/css/admin-style.css">
    
    <!-- Preload critical resources -->
    <link rel="preload" href="<?= BASE_URL ?>assets/fonts/Cairo-Regular.woff2" as="font" type="font/woff2" crossorigin>
    <link rel="preload" href="<?= BASE_URL ?>assets/fonts/fontawesome-webfont.woff2" as="font" type="font/woff2" crossorigin>
    
    <!-- Additional inline styles for critical path -->
    <style>
        /* Critical CSS for above-the-fold content */
        body {
            font-family: 'Cairo', 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            margin: 0;
            padding: 0;
            direction: rtl;
            text-align: right;
        }
        
        .codepen-nav {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            z-index: 1000;
            height: 70px;
        }
        
        .content-wrapper {
            margin-top: 70px;
            min-height: calc(100vh - 70px);
        }
        
        .loading {
            display: flex;
            justify-content: center;
            align-items: center;
            height: 200px;
        }
        
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #667eea;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 2s linear infinite;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <!-- Loading indicator -->
    <div id="pageLoader" class="loading">
        <div class="spinner"></div>
    </div>

    <!-- Navigation -->
    <nav class="codepen-nav">
        <div class="nav-container">
            <a href="<?= BASE_URL ?>" class="nav-logo">
                <i class="fas fa-hotel"></i>
                فندق مارينا
            </a>

            <ul class="main-nav" id="mainNav">
                <li class="nav-item">
                    <a href="<?= admin_url('dash.php') ?>" class="nav-link">
                        <i class="fas fa-tachometer-alt"></i>
                        الرئيسية
                    </a>
                </li>

                <li class="nav-item">
                    <a href="<?= BASE_URL ?>#" class="nav-link">
                        <i class="fas fa-bed"></i>
                        الغرف
                        <i class="fas fa-chevron-down" style="margin-left: 5px; font-size: 0.8rem;"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('rooms/list.php') ?>" class="sub-nav-link">
                                <i class="fas fa-list"></i>
                                قائمة الغرف
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('rooms/add.php') ?>" class="sub-nav-link">
                                <i class="fas fa-plus"></i>
                                إضافة غرفة
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('settings/rooms_status.php') ?>" class="sub-nav-link">
                                <i class="fas fa-chart-bar"></i>
                                حالة الغرف
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item">
                    <a href="<?= BASE_URL ?>#" class="nav-link">
                        <i class="fas fa-calendar-alt"></i>
                        الحجوزات
                        <i class="fas fa-chevron-down" style="margin-left: 5px; font-size: 0.8rem;"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('bookings/list.php') ?>" class="sub-nav-link">
                                <i class="fas fa-list"></i>
                                قائمة الحجوزات
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('bookings/add.php') ?>" class="sub-nav-link">
                                <i class="fas fa-plus"></i>
                                حجز جديد
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('bookings/checkout.php') ?>" class="sub-nav-link">
                                <i class="fas fa-sign-out-alt"></i>
                                تسجيل الخروج
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item">
                    <a href="<?= BASE_URL ?>#" class="nav-link">
                        <i class="fas fa-chart-line"></i>
                        التقارير
                        <i class="fas fa-chevron-down" style="margin-left: 5px; font-size: 0.8rem;"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('reports/revenue.php') ?>" class="sub-nav-link">
                                <i class="fas fa-dollar-sign"></i>
                                تقرير الإيرادات
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('reports/occupancy.php') ?>" class="sub-nav-link">
                                <i class="fas fa-chart-pie"></i>
                                تقرير الإشغال
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('reports/comprehensive_reports.php') ?>" class="sub-nav-link">
                                <i class="fas fa-file-alt"></i>
                                التقارير الشاملة
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item">
                    <a href="<?= BASE_URL ?>#" class="nav-link">
                        <i class="fas fa-users"></i>
                        الموظفين
                        <i class="fas fa-chevron-down" style="margin-left: 5px; font-size: 0.8rem;"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('employees/salary_withdrawals.php') ?>" class="sub-nav-link">
                                <i class="fas fa-money-check-alt"></i>
                                سحوبات الراتب
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('settings/employees.php') ?>" class="sub-nav-link">
                                <i class="fas fa-user-tie"></i>
                                إدارة الموظفين
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item">
                    <a href="<?= BASE_URL ?>#" class="nav-link">
                        <i class="fas fa-wallet"></i>
                        المالية
                        <i class="fas fa-chevron-down" style="margin-left: 5px; font-size: 0.8rem;"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('finance/cash_register.php') ?>" class="sub-nav-link">
                                <i class="fas fa-cash-register"></i>
                                الصندوق
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('expenses/expenses.php') ?>" class="sub-nav-link">
                                <i class="fas fa-receipt"></i>
                                المصروفات
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('finance/cash_reports.php') ?>" class="sub-nav-link">
                                <i class="fas fa-chart-bar"></i>
                                تقارير الصندوق
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item">
                    <a href="<?= BASE_URL ?>#" class="nav-link">
                        <i class="fas fa-cogs"></i>
                        الإعدادات
                        <i class="fas fa-chevron-down" style="margin-left: 5px; font-size: 0.8rem;"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('settings/users.php') ?>" class="sub-nav-link">
                                <i class="fas fa-user"></i>
                                المستخدمين
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('settings/guests.php') ?>" class="sub-nav-link">
                                <i class="fas fa-user-friends"></i>
                                النزلاء
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= admin_url('system_tools/backup_manager.php') ?>" class="sub-nav-link">
                                <i class="fas fa-database"></i>
                                النسخ الاحتياطي
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item user-menu">
                    <a href="<?= BASE_URL ?>#" class="user-toggle">
                        <i class="fas fa-user"></i>
                        <?= $_SESSION['username'] ?? 'مستخدم' ?>
                        <i class="fas fa-chevron-down" style="margin-right: 5px; font-size: 0.8rem;"></i>
                    </a>
                    <div class="user-dropdown">
                        <a href="<?= admin_url('settings/users.php') ?>" class="user-dropdown-item">
                            <i class="fas fa-user-edit"></i>
                            الملف الشخصي
                        </a>
                        <a href="<?= BASE_URL ?>logout.php" class="user-dropdown-item">
                            <i class="fas fa-sign-out-alt"></i>
                            تسجيل الخروج
                        </a>
                    </div>
                </li>
            </ul>

            <button class="mobile-toggle" id="mobileToggle">
                <i class="fas fa-bars"></i>
            </button>
        </div>
    </nav>

    <!-- Content Wrapper -->
    <div class="content-wrapper">
        <main class="main-content fade-in">

    <!-- Local JavaScript -->
    <script src="<?= BASE_URL ?>assets/js/admin-script.js"></script>
    
    <script>
        // Hide loading indicator when page is ready
        document.addEventListener('DOMContentLoaded', function() {
            const loader = document.getElementById('pageLoader');
            if (loader) {
                loader.style.display = 'none';
            }
        });

        // Service Worker for offline functionality (optional)
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', function() {
                navigator.serviceWorker.register('<?= BASE_URL ?>sw.js')
                    .then(function(registration) {
                        console.log('SW registered: ', registration);
                    })
                    .catch(function(registrationError) {
                        console.log('SW registration failed: ', registrationError);
                    });
            });
        }
    </script>
