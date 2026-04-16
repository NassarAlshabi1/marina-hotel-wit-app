<?php
require_once 'auth.php';
require_once __DIR__ . '/config.php';

// تحديد المنطقة الزمنية لعدن (اليمن)
date_default_timezone_set('Asia/Aden');

// تحديد المسار النسبي للأصول حسب موقع الملف
$current_dir = dirname($_SERVER['SCRIPT_NAME']);
$depth = substr_count($current_dir, '/') - 1;
$assets_path = str_repeat('../', max(0, $depth)) . 'assets/';
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
    <title>نظام إدارة الفندق | فندق مارينا</title>
    <meta name="description" content="نظام إدارة الفندق الذكي لفندق مارينا">
    <meta name="keywords" content="فندق,مارينا,نظام,إدارة,حجوزات">
    
    <!-- PWA Configuration -->
    <link rel="manifest" href="<?= BASE_URL ?>manifest.json">
    <meta name="theme-color" content="#2196f3">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-status-bar-style" content="default">
    <meta name="apple-mobile-web-app-title" content="فندق مارينا">
    <link rel="apple-touch-icon" href="<?= BASE_URL ?>assets/icons/icon-192x192.png">
    <meta name="msapplication-TileColor" content="#2196f3">
    <meta name="msapplication-TileImage" content="<?= BASE_URL ?>assets/icons/icon-144x144.png">

    <!-- Preconnect for faster loading -->
    <link rel="preconnect" href="<?= BASE_URL ?>">
    <link rel="dns-prefetch" href="<?= BASE_URL ?>">

    <!-- CSS Files with loading optimization -->
    <link rel="preload" href="<?= BASE_URL ?>includes/css/bootstrap.min.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
    <link rel="preload" href="<?= BASE_URL ?>includes/css/tajawal-font.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
    <link rel="preload" href="<?= BASE_URL ?>includes/css/cairo-font.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
    <link rel="preload" href="<?= BASE_URL ?>includes/css/fontawesome.min.css" as="style" onload="this.onload=null;this.rel='stylesheet'">
    
    <!-- Fallback for browsers that don't support preload -->
    <noscript>
        <link href="<?= BASE_URL ?>includes/css/bootstrap.min.css" rel="stylesheet">
        <link href="<?= BASE_URL ?>includes/css/tajawal-font.css" rel="stylesheet">
        <link href="<?= BASE_URL ?>includes/css/cairo-font.css" rel="stylesheet">
        <link href="<?= BASE_URL ?>includes/css/fontawesome.min.css" rel="stylesheet">
    </noscript>

    <style>
        /* متغيرات CSS للألوان والتأثيرات */
        :root {
            --primary-color: #667eea;
            --secondary-color: #764ba2;
            --accent-color: #ffc107;
            --success-color: #28a745;
            --danger-color: #dc3545;
            --warning-color: #ffc107;
            --info-color: #17a2b8;
            --light-color: #f8f9fa;
            --dark-color: #343a40;
            --shadow-sm: 0 2px 4px rgba(0,0,0,0.1);
            --shadow-md: 0 4px 8px rgba(0,0,0,0.15);
            --shadow-lg: 0 8px 16px rgba(0,0,0,0.2);
            --border-radius: 8px;
            --transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        }

        /* تحسين الأداء مع will-change */
        .animated-element {
            will-change: transform, opacity;
        }

        /* تحسين الخط الأساسي */
        * {
            font-family: 'Tajawal', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }

        body {
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            margin: 0;
            padding-top: 85px;
            direction: rtl;
            text-align: right;
            min-height: 100vh;
            font-size: 14px;
            line-height: 1.6;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
        }

        /* تحسين شريط التنقل */
        .navbar {
            background: linear-gradient(135deg, var(--primary-color) 0%, var(--secondary-color) 100%) !important;
            box-shadow: var(--shadow-md);
            padding: 1rem 0;
            transition: var(--transition);
            backdrop-filter: blur(10px);
            -webkit-backdrop-filter: blur(10px);
        }

        .navbar.scrolled {
            padding: 0.5rem 0;
            box-shadow: var(--shadow-lg);
        }

        .navbar-brand {
            font-weight: 700;
            font-size: 1.5rem;
            color: white !important;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
            transition: var(--transition);
        }

        .navbar-brand:hover {
            color: var(--accent-color) !important;
            transform: scale(1.05);
        }

        .navbar-nav .nav-link {
            font-weight: 500;
            font-size: 0.95rem;
            padding: 0.75rem 1rem;
            transition: var(--transition);
            color: rgba(255,255,255,0.9) !important;
            border-radius: var(--border-radius);
            margin: 0 2px;
            position: relative;
            overflow: hidden;
        }

        .navbar-nav .nav-link::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: linear-gradient(45deg, transparent, rgba(255,255,255,0.1), transparent);
            transform: translateX(-100%);
            transition: var(--transition);
        }

        .navbar-nav .nav-link:hover::before {
            transform: translateX(100%);
        }

        .navbar-nav .nav-link:hover,
        .navbar-nav .nav-link:focus {
            color: var(--accent-color) !important;
            background-color: rgba(255,255,255,0.1);
            transform: translateY(-2px);
        }

        .navbar-nav .nav-link.active {
            background-color: rgba(255,255,255,0.2);
            color: var(--accent-color) !important;
        }

        /* تحسين القوائم المنسدلة */
        .dropdown-menu {
            border: none;
            border-radius: 12px;
            box-shadow: var(--shadow-lg);
            padding: 0.5rem 0;
            margin-top: 0.5rem;
            min-width: 300px;
            background: rgba(255,255,255,0.95);
            backdrop-filter: blur(10px);
            -webkit-backdrop-filter: blur(10px);
            animation: dropdownFadeIn 0.3s ease;
        }

        @keyframes dropdownFadeIn {
            from {
                opacity: 0;
                transform: translateY(-10px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        .dropdown-header {
            color: var(--primary-color) !important;
            font-weight: 700;
            font-size: 0.8rem;
            padding: 0.5rem 1.25rem;
            margin-bottom: 0.25rem;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            position: relative;
        }

        .dropdown-header::after {
            content: '';
            position: absolute;
            bottom: 0;
            left: 1.25rem;
            right: 1.25rem;
            height: 1px;
            background: linear-gradient(to right, var(--primary-color), transparent);
        }

        .dropdown-item {
            padding: 0.75rem 1.25rem;
            font-size: 0.9rem;
            color: #495057;
            transition: var(--transition);
            border-radius: 0;
            position: relative;
            overflow: hidden;
        }

        .dropdown-item::before {
            content: '';
            position: absolute;
            top: 0;
            right: 0;
            width: 0;
            height: 100%;
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            transition: var(--transition);
            z-index: -1;
        }

        .dropdown-item:hover::before,
        .dropdown-item:focus::before {
            width: 100%;
        }

        .dropdown-item:hover,
        .dropdown-item:focus {
            background: transparent;
            color: white;
            transform: translateX(-5px);
        }

        .dropdown-item i {
            width: 20px;
            text-align: center;
            margin-left: 0.5rem;
            transition: var(--transition);
        }

        .dropdown-divider {
            margin: 0.5rem 0;
            border-color: rgba(0,0,0,0.1);
        }

        /* تحسين الجداول */
        .table {
            direction: rtl;
            text-align: right;
            background: white;
            border-radius: var(--border-radius);
            overflow: hidden;
            box-shadow: var(--shadow-sm);
            border: none;
        }

        .table th {
            background: linear-gradient(135deg, var(--primary-color) 0%, var(--secondary-color) 100%);
            color: white;
            font-weight: 600;
            border: none;
            padding: 1rem;
            position: relative;
        }

        .table th::after {
            content: '';
            position: absolute;
            bottom: 0;
            left: 0;
            right: 0;
            height: 2px;
            background: var(--accent-color);
        }

        .table td {
            padding: 0.75rem 1rem;
            border-bottom: 1px solid #eee;
            vertical-align: middle;
            transition: var(--transition);
        }

        .table tbody tr:hover {
            background-color: rgba(102, 126, 234, 0.05);
            transform: translateX(5px);
        }

        /* تحسين النماذج */
        .form-control, .form-select {
            direction: rtl;
            text-align: right;
            border-radius: var(--border-radius);
            border: 2px solid #e9ecef;
            transition: var(--transition);
            font-size: 0.9rem;
            padding: 0.625rem 0.75rem;
        }

        .form-control:focus, .form-select:focus {
            border-color: var(--primary-color);
            box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
            transform: translateY(-1px);
        }

        .form-label {
            font-weight: 600;
            color: #495057;
            margin-bottom: 0.5rem;
        }

        /* تحسين الأزرار */
        .btn {
            border-radius: var(--border-radius);
            font-weight: 500;
            transition: var(--transition);
            border: none;
            padding: 0.625rem 1.25rem;
            font-size: 0.9rem;
            position: relative;
            overflow: hidden;
        }

        .btn::before {
            content: '';
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: linear-gradient(45deg, transparent, rgba(255,255,255,0.2), transparent);
            transform: translateX(-100%);
            transition: var(--transition);
        }

        .btn:hover::before {
            transform: translateX(100%);
        }

        .btn:hover {
            transform: translateY(-2px);
            box-shadow: var(--shadow-md);
        }

        .btn-primary {
            background: linear-gradient(135deg, var(--primary-color) 0%, var(--secondary-color) 100%);
            color: white;
        }

        .btn-success {
            background: linear-gradient(135deg, #56ab2f 0%, #a8e6cf 100%);
            color: white;
        }

        .btn-danger {
            background: linear-gradient(135deg, #ff416c 0%, #ff4b2b 100%);
            color: white;
        }

        .btn-warning {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
        }

        /* تحسين التنبيهات */
        .alert {
            border-radius: 12px;
            border: none;
            box-shadow: var(--shadow-sm);
            padding: 1rem 1.25rem;
            margin-bottom: 1rem;
            animation: alertSlideIn 0.3s ease;
        }

        @keyframes alertSlideIn {
            from {
                opacity: 0;
                transform: translateY(-20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }

        /* تحسين البطاقات */
        .card {
            border: none;
            border-radius: 15px;
            box-shadow: var(--shadow-sm);
            transition: var(--transition);
            overflow: hidden;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: var(--shadow-lg);
        }

        .card-header {
            background: linear-gradient(135deg, var(--primary-color) 0%, var(--secondary-color) 100%);
            color: white;
            border-radius: 15px 15px 0 0 !important;
            border: none;
            font-weight: 600;
            padding: 1rem 1.25rem;
        }

        /* تحسين المؤشرات */
        .spinner-border {
            width: 1rem;
            height: 1rem;
            border-width: 0.1em;
        }

        .loading-overlay {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(255, 255, 255, 0.9);
            display: flex;
            justify-content: center;
            align-items: center;
            z-index: 9999;
            backdrop-filter: blur(5px);
        }

        /* تحسين التنقل للأجهزة المحمولة */
        @media (max-width: 768px) {
            body {
                padding-top: 75px;
            }

            .navbar-brand {
                font-size: 1.25rem;
            }

            .navbar-nav .nav-link {
                padding: 0.5rem 1rem;
                font-size: 0.9rem;
            }

            .dropdown-menu {
                min-width: 250px;
                position: static !important;
                transform: none !important;
                box-shadow: none;
                border: 1px solid #dee2e6;
                margin-top: 0.25rem;
            }

            .table {
                font-size: 0.85rem;
            }

            .table th, .table td {
                padding: 0.5rem;
            }

            .btn {
                font-size: 0.85rem;
                padding: 0.5rem 1rem;
            }
        }

        @media (max-width: 576px) {
            .table th, .table td {
                padding: 0.4rem;
                font-size: 0.8rem;
            }

            .dropdown-menu {
                min-width: 100%;
            }
        }

        /* تحسين إمكانية الوصول */
        .focus-visible {
            outline: 2px solid var(--primary-color);
            outline-offset: 2px;
        }

        /* تحسين الطباعة */
        @media print {
            .navbar, .btn, .alert {
                display: none !important;
            }

            body {
                padding-top: 0;
                background: white !important;
            }

            .table {
                box-shadow: none;
            }
        }

        /* تحسين الوضع المظلم */
        @media (prefers-color-scheme: dark) {
            :root {
                --light-color: #2d3748;
                --dark-color: #f7fafc;
            }
        }
    </style>
</head>
<body>
    <!-- Loading Overlay -->
    <div id="loadingOverlay" class="loading-overlay" style="display: none;">
        <div class="text-center">
            <div class="spinner-border text-primary" role="status">
                <span class="visually-hidden">جاري التحميل...</span>
            </div>
            <div class="mt-2">جاري التحميل...</div>
        </div>
    </div>

    <!-- شريط التنقل المحسن -->
    <nav class="navbar navbar-expand-lg fixed-top" id="mainNavbar" aria-label="التنقل الرئيسي">
        <div class="container">
            <a class="navbar-brand animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>dash.php" title="الصفحة الرئيسية">
                <i class="fas fa-hotel me-2"></i>
                نظام إدارة الفندق
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
                        <a class="nav-link animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>dash.php">
                            <i class="fas fa-tachometer-alt me-1"></i>لوحة التحكم
                        </a>
                    </li>
                    
                    <!-- قائمة الغرف -->
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle animated-element" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-bed me-1"></i>إدارة الغرف
                        </a>
                        <ul class="dropdown-menu" role="menu">
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-bed me-1"></i>إدارة الغرف
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>rooms/list.php" role="menuitem">
                                <i class="fas fa-list me-2"></i>قائمة الغرف
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>rooms/add.php" role="menuitem">
                                <i class="fas fa-plus-circle me-2"></i>إضافة غرفة جديدة
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-chart-bar me-1"></i>حالة الغرف
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>settings/rooms_status.php" role="menuitem">
                                <i class="fas fa-chart-pie me-2"></i>تقرير حالة الغرف
                            </a></li>
                        </ul>
                    </li>
                    
                    <!-- قائمة الحجوزات -->
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle animated-element" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-calendar-alt me-1"></i>الحجوزات
                        </a>
                        <ul class="dropdown-menu" role="menu">
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-calendar me-1"></i>إدارة الحجوزات
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>bookings/list.php" role="menuitem">
                                <i class="fas fa-list me-2"></i>قائمة الحجوزات
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>bookings/add_booking.php" role="menuitem">
                                <i class="fas fa-plus-circle me-2"></i>حجز جديد
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-sign-out-alt me-1"></i>عمليات الخروج
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>bookings/checkout.php" role="menuitem">
                                <i class="fas fa-door-open me-2"></i>تسجيل الخروج
                            </a></li>
                        </ul>
                    </li>
                    
                    <!-- قائمة الموظفين -->
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle animated-element" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-users me-1"></i>الموظفين
                        </a>
                        <ul class="dropdown-menu" role="menu">
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-users-cog me-1"></i>إدارة الموظفين
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>employees/list.php" role="menuitem">
                                <i class="fas fa-list me-2"></i>قائمة الموظفين
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>employees/add_employee.php" role="menuitem">
                                <i class="fas fa-user-plus me-2"></i>إضافة موظف جديد
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-money-bill-wave me-1"></i>الرواتب والسحوبات
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>employees/salary_withdrawals.php" role="menuitem">
                                <i class="fas fa-hand-holding-usd me-2"></i>سحوبات الرواتب
                            </a></li>
                        </ul>
                    </li>
                    
                    <!-- قائمة المالية -->
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle animated-element" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-wallet me-1"></i>المالية
                        </a>
                        <ul class="dropdown-menu" role="menu">
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-cash-register me-1"></i>إدارة الصندوق
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>finance/cash_register.php" role="menuitem">
                                <i class="fas fa-cash-register me-2"></i>سجل الصندوق
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>finance/cash_reports.php" role="menuitem">
                                <i class="fas fa-file-invoice-dollar me-2"></i>تقارير الصندوق
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-file-invoice me-1"></i>المصروفات
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>expenses/list.php" role="menuitem">
                                <i class="fas fa-list me-2"></i>قائمة المصروفات
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>expenses/expenses.php" role="menuitem">
                                <i class="fas fa-plus-circle me-2"></i>إضافة مصروف جديد
                            </a></li>
                        </ul>
                    </li>
                    
                    <!-- قائمة التقارير -->
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle animated-element" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-chart-bar me-1"></i>التقارير
                        </a>
                        <ul class="dropdown-menu" role="menu">
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-money-bill-wave me-1"></i>التقارير المالية
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>reports/revenue.php" role="menuitem">
                                <i class="fas fa-chart-line me-2"></i>تقارير الإيرادات
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>reports/report.php" role="menuitem">
                                <i class="fas fa-chart-pie me-2"></i>التقارير الشاملة
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>reports/comprehensive_reports.php" role="menuitem">
                                <i class="fas fa-file-alt me-2"></i>التقارير التفصيلية
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-users me-1"></i>تقارير الموظفين
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>reports/employee_withdrawals_report.php" role="menuitem">
                                <i class="fas fa-hand-holding-usd me-2"></i>سحوبات الموظفين
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-bed me-1"></i>تقارير الإشغال
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>reports/occupancy.php" role="menuitem">
                                <i class="fas fa-chart-area me-2"></i>تقرير الإشغال
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-print me-1"></i>التصدير
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>reports/export_excel.php" role="menuitem">
                                <i class="fas fa-file-excel me-2"></i>تصدير Excel
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>reports/export_pdf.php" role="menuitem">
                                <i class="fas fa-file-pdf me-2"></i>تصدير PDF
                            </a></li>
                        </ul>
                    </li>
                    
                    <!-- قائمة الإعدادات -->
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle animated-element" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-cogs me-1"></i>الإعدادات
                        </a>
                        <ul class="dropdown-menu" role="menu">
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-users-cog me-1"></i>إدارة المستخدمين
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>settings/users.php" role="menuitem">
                                <i class="fas fa-users me-2"></i>المستخدمون
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>settings/add_user.php" role="menuitem">
                                <i class="fas fa-user-plus me-2"></i>إضافة مستخدم
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-user-friends me-1"></i>إدارة النزلاء
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>settings/guests.php" role="menuitem">
                                <i class="fas fa-users me-2"></i>قائمة النزلاء
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>settings/guest_history.php" role="menuitem">
                                <i class="fas fa-history me-2"></i>سجل النزلاء
                            </a></li>
                            <li><hr class="dropdown-divider"></li>
                            <li><h6 class="dropdown-header">
                                <i class="fas fa-tools me-1"></i>أدوات النظام
                            </h6></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>system_tools/backup_manager.php" role="menuitem">
                                <i class="fas fa-database me-2"></i>النسخ الاحتياطي
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>settings/maintenance.php" role="menuitem">
                                <i class="fas fa-tools me-2"></i>صيانة النظام
                            </a></li>
                        </ul>
                    </li>
                </ul>

                <!-- معلومات المستخدم -->
                <ul class="navbar-nav">
                    <li class="nav-item dropdown">
                        <a class="nav-link dropdown-toggle animated-element" href="#" role="button" data-bs-toggle="dropdown" aria-expanded="false">
                            <i class="fas fa-user me-1"></i>
                            <span class="d-none d-md-inline"><?= $_SESSION['username'] ?? 'المستخدم' ?></span>
                        </a>
                        <ul class="dropdown-menu dropdown-menu-end" role="menu">
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>settings/users.php" role="menuitem">
                                <i class="fas fa-user-edit me-2"></i>الملف الشخصي
                            </a></li>
                            <li><a class="dropdown-item animated-element" href="<?php echo str_repeat('../', max(0, $depth)); ?>logout.php" role="menuitem">
                                <i class="fas fa-sign-out-alt me-2"></i>تسجيل الخروج
                            </a></li>
                        </ul>
                    </li>
                </ul>
            </div>
        </div>
    </nav>

    <!-- حاوي المحتوى -->
    <main class="container mt-4" id="mainContent">
        <!-- عرض الرسائل المحسن -->
        <?php if (isset($_SESSION['success'])): ?>
            <div class="alert alert-success alert-dismissible fade show" role="alert">
                <i class="fas fa-check-circle me-2"></i>
                <?= htmlspecialchars($_SESSION['success']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['success']); ?>
        <?php endif; ?>

        <?php if (isset($_SESSION['error'])): ?>
            <div class="alert alert-danger alert-dismissible fade show" role="alert">
                <i class="fas fa-exclamation-circle me-2"></i>
                <?= htmlspecialchars($_SESSION['error']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['error']); ?>
        <?php endif; ?>

        <?php if (isset($_SESSION['warning'])): ?>
            <div class="alert alert-warning alert-dismissible fade show" role="alert">
                <i class="fas fa-exclamation-triangle me-2"></i>
                <?= htmlspecialchars($_SESSION['warning']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['warning']); ?>
        <?php endif; ?>

        <?php if (isset($_SESSION['info'])): ?>
            <div class="alert alert-info alert-dismissible fade show" role="alert">
                <i class="fas fa-info-circle me-2"></i>
                <?= htmlspecialchars($_SESSION['info']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['info']); ?>
        <?php endif; ?>
    </main>

    <!-- JavaScript Files -->
    <script src="<?= BASE_URL ?>includes/js/bootstrap.bundle.min.js"></script>
    <script src="<?= BASE_URL ?>includes/js/dashboard.js"></script>
    <script src="<?= BASE_URL ?>includes/js/custom.js"></script>

    <script>
        // إعدادات محسنة للأداء
        document.addEventListener('DOMContentLoaded', function() {
            // تحسين الأداء مع Intersection Observer
            const observerOptions = {
                threshold: 0.1,
                rootMargin: '0px 0px -50px 0px'
            };

            const observer = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        entry.target.style.opacity = '1';
                        entry.target.style.transform = 'translateY(0)';
                    }
                });
            }, observerOptions);

            // مراقبة العناصر المتحركة
            document.querySelectorAll('.animated-element').forEach(el => {
                el.style.opacity = '0';
                el.style.transform = 'translateY(20px)';
                el.style.transition = 'all 0.6s ease';
                observer.observe(el);
            });

            // تحسين شريط التنقل
            initEnhancedNavbar();
            
            // تحسين القوائم المنسدلة
            initEnhancedDropdowns();
            
            // تحسين النماذج
            initEnhancedForms();
            
            // تحسين التنبيهات
            initEnhancedAlerts();
            
            // تحسين الجداول
            initEnhancedTables();
            
            // تحسين الأزرار
            initEnhancedButtons();
        });

        // تحسين شريط التنقل
        function initEnhancedNavbar() {
            const navbar = document.getElementById('mainNavbar');
            let lastScrollTop = 0;

            window.addEventListener('scroll', function() {
                const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
                
                // إضافة تأثير الظل عند التمرير
                if (scrollTop > 50) {
                    navbar.classList.add('scrolled');
                } else {
                    navbar.classList.remove('scrolled');
                }

                // إخفاء/إظهار الشريط عند التمرير (اختياري)
                if (scrollTop > lastScrollTop && scrollTop > 100) {
                    navbar.style.transform = 'translateY(-100%)';
                } else {
                    navbar.style.transform = 'translateY(0)';
                }
                
                lastScrollTop = scrollTop;
            });

            // تحديد الرابط النشط
            const currentPath = window.location.pathname;
            document.querySelectorAll('.nav-link').forEach(link => {
                if (link.getAttribute('href') && currentPath.includes(link.getAttribute('href'))) {
                    link.classList.add('active');
                }
            });
        }

        // تحسين القوائم المنسدلة
        function initEnhancedDropdowns() {
            document.querySelectorAll('.dropdown').forEach(dropdown => {
                const toggle = dropdown.querySelector('.dropdown-toggle');
                const menu = dropdown.querySelector('.dropdown-menu');
                
                if (toggle && menu) {
                    // تحسين الوضع للغة العربية
                    menu.style.right = '0';
                    menu.style.left = 'auto';
                    
                    // تحسين التفاعل
                    let hoverTimeout;
                    
                    if (window.innerWidth > 768) {
                        dropdown.addEventListener('mouseenter', function() {
                            clearTimeout(hoverTimeout);
                            menu.classList.add('show');
                            toggle.setAttribute('aria-expanded', 'true');
                        });
                        
                        dropdown.addEventListener('mouseleave', function() {
                            hoverTimeout = setTimeout(() => {
                                menu.classList.remove('show');
                                toggle.setAttribute('aria-expanded', 'false');
                            }, 150);
                        });
                    }
                    
                    // تحسين النقر
                    toggle.addEventListener('click', function(e) {
                        e.preventDefault();
                        e.stopPropagation();
                        
                        const isShown = menu.classList.contains('show');
                        closeAllDropdowns();
                        
                        if (!isShown) {
                            menu.classList.add('show');
                            toggle.setAttribute('aria-expanded', 'true');
                        }
                    });
                }
            });
            
            // إغلاق القوائم عند النقر خارجها
            document.addEventListener('click', function(e) {
                if (!e.target.closest('.dropdown')) {
                    closeAllDropdowns();
                }
            });
            
            // إغلاق القوائم بمفتاح Escape
            document.addEventListener('keydown', function(e) {
                if (e.key === 'Escape') {
                    closeAllDropdowns();
                }
            });
        }

        function closeAllDropdowns() {
            document.querySelectorAll('.dropdown-menu.show').forEach(menu => {
                menu.classList.remove('show');
                const toggle = menu.parentElement.querySelector('.dropdown-toggle');
                if (toggle) toggle.setAttribute('aria-expanded', 'false');
            });
        }

        // تحسين النماذج
        function initEnhancedForms() {
            // إضافة تأثيرات للحقول
            document.querySelectorAll('.form-control, .form-select').forEach(field => {
                field.addEventListener('focus', function() {
                    this.parentElement.classList.add('focused');
                });
                
                field.addEventListener('blur', function() {
                    this.parentElement.classList.remove('focused');
                });
                
                // تحسين التحقق من الصحة
                field.addEventListener('input', function() {
                    validateField(this);
                });
            });
        }

        function validateField(field) {
            const isValid = field.checkValidity();
            field.classList.toggle('is-valid', isValid);
            field.classList.toggle('is-invalid', !isValid);
        }

        // تحسين التنبيهات
        function initEnhancedAlerts() {
            document.querySelectorAll('.alert').forEach(alert => {
                // إضافة تأثير الظهور
                alert.style.animation = 'alertSlideIn 0.5s ease';
                
                // إغلاق تلقائي
                setTimeout(() => {
                    if (alert.classList.contains('alert-dismissible')) {
                        const closeBtn = alert.querySelector('.btn-close');
                        if (closeBtn) {
                            closeBtn.click();
                        }
                    }
                }, 7000);
            });
        }

        // تحسين الجداول
        function initEnhancedTables() {
            document.querySelectorAll('.table').forEach(table => {
                // إضافة تأثيرات للصفوف
                table.querySelectorAll('tbody tr').forEach(row => {
                    row.addEventListener('mouseenter', function() {
                        this.style.backgroundColor = 'rgba(102, 126, 234, 0.1)';
                    });
                    
                    row.addEventListener('mouseleave', function() {
                        this.style.backgroundColor = '';
                    });
                });
                
                // تحسين التمرير الأفقي
                if (table.scrollWidth > table.clientWidth) {
                    table.style.overflowX = 'auto';
                }
            });
        }

        // تحسين الأزرار
        function initEnhancedButtons() {
            document.querySelectorAll('.btn').forEach(button => {
                button.addEventListener('click', function(e) {
                    // إضافة تأثير الضغط
                    const ripple = document.createElement('span');
                    ripple.classList.add('ripple');
                    
                    const rect = this.getBoundingClientRect();
                    const size = Math.max(rect.width, rect.height);
                    const x = e.clientX - rect.left - size / 2;
                    const y = e.clientY - rect.top - size / 2;
                    
                    ripple.style.cssText = `
                        position: absolute;
                        border-radius: 50%;
                        background: rgba(255, 255, 255, 0.6);
                        transform: scale(0);
                        animation: ripple 0.6s linear;
                        left: ${x}px;
                        top: ${y}px;
                        width: ${size}px;
                        height: ${size}px;
                    `;
                    
                    this.appendChild(ripple);
                    
                    setTimeout(() => {
                        ripple.remove();
                    }, 600);
                });
            });
        }

        // دوال مساعدة محسنة
        function showLoading() {
            const overlay = document.getElementById('loadingOverlay');
            overlay.style.display = 'flex';
            overlay.style.animation = 'fadeIn 0.3s ease';
        }

        function hideLoading() {
            const overlay = document.getElementById('loadingOverlay');
            overlay.style.animation = 'fadeOut 0.3s ease';
            setTimeout(() => {
                overlay.style.display = 'none';
            }, 300);
        }

        function showNotification(message, type = 'info', duration = 5000) {
            const notification = document.createElement('div');
            notification.className = `alert alert-${type} position-fixed`;
            notification.style.cssText = `
                top: 100px;
                right: 20px;
                z-index: 1055;
                max-width: 300px;
                border-radius: 10px;
                box-shadow: 0 4px 15px rgba(0,0,0,0.2);
                animation: slideInRight 0.3s ease;
            `;
            
            notification.innerHTML = `
                <div class="d-flex align-items-center">
                    <i class="fas fa-${type === 'success' ? 'check-circle' : type === 'error' ? 'exclamation-circle' : 'info-circle'} me-2"></i>
                    <div>${message}</div>
                </div>
            `;
            
            document.body.appendChild(notification);
            
            setTimeout(() => {
                notification.style.animation = 'slideOutRight 0.3s ease';
                setTimeout(() => {
                    notification.remove();
                }, 300);
            }, duration);
        }

        // تحسين PWA
        if ('serviceWorker' in navigator) {
            window.addEventListener('load', function() {
                navigator.serviceWorker.register('<?= BASE_URL ?>sw.js')
                    .then(function(registration) {
                        console.log('SW registered: ', registration);
                        addInstallButton();
                    })
                    .catch(function(registrationError) {
                        console.log('SW registration failed: ', registrationError);
                    });
            });
        }

        // إضافة أنيميشن CSS
        const style = document.createElement('style');
        style.textContent = `
            @keyframes ripple {
                to {
                    transform: scale(4);
                    opacity: 0;
                }
            }
            
            @keyframes fadeIn {
                from { opacity: 0; }
                to { opacity: 1; }
            }
            
            @keyframes fadeOut {
                from { opacity: 1; }
                to { opacity: 0; }
            }
            
            @keyframes slideInRight {
                from {
                    transform: translateX(100%);
                    opacity: 0;
                }
                to {
                    transform: translateX(0);
                    opacity: 1;
                }
            }
            
            @keyframes slideOutRight {
                from {
                    transform: translateX(0);
                    opacity: 1;
                }
                to {
                    transform: translateX(100%);
                    opacity: 0;
                }
            }
        `;
        document.head.appendChild(style);

        // تحسين الأداء
        function optimizePerformance() {
            // Preload important resources
            const preloadLinks = [
                '<?= BASE_URL ?>includes/css/bootstrap.min.css',
                '<?= BASE_URL ?>includes/js/bootstrap.bundle.min.js'
            ];
            
            preloadLinks.forEach(href => {
                const link = document.createElement('link');
                link.rel = 'preload';
                link.href = href;
                link.as = href.endsWith('.css') ? 'style' : 'script';
                document.head.appendChild(link);
            });
            
            // Lazy load images
            if ('IntersectionObserver' in window) {
                const imageObserver = new IntersectionObserver((entries) => {
                    entries.forEach(entry => {
                        if (entry.isIntersecting) {
                            const img = entry.target;
                            img.src = img.dataset.src;
                            img.classList.remove('lazy');
                            imageObserver.unobserve(img);
                        }
                    });
                });
                
                document.querySelectorAll('img[data-src]').forEach(img => {
                    imageObserver.observe(img);
                });
            }
        }

        // تشغيل تحسين الأداء
        optimizePerformance();
    </script>
</body>
</html>