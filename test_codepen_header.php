<?php
session_start();

// تسجيل دخول مؤقت للاختبار
if (!isset($_SESSION['username'])) {
    $_SESSION['username'] = 'مدير النظام';
    $_SESSION['user_id'] = 1;
    $_SESSION['role'] = 'admin';
}

// تضمين الهيدر الجديد
include 'includes/header-codepen.php';
?>

<div class="bg-white rounded shadow p-3 mb-3">
    <h2 class="text-center mb-3">
        <i class="fas fa-star text-warning"></i>
        مرحباً بك في النظام الجديد
    </h2>
    <p class="text-center text-muted">
        تم تطوير نظام التنقل الجديد بأسلوب CodePen الحديث مع القوائم الفرعية التفاعلية
    </p>
</div>

<div class="row">
    <div class="col-md-4 mb-3">
        <div class="bg-white rounded shadow p-3">
            <h4 class="text-primary">
                <i class="fas fa-bed"></i>
                إدارة الغرف
            </h4>
            <p class="text-muted">قم بإدارة جميع غرف الفندق بسهولة</p>
            <ul class="list-unstyled">
                <li><i class="fas fa-check text-success"></i> قائمة الغرف</li>
                <li><i class="fas fa-check text-success"></i> إضافة غرفة جديدة</li>
                <li><i class="fas fa-check text-success"></i> متابعة حالة الغرف</li>
            </ul>
        </div>
    </div>
    
    <div class="col-md-4 mb-3">
        <div class="bg-white rounded shadow p-3">
            <h4 class="text-success">
                <i class="fas fa-calendar-alt"></i>
                إدارة الحجوزات
            </h4>
            <p class="text-muted">تتبع وإدارة جميع الحجوزات</p>
            <ul class="list-unstyled">
                <li><i class="fas fa-check text-success"></i> قائمة الحجوزات</li>
                <li><i class="fas fa-check text-success"></i> حجز جديد</li>
                <li><i class="fas fa-check text-success"></i> تسجيل الخروج</li>
            </ul>
        </div>
    </div>
    
    <div class="col-md-4 mb-3">
        <div class="bg-white rounded shadow p-3">
            <h4 class="text-info">
                <i class="fas fa-chart-line"></i>
                التقارير والإحصائيات
            </h4>
            <p class="text-muted">تقارير مالية وإحصائيات مفصلة</p>
            <ul class="list-unstyled">
                <li><i class="fas fa-check text-success"></i> تقارير الإيرادات</li>
                <li><i class="fas fa-check text-success"></i> تقارير الإشغال</li>
                <li><i class="fas fa-check text-success"></i> التقارير الشاملة</li>
            </ul>
        </div>
    </div>
</div>

<div class="row">
    <div class="col-md-6 mb-3">
        <div class="bg-white rounded shadow p-3">
            <h4 class="text-warning">
                <i class="fas fa-users"></i>
                إدارة الموظفين
            </h4>
            <p class="text-muted">تنظيم شؤون الموظفين والرواتب</p>
            <div class="row">
                <div class="col-6">
                    <div class="text-center p-2 bg-light rounded">
                        <i class="fas fa-money-check-alt fa-2x text-success"></i>
                        <p class="mt-2 mb-0">سحوبات الراتب</p>
                    </div>
                </div>
                <div class="col-6">
                    <div class="text-center p-2 bg-light rounded">
                        <i class="fas fa-user-tie fa-2x text-primary"></i>
                        <p class="mt-2 mb-0">إدارة الموظفين</p>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <div class="col-md-6 mb-3">
        <div class="bg-white rounded shadow p-3">
            <h4 class="text-danger">
                <i class="fas fa-wallet"></i>
                الإدارة المالية
            </h4>
            <p class="text-muted">إدارة الشؤون المالية والمصروفات</p>
            <div class="row">
                <div class="col-4">
                    <div class="text-center p-2 bg-light rounded">
                        <i class="fas fa-cash-register fa-2x text-success"></i>
                        <p class="mt-2 mb-0">الصندوق</p>
                    </div>
                </div>
                <div class="col-4">
                    <div class="text-center p-2 bg-light rounded">
                        <i class="fas fa-receipt fa-2x text-warning"></i>
                        <p class="mt-2 mb-0">المصروفات</p>
                    </div>
                </div>
                <div class="col-4">
                    <div class="text-center p-2 bg-light rounded">
                        <i class="fas fa-chart-bar fa-2x text-info"></i>
                        <p class="mt-2 mb-0">التقارير</p>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<div class="bg-white rounded shadow p-3">
    <h4 class="text-center mb-3">
        <i class="fas fa-cogs text-secondary"></i>
        الإعدادات والأدوات
    </h4>
    <div class="row">
        <div class="col-md-3 text-center mb-3">
            <div class="p-3 bg-light rounded">
                <i class="fas fa-user fa-3x text-primary mb-2"></i>
                <h6>إدارة المستخدمين</h6>
                <p class="text-muted small">تحكم في صلاحيات المستخدمين</p>
            </div>
        </div>
        <div class="col-md-3 text-center mb-3">
            <div class="p-3 bg-light rounded">
                <i class="fas fa-user-friends fa-3x text-success mb-2"></i>
                <h6>إدارة النزلاء</h6>
                <p class="text-muted small">متابعة بيانات النزلاء</p>
            </div>
        </div>
        <div class="col-md-3 text-center mb-3">
            <div class="p-3 bg-light rounded">
                <i class="fas fa-database fa-3x text-warning mb-2"></i>
                <h6>النسخ الاحتياطي</h6>
                <p class="text-muted small">حماية البيانات</p>
            </div>
        </div>
        <div class="col-md-3 text-center mb-3">
            <div class="p-3 bg-light rounded">
                <i class="fas fa-tools fa-3x text-info mb-2"></i>
                <h6>أدوات النظام</h6>
                <p class="text-muted small">صيانة وتحديث النظام</p>
            </div>
        </div>
    </div>
</div>

<style>
    .list-unstyled li {
        padding: 5px 0;
    }
    
    .bg-light {
        background-color: #f8f9fa !important;
    }
    
    .row {
        margin-left: -15px;
        margin-right: -15px;
    }
    
    .col-md-3, .col-md-4, .col-md-6 {
        padding-left: 15px;
        padding-right: 15px;
    }
    
    .col-4, .col-6 {
        padding-left: 5px;
        padding-right: 5px;
    }
    
    .text-primary { color: #3498db !important; }
    .text-success { color: #27ae60 !important; }
    .text-info { color: #17a2b8 !important; }
    .text-warning { color: #f39c12 !important; }
    .text-danger { color: #e74c3c !important; }
    .text-secondary { color: #6c757d !important; }
    .text-muted { color: #6c757d !important; }
    
    .mb-0 { margin-bottom: 0 !important; }
    .mb-2 { margin-bottom: 0.5rem !important; }
    .mb-3 { margin-bottom: 1rem !important; }
    .mt-2 { margin-top: 0.5rem !important; }
    .mt-3 { margin-top: 1rem !important; }
    .p-2 { padding: 0.5rem !important; }
    .p-3 { padding: 1rem !important; }
    
    .list-unstyled {
        padding-left: 0;
        list-style: none;
    }
    
    .small {
        font-size: 0.875em;
    }
</style>

</main>
</div>

</body>
</html>