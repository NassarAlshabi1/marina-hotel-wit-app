<?php
require_once __DIR__ . '/../../includes/auth_check.php';
require_once __DIR__ . '/../../includes/config.php';

$configFile = __DIR__ . '/../../includes/offline_config.php';
$isEnabled = false;
if (file_exists($configFile)) {
    include $configFile;
    $isEnabled = defined('OFFLINE_MODE_ENABLED') ? (bool)OFFLINE_MODE_ENABLED : false;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $enable = isset($_POST['enable']) && $_POST['enable'] === '1';
    $content = "<?php\n";
    $content .= "define('OFFLINE_MODE_ENABLED', " . ($enable ? 'true' : 'false') . ");\n";
    file_put_contents($configFile, $content);
    header('Location: ' . BASE_URL . 'admin/system/maintenance.php?saved=1');
    exit;
}

require_once __DIR__ . '/../../includes/header.php';
require_once __DIR__ . '/../../includes/sidebar.php';
?>
<div class="container py-4">
    <h3 class="mb-3">وضع الصيانة</h3>
    <?php if (isset($_GET['saved'])): ?>
        <div class="alert alert-success">تم حفظ الإعداد بنجاح.</div>
    <?php endif; ?>
    <form method="post">
        <div class="form-check form-switch mb-3">
            <input class="form-check-input" type="checkbox" id="enableSwitch" name="enable" value="1" <?= $isEnabled ? 'checked' : '' ?>>
            <label class="form-check-label" for="enableSwitch">تفعيل وضع الصيانة</label>
        </div>
        <button type="submit" class="btn btn-warning">حفظ</button>
        <a href="<?= BASE_URL ?>offline.html" target="_blank" class="btn btn-outline-secondary">معاينة صفحة الصيانة</a>
    </form>
</div>
<?php require_once __DIR__ . '/../../includes/footer.php'; ?>

