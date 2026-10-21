<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// جلب إحصائيات سريعة
$stats = [];

// عدد الغرف
$rooms_count = $conn->query("SELECT COUNT(*) as count FROM rooms")->fetch_assoc()['count'];
$stats['rooms'] = $rooms_count;

// عدد الحجوزات النشطة
$active_bookings = $conn->query("SELECT COUNT(*) as count FROM bookings WHERE status = 'محجوزة'")->fetch_assoc()['count'];
$stats['active_bookings'] = $active_bookings;

// عدد المستخدمين
$users_count = $conn->query("SELECT COUNT(*) as count FROM users")->fetch_assoc()['count'];
$stats['users'] = $users_count;

// عدد الموظفين
$employees_count = $conn->query("SELECT COUNT(*) as count FROM employees")->fetch_assoc()['count'];
$stats['employees'] = $employees_count;

// تضمين الهيدر
include_once '../../includes/header.php';
?>

<style>
    /* تحسينات بطاقات الإعدادات السريعة */
    .quick-setting-card {
        transition: all 0.3s ease;
        cursor: pointer;
    }
    
    .quick-setting-card:hover {
        transform: translateY(-8px) scale(1.02);
        box-shadow: 0 10px 30px rgba(0, 0, 0, 0.15);
    }
    
    .quick-setting-card.border-primary:hover {
        box-shadow: 0 10px 30px rgba(102, 126, 234, 0.3);
    }
    
    .quick-setting-card.border-success:hover {
        box-shadow: 0 10px 30px rgba(86, 171, 47, 0.3);
    }
    
    .quick-setting-card.border-info:hover {
        box-shadow: 0 10px 30px rgba(79, 172, 254, 0.3);
    }
    
    .quick-setting-card.border-warning:hover {
        box-shadow: 0 10px 30px rgba(240, 147, 251, 0.3);
    }
    
    /* تحسين الأيقونات */
    .quick-setting-card .icon-wrapper {
        display: inline-block;
        transition: all 0.3s ease;
        width: 60px;
        height: 60px;
        display: flex;
        align-items: center;
        justify-content: center;
        border-radius: 50%;
        margin: 0 auto 1rem;
    }
    
    .quick-setting-card:hover .icon-wrapper {
        transform: scale(1.1) rotate(5deg);
    }
    
    /* تحسين الأزرار */
    .quick-setting-card .btn {
        transition: all 0.3s ease;
        font-weight: 600;
    }
    
    .quick-setting-card:hover .btn {
        transform: translateY(-2px);
        box-shadow: 0 5px 15px rgba(0, 0, 0, 0.2);
    }
    
    /* تحسين النصوص */
    .quick-setting-card .card-title {
        font-size: 1.1rem;
        margin-bottom: 0.75rem;
    }
    
    .quick-setting-card .card-text {
        font-size: 0.9rem;
        line-height: 1.4;
    }
    
    /* تحسين بطاقات الإحصائيات */
    .stat-icon {
        font-size: 3rem;
        opacity: 0.8;
    }
    
    .bg-primary, .bg-success, .bg-info, .bg-warning {
        position: relative;
        overflow: hidden;
    }
    
    .bg-primary::before,
    .bg-success::before,
    .bg-info::before,
    .bg-warning::before {
        content: '';
        position: absolute;
        top: 0;
        right: 0;
        bottom: 0;
        left: 0;
        background: linear-gradient(45deg, rgba(255,255,255,0.1) 0%, transparent 50%);
        pointer-events: none;
    }
    
    /* تحسين الأنيميشن للدخول */
    @keyframes slideInUp {
        from {
            opacity: 0;
            transform: translateY(30px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
    
    .fade-in-up {
        animation: slideInUp 0.6s ease-out;
    }
    
    /* تحسين الاستجابة */
    @media (max-width: 768px) {
        .quick-setting-card .icon-wrapper {
            width: 50px;
            height: 50px;
        }
        
        .quick-setting-card .card-title {
            font-size: 1rem;
        }
        
        .quick-setting-card .card-text {
            font-size: 0.85rem;
        }
    }
    
    /* تحسين التركيز */
    .quick-setting-card:focus,
    .quick-setting-card .btn:focus {
        outline: 3px solid rgba(102, 126, 234, 0.5);
        outline-offset: 2px;
    }
</style>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-cogs me-2"></i>الإعدادات الرئيسية</h2>
                <a href="../dash.php" class="btn btn-outline-primary">
                    <i class="fas fa-arrow-right me-1"></i> العودة للوحة التحكم
                </a>
            </div>
        </div>
    </div>

    <!-- إحصائيات سريعة محسنة -->
    <div class="row mb-4">
        <div class="col-md-3 mb-3">
            <div class="card bg-primary text-white h-100">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h3 class="mb-1"><?= $stats['rooms'] ?></h3>
                            <p class="mb-0 opacity-75">إجمالي الغرف</p>
                        </div>
                        <div class="text-center">
                            <i class="fas fa-bed stat-icon"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3 mb-3">
            <div class="card bg-success text-white h-100">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h3 class="mb-1"><?= $stats['active_bookings'] ?></h3>
                            <p class="mb-0 opacity-75">الحجوزات النشطة</p>
                        </div>
                        <div class="text-center">
                            <i class="fas fa-calendar-check stat-icon"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3 mb-3">
            <div class="card bg-info text-white h-100">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h3 class="mb-1"><?= $stats['users'] ?></h3>
                            <p class="mb-0 opacity-75">المستخدمين</p>
                        </div>
                        <div class="text-center">
                            <i class="fas fa-user stat-icon"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3 mb-3">
            <div class="card bg-warning text-white h-100">
                <div class="card-body">
                    <div class="d-flex justify-content-between align-items-center">
                        <div>
                            <h3 class="mb-1"><?= $stats['employees'] ?></h3>
                            <p class="mb-0 opacity-75">الموظفين</p>
                        </div>
                        <div class="text-center">
                            <i class="fas fa-user-tie stat-icon"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- قسم الإعدادات السريعة المحسن -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-dark text-white">
                    <h5 class="mb-0"><i class="fas fa-bolt me-2"></i>الإعدادات السريعة</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-lg-3 col-md-6 mb-3">
                            <div class="card h-100 border-primary quick-setting-card">
                                <div class="card-body text-center p-4">
                                    <div class="icon-wrapper bg-primary bg-opacity-10 text-primary">
                                        <i class="fas fa-bed fa-2x"></i>
                                    </div>
                                    <h6 class="card-title text-primary fw-bold">إدارة الغرف</h6>
                                    <p class="card-text text-muted small mb-3">إضافة وتعديل وحذف الغرف</p>
                                    <a href="../rooms/list.php" class="btn btn-primary btn-sm w-100">
                                        <i class="fas fa-arrow-left me-1"></i> دخول
                                    </a>
                                </div>
                            </div>
                        </div>
                        <div class="col-lg-3 col-md-6 mb-3">
                            <div class="card h-100 border-success quick-setting-card">
                                <div class="card-body text-center p-4">
                                    <div class="icon-wrapper bg-success bg-opacity-10 text-success">
                                        <i class="fas fa-users fa-2x"></i>
                                    </div>
                                    <h6 class="card-title text-success fw-bold">إدارة المستخدمين</h6>
                                    <p class="card-text text-muted small mb-3">إضافة وتعديل المستخدمين</p>
                                    <a href="users.php" class="btn btn-success btn-sm w-100">
                                        <i class="fas fa-arrow-left me-1"></i> دخول
                                    </a>
                                </div>
                            </div>
                        </div>
                        <div class="col-lg-3 col-md-6 mb-3">
                            <div class="card h-100 border-info quick-setting-card">
                                <div class="card-body text-center p-4">
                                    <div class="icon-wrapper bg-info bg-opacity-10 text-info">
                                        <i class="fas fa-user-tie fa-2x"></i>
                                    </div>
                                    <h6 class="card-title text-info fw-bold">إدارة الموظفين</h6>
                                    <p class="card-text text-muted small mb-3">إضافة وتعديل الموظفين</p>
                                    <a href="employees.php" class="btn btn-info btn-sm w-100">
                                        <i class="fas fa-arrow-left me-1"></i> دخول
                                    </a>
                                </div>
                            </div>
                        </div>
                        <div class="col-lg-3 col-md-6 mb-3">
                            <div class="card h-100 border-warning quick-setting-card">
                                <div class="card-body text-center p-4">
                                    <div class="icon-wrapper bg-warning bg-opacity-10 text-warning">
                                        <i class="fas fa-tools fa-2x"></i>
                                    </div>
                                    <h6 class="card-title text-warning fw-bold">جميع الإعدادات</h6>
                                    <p class="card-text text-muted small mb-3">الوصول لجميع الإعدادات</p>
                                    <a href="#detailed-settings" class="btn btn-warning btn-sm w-100">
                                        <i class="fas fa-chevron-down me-1"></i> عرض
                                    </a>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- قسم إدارة الغرف المحسن -->
    <div class="row mb-4 fade-in-up" id="detailed-settings">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0"><i class="fas fa-bed me-2"></i>إدارة الغرف</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="../rooms/list.php" class="btn btn-outline-primary btn-lg">
                                    <i class="fas fa-list me-2"></i>قائمة الغرف
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="../rooms/add.php" class="btn btn-success btn-lg">
                                    <i class="fas fa-plus me-2"></i>إضافة غرفة جديدة
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="rooms_status.php" class="btn btn-info btn-lg">
                                    <i class="fas fa-chart-bar me-2"></i>حالة الغرف
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- قسم إدارة المستخدمين المحسن -->
    <div class="row mb-4 fade-in-up">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-success text-white">
                    <h5 class="mb-0"><i class="fas fa-users me-2"></i>إدارة المستخدمين</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="users.php" class="btn btn-outline-success btn-lg">
                                    <i class="fas fa-user me-2"></i>قائمة المستخدمين
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="add_user.php" class="btn btn-success btn-lg">
                                    <i class="fas fa-user-plus me-2"></i>إضافة مستخدم جديد
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="users.php" class="btn btn-info btn-lg">
                                    <i class="fas fa-key me-2"></i>صلاحيات المستخدمين
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- قسم إدارة الموظفين -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0"><i class="fas fa-user-tie me-2"></i>إدارة الموظفين</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="employees.php" class="btn btn-outline-info btn-lg">
                                    <i class="fas fa-list me-2"></i>قائمة الموظفين
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="add_employee.php" class="btn btn-info btn-lg">
                                    <i class="fas fa-user-plus me-2"></i>إضافة موظف جديد
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="../employees/salary_withdrawals.php" class="btn btn-warning btn-lg">
                                    <i class="fas fa-money-bill-wave me-2"></i>سحوبات الرواتب
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- قسم إدارة النزلاء -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-warning text-white">
                    <h5 class="mb-0"><i class="fas fa-user-friends me-2"></i>إدارة النزلاء</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="guests.php" class="btn btn-outline-warning btn-lg">
                                    <i class="fas fa-list me-2"></i>قائمة النزلاء
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="guest_history.php" class="btn btn-warning btn-lg">
                                    <i class="fas fa-history me-2"></i>تاريخ النزلاء
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4 mb-3">
                            <div class="d-grid">
                                <a href="guests.php" class="btn btn-danger btn-lg">
                                    <i class="fas fa-ban me-2"></i>إدارة النزلاء المحظورين
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- قسم إعدادات النظام -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-dark text-white">
                    <h5 class="mb-0"><i class="fas fa-cogs me-2"></i>إعدادات النظام</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-3 mb-3">
                            <div class="d-grid">
                                <a href="maintenance.php" class="btn btn-outline-dark btn-lg">
                                    <i class="fas fa-sliders-h me-2"></i>إعدادات عامة
                                </a>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="d-grid">
                                <a href="../system_tools/backup_manager.php" class="btn btn-secondary btn-lg">
                                    <i class="fas fa-database me-2"></i>النسخ الاحتياطي
                                </a>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="d-grid">
                                <a href="../system_tools/backup_database.php" class="btn btn-info btn-lg">
                                    <i class="fas fa-file-alt me-2"></i>نسخ قاعدة البيانات
                                </a>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="d-grid">
                                <a href="maintenance.php" class="btn btn-warning btn-lg">
                                    <i class="fas fa-tools me-2"></i>صيانة النظام
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
// التمرير السلس للإعدادات التفصيلية
document.addEventListener('DOMContentLoaded', function() {
    const detailedSettingsLink = document.querySelector('a[href="#detailed-settings"]');
    if (detailedSettingsLink) {
        detailedSettingsLink.addEventListener('click', function(e) {
            e.preventDefault();
            const target = document.getElementById('detailed-settings');
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    }
});
</script>

<?php include_once '../../includes/footer.php'; ?>
