<?php
require_once __DIR__ . '/../../includes/auth_check.php';
require_once __DIR__ . '/../../includes/config.php';
require_once __DIR__ . '/../../includes/security.php';

require_once __DIR__ . '/../../includes/header.php';
require_once __DIR__ . '/../../includes/sidebar.php';
?>
<div class="container py-4">
    <h3 class="mb-3">أدوات الأمان</h3>
    <ul class="list-group">
        <li class="list-group-item d-flex justify-content-between align-items-center">
            سياسات الجلسات وحماية CSRF
            <a href="<?= BASE_URL ?>setup_security_tables.php" class="btn btn-sm btn-outline-primary">إعادة تهيئة</a>
        </li>
        <li class="list-group-item d-flex justify-content-between align-items-center">
            مراقبة الأخطاء
            <a href="<?= BASE_URL ?>system_health_report.php" class="btn btn-sm btn-outline-secondary">عرض تقرير الصحة</a>
        </li>
    </ul>
</div>
<?php require_once __DIR__ . '/../../includes/footer.php'; ?>

