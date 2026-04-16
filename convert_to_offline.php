<?php
/**
 * أداة تحويل الصفحات للعمل بدون انترنت
 * تستبدل روابط CDN بالمكتبات المحلية
 */

function convertPageToOffline($filePath) {
    if (!file_exists($filePath)) {
        return "الملف غير موجود: $filePath";
    }
    
    $content = file_get_contents($filePath);
    $originalContent = $content;
    
    // استبدال Bootstrap CSS
    $content = preg_replace(
        '/https:\/\/cdn\.jsdelivr\.net\/npm\/bootstrap@[\d.]+\/dist\/css\/bootstrap\.min\.css/',
        '<?= BASE_URL ?>assets/css/bootstrap-complete.css',
        $content
    );
    
    // استبدال Font Awesome CSS
    $content = preg_replace(
        '/https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/font-awesome\/[\d.]+\/css\/all\.min\.css/',
        '<?= BASE_URL ?>assets/css/fontawesome-offline.css',
        $content
    );
    
    // استبدال Google Fonts
    $content = preg_replace(
        '/https:\/\/fonts\.googleapis\.com\/css2\?family=Tajawal[^"]*/',
        '<?= BASE_URL ?>assets/fonts/tajawal-offline.css',
        $content
    );
    
    // استبدال Bootstrap JS
    $content = preg_replace(
        '/https:\/\/cdn\.jsdelivr\.net\/npm\/bootstrap@[\d.]+\/dist\/js\/bootstrap\.bundle\.min\.js/',
        '<?= BASE_URL ?>assets/js/bootstrap-local.js',
        $content
    );
    
    // استبدال jQuery CDN
    $content = preg_replace(
        '/https:\/\/code\.jquery\.com\/jquery-[\d.]+\.min\.js/',
        '<?= BASE_URL ?>assets/js/jquery.min.js',
        $content
    );
    
    if ($content !== $originalContent) {
        // إنشاء نسخة احتياطية
        $backupPath = $filePath . '.backup.' . date('Y-m-d-H-i-s');
        copy($filePath, $backupPath);
        
        // حفظ الملف المحدث
        file_put_contents($filePath, $content);
        
        return "تم تحويل الملف بنجاح!\nالنسخة الاحتياطية: $backupPath";
    } else {
        return "لم يتم العثور على روابط CDN للاستبدال";
    }
}

// إذا تم استدعاء الملف مباشرة
if (php_sapi_name() === 'cli') {
    if (isset($argv[1])) {
        $result = convertPageToOffline($argv[1]);
        echo $result . "\n";
    } else {
        echo "الاستخدام: php convert_to_offline.php [مسار_الملف]\n";
        echo "مثال: php convert_to_offline.php admin/dashboard.php\n";
    }
} else {
    // إذا تم الوصول عبر المتصفح
    ?>
    <!DOCTYPE html>
    <html lang="ar" dir="rtl">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>أداة تحويل الصفحات للعمل بدون انترنت</title>
        <style>
            body {
                font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
                background: #f8f9fa;
            }
            .container {
                background: white;
                padding: 30px;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            }
            h1 {
                color: #2c3e50;
                text-align: center;
                margin-bottom: 30px;
            }
            .form-group {
                margin-bottom: 20px;
            }
            label {
                display: block;
                margin-bottom: 5px;
                font-weight: bold;
                color: #495057;
            }
            input[type="text"] {
                width: 100%;
                padding: 12px;
                border: 1px solid #ddd;
                border-radius: 4px;
                font-size: 16px;
            }
            button {
                background: #007bff;
                color: white;
                border: none;
                padding: 12px 24px;
                border-radius: 4px;
                cursor: pointer;
                font-size: 16px;
                width: 100%;
            }
            button:hover {
                background: #0056b3;
            }
            .result {
                margin-top: 20px;
                padding: 15px;
                border-radius: 4px;
                white-space: pre-line;
            }
            .success {
                background: #d4edda;
                color: #155724;
                border: 1px solid #c3e6cb;
            }
            .error {
                background: #f8d7da;
                color: #721c24;
                border: 1px solid #f5c6cb;
            }
            .file-list {
                background: #e9ecef;
                padding: 15px;
                border-radius: 4px;
                margin-top: 20px;
            }
            .file-list h3 {
                margin-top: 0;
                color: #495057;
            }
            .file-list ul {
                margin: 0;
                padding-right: 20px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🔄 أداة تحويل الصفحات للعمل بدون انترنت</h1>
            
            <form method="POST">
                <div class="form-group">
                    <label for="file_path">مسار الملف (نسبة إلى مجلد المشروع):</label>
                    <input type="text" id="file_path" name="file_path" 
                           placeholder="مثال: admin/dashboard.php أو bookings/add.php"
                           value="<?= isset($_POST['file_path']) ? htmlspecialchars($_POST['file_path']) : '' ?>">
                </div>
                <button type="submit">تحويل الملف</button>
            </form>

            <?php
            if (isset($_POST['file_path'])) {
                $filePath = trim($_POST['file_path']);
                if ($filePath) {
                    $result = convertPageToOffline($filePath);
                    $isSuccess = strpos($result, 'تم تحويل الملف بنجاح') !== false;
                    echo '<div class="result ' . ($isSuccess ? 'success' : 'error') . '">';
                    echo htmlspecialchars($result);
                    echo '</div>';
                }
            }
            ?>

            <div class="file-list">
                <h3>📁 الملفات المحولة مسبقاً:</h3>
                <ul>
                    <li>✅ <strong>admin/dash.php</strong> - لوحة التحكم الرئيسية</li>
                </ul>
                
                <h3>📦 الملفات المحلية المتاحة:</h3>
                <ul>
                    <li>✅ <code>assets/css/bootstrap-complete.css</code> - Bootstrap RTL</li>
                    <li>✅ <code>assets/css/fontawesome-offline.css</code> - أيقونات محلية</li>
                    <li>✅ <code>assets/fonts/tajawal-offline.css</code> - خط تجوال محلي</li>
                    <li>✅ <code>assets/js/bootstrap-local.js</code> - Bootstrap JavaScript</li>
                    <li>✅ <code>assets/js/jquery.min.js</code> - jQuery محلي</li>
                </ul>

                <h3>🎯 ملفات مقترحة للتحويل:</h3>
                <ul>
                    <li>admin/dashboard.php</li>
                    <li>admin/bookings/add.php</li>
                    <li>admin/bookings/list.php</li>
                    <li>admin/rooms/list.php</li>
                    <li>admin/reports/report.php</li>
                    <li>admin/settings/index.php</li>
                </ul>
            </div>
        </div>
    </body>
    </html>
    <?php
}
?>