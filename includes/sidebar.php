<?php
/**
 * ملف قالب القائمة الجانبية
 * يعرض القائمة الجانبية
 * ملاحظة: هذا الملف اختياري - النظام يستخدم شريط التنقل العلوي من header.php
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
                <div class="user-name"><?= htmlspecialchars($_SESSION['full_name'] ?? 'مستخدم'); ?></div>
                <div class="user-role"><?= ($_SESSION['user_type'] ?? '') === 'admin' ? 'مدير النظام' : 'موظف'; ?></div>
            </div>
        </div>
    </div>
    
    <div class="sidebar-menu">
        <ul>
            <li>
                <a href="/admin/dashboard.php" class="<?= basename($_SERVER['PHP_SELF']) === 'dashboard.php' ? 'active' : ''; ?>">
                    <i class="fas fa-tachometer-alt"></i>
                    <span>لوحة التحكم</span>
                </a>
            </li>
            
            <li>
                <a href="/admin/rooms/list.php" class="<?= strpos($_SERVER['PHP_SELF'], '/rooms/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-bed"></i>
                    <span>إدارة الغرف</span>
                </a>
            </li>
            
            <li>
                <a href="/admin/bookings/list.php" class="<?= strpos($_SERVER['PHP_SELF'], '/bookings/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-calendar-check"></i>
                    <span>إدارة الحجوزات</span>
                </a>
            </li>
            
            <li>
                <a href="/admin/finance/cash_register.php" class="<?= strpos($_SERVER['PHP_SELF'], '/finance/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-money-bill-wave"></i>
                    <span>المدفوعات والصندوق</span>
                </a>
            </li>
            
            <li>
                <a href="/admin/expenses/list.php" class="<?= strpos($_SERVER['PHP_SELF'], '/expenses/') !== false ? 'active' : ''; ?>">
                    <i class="fas fa-file-invoice-dollar"></i>
                    <span>المصروفات</span>
                </a>
            </li>
            
            <li>
                <a href="/admin/reports/revenue.php" class="<?= strpos($_SERVER['PHP_SELF'], '/reports/') !== false ? 'active' : ''; ?>">
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
                        <a href="/admin/settings/users.php" class="<?= basename($_SERVER['PHP_SELF']) === 'users.php' ? 'active' : ''; ?>">
                            <i class="fas fa-users"></i>
                            <span>المستخدمين والصلاحيات</span>
                        </a>
                    </li>
                    <li>
                        <a href="/admin/settings/employees.php" class="<?= basename($_SERVER['PHP_SELF']) === 'employees.php' ? 'active' : ''; ?>">
                            <i class="fas fa-user-tie"></i>
                            <span>إدارة الموظفين</span>
                        </a>
                    </li>
                    <li>
                        <a href="/admin/settings/guests.php" class="<?= basename($_SERVER['PHP_SELF']) === 'guests.php' ? 'active' : ''; ?>">
                            <i class="fas fa-user-friends"></i>
                            <span>إدارة النزلاء</span>
                        </a>
                    </li>
                    <li>
                        <a href="/admin/settings/maintenance.php" class="<?= basename($_SERVER['PHP_SELF']) === 'maintenance.php' ? 'active' : ''; ?>">
                            <i class="fas fa-wrench"></i>
                            <span>صيانة النظام</span>
                        </a>
                    </li>
                    <li>
                        <a href="/admin/system_tools/backup_manager.php" class="<?= basename($_SERVER['PHP_SELF']) === 'backup_manager.php' ? 'active' : ''; ?>">
                            <i class="fas fa-database"></i>
                            <span>النسخ الاحتياطي</span>
                        </a>
                    </li>
                </ul>
            </li>
        </ul>
    </div>
    
    <div class="sidebar-footer">
        <a href="/logout.php">
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
                if (submenu && submenu.style.maxHeight) {
                    submenu.style.maxHeight = null;
                } else if (submenu) {
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
