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

// حساب عمق المجلد الحالي
$current_dir = dirname($_SERVER['SCRIPT_NAME']);
$depth = substr_count($current_dir, '/') - 1;
$base_path = str_repeat('../', max(0, $depth));
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
    <link rel="stylesheet" href="<?= $base_path ?>includes/css/fontawesome.min.css">
    <!-- Bootstrap CSS -->
    <link rel="stylesheet" href="<?= $base_path ?>includes/css/bootstrap.min.css">
    <!-- Tajawal Font -->
    <link rel="stylesheet" href="<?= $base_path ?>includes/css/tajawal-font.css">
    
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Tajawal', sans-serif;
        }

        body {
            background: #f5f7fa;
            color: #333;
            line-height: 1.6;
            padding-top: 70px;
            direction: rtl;
        }

        /* CodePen Style Navigation */
        .codepen-nav {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            z-index: 1000;
            backdrop-filter: blur(10px);
        }

        .nav-container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 1rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
            height: 70px;
        }

        .nav-logo {
            font-size: 1.5rem;
            font-weight: bold;
            color: white;
            text-decoration: none;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            transition: all 0.3s ease;
        }

        .nav-logo:hover {
            color: #f0f0f0;
            transform: scale(1.05);
        }

        .main-nav {
            display: flex;
            list-style: none;
            align-items: center;
            gap: 0.5rem;
        }

        .nav-item {
            position: relative;
        }

        .nav-link {
            color: white;
            text-decoration: none;
            padding: 0.75rem 1rem;
            border-radius: 8px;
            transition: all 0.3s ease;
            display: flex;
            align-items: center;
            gap: 0.5rem;
            font-weight: 500;
            white-space: nowrap;
        }

        .nav-link:hover {
            background: rgba(255, 255, 255, 0.1);
            color: white;
            transform: translateY(-2px);
        }

        .sub-nav {
            position: absolute;
            top: 100%;
            right: 0;
            background: white;
            min-width: 200px;
            border-radius: 10px;
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15);
            opacity: 0;
            visibility: hidden;
            transform: translateY(-10px);
            transition: all 0.3s ease;
            list-style: none;
            padding: 0.5rem 0;
            z-index: 1001;
        }

        .nav-item:hover .sub-nav {
            opacity: 1;
            visibility: visible;
            transform: translateY(0);
        }

        .sub-nav-item {
            margin: 0;
        }

        .sub-nav-link {
            color: #333;
            text-decoration: none;
            padding: 0.75rem 1.25rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
            transition: all 0.3s ease;
            border-radius: 0;
        }

        .sub-nav-link:hover {
            background: rgba(102, 126, 234, 0.1);
            color: #667eea;
            transform: translateX(5px);
        }

        .user-menu {
            margin-right: 1rem;
        }

        .user-toggle {
            background: rgba(255, 255, 255, 0.1);
            border: 1px solid rgba(255, 255, 255, 0.2);
            border-radius: 25px;
            padding: 0.5rem 1rem;
            cursor: pointer;
            color: white;
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .user-dropdown {
            position: absolute;
            top: 100%;
            left: 0;
            background: white;
            min-width: 180px;
            border-radius: 10px;
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15);
            opacity: 0;
            visibility: hidden;
            transform: translateY(-10px);
            transition: all 0.3s ease;
            padding: 0.5rem 0;
            z-index: 1001;
        }

        .user-menu:hover .user-dropdown {
            opacity: 1;
            visibility: visible;
            transform: translateY(0);
        }

        .user-dropdown-item {
            color: #333;
            text-decoration: none;
            padding: 0.75rem 1.25rem;
            display: flex;
            align-items: center;
            gap: 0.75rem;
            transition: all 0.3s ease;
        }

        .user-dropdown-item:hover {
            background: rgba(102, 126, 234, 0.1);
            color: #667eea;
        }

        .mobile-toggle {
            display: none;
            background: none;
            border: none;
            color: white;
            font-size: 1.5rem;
            cursor: pointer;
            padding: 0.5rem;
            border-radius: 5px;
            transition: all 0.3s ease;
        }

        .mobile-toggle:hover {
            background: rgba(255, 255, 255, 0.1);
        }

        /* Dropdown indicators */
        .nav-item.dropdown > .nav-link:after {
            content: none; /* Remove default Bootstrap caret */
        }

        .nav-item.dropdown > .nav-link .fa-chevron-down {
            transition: transform 0.3s ease;
            margin-right: 5px;
            font-size: 0.8rem;
        }

        .nav-item.dropdown.show > .nav-link .fa-chevron-down {
            transform: rotate(180deg);
        }

        /* Content Wrapper */
        .content-wrapper {
            margin-top: 70px;
            min-height: calc(100vh - 70px);
        }

        .main-content {
            padding: 2rem;
            max-width: 1200px;
            margin: 0 auto;
        }

        /* Alerts */
        .alert {
            border-radius: 8px;
            padding: 1rem;
            margin-bottom: 1rem;
        }

        .alert-success {
            background-color: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }

        .alert-danger {
            background-color: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }

        .alert-warning {
            background-color: #fff3cd;
            color: #856404;
            border: 1px solid #ffeeba;
        }

        .alert-info {
            background-color: #d1ecf1;
            color: #0c5460;
            border: 1px solid #bee5eb;
        }

        /* Mobile Responsive */
        @media (max-width: 768px) {
            .main-nav {
                position: fixed;
                top: 70px;
                right: -100%;
                width: 280px;
                height: calc(100vh - 70px);
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                flex-direction: column;
                align-items: stretch;
                padding: 1rem;
                transition: right 0.3s ease;
                overflow-y: auto;
            }

            .main-nav.active {
                right: 0;
            }

            .nav-item {
                margin-bottom: 0.5rem;
            }

            .nav-link {
                justify-content: space-between;
                padding: 1rem;
                border-radius: 10px;
            }

            .sub-nav {
                position: static;
                opacity: 1;
                visibility: visible;
                transform: none;
                background: rgba(255, 255, 255, 0.1);
                margin-top: 0.5rem;
                border-radius: 8px;
                display: none;
            }

            .nav-item.dropdown > .nav-link:after {
                content: none;
            }
            
            .nav-item.dropdown > .nav-link .fa-chevron-down {
                margin-right: auto;
                margin-left: 5px;
            }

            .nav-item:hover .sub-nav {
                display: block;
            }

            .sub-nav-link {
                color: white;
                padding: 0.75rem 1rem;
            }

            .sub-nav-link:hover {
                background: rgba(255, 255, 255, 0.1);
                color: white;
            }

            .mobile-toggle {
                display: block;
            }

            .user-menu {
                margin-right: 0;
                margin-top: 1rem;
            }

            .user-dropdown {
                position: static;
                opacity: 1;
                visibility: visible;
                transform: none;
                background: rgba(255, 255, 255, 0.1);
                margin-top: 0.5rem;
                display: none;
            }

            .user-menu:hover .user-dropdown {
                display: block;
            }

            .user-dropdown-item {
                color: white;
            }

            .user-dropdown-item:hover {
                background: rgba(255, 255, 255, 0.1);
                color: white;
            }
        }

        /* Animation */
        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .fade-in {
            animation: fadeIn 0.6s ease-out;
        }
    </style>
