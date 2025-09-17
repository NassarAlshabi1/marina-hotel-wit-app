<?php
require_once 'auth.php';
require_once __DIR__ . '/config.php';

// تحديد المنطقة الزمنية لعدن (اليمن)
date_default_timezone_set('Asia/Aden');

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
    
    <!-- Font Awesome للأيقونات -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f7fa;
            color: #333;
            line-height: 1.6;
        }

        /* CodePen Style Navigation */
        .codepen-nav {
            background: #2c3e50;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            z-index: 1000;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            border-bottom: 3px solid #3498db;
        }

        .nav-container {
            max-width: 1200px;
            margin: 0 auto;
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 0 20px;
            height: 70px;
        }

        .nav-logo {
            display: flex;
            align-items: center;
            color: #fff;
            text-decoration: none;
            font-size: 1.5rem;
            font-weight: bold;
            transition: all 0.3s ease;
        }

        .nav-logo:hover {
            color: #3498db;
            transform: scale(1.05);
        }

        .nav-logo i {
            margin-left: 10px;
            font-size: 1.8rem;
        }

        /* Main Navigation */
        .main-nav {
            display: flex;
            list-style: none;
            align-items: center;
            gap: 0;
        }

        .nav-item {
            position: relative;
        }

        .nav-link {
            display: flex;
            align-items: center;
            padding: 25px 20px;
            color: #ecf0f1;
            text-decoration: none;
            transition: all 0.3s ease;
            font-weight: 500;
            border-bottom: 3px solid transparent;
        }

        .nav-link:hover,
        .nav-link.active {
            color: #3498db;
            background: rgba(52, 152, 219, 0.1);
            border-bottom-color: #3498db;
        }

        .nav-link i {
            margin-left: 8px;
            font-size: 1.1rem;
        }

        /* Sub Navigation Dropdown */
        .sub-nav {
            position: absolute;
            top: 100%;
            right: 0;
            background: #34495e;
            min-width: 250px;
            list-style: none;
            opacity: 0;
            visibility: hidden;
            transform: translateY(-10px);
            transition: all 0.3s ease;
            border-radius: 0 0 8px 8px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }

        .nav-item:hover .sub-nav {
            opacity: 1;
            visibility: visible;
            transform: translateY(0);
        }

        .sub-nav-item {
            border-bottom: 1px solid rgba(255,255,255,0.1);
        }

        .sub-nav-item:last-child {
            border-bottom: none;
        }

        .sub-nav-link {
            display: flex;
            align-items: center;
            padding: 15px 20px;
            color: #bdc3c7;
            text-decoration: none;
            transition: all 0.3s ease;
            font-size: 0.9rem;
        }

        .sub-nav-link:hover {
            color: #3498db;
            background: rgba(52, 152, 219, 0.1);
            padding-right: 30px;
        }

        .sub-nav-link i {
            margin-left: 10px;
            width: 16px;
            text-align: center;
        }

        /* User Menu */
        .user-menu {
            position: relative;
        }

        .user-toggle {
            display: flex;
            align-items: center;
            padding: 10px 15px;
            background: #3498db;
            color: white;
            border: none;
            border-radius: 25px;
            cursor: pointer;
            transition: all 0.3s ease;
            font-weight: 500;
        }

        .user-toggle:hover {
            background: #2980b9;
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.3);
        }

        .user-toggle i {
            margin-left: 8px;
        }

        .user-dropdown {
            position: absolute;
            top: 100%;
            left: 0;
            background: white;
            min-width: 200px;
            border-radius: 8px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            opacity: 0;
            visibility: hidden;
            transform: translateY(-10px);
            transition: all 0.3s ease;
            margin-top: 10px;
        }

        .user-menu:hover .user-dropdown {
            opacity: 1;
            visibility: visible;
            transform: translateY(0);
        }

        .user-dropdown-item {
            padding: 12px 20px;
            color: #333;
            text-decoration: none;
            display: flex;
            align-items: center;
            transition: all 0.3s ease;
            border-bottom: 1px solid #eee;
        }

        .user-dropdown-item:last-child {
            border-bottom: none;
        }

        .user-dropdown-item:hover {
            background: #f8f9fa;
            color: #3498db;
        }

        .user-dropdown-item i {
            margin-left: 10px;
            width: 16px;
            text-align: center;
        }

        /* Mobile Menu */
        .mobile-toggle {
            display: none;
            background: none;
            border: none;
            color: white;
            font-size: 1.5rem;
            cursor: pointer;
            padding: 10px;
        }

        /* Content Area */
        .content-wrapper {
            margin-top: 70px;
            min-height: calc(100vh - 70px);
        }

        .main-content {
            padding: 30px 20px;
            max-width: 1200px;
            margin: 0 auto;
        }

        /* Responsive Design */
        @media (max-width: 768px) {
            .nav-container {
                padding: 0 15px;
            }

            .main-nav {
                position: fixed;
                top: 70px;
                right: -100%;
                width: 100%;
                height: calc(100vh - 70px);
                background: #2c3e50;
                flex-direction: column;
                align-items: stretch;
                transition: all 0.3s ease;
                overflow-y: auto;
            }

            .main-nav.active {
                right: 0;
            }

            .nav-item {
                width: 100%;
            }

            .nav-link {
                padding: 20px;
                border-bottom: 1px solid rgba(255,255,255,0.1);
                border-left: none;
                justify-content: space-between;
            }

            .nav-link:hover {
                border-left: 4px solid #3498db;
            }

            .sub-nav {
                position: static;
                opacity: 1;
                visibility: visible;
                transform: none;
                background: #34495e;
                margin-top: 0;
                border-radius: 0;
                box-shadow: none;
                max-height: 0;
                overflow: hidden;
                transition: max-height 0.3s ease;
            }

            .nav-item:hover .sub-nav {
                max-height: 500px;
            }

            .mobile-toggle {
                display: block;
            }

            .user-menu {
                position: static;
                width: 100%;
                margin-top: 20px;
            }

            .user-toggle {
                width: 100%;
                justify-content: center;
                border-radius: 0;
            }

            .user-dropdown {
                position: static;
                opacity: 1;
                visibility: visible;
                transform: none;
                margin-top: 0;
                border-radius: 0;
                box-shadow: none;
                max-height: 0;
                overflow: hidden;
                transition: max-height 0.3s ease;
            }

            .user-menu:hover .user-dropdown {
                max-height: 200px;
            }
        }

        /* Animations */
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .fade-in {
            animation: fadeIn 0.6s ease-out;
        }

        /* Badge for notifications */
        .nav-badge {
            position: absolute;
            top: 5px;
            left: 5px;
            background: #e74c3c;
            color: white;
            border-radius: 50%;
            width: 20px;
            height: 20px;
            font-size: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            animation: pulse 2s infinite;
        }

        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.1); }
            100% { transform: scale(1); }
        }

        /* Utility Classes */
        .text-center { text-align: center; }
        .text-left { text-align: left; }
        .text-right { text-align: right; }
        .mb-0 { margin-bottom: 0; }
        .mb-3 { margin-bottom: 1rem; }
        .mt-3 { margin-top: 1rem; }
        .p-3 { padding: 1rem; }
        .bg-white { background: white; }
        .shadow { box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .rounded { border-radius: 8px; }
    </style>
</head>
<body>
    <!-- CodePen Style Navigation -->
    <nav class="codepen-nav">
        <div class="nav-container">
            <a href="<?= site_url() ?>" class="nav-logo">
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
                    <a href="<?= admin_url('rooms/list.php') ?>" class="nav-link">
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
                    <a href="<?= admin_url('bookings/list.php') ?>" class="nav-link">
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
                    <a href="<?= admin_url('reports/revenue.php') ?>" class="nav-link">
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
                    <a href="<?= admin_url('employees/salary_withdrawals.php') ?>" class="nav-link">
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
                    <a href="<?= admin_url('finance/cash_register.php') ?>" class="nav-link">
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
                    <a href="<?= admin_url('settings/users.php') ?>" class="nav-link">
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
                    <button class="user-toggle">
                        <i class="fas fa-user"></i>
                        <?= $_SESSION['username'] ?? 'مستخدم' ?>
                        <i class="fas fa-chevron-down" style="margin-right: 5px; font-size: 0.8rem;"></i>
                    </button>
                    <div class="user-dropdown">
                        <a href="<?= admin_url('settings/users.php') ?>" class="user-dropdown-item">
                            <i class="fas fa-user-edit"></i>
                            الملف الشخصي
                        </a>
                        <a href="<?= site_url('logout.php') ?>" class="user-dropdown-item">
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

    <script>
        // Mobile menu toggle
        document.getElementById('mobileToggle').addEventListener('click', function() {
            const nav = document.getElementById('mainNav');
            nav.classList.toggle('active');
            
            // Change icon
            const icon = this.querySelector('i');
            if (nav.classList.contains('active')) {
                icon.classList.remove('fa-bars');
                icon.classList.add('fa-times');
            } else {
                icon.classList.remove('fa-times');
                icon.classList.add('fa-bars');
            }
        });

        // Close mobile menu when clicking outside
        document.addEventListener('click', function(event) {
            const nav = document.getElementById('mainNav');
            const toggle = document.getElementById('mobileToggle');
            
            if (!nav.contains(event.target) && !toggle.contains(event.target)) {
                nav.classList.remove('active');
                toggle.querySelector('i').classList.remove('fa-times');
                toggle.querySelector('i').classList.add('fa-bars');
            }
        });

        // Highlight active page
        document.addEventListener('DOMContentLoaded', function() {
            const currentPath = window.location.pathname;
            const navLinks = document.querySelectorAll('.nav-link, .sub-nav-link');
            
            navLinks.forEach(link => {
                if (link.getAttribute('href') && currentPath.includes(link.getAttribute('href'))) {
                    link.classList.add('active');
                }
            });
        });
    </script>