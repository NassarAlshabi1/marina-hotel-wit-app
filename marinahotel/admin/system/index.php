<?php
require_once __DIR__ . '/../../includes/auth_check.php';
require_once __DIR__ . '/../../includes/config.php';
require_once __DIR__ . '/../../includes/header.php';
require_once __DIR__ . '/../../includes/sidebar.php';
?>
<div class="container-fluid py-4">
    <div class="row mb-4">
        <div class="col-12 d-flex align-items-center justify-content-between">
            <h2 class="mb-0">إدارة النظام</h2>
            <div>
                <a href="<?= BASE_URL ?>admin/system/network.php" class="btn btn-outline-primary">إعدادات الشبكة</a>
                <a href="<?= BASE_URL ?>admin/system/security.php" class="btn btn-outline-danger">الأمان</a>
                <a href="<?= BASE_URL ?>admin/system/logs.php" class="btn btn-outline-secondary">السجلات</a>
            </div>
        </div>
    </div>

    <div class="row g-4">
        <div class="col-md-6">
            <div class="card h-100">
                <div class="card-body">
                    <h5 class="card-title">وضع الصيانة</h5>
                    <p class="text-muted mb-3">تفعيل/إيقاف وضع الصيانة وإعداد صفحة الصيانة.</p>
                    <a href="<?= BASE_URL ?>admin/system/maintenance.php" class="btn btn-warning">إدارة وضع الصيانة</a>
                </div>
            </div>
        </div>
        <div class="col-md-6">
            <div class="card h-100">
                <div class="card-body">
                    <h5 class="card-title">إعدادات عامة</h5>
                    <p class="text-muted mb-3">تعيين BASE_URL، المنطقة الزمنية، ووضع التصحيح.</p>
                    <a href="<?= BASE_URL ?>admin/system/settings.php" class="btn btn-primary">إدارة الإعدادات</a>
                </div>
            </div>
        </div>
    </div>
</div>
<?php require_once __DIR__ . '/../../includes/footer.php'; ?>

