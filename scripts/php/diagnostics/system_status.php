<?php

require_once dirname(__DIR__) . '/bootstrap.php';
/*!
 * System Status Page - Marina Hotel
 * Comprehensive system diagnostics and health check
 */

// Include configuration
require_once 'includes/local-system-config.php';

// Get system status
$systemStatus = SystemHealthChecker::getSystemStatus();
$systemReport = SystemHealthChecker::generateReport();
$fileCheck = SystemHealthChecker::checkLocalFiles();

// Page info
$pageTitle = 'حالة النظام - مارينا هوتل';
$currentTime = date('Y-m-d H:i:s');
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= $pageTitle ?></title>
    
    <!-- Local CSS Files -->
    <link href="includes/css/bootstrap.min.css" rel="stylesheet">
    <link href="includes/css/fontawesome.min.css" rel="stylesheet">
    <link href="includes/css/tajawal-font.css" rel="stylesheet">
    <link href="includes/css/custom.css" rel="stylesheet">
    
    <style>
        body {
            font-family: 'Tajawal', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px 0;
        }
        
        .status-card {
            background: white;
            border-radius: 20px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.1);
            margin-bottom: 2rem;
            overflow: hidden;
        }
        
        .status-header {
            background: linear-gradient(135deg, #36d1dc 0%, #5b86e5 100%);
            color: white;
            padding: 1.5rem;
            text-align: center;
        }
        
        .status-body {
            padding: 2rem;
        }
        
        .status-ok {
            color: #28a745;
            background: #d4edda;
            padding: 10px 20px;
            border-radius: 25px;
            border: 2px solid #28a745;
        }
        
        .status-error {
            color: #dc3545;
            background: #f8d7da;
            padding: 10px 20px;
            border-radius: 25px;
            border: 2px solid #dc3545;
        }
        
        .file-list {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 1rem;
            margin-top: 1rem;
        }
        
        .file-item {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 10px;
            border-left: 4px solid #28a745;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .file-item.missing {
            border-left-color: #dc3545;
            background: #fff5f5;
        }
        
        .system-info {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem;
            border-radius: 15px;
            margin-bottom: 2rem;
        }
        
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-top: 1rem;
        }
        
        .info-item {
            background: rgba(255, 255, 255, 0.1);
            padding: 1rem;
            border-radius: 10px;
            text-align: center;
        }
        
        .info-value {
            font-size: 1.5rem;
            font-weight: 700;
            margin-top: 0.5rem;
        }
        
        .report-text {
            background: #f8f9fa;
            padding: 1.5rem;
            border-radius: 10px;
            font-family: 'Courier New', monospace;
            white-space: pre-line;
            max-height: 400px;
            overflow-y: auto;
            font-size: 0.9rem;
            direction: ltr;
            text-align: left;
        }
        
        .badge-large {
            font-size: 1.2rem;
            padding: 10px 20px;
            border-radius: 25px;
        }
        
        .action-buttons {
            text-align: center;
            margin-top: 2rem;
        }
        
        .btn-action {
            margin: 0.5rem;
            padding: 12px 30px;
            border-radius: 25px;
            text-decoration: none;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(102, 126, 234, 0.4);
            color: white;
        }
        
        .btn-success {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            color: white;
            border: none;
        }
        
        .btn-success:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(40, 167, 69, 0.4);
            color: white;
        }
        
        .btn-warning {
            background: linear-gradient(135deg, #ffc107 0%, #e0a800 100%);
            color: #212529;
            border: none;
        }
        
        .btn-warning:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(255, 193, 7, 0.4);
        }
    </style>
</head>
<body>