</head>
<body>
    <!-- CodePen Style Navigation -->
    <nav class="codepen-nav">
        <div class="nav-container">
            <a href="<?= $base_path ?>" class="nav-logo">
                <i class="fas fa-hotel"></i>
                فندق مارينا
            </a>

            <ul class="main-nav" id="mainNav">
                <li class="nav-item">
                    <a href="<?= $base_path ?>dash.php" class="nav-link">
                        <i class="fas fa-tachometer-alt"></i>
                        الرئيسية
                    </a>
                </li>

                <li class="nav-item dropdown">
                    <a href="<?= $base_path ?>rooms/list.php" class="nav-link">
                        <i class="fas fa-bed"></i>
                        الغرف
                        <i class="fas fa-chevron-down"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>rooms/list.php" class="sub-nav-link">
                                <i class="fas fa-list"></i>
                                قائمة الغرف
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>rooms/add.php" class="sub-nav-link">
                                <i class="fas fa-plus"></i>
                                إضافة غرفة
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>settings/rooms_status.php" class="sub-nav-link">
                                <i class="fas fa-chart-bar"></i>
                                حالة الغرف
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item dropdown">
                    <a href="<?= $base_path ?>bookings/list.php" class="nav-link">
                        <i class="fas fa-calendar-alt"></i>
                        الحجوزات
                        <i class="fas fa-chevron-down"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>bookings/list.php" class="sub-nav-link">
                                <i class="fas fa-list"></i>
                                قائمة الحجوزات
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>bookings/add_booking.php" class="sub-nav-link">
                                <i class="fas fa-plus"></i>
                                حجز جديد
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>bookings/checkout.php" class="sub-nav-link">
                                <i class="fas fa-sign-out-alt"></i>
                                تسجيل الخروج
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item dropdown">
                    <a href="<?= $base_path ?>reports/revenue.php" class="nav-link">
                        <i class="fas fa-chart-line"></i>
                        التقارير
                        <i class="fas fa-chevron-down"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>reports/revenue.php" class="sub-nav-link">
                                <i class="fas fa-dollar-sign"></i>
                                تقرير الإيرادات
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>reports/occupancy.php" class="sub-nav-link">
                                <i class="fas fa-chart-pie"></i>
                                تقرير الإشغال
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>reports/comprehensive_reports.php" class="sub-nav-link">
                                <i class="fas fa-file-alt"></i>
                                التقارير الشاملة
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>reports/employee_withdrawals_report.php" class="sub-nav-link">
                                <i class="fas fa-users"></i>
                                تقرير سحوبات الموظفين
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item dropdown">
                    <a href="<?= $base_path ?>employees/list.php" class="nav-link">
                        <i class="fas fa-users"></i>
                        الموظفين
                        <i class="fas fa-chevron-down"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>employees/list.php" class="sub-nav-link">
                                <i class="fas fa-list"></i>
                                قائمة الموظفين
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>employees/add_employee.php" class="sub-nav-link">
                                <i class="fas fa-user-plus"></i>
                                إضافة موظف
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>employees/salary_withdrawals.php" class="sub-nav-link">
                                <i class="fas fa-money-bill-wave"></i>
                                سحوبات الرواتب
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item dropdown">
                    <a href="<?= $base_path ?>finance/cash_register.php" class="nav-link">
                        <i class="fas fa-wallet"></i>
                        المالية
                        <i class="fas fa-chevron-down"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>finance/cash_register.php" class="sub-nav-link">
                                <i class="fas fa-cash-register"></i>
                                الصندوق
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>finance/cash_reports.php" class="sub-nav-link">
                                <i class="fas fa-file-invoice-dollar"></i>
                                تقارير الصندوق
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>expenses/list.php" class="sub-nav-link">
                                <i class="fas fa-receipt"></i>
                                المصروفات
                            </a>
                        </li>
                    </ul>
                </li>

                <li class="nav-item dropdown">
                    <a href="<?= $base_path ?>settings/users.php" class="nav-link">
                        <i class="fas fa-cogs"></i>
                        الإعدادات
                        <i class="fas fa-chevron-down"></i>
                    </a>
                    <ul class="sub-nav">
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>settings/users.php" class="sub-nav-link">
                                <i class="fas fa-user"></i>
                                المستخدمين
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>settings/add_user.php" class="sub-nav-link">
                                <i class="fas fa-user-plus"></i>
                                إضافة مستخدم
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>settings/guests.php" class="sub-nav-link">
                                <i class="fas fa-user-friends"></i>
                                النزلاء
                            </a>
                        </li>
                        <li class="sub-nav-item">
                            <a href="<?= $base_path ?>system_tools/backup_manager.php" class="sub-nav-link">
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
                        <a href="<?= $base_path ?>settings/users.php" class="user-dropdown-item">
                            <i class="fas fa-user-edit"></i>
                            الملف الشخصي
                        </a>
                        <a href="<?= $base_path ?>logout.php" class="user-dropdown-item">
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
            <!-- عرض الرسائل -->
            <?php if (isset($_SESSION['success'])): ?>
                <div class="alert alert-success">
                    <i class="fas fa-check-circle me-2"></i>
                    <?= htmlspecialchars($_SESSION['success']) ?>
                </div>
                <?php unset($_SESSION['success']); ?>
            <?php endif; ?>

            <?php if (isset($_SESSION['error'])): ?>
                <div class="alert alert-danger">
                    <i class="fas fa-exclamation-circle me-2"></i>
                    <?= htmlspecialchars($_SESSION['error']) ?>
                </div>
                <?php unset($_SESSION['error']); ?>
            <?php endif; ?>

            <?php if (isset($_SESSION['warning'])): ?>
                <div class="alert alert-warning">
                    <i class="fas fa-exclamation-triangle me-2"></i>
                    <?= htmlspecialchars($_SESSION['warning']) ?>
                </div>
                <?php unset($_SESSION['warning']); ?>
            <?php endif; ?>

            <?php if (isset($_SESSION['info'])): ?>
                <div class="alert alert-info">
                    <i class="fas fa-info-circle me-2"></i>
                    <?= htmlspecialchars($_SESSION['info']) ?>
                </div>
                <?php unset($_SESSION['info']); ?>
            <?php endif; ?>

    <script src="<?= $base_path ?>includes/js/bootstrap.bundle.min.js"></script>
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
        document.addEventListener('click', function(e) {
            const nav = document.getElementById('mainNav');
            const toggle = document.getElementById('mobileToggle');
            
            if (!nav.contains(e.target) && !toggle.contains(e.target)) {
                nav.classList.remove('active');
                const icon = toggle.querySelector('i');
                icon.classList.remove('fa-times');
                icon.classList.add('fa-bars');
            }
        });

        // Handle dropdown menus - prevent parent link navigation
        document.querySelectorAll('.nav-item.dropdown > .nav-link').forEach(link => {
            link.addEventListener('click', function(e) {
                // On mobile, always allow click to open dropdown
                if (window.innerWidth <= 768) {
                    return;
                }
                
                // Check if click was on the chevron icon
                const chevron = this.querySelector('.fa-chevron-down');
                const clickedChevron = chevron && chevron.contains(e.target);
                
                // If not chevron and dropdown is closed, prevent default
                if (!clickedChevron && !this.parentElement.classList.contains('show')) {
                    e.preventDefault();
                    e.stopPropagation();
                }
            });
        });

        // Highlight active page
        document.addEventListener('DOMContentLoaded', function() {
            const currentPath = window.location.pathname;
            const navLinks = document.querySelectorAll('.nav-link, .sub-nav-link');
            
            navLinks.forEach(link => {
                if (link.getAttribute('href') && currentPath.includes(link.getAttribute('href'))) {
                    link.classList.add('active');
                    
                    // Also activate parent dropdown if this is a sub-item
                    if (link.classList.contains('sub-nav-link')) {
                        const parentItem = link.closest('.nav-item');
                        if (parentItem) {
                            parentItem.querySelector('.nav-link').classList.add('active');
                        }
                    }
                }
            });
            
            // Initialize Bootstrap dropdowns
            const dropdowns = document.querySelectorAll('.dropdown');
            dropdowns.forEach(dropdown => {
                dropdown.addEventListener('hide.bs.dropdown', function() {
                    this.querySelector('.nav-link').classList.remove('active');
                });
                
                dropdown.addEventListener('show.bs.dropdown', function() {
                    this.querySelector('.nav-link').classList.add('active');
                });
            });
        });
    </script>
</body>
</html>