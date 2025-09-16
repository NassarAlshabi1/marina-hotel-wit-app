<?php
require_once __DIR__ . '/../../includes/auth_check.php';
require_once __DIR__ . '/../../includes/config.php';

$logFile = __DIR__ . '/../../logs/error.log';
$logContent = file_exists($logFile) ? file_get_contents($logFile) : 'لا توجد سجلات بعد.';

require_once __DIR__ . '/../../includes/header.php';
require_once __DIR__ . '/../../includes/sidebar.php';
?>
<div class="container py-4">
    <h3 class="mb-3">سجلات النظام</h3>
    <pre style="background:#111;color:#0f0;padding:16px;max-height:60vh;overflow:auto;white-space:pre-wrap;word-wrap:break-word;"><?= htmlspecialchars($logContent) ?></pre>
</div>
<?php require_once __DIR__ . '/../../includes/footer.php'; ?>