<div class="container">
    
    <!-- Header -->
    <div class="system-info">
        <div class="text-center">
            <i class="fas fa-server fa-3x mb-3"></i>
            <h1 class="mb-3"><?= $pageTitle ?></h1>
            <p class="mb-0">تشخيص شامل لحالة النظام المحلي</p>
        </div>
        
        <div class="info-grid">
            <div class="info-item">
                <i class="fas fa-code-branch fa-2x"></i>
                <div class="info-value"><?= $systemStatus['version'] ?></div>
                <div>إصدار النظام</div>
            </div>
            <div class="info-item">
                <i class="fas fa-wifi-slash fa-2x"></i>
                <div class="info-value"><?= $systemStatus['type'] ?></div>
                <div>نوع النظام</div>
            </div>
            <div class="info-item">
                <i class="fas fa-clock fa-2x"></i>
                <div class="info-value"><?= $currentTime ?></div>
                <div>الوقت الحالي</div>
            </div>
            <div class="info-item">
                <i class="fas fa-calendar fa-2x"></i>
                <div class="info-value"><?= $systemStatus['last_updated'] ?></div>
                <div>آخر تحديث</div>
            </div>
        </div>
    </div>
    
    <!-- Overall Status -->
    <div class="status-card">
        <div class="status-header">
            <h2><i class="fas fa-heartbeat me-2"></i>الحالة العامة للنظام</h2>
        </div>
        <div class="status-body text-center">
            <?php if ($systemStatus['offline_ready']): ?>
                <div class="status-ok badge-large">
                    <i class="fas fa-check-circle fa-2x mb-2"></i>
                    <div>✅ النظام جاهز للعمل بدون إنترنت</div>
                </div>
                <p class="mt-3 text-success">جميع الملفات المطلوبة متوفرة محلياً</p>
            <?php else: ?>
                <div class="status-error badge-large">
                    <i class="fas fa-exclamation-triangle fa-2x mb-2"></i>
                    <div>❌ النظام غير جاهز للعمل بدون إنترنت</div>
                </div>
                <p class="mt-3 text-danger">بعض الملفات المطلوبة مفقودة</p>
            <?php endif; ?>
        </div>
    </div>
    
    <!-- Files Status -->
    <div class="status-card">
        <div class="status-header">
            <h3><i class="fas fa-folder-open me-2"></i>حالة الملفات المحلية</h3>
        </div>
        <div class="status-body">
            <div class="row">
                <div class="col-md-6">
                    <h4><i class="fas fa-palette me-2"></i>ملفات CSS</h4>
                    <div class="file-list">
                        <?php foreach ($fileCheck['css'] as $name => $status): ?>
                        <div class="file-item <?= $status === 'missing' ? 'missing' : '' ?>">
                            <span>
                                <i class="fas fa-<?= $status === 'exists' ? 'check-circle text-success' : 'times-circle text-danger' ?> me-2"></i>
                                <?= $name ?>
                            </span>
                            <span class="badge bg-<?= $status === 'exists' ? 'success' : 'danger' ?>">
                                <?= $status === 'exists' ? 'موجود' : 'مفقود' ?>
                            </span>
                        </div>
                        <?php endforeach; ?>
                    </div>
                </div>
                
                <div class="col-md-6">
                    <h4><i class="fas fa-code me-2"></i>ملفات JavaScript</h4>
                    <div class="file-list">
                        <?php foreach ($fileCheck['js'] as $name => $status): ?>
                        <div class="file-item <?= $status === 'missing' ? 'missing' : '' ?>">
                            <span>
                                <i class="fas fa-<?= $status === 'exists' ? 'check-circle text-success' : 'times-circle text-danger' ?> me-2"></i>
                                <?= $name ?>
                            </span>
                            <span class="badge bg-<?= $status === 'exists' ? 'success' : 'danger' ?>">
                                <?= $status === 'exists' ? 'موجود' : 'مفقود' ?>
                            </span>
                        </div>
                        <?php endforeach; ?>
                    </div>
                </div>
            </div>
            
            <!-- Summary -->
            <div class="mt-4 p-3 bg-light rounded">
                <div class="row text-center">
                    <div class="col-md-3">
                        <h5 class="text-info"><?= $systemStatus['total_css_files'] ?></h5>
                        <small>إجمالي ملفات CSS</small>
                    </div>
                    <div class="col-md-3">
                        <h5 class="text-info"><?= $systemStatus['total_js_files'] ?></h5>
                        <small>إجمالي ملفات JS</small>
                    </div>
                    <div class="col-md-3">
                        <h5 class="text-success"><?= count($fileCheck['css']) + count($fileCheck['js']) - count($systemStatus['missing_files']) ?></h5>
                        <small>الملفات الموجودة</small>
                    </div>
                    <div class="col-md-3">
                        <h5 class="text-danger"><?= count($systemStatus['missing_files']) ?></h5>
                        <small>الملفات المفقودة</small>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <!-- Missing Files Alert -->
    <?php if (!empty($systemStatus['missing_files'])): ?>
    <div class="status-card">
        <div class="status-header bg-danger">
            <h3><i class="fas fa-exclamation-triangle me-2"></i>الملفات المفقودة</h3>
        </div>
        <div class="status-body">
            <div class="alert alert-danger">
                <h5>الملفات التالية مفقودة ويجب إنشاؤها:</h5>
                <ul class="mt-3">
                    <?php foreach ($systemStatus['missing_files'] as $file): ?>
                    <li><code><?= htmlspecialchars($file) ?></code></li>
                    <?php endforeach; ?>
                </ul>
            </div>
            <div class="text-center">
                <a href="scripts/php/maintenance/fix_system.php" class="btn-action btn-warning">
                    <i class="fas fa-tools me-2"></i>إصلاح النظام تلقائياً
                </a>
            </div>
        </div>
    </div>
    <?php endif; ?>
    
    <!-- Detailed Report -->
    <div class="status-card">
        <div class="status-header">
            <h3><i class="fas fa-clipboard-list me-2"></i>التقرير التفصيلي</h3>
        </div>
        <div class="status-body">
            <div class="report-text"><?= htmlspecialchars($systemReport) ?></div>
        </div>
    </div>
    
    <!-- Action Buttons -->
    <div class="action-buttons">
        <a href="admin/dash.php" class="btn-action btn-primary">
            <i class="fas fa-tachometer-alt me-2"></i>لوحة التحكم
        </a>
        
        <a href="marina_hotel_offline.html" class="btn-action btn-success">
            <i class="fas fa-home me-2"></i>الصفحة الرئيسية
        </a>
        
        <button onclick="window.location.reload()" class="btn-action btn-primary">
            <i class="fas fa-sync-alt me-2"></i>تحديث الصفحة
        </button>
        
        <button onclick="downloadReport()" class="btn-action btn-success">
            <i class="fas fa-download me-2"></i>تحميل التقرير
        </button>
    </div>
    
    <!-- Footer -->
    <div class="text-center mt-5">
        <p class="text-white">
            <i class="fas fa-hotel me-2"></i>
            نظام إدارة مارينا هوتل - الإصدار <?= $systemStatus['version'] ?> - يعمل بدون إنترنت
        </p>
        <small class="text-white-50">
            تم التطوير بواسطة فريق مارينا هوتل التقني • آخر تحديث: <?= $systemStatus['last_updated'] ?>
        </small>
    </div>
    
