<?php
/**
 * إعداد نظام المزامنة التلقائية
 * Auto Sync Setup Script
 */

require_once 'includes/db.php';
require_once 'includes/email_sync.php';

?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إعداد نظام المزامنة التلقائية</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        .setup-container { max-width: 800px; margin: 50px auto; }
        .step-card { margin-bottom: 20px; }
        .status-indicator { width: 20px; height: 20px; border-radius: 50%; display: inline-block; margin-left: 10px; }
        .status-success { background-color: #28a745; }
        .status-warning { background-color: #ffc107; }
        .status-error { background-color: #dc3545; }
        .code-block { background: #f8f9fa; padding: 15px; border-radius: 5px; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container setup-container">
        <div class="text-center mb-5">
            <h1><i class="fas fa-sync-alt text-primary"></i> إعداد نظام المزامنة التلقائية</h1>
            <p class="text-muted">مزامنة كل دقيقتين مع البريد الإلكتروني: adenmarina2@gmail.com</p>
        </div>

        <!-- خطوة 1: فحص المتطلبات -->
        <div class="card step-card">
            <div class="card-header">
                <h5><i class="fas fa-check-circle"></i> الخطوة 1: فحص المتطلبات</h5>
            </div>
            <div class="card-body">
                <?php
                $requirements = [
                    'PHP Version >= 7.4' => version_compare(PHP_VERSION, '7.4.0', '>='),
                    'Database Connection' => $conn !== false,
                    'Logs Directory' => is_dir('logs') && is_writable('logs'),
                    'Email Function' => function_exists('mail'),
                    'JSON Extension' => extension_loaded('json'),
                    'cURL Extension' => extension_loaded('curl')
                ];

                foreach ($requirements as $requirement => $status) {
                    $icon = $status ? 'fas fa-check text-success' : 'fas fa-times text-danger';
                    $badge = $status ? 'badge bg-success' : 'badge bg-danger';
                    $text = $status ? 'متوفر' : 'غير متوفر';
                    
                    echo "<div class='d-flex justify-content-between align-items-center mb-2'>";
                    echo "<span><i class='$icon'></i> $requirement</span>";
                    echo "<span class='$badge'>$text</span>";
                    echo "</div>";
                }
                ?>
            </div>
        </div>

        <!-- خطوة 2: إنشاء الجداول المطلوبة -->
        <div class="card step-card">
            <div class="card-header">
                <h5><i class="fas fa-database"></i> الخطوة 2: إنشاء الجداول المطلوبة</h5>
            </div>
            <div class="card-body">
                <?php
                // إنشاء جدول أحداث المزامنة
                $sync_events_table = "CREATE TABLE IF NOT EXISTS sync_events (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    event_type VARCHAR(50) NOT NULL,
                    event_data TEXT,
                    timestamp DATETIME NOT NULL,
                    synced TINYINT(1) DEFAULT 0,
                    sync_timestamp DATETIME NULL,
                    INDEX idx_event_type (event_type),
                    INDEX idx_timestamp (timestamp),
                    INDEX idx_synced (synced)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

                // إنشاء جدول سجل تغييرات الغرف
                $room_log_table = "CREATE TABLE IF NOT EXISTS room_status_log (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    room_number VARCHAR(10) NOT NULL,
                    old_status VARCHAR(20),
                    new_status VARCHAR(20) NOT NULL,
                    changed_by VARCHAR(100),
                    change_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_room_number (room_number),
                    INDEX idx_change_time (change_time)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

                $tables = [
                    'sync_events' => $sync_events_table,
                    'room_status_log' => $room_log_table
                ];

                foreach ($tables as $table_name => $sql) {
                    $result = $conn->query($sql);
                    $icon = $result ? 'fas fa-check text-success' : 'fas fa-times text-danger';
                    $badge = $result ? 'badge bg-success' : 'badge bg-danger';
                    $text = $result ? 'تم إنشاؤه' : 'فشل';
                    
                    echo "<div class='d-flex justify-content-between align-items-center mb-2'>";
                    echo "<span><i class='$icon'></i> جدول $table_name</span>";
                    echo "<span class='$badge'>$text</span>";
                    echo "</div>";
                }

                // إنشاء مجلد السجلات
                if (!is_dir('logs')) {
                    $logs_created = mkdir('logs', 0755, true);
                } else {
                    $logs_created = true;
                }

                $icon = $logs_created ? 'fas fa-check text-success' : 'fas fa-times text-danger';
                $badge = $logs_created ? 'badge bg-success' : 'badge bg-danger';
                $text = $logs_created ? 'تم إنشاؤه' : 'فشل';
                
                echo "<div class='d-flex justify-content-between align-items-center mb-2'>";
                echo "<span><i class='$icon'></i> مجلد logs</span>";
                echo "<span class='$badge'>$text</span>";
                echo "</div>";
                ?>
            </div>
        </div>

        <!-- خطوة 3: اختبار النظام -->
        <div class="card step-card">
            <div class="card-header">
                <h5><i class="fas fa-vial"></i> الخطوة 3: اختبار النظام</h5>
            </div>
            <div class="card-body">
                <button class="btn btn-primary" onclick="testSync()">
                    <i class="fas fa-play"></i> تشغيل اختبار شامل
                </button>
                <div id="test-results" class="mt-3"></div>
            </div>
        </div>

        <!-- خطوة 4: إعداد المهمة المجدولة -->
        <div class="card step-card">
            <div class="card-header">
                <h5><i class="fas fa-clock"></i> الخطوة 4: إعداد المهمة المجدولة</h5>
            </div>
            <div class="card-body">
                <div class="alert alert-info">
                    <h6><i class="fas fa-info-circle"></i> لنظام Windows:</h6>
                    <p>افتح Command Prompt كمدير وقم بتشغيل الأمر التالي:</p>
                    <div class="code-block">
                        schtasks /create /tn "HotelSyncTask" /tr "php <?php echo __DIR__; ?>\sync_cron.php" /sc minute /mo 2 /f
                    </div>
                </div>

                <div class="alert alert-warning">
                    <h6><i class="fas fa-info-circle"></i> لنظام Linux:</h6>
                    <p>أضف السطر التالي إلى crontab (crontab -e):</p>
                    <div class="code-block">
                        */2 * * * * /usr/bin/php <?php echo __DIR__; ?>/sync_cron.php
                    </div>
                </div>

                <div class="alert alert-success">
                    <h6><i class="fas fa-lightbulb"></i> بديل سهل:</h6>
                    <p>يمكنك استخدام خدمة cron job مجانية مثل:</p>
                    <ul>
                        <li><a href="https://cron-job.org" target="_blank">cron-job.org</a></li>
                        <li><a href="https://www.easycron.com" target="_blank">easycron.com</a></li>
                    </ul>
                    <p>URL للمزامنة:</p>
                    <div class="code-block">
                        <?php echo (isset($_SERVER['HTTPS']) ? 'https' : 'http') . '://' . $_SERVER['HTTP_HOST'] . dirname($_SERVER['REQUEST_URI']); ?>/sync_cron.php?manual_run=1
                    </div>
                </div>
            </div>
        </div>

        <!-- خطوة 5: مراقبة النظام -->
        <div class="card step-card">
            <div class="card-header">
                <h5><i class="fas fa-chart-line"></i> الخطوة 5: مراقبة النظام</h5>
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-6">
                        <button class="btn btn-info w-100 mb-2" onclick="checkStatus()">
                            <i class="fas fa-info-circle"></i> فحص حالة المزامنة
                        </button>
                    </div>
                    <div class="col-md-6">
                        <button class="btn btn-success w-100 mb-2" onclick="runManualSync()">
                            <i class="fas fa-sync"></i> تشغيل مزامنة يدوية
                        </button>
                    </div>
                </div>
                <div id="status-results" class="mt-3"></div>
            </div>
        </div>

        <div class="text-center mt-4">
            <a href="admin/dash.php" class="btn btn-primary btn-lg">
                <i class="fas fa-arrow-right"></i> الانتقال إلى لوحة التحكم
            </a>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        async function testSync() {
            const resultsDiv = document.getElementById('test-results');
            resultsDiv.innerHTML = '<div class="spinner-border text-primary" role="status"></div> جاري تشغيل الاختبار...';
            
            try {
                const response = await fetch('api/email_sync.php?action=test');
                const data = await response.json();
                
                if (data.success) {
                    let html = '<div class="alert alert-success"><h6>نتائج الاختبار:</h6>';
                    for (const [test, result] of Object.entries(data.tests)) {
                        const icon = result.includes('نجح') ? 'fas fa-check text-success' : 'fas fa-times text-danger';
                        html += `<div><i class="${icon}"></i> ${test}: ${result}</div>`;
                    }
                    html += '</div>';
                    resultsDiv.innerHTML = html;
                } else {
                    resultsDiv.innerHTML = `<div class="alert alert-danger">خطأ: ${data.message}</div>`;
                }
            } catch (error) {
                resultsDiv.innerHTML = `<div class="alert alert-danger">خطأ في الاتصال: ${error.message}</div>`;
            }
        }

        async function checkStatus() {
            const resultsDiv = document.getElementById('status-results');
            resultsDiv.innerHTML = '<div class="spinner-border text-info" role="status"></div> جاري فحص الحالة...';
            
            try {
                const response = await fetch('api/email_sync.php?action=status');
                const data = await response.json();
                
                if (data.success) {
                    let html = '<div class="alert alert-info"><h6>حالة النظام:</h6>';
                    html += `<div><strong>آخر مزامنة:</strong> ${data.last_sync}</div>`;
                    html += `<div><strong>حالة المزامنة:</strong> ${data.sync_enabled ? 'مفعلة' : 'معطلة'}</div>`;
                    html += `<div><strong>فترة المزامنة:</strong> ${data.sync_interval}</div>`;
                    html += `<div><strong>الأحداث المعلقة:</strong> ${data.pending_events}</div>`;
                    html += '</div>';
                    resultsDiv.innerHTML = html;
                } else {
                    resultsDiv.innerHTML = `<div class="alert alert-danger">خطأ: ${data.message}</div>`;
                }
            } catch (error) {
                resultsDiv.innerHTML = `<div class="alert alert-danger">خطأ في الاتصال: ${error.message}</div>`;
            }
        }

        async function runManualSync() {
            const resultsDiv = document.getElementById('status-results');
            resultsDiv.innerHTML = '<div class="spinner-border text-success" role="status"></div> جاري تشغيل المزامنة...';
            
            try {
                const response = await fetch('api/email_sync.php?action=run_sync');
                const data = await response.json();
                
                const alertClass = data.success ? 'alert-success' : 'alert-danger';
                resultsDiv.innerHTML = `<div class="alert ${alertClass}">${data.message}</div>`;
            } catch (error) {
                resultsDiv.innerHTML = `<div class="alert alert-danger">خطأ في الاتصال: ${error.message}</div>`;
            }
        }
    </script>
</body>
</html>
