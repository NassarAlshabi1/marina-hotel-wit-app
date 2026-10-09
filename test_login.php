<?php
/**
 * سكريبت اختبار تسجيل الدخول
 * يقوم بفحص إعدادات قاعدة البيانات وجدول المستخدمين
 */

require_once 'includes/config.php';
require_once 'includes/db.php';

echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>اختبار نظام تسجيل الدخول</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; direction: rtl; }
        .success { color: green; background: #d4edda; padding: 10px; margin: 10px 0; border-radius: 5px; }
        .error { color: red; background: #f8d7da; padding: 10px; margin: 10px 0; border-radius: 5px; }
        .info { color: blue; background: #d1ecf1; padding: 10px; margin: 10px 0; border-radius: 5px; }
        .warning { color: orange; background: #fff3cd; padding: 10px; margin: 10px 0; border-radius: 5px; }
        table { border-collapse: collapse; width: 100%; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: right; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>";

echo "<h1>اختبار نظام تسجيل الدخول</h1>";

try {
    // اختبار الاتصال بقاعدة البيانات
    echo "<h2>1. اختبار الاتصال بقاعدة البيانات</h2>";
    if ($conn->ping()) {
        echo "<div class='success'>✅ الاتصال بقاعدة البيانات ناجح</div>";
        echo "<div class='info'>خادم قاعدة البيانات: " . DB_HOST . "</div>";
        echo "<div class='info'>اسم قاعدة البيانات: " . DB_NAME . "</div>";
        echo "<div class='info'>إصدار MySQL: " . $conn->server_info . "</div>";
    } else {
        echo "<div class='error'>❌ فشل الاتصال بقاعدة البيانات</div>";
        exit;
    }

    // التحقق من وجود جدول المستخدمين
    echo "<h2>2. التحقق من جدول المستخدمين</h2>";
    $check_table = $conn->query("SHOW TABLES LIKE 'users'");
    if ($check_table && $check_table->num_rows > 0) {
        echo "<div class='success'>✅ جدول المستخدمين موجود</div>";
        
        // عرض هيكل الجدول
        echo "<h3>هيكل جدول المستخدمين:</h3>";
        $structure = $conn->query("DESCRIBE users");
        echo "<table>";
        echo "<tr><th>اسم العمود</th><th>النوع</th><th>Null</th><th>Key</th><th>Default</th><th>Extra</th></tr>";
        while ($row = $structure->fetch_assoc()) {
            echo "<tr>";
            echo "<td>" . $row['Field'] . "</td>";
            echo "<td>" . $row['Type'] . "</td>";
            echo "<td>" . $row['Null'] . "</td>";
            echo "<td>" . $row['Key'] . "</td>";
            echo "<td>" . ($row['Default'] ?: 'NULL') . "</td>";
            echo "<td>" . $row['Extra'] . "</td>";
            echo "</tr>";
        }
        echo "</table>";
        
    } else {
        echo "<div class='error'>❌ جدول المستخدمين غير موجود</div>";
        echo "<div class='warning'>يرجى تشغيل update_users_table.php أولاً</div>";
        exit;
    }

    // عرض المستخدمين الموجودين
    echo "<h2>3. المستخدمين الموجودين</h2>";
    $users_result = $conn->query("SELECT user_id, username, full_name, user_type, is_active, 
                                         CASE 
                                             WHEN password_hash IS NOT NULL AND password_hash != '' THEN 'مشفرة' 
                                             WHEN password IS NOT NULL AND password != '' THEN 'غير مشفرة'
                                             ELSE 'غير محددة'
                                         END as password_status,
                                         last_login, created_at 
                                  FROM users ORDER BY user_id");
    
    if ($users_result && $users_result->num_rows > 0) {
        echo "<table>";
        echo "<tr><th>ID</th><th>اسم المستخدم</th><th>الاسم الكامل</th><th>النوع</th><th>الحالة</th><th>حالة كلمة المرور</th><th>آخر دخول</th></tr>";
        
        while ($user = $users_result->fetch_assoc()) {
            $status_color = $user['is_active'] ? 'green' : 'red';
            $password_color = $user['password_status'] == 'مشفرة' ? 'green' : ($user['password_status'] == 'غير مشفرة' ? 'orange' : 'red');
            
            echo "<tr>";
            echo "<td>" . $user['user_id'] . "</td>";
            echo "<td><strong>" . htmlspecialchars($user['username']) . "</strong></td>";
            echo "<td>" . htmlspecialchars($user['full_name']) . "</td>";
            echo "<td>" . htmlspecialchars($user['user_type']) . "</td>";
            echo "<td style='color: $status_color;'>" . ($user['is_active'] ? 'نشط' : 'غير نشط') . "</td>";
            echo "<td style='color: $password_color;'>" . $user['password_status'] . "</td>";
            echo "<td>" . ($user['last_login'] ?: 'لم يسجل دخول') . "</td>";
            echo "</tr>";
        }
        echo "</table>";
    } else {
        echo "<div class='error'>❌ لا توجد مستخدمين في النظام</div>";
    }

    // اختبار تسجيل الدخول
    echo "<h2>4. اختبار تسجيل الدخول</h2>";
    
    // اختبار المستخدم admin
    $test_username = 'admin';
    $test_password = '1234';
    
    echo "<div class='info'>اختبار تسجيل الدخول للمستخدم: $test_username</div>";
    
    $stmt = $conn->prepare("SELECT user_id, username, password, password_hash, user_type, is_active FROM users WHERE username = ? AND is_active = 1");
    if ($stmt) {
        $stmt->bind_param("s", $test_username);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows === 1) {
            $user = $result->fetch_assoc();
            echo "<div class='success'>✅ تم العثور على المستخدم</div>";
            
            // اختبار كلمة المرور
            $password_valid = false;
            
            if (!empty($user['password_hash'])) {
                $password_valid = password_verify($test_password, $user['password_hash']);
                echo "<div class='info'>اختبار كلمة المرور المشفرة: " . ($password_valid ? "✅ صحيحة" : "❌ خاطئة") . "</div>";
            } elseif (!empty($user['password'])) {
                $password_valid = ($test_password === $user['password']);
                echo "<div class='info'>اختبار كلمة المرور غير المشفرة: " . ($password_valid ? "✅ صحيحة" : "❌ خاطئة") . "</div>";
            }
            
            if ($password_valid) {
                echo "<div class='success'>🎉 تسجيل الدخول سيعمل بشكل صحيح!</div>";
            } else {
                echo "<div class='error'>❌ كلمة المرور غير صحيحة</div>";
            }
            
        } else {
            echo "<div class='error'>❌ لم يتم العثور على المستخدم أو المستخدم غير نشط</div>";
        }
        $stmt->close();
    }

    // التحقق من ملفات النظام المطلوبة
    echo "<h2>5. التحقق من ملفات النظام</h2>";
    $required_files = [
        'includes/config.php' => 'ملف الإعدادات',
        'includes/db.php' => 'ملف الاتصال بقاعدة البيانات',
        'includes/security.php' => 'ملف الأمان',
        'admin/dash.php' => 'لوحة التحكم'
    ];
    
    foreach ($required_files as $file => $description) {
        if (file_exists($file)) {
            echo "<div class='success'>✅ $description موجود</div>";
        } else {
            echo "<div class='error'>❌ $description غير موجود: $file</div>";
        }
    }

    echo "<h2>6. تعليمات تسجيل الدخول</h2>";
    echo "<div class='info'>";
    echo "<strong>لتسجيل الدخول:</strong><br>";
    echo "1. انتقل إلى صفحة تسجيل الدخول: <a href='login.php'>login.php</a><br>";
    echo "2. استخدم البيانات التالية:<br>";
    echo "   - اسم المستخدم: admin<br>";
    echo "   - كلمة المرور: 1234<br>";
    echo "3. إذا لم تعمل، قم بتشغيل: <a href='update_users_table.php?confirm=yes'>update_users_table.php</a><br>";
    echo "</div>";

} catch (Exception $e) {
    echo "<div class='error'>❌ حدث خطأ: " . htmlspecialchars($e->getMessage()) . "</div>";
}

echo "</body></html>";
?>