</div>

<!-- Local JavaScript Files -->
<script src="includes/js/bootstrap.bundle.min.js"></script>
<script src="includes/js/custom.js"></script>

<script>
// System Status JavaScript
document.addEventListener('DOMContentLoaded', function() {
    console.log('🏨 Marina Hotel System Status Page Loaded');
    console.log('System Version:', '<?= $systemStatus['version'] ?>');
    console.log('Offline Ready:', <?= $systemStatus['offline_ready'] ? 'true' : 'false' ?>);
    
    // Add animations
    const cards = document.querySelectorAll('.status-card');
    cards.forEach((card, index) => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(30px)';
        
        setTimeout(() => {
            card.style.transition = 'all 0.6s ease';
            card.style.opacity = '1';
            card.style.transform = 'translateY(0)';
        }, index * 200 + 300);
    });
    
    // Auto-refresh every 30 seconds
    setTimeout(() => {
        if (confirm('هل تريد تحديث حالة النظام؟')) {
            window.location.reload();
        }
    }, 30000);
});

// Download report function
function downloadReport() {
    const report = <?= json_encode($systemReport) ?>;
    const blob = new Blob([report], { type: 'text/plain;charset=utf-8' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'marina-hotel-system-report-<?= date('Y-m-d-H-i-s') ?>.txt';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
}

// System monitoring
setInterval(() => {
    console.log('🔄 System heartbeat - All systems operational');
}, 10000);
</script>

</body>
</html>