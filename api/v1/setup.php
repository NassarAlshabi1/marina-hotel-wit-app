<?php
/**
 * سكريبت تثبيت API v1 وإعداد قاعدة البيانات
 * قم بتشغيل هذا الملف مرة واحدة لتطبيق جميع التغييرات
 */

require_once __DIR__ . '/../../includes/config.php';
require_once __DIR__ . '/../../includes/db.php';

// تفعيل عرض الأخطاء
ini_set('display_errors', 1);
error_reporting(E_ALL);

echo "<!DOCTYPE html><html><head><meta charset='utf-8'><title>تثبيت API v1</title>";
echo "<style>body{font-family:Arial,sans-serif;max-width:800px;margin:50px auto;padding:20px;direction:rtl;}";
echo ".success{color:green;padding:10px;border:1px solid green;background:#e7f7e7;margin:10px 0;}";
echo ".error{color:red;padding:10px;border:1px solid red;background:#ffe7e7;margin:10px 0;}";
echo ".info{color:blue;padding:10px;border:1px solid blue;background:#e7f0ff;margin:10px 0;}";
echo "pre{background:#f4f4f4;padding:10px;border-radius:4px;overflow:auto;}";
echo "</style></head><body>";

echo "<h1>🚀 تثبيت وإعداد API v1</h1>";

// قائمة ملفات Migration
$migrations = [
    '001_add_sync_tables.sql' => 'إنشاء الجداول الناقصة (expense_categories, shift_notes, daily_closures)',
    '002_add_sync_fields.sql' => 'إضافة حقول التزامن (local_uuid, updated_at, deleted_at)',
    '003_add_new_fields.sql' => 'إضافة الحقول الجديدة المطلوبة للتطبيق'
];

$migrationsPath = __DIR__ . '/../../sql/migrations/';

echo "<div class='info'>";
echo "<h3>📋 سيتم تطبيق التحديثات التالية:</h3>";
echo "<ul>";
foreach ($migrations as $file => $desc) {
    echo "<li><strong>$file</strong>: $desc</li>";
}
echo "</ul>";
echo "</div>";

$allSuccess = true;
$results = [];

try {
    // تعطيل فحص المفاتيح الخارجية مؤقتاً
    $conn->query("SET FOREIGN_KEY_CHECKS = 0");
    
    foreach ($migrations as $file => $desc) {
        $filePath = $migrationsPath . $file;
        
        if (!file_exists($filePath)) {
            $results[] = [
                'file' => $file,
                'status' => 'error',
                'message' => "الملف غير موجود: $filePath"
            ];
            $allSuccess = false;
            continue;
        }
        
        // قراءة محتوى الملف
        $sql = file_get_contents($filePath);
        
        if (empty($sql)) {
            $results[] = [
                'file' => $file,
                'status' => 'error',
                'message' => 'الملف فارغ'
            ];
            $allSuccess = false;
            continue;
        }
        
        // تقسيم الاستعلامات
        $queries = array_filter(
            array_map('trim', explode(';', $sql)),
            function($q) {
                // تجاهل التعليقات والأسطر الفارغة
                return !empty($q) && 
                       !preg_match('/^--/', $q) && 
                       !preg_match('/^\/\*/', $q) &&
                       strtoupper(trim($q)) !== 'DELIMITER $$' &&
                       strtoupper(trim($q)) !== 'DELIMITER ;';
            }
        );
        
        $executed = 0;
        $errors = [];
        
        foreach ($queries as $query) {
            $query = trim($query);
            if (empty($query)) continue;
            
            // تخطي أوامر USE و DELIMITER
            if (preg_match('/^(USE|DELIMITER)/i', $query)) {
                continue;
            }
            
            try {
                // محاولة تنفيذ multi_query للدعم الكامل
                if ($conn->multi_query($query . ';')) {
                    do {
                        if ($result = $conn->store_result()) {
                            $result->free();
                        }
                    } while ($conn->more_results() && $conn->next_result());
                    $executed++;
                } else {
                    // إذا فشل multi_query، جرب query عادي
                    if ($conn->query($query)) {
                        $executed++;
                    } else {
                        // تجاهل بعض الأخطاء المتوقعة
                        if (strpos($conn->error, 'Duplicate column') === false &&
                            strpos($conn->error, 'already exists') === false &&
                            strpos($conn->error, 'Multiple primary key') === false) {
                            $errors[] = $conn->error;
                        } else {
                            $executed++; // نعتبره نجاح (الحقل موجود مسبقاً)
                        }
                    }
                }
            } catch (Exception $e) {
                if (strpos($e->getMessage(), 'Duplicate column') === false &&
                    strpos($e->getMessage(), 'already exists') === false) {
                    $errors[] = $e->getMessage();
                }
            }
        }
        
        if (empty($errors)) {
            $results[] = [
                'file' => $file,
                'status' => 'success',
                'message' => "تم تطبيق $executed استعلام بنجاح"
            ];
        } else {
            $results[] = [
                'file' => $file,
                'status' => 'partial',
                'message' => "تم تطبيق $executed استعلام مع " . count($errors) . " خطأ",
                'errors' => $errors
            ];
            $allSuccess = false;
        }
    }
    
    // إعادة تفعيل فحص المفاتيح الخارجية
    $conn->query("SET FOREIGN_KEY_CHECKS = 1");
    
} catch (Exception $e) {
    echo "<div class='error'>";
    echo "<h3>❌ خطأ عام:</h3>";
    echo "<p>" . htmlspecialchars($e->getMessage()) . "</p>";
    echo "</div>";
    $allSuccess = false;
}

