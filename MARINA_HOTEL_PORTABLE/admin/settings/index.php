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

// تضمين الهيدر بعد انتهاء معالجة البيانات
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-cogs me-2"></i>الإعدادات الرئيسية</h2>
                <a href="../dash.php" class="btn btn-outline-primary">
                    <i class="fas fa-arrow-left me-1"></i>العودة للوحة التحكم
                </a>
            </div>
        </div>
    </div>

    <!-- إحصائيات سريعة -->
    <div class="row mb-4">
        <div class="col-md-3">
            <div class="card bg-primary text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['rooms'] ?></h4>
                            <p class="mb-0">إجمالي الغرف</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-bed fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-success text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['active_bookings'] ?></h4>
                            <p class="mb-0">الحجوزات النشطة</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-calendar-check fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-info text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['users'] ?></h4>
                            <p class="mb-0">المستخدمين</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-users fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-warning text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['employees'] ?></h4>
                            <p class="mb-0">الموظفين</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-user-tie fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- قسم الإعدادات السريعة -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-dark text-white">
                    <h5 class="mb-0"><i class="fas fa-bolt me-2"></i>الإعدادات السريعة</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-3 mb-3">
                            <div class="card h-100 border-primary">
                                <div class="card-body text-center">
                                    <i class="fas fa-bed fa-2x text-primary mb-2"></i>
                                    <h6 class="card-title">إدارة الغرف</h6>
                                    <p class="card-text small">إضافة وتعديل الغرف</p>
                                    <a href="../rooms/list.php" class="btn btn-primary btn-sm">
                                        <i class="fas fa-arrow-left me-1"></i>دخول
                                    </a>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="card h-100 border-success">
                                <div class="card-body text-center">
                                    <i class="fas fa-users fa-2x text-success mb-2"></i>
                                    <h6 class="card-title">إدارة المستخدمين</h6>
                                    <p class="card-text small">إضافة وتعديل المستخدمين</p>
                                    <a href="add_user.php" class="btn btn-success btn-sm">
                                        <i class="fas fa-arrow-left me-1"></i>دخول
                                    </a>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="card h-100 border-info">
                                <div class="card-body text-center">
                                    <i class="fas fa-user-tie fa-2x text-info mb-2"></i>
                                    <h6 class="card-title">إدارة الموظفين</h6>
                                    <p class="card-text small">إضافة وتعديل الموظفين</p>
                                    <a href="employees.php" class="btn btn-info btn-sm">
                                        <i class="fas fa-arrow-left me-1"></i>دخول
                                    </a>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="card h-100 border-warning">
                                <div class="card-body text-center">
                                    <i class="fas fa-cogs fa-2x text-warning mb-2"></i>
                                    <h6 class="card-title">جميع الإعدادات</h6>
                                    <p class="card-text small">الوصول لجميع الإعدادات</p>
                                    <a href="#detailed-settings" class="btn btn-warning btn-sm">
                                        <i class="fas fa-arrow-down me-1"></i>عرض
                                    </a>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <style>
        .card.border-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,123,255,0.3);
            transition: all 0.3s ease;
        }
        .card.border-success:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(40,167,69,0.3);
            transition: all 0.3s ease;
        }
        .card.border-info:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(23,162,184,0.3);
            transition: all 0.3s ease;
        }
        .card.border-warning:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(255,193,7,0.3);
            transition: all 0.3s ease;
        }
    </style>

    <!-- قسم إدارة الغرف -->
    <div class="row mb-4" id="detailed-settings">
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

    <!-- قسم إدارة المستخدمين -->
    <div class="row mb-4">
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
                                    <i class="fas fa-users me-2"></i>قائمة المستخدمين
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
                                <a href="user_permissions.php" class="btn btn-info btn-lg">
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
                    <h5 class="mb-0"><i class="fas fa-users me-2"></i>إدارة النزلاء</h5>
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
                                <a href="blacklist.php" class="btn btn-danger btn-lg">
                                    <i class="fas fa-ban me-2"></i>القائمة السوداء
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
                                <a href="system_config.php" class="btn btn-outline-dark btn-lg">
                                    <i class="fas fa-sliders-h me-2"></i>إعدادات عامة
                                </a>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="d-grid">
                                <a href="backup.php" class="btn btn-secondary btn-lg">
                                    <i class="fas fa-database me-2"></i>النسخ الاحتياطي
                                </a>
                            </div>
                        </div>
                        <div class="col-md-3 mb-3">
                            <div class="d-grid">
                                <a href="logs.php" class="btn btn-info btn-lg">
                                    <i class="fas fa-file-alt me-2"></i>سجلات النظام
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
