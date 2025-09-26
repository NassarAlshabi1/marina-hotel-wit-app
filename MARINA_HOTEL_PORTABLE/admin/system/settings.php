<?php
require_once __DIR__ . '/../../includes/auth_check.php';
require_once __DIR__ . '/../../includes/config.php';

$envPath = __DIR__ . '/../../.env';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $baseUrl = trim($_POST['BASE_URL'] ?? '');
    $timezone = trim($_POST['TIMEZONE'] ?? '');
    $debug = isset($_POST['DEBUG_MODE']) ? '1' : '0';

    $env = [
        'BASE_URL' => $baseUrl,
        'TIMEZONE' => $timezone,
        'DEBUG_MODE' => $debug,
    ];

    $lines = [];
    foreach ($env as $k => $v) {
        if ($v !== '') { $lines[] = $k . '=' . $v; }
    }
    file_put_contents($envPath, implode("\n", $lines) . "\n", FILE_APPEND);
    header('Location: ' . BASE_URL . 'admin/system/settings.php?saved=1');
    exit;
}

require_once __DIR__ . '/../../includes/header.php';
require_once __DIR__ . '/../../includes/sidebar.php';
?>
<div class="container py-4">
    <h3 class="mb-3">إعدادات عامة للنظام</h3>
    <?php if (isset($_GET['saved'])): ?>
        <div class="alert alert-success">تم حفظ الإعدادات. قد تحتاج لإعادة تشغيل الحاويات.</div>
    <?php endif; ?>
    <form method="post">
        <div class="mb-3">
            <label class="form-label">BASE_URL</label>
            <input type="text" name="BASE_URL" class="form-control" value="<?= htmlspecialchars(BASE_URL) ?>" placeholder="http://server-ip:8080/">
        </div>
        <div class="mb-3">
            <label class="form-label">المنطقة الزمنية</label>
            <input type="text" name="TIMEZONE" class="form-control" value="<?= htmlspecialchars(TIMEZONE) ?>" placeholder="Asia/Riyadh">
        </div>
        <div class="form-check mb-3">
            <input type="checkbox" class="form-check-input" id="debug" name="DEBUG_MODE" <?= DEBUG_MODE ? 'checked' : '' ?>>
            <label class="form-check-label" for="debug">وضع التطوير (DEBUG)</label>
        </div>
        <button type="submit" class="btn btn-primary">حفظ</button>
    </form>
</div>
<?php require_once __DIR__ . '/../../includes/footer.php'; ?>