// عرض النتائج
echo "<h2>📊 نتائج التثبيت</h2>";

foreach ($results as $result) {
    $class = $result['status'] === 'success' ? 'success' : ($result['status'] === 'error' ? 'error' : 'info');
    $icon = $result['status'] === 'success' ? '✅' : ($result['status'] === 'error' ? '❌' : '⚠️');
    
    echo "<div class='$class'>";
    echo "<h4>$icon {$result['file']}</h4>";
    echo "<p>{$result['message']}</p>";
    
    if (isset($result['errors']) && !empty($result['errors'])) {
        echo "<details><summary>عرض الأخطاء</summary><pre>";
        foreach ($result['errors'] as $error) {
            echo htmlspecialchars($error) . "\n";
        }
        echo "</pre></details>";
    }
    echo "</div>";
}

// التحقق من نجاح التثبيت
if ($allSuccess) {
    echo "<div class='success'>";
    echo "<h2>🎉 تم التثبيت بنجاح!</h2>";
    echo "<p>API v1 جاهز للاستخدام الآن.</p>";
    echo "<h3>الخطوات التالية:</h3>";
    echo "<ol>";
    echo "<li>قم بتحديث <code>mobile/lib/utils/env.dart</code> بعنوان API الصحيح</li>";
    echo "<li>قم بتسجيل الدخول عبر <code>/api/v1/auth/login.php</code></li>";
    echo "<li>ابدأ استخدام التزامن عبر <code>/api/v1/sync/pull.php</code> و <code>/api/v1/sync/push.php</code></li>";
    echo "</ol>";
    echo "<p><strong>نقطة البداية:</strong> <a href='../README.md'>اقرأ التوثيق الكامل</a></p>";
    echo "</div>";
} else {
    echo "<div class='error'>";
    echo "<h2>⚠️ التثبيت مكتمل مع بعض الأخطاء</h2>";
    echo "<p>راجع الأخطاء أعلاه وقم بتصحيحها يدوياً إذا لزم الأمر.</p>";
    echo "</div>";
}

// عرض معلومات النظام
echo "<div class='info'>";
echo "<h3>ℹ️ معلومات النظام</h3>";
echo "<pre>";
echo "PHP Version: " . PHP_VERSION . "\n";
echo "MySQL Version: " . $conn->server_info . "\n";
echo "Database: " . DB_NAME . "\n";
echo "Character Set: " . $conn->character_set_name() . "\n";
echo "Time: " . date('Y-m-d H:i:s') . "\n";
echo "</pre>";
echo "</div>";

echo "</body></html>";
