<?php
require_once __DIR__ . '/config.php';
/**
 * ملف قالب القائمة الجانبية
 * يعرض القائمة الجانبية
 */
?>

<div class="sidebar">
    <div class="sidebar-header">
        <div class="logo">
            <i class="fas fa-hotel"></i>
            <h3>فندق مارينا بلازا</h3>
        </div>
        <div class="user-info">
            <div class="user-avatar">
                <i class="fas fa-user"></i>
            </div>
            <div class="user-details">
                <div class="user-name"><?= isset($_SESSION['full_name']) ? htmlspecialchars($_SESSION['full_name']) : ''; ?></div>
                <div class="user-role"><?= $_SESSION['user_type'] === 'admin' ? 'مدير النظام' : 'موظف'; ?></div>
            </div>
        </div>
    </div>
    
    <div class="sidebar-menu">
        <ul>
            <li>
                <a href="<?= BASE_URL ?>admin/dashboard.php" class="<?= basename($_SERVER['PHP_SELF']) === 'dashboard.php' ? 'active' : ''; ?>">
                    <i class="fas fa-tachometer-alt"></i>
                    <span>لوحة التحكم</span>
                </a>
            </li>
            
            <li>
                <a href="<?= BASE_URL ?>admin/rooms/list.php" class="<?= strpos($_SERVER['PHP_SELF'], '/rooms/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-bed"></i>
                    <span>إدارة الغرف</span>
                </a>
            </li>
            
            <li>
                <a href="<?= BASE_URL ?>admin/bookings/list.php" class="<?= strpos($_SERVER['PHP_SELF'], '/bookings/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-calendar-check"></i>
                    <span>إدارة الحجوزات</span>
                </a>
            </li>
            
            <li>
                <a href="<?= BASE_URL ?>admin/payments/list.php" class="<?= strpos($_SERVER['PHP_SELF'], '/payments/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-money-bill-wave"></i>
                    <span>المدفوعات</span>
                </a>
            </li>
            
            <li>
                <a href="<?= BASE_URL ?>admin/expenses/list.php" class="<?= strpos($_SERVER['PHP_SELF'], '/expenses/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-file-invoice-dollar"></i>
                    <span>المصروفات</span>
                </a>
            </li>
            
            <li>
                <a href="<?= BASE_URL ?>admin/finance/cash_register.php" class="<?= strpos($_SERVER['PHP_SELF'], '/finance/cash_register.php') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-cash-register"></i>
                    <span>الصندوق</span>
                </a>
            </li>
            
            <li>
                <a href="<?= BASE_URL ?>admin/reports/index.php" class="<?= strpos($_SERVER['PHP_SELF'], '/reports/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-chart-bar"></i>
                    <span>التقارير</span>
                </a>
            </li>
            
            <li class="menu-dropdown">
                <a href="#" class="<?= strpos($_SERVER['PHP_SELF'], '/settings/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-cog"></i>
                    <span>الإعدادات</span>
                    <i class="fas fa-chevron-down dropdown-icon"></i>
                </a>
                <ul class="submenu">
                    <li>
                        <a href="<?= BASE_URL ?>admin/settings/users.php" class="<?= basename($_SERVER['PHP_SELF']) === 'users.php' ? 'active' : ''; ?>">
                            <i class="fas fa-users"></i>
                            <span>المستخدمين والصلاحيات</span>
                        </a>
                    <li>
                        <a href="<?= BASE_URL ?>admin/settings/hotel.php" class="<?= basename($_SERVER['PHP_SELF']) === 'hotel.php' ? 'active' : ''; ?>">
                            <i class="fas fa-hotel"></i>
                            <span>إعدادات الفندق</span>
                        </a>
                    </li>
                    <li>
                        <a href="<?= BASE_URL ?>admin/settings/system.php" class="<?= basename($_SERVER['PHP_SELF']) === 'system.php' ? 'active' : ''; ?>">
                            <i class="fas fa-wrench"></i>
                            <span>إعدادات النظام</span>
                        </a>
                    </li>
                </ul>
            </li>/ul>
    </div>
    
    <div class="sidebar-footer">
        <a href="<?= BASE_URL ?>logout.php">
            <i class="fas fa-sign-out-alt"></i>
            <span>تسجيل الخروج</span>
        </a>
    </div>
</div>

<script>
    // تفعيل القوائم المنسدلة
    document.addEventListener('DOMContentLoaded', function() {
        const dropdowns = document.querySelectorAll('.menu-dropdown > a');
        
        dropdowns.forEach(dropdown => {
            dropdown.addEventListener('click', function(e) {
                e.preventDefault();
                this.parentElement.classList.toggle('open');
                
                const submenu = this.nextElementSibling;
                if (submenu.style.maxHeight) {
                    submenu.style.maxHeight = null;
                } else {
                    submenu.style.maxHeight = submenu.scrollHeight + "px";
                }
            });
        });
        
        // فتح القائمة المنسدلة النشطة تلقائياً
        const activeDropdown = document.querySelector('.menu-dropdown > a.active');
        if (activeDropdown) {
            activeDropdown.click();
        }
    });
</script>
