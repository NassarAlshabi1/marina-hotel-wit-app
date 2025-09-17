<?php
session_start();
require_once '../../includes/db.php';

// التحقق من صلاحيات المستخدم
require_once '../../includes/auth_check_finance.php';
if (!check_system_tools_permission()) {
    header("Location: ../../index.php?error=ليس لديك صلاحية للوصول إلى هذه الصفحة");
    exit();
}

// إعداد الصفحة
echo "<!DOCTYPE html>
<html dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>نسخ احتياطي لقاعدة البيانات</title>
    <style>
        body { font-family: 'Tajawal', sans-serif; padding: 20px; }
        h1, h2 { color: #333; }
        .success { color: green; }
        .error { color: red; }
        .warning { color: orange; }
        pre { background-color: #f5f5f5; padding: 10px; border-radius: 5px; overflow: auto; }
        .btn { display: inline-block; padding: 10px 15px; background-color: #4CAF50; color: white; 
               text-decoration: none; border-radius: 5px; margin: 5px; border: none; cursor: pointer; }
        .btn-warning { background-color: #ff9800; }
    </style>
</head>
<body>
    <h1>نسخ احتياطي لقاعدة البيانات</h1>";

// تسجيل الإجراء في سجل النظام
function log_action($conn, $action, $details) {
    $query = "INSERT INTO system_logs (action, details, user_id, created_at) 
              VALUES (?, ?, ?, NOW())";
    $stmt = $conn->prepare($query);
    $user_id = $_SESSION['user_id'] ?? 0;
    $stmt->bind_param("ssi", $action, $details, $user_id);
    $stmt->execute();
}

// إنشاء مجلد للنسخ الاحتياطية إذا لم يكن موجودًا
$backup_dir = '../../backups';
if (!file_exists($backup_dir)) {
    if (!mkdir($backup_dir, 0755, true)) {
        echo "<p class='error'>❌ فشل في إنشاء مجلد النسخ الاحتياطية.</p>";
        exit;
    }
}

// إنشاء ملف .htaccess لحماية مجلد النسخ الاحتياطية
$htaccess_file = $backup_dir . '/.htaccess';
if (!file_exists($htaccess_file)) {
    $htaccess_content = "Order deny,allow\nDeny from all\n";
    file_put_contents($htaccess_file, $htaccess_content);
}

// إنشاء نسخة احتياطية
if (isset($_POST['create_backup'])) {
    $timestamp = date('Y-m-d_H-i-s');
    $backup_file = $backup_dir . '/backup_' . $timestamp . '.sql';
    
    // الحصول على قائمة الجداول
    $tables = [];
    $result = $conn->query("SHOW TABLES");
    while ($row = $result->fetch_row()) {
        $tables[] = $row[0];
    }
    
    if (empty($tables)) {
        echo "<p class='error'>❌ لم يتم العثور على جداول في قاعدة البيانات.</p>";
    } else {
        // بدء محتوى ملف النسخ الاحتياطي
        $sql = "-- نسخة احتياطية لقاعدة بيانات " . DB_NAME . "\n";
        $sql .= "-- تاريخ: " . date('Y-m-d H:i:s') . "\n";
        $sql .= "-- خادم: " . DB_HOST . "\n\n";
        $sql .= "SET SQL_MODE = \"NO_AUTO_VALUE_ON_ZERO\";\n";
        $sql .= "SET time_zone = \"+00:00\";\n\n";
        
        // إنشاء نسخة احتياطية لكل جدول
        foreach ($tables as $table) {
            // الحصول على هيكل الجدول
            $result = $conn->query("SHOW CREATE TABLE `$table`");
            $row = $result->fetch_row();
            $sql .= "\n-- --------------------------------------------------------\n";
            $sql .= "\n-- هيكل جدول `$table`\n\n";
            $sql .= "DROP TABLE IF EXISTS `$table`;\n";
            $sql .= $row[1] . ";\n\n";
            
            // الحصول على بيانات الجدول
            $result = $conn->query("SELECT * FROM `$table`");
            if ($result->num_rows > 0) {
                $sql .= "\n-- بيانات جدول `$table`\n\n";
                $sql .= "INSERT INTO `$table` VALUES\n";
                
                $first_row = true;
                while ($row = $result->fetch_row()) {
                    if (!$first_row) {
                        $sql .= ",\n";
                    } else {
                        $first_row = false;
                    }
                    
                    $sql .= "(";
                    for ($i = 0; $i < count($row); $i++) {
                        if ($i > 0) {
                            $sql .= ", ";
                        }
                        if ($row[$i] === null) {
                            $sql .= "NULL";
                        } else {
                            $sql .= "'" . $conn->real_escape_string($row[$i]) . "'";
                        }
                    }
                    $sql .= ")";
                }
                $sql .= ";\n";
            }
        }
        
        // حفظ ملف النسخ الاحتياطي
        if (file_put_contents($backup_file, $sql)) {
            echo "<p class='success'>✅ تم إنشاء النسخة الاحتياطية بنجاح.</p>";
            echo "<p>اسم الملف: " . basename($backup_file) . "</p>";
            echo "<p>حجم الملف: " . round(filesize($backup_file) / 1024, 2) . " كيلوبايت</p>";
            
            // تسجيل الإجراء
            log_action($conn, "create_backup", "تم إنشاء نسخة احتياطية: " . basename($backup_file));
        } else {
            echo "<p class='error'>❌ فشل في حفظ ملف النسخة الاحتياطية.</p>";
        }
    }
}

// عرض النسخ الاحتياطية الموجودة
echo "<h2>النسخ الاحتياطية الموجودة:</h2>";
$backup_files = glob($backup_dir . '/backup_*.sql');
if (empty($backup_files)) {
    echo "<p>لا توجد نسخ احتياطية.</p>";
} else {
    echo "<table border='1' style='width:100%;border-collapse:collapse;'>";
    echo "<tr><th>اسم الملف</th><th>تاريخ الإنشاء</th><th>الحجم</th><th>الإجراءات</th></tr>";
    
    foreach ($backup_files as $file) {
        $filename = basename($file);
        $created = date('Y-m-d H:i:s', filemtime($file));
        $size = round(filesize($file) / 1024, 2) . " كيلوبايت";
        
        echo "<tr>";
        echo "<td>$filename</td>";
        echo "<td>$created</td>";
        echo "<td>$size</td>";
        echo "<td>";
        echo "<form method='post' style='display:inline;'>";
        echo "<input type='hidden' name='file' value='$filename'>";
        echo "<button type='submit' name='download_backup' class='btn'>تحميل</button>";
        echo "<button type='submit' name='delete_backup' class='btn btn-warning' onclick='return confirm(\"هل أنت متأكد من حذف هذه النسخة الاحتياطية؟\")'>حذف</button>";
        echo "</form>";
        echo "</td>";
        echo "</tr>";
    }
    
    echo "</table>";
}

// تحميل نسخة احتياطية
if (isset($_POST['download_backup']) && isset($_POST['file'])) {
    $filename = $_POST['file'];
    $file_path = $backup_dir . '/' . $filename;
    
    if (file_exists($file_path) && is_file($file_path)) {
        // تسجيل الإجراء
        log_action($conn, "download_backup", "تم تحميل نسخة احتياطية: $filename");
        
        // إرسال الملف للتحميل
        header('Content-Description: File Transfer');
        header('Content-Type: application/octet-stream');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Expires: 0');
        header('Cache-Control: must-revalidate');
        header('Pragma: public');
        header('Content-Length: ' . filesize($file_path));
        readfile($file_path);
        exit;
    }
}

// حذف نسخة احتياطية
if (isset($_POST['delete_backup']) && isset($_POST['file'])) {
    $filename = $_POST['file'];
    $file_path = $backup_dir . '/' . $filename;
    
    if (file_exists($file_path) && is_file($file_path)) {
        if (unlink($file_path)) {
            // تسجيل الإجراء
            log_action($conn, "delete_backup", "تم حذف نسخة احتياطية: $filename");
            
            echo "<p class='success'>✅ تم حذف النسخة الاحتياطية بنجاح.</p>";
            echo "<script>window.location.href = window.location.pathname;</script>";
        } else {
            echo "<p class='error'>❌ فشل في حذف النسخة الاحتياطية.</p>";
        }
    }
}

// نموذج إنشاء نسخة احتياطية جديدة
echo "<h2>إنشاء نسخة احتياطية جديدة:</h2>";
echo "<form method='post'>";
echo "<button type='submit' name='create_backup' class='btn'>إنشاء نسخة احتياطية جديدة</button>";
echo "</form>";

// زر العودة
echo "<p><a href='../index.php' class='btn' style='background-color:#2196F3;'>العودة إلى لوحة التحكم</a></p>";

echo "</body></html>";
?>