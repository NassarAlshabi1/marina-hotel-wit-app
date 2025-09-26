<?php
require_once __DIR__ . '/../../includes/auth_check.php';
require_once __DIR__ . '/../../includes/config.php';

$hostIp = $_SERVER['HTTP_HOST'] ?? 'localhost:8080';

require_once __DIR__ . '/../../includes/header.php';
require_once __DIR__ . '/../../includes/sidebar.php';
?>
<div class="container py-4">
    <h3 class="mb-3">إعدادات الشبكة والوصول</h3>
    <div class="alert alert-info">
        افتح النظام من أي جهاز على الشبكة عبر: <strong><?= 'http://' . htmlspecialchars($hostIp) ?><?= rtrim(parse_url(BASE_URL, PHP_URL_PATH) ?: '/', '/') ?>/</strong>
    </div>
    <p>للوصول من خارج الشبكة، قم بفتح المنفذ 8080 على الراوتر وتوجيهه إلى الخادم.</p>
    <ul>
        <li>إذا كنت تستخدم Docker Compose: الخدمة تفتح المنفذ 8080 تلقائياً.</li>
        <li>اضبط <code>BASE_URL</code> ليتوافق مع عنوان الخادم.</li>
    </ul>
</div>
<?php require_once __DIR__ . '/../../includes/footer.php'; ?>

