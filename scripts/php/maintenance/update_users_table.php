<?php

require_once dirname(__DIR__) . '/bootstrap.php';
/**
 * سكريبت تحديث جدول المستخدمين
 * يقوم بإضافة الأعمدة الأمنية المطلوبة وتشفير كلمات المرور الموجودة
 */

require_once 'includes/config.php';
require_once 'includes/db.php';

// التحقق من الوصول المباشر
if (!isset($_GET['confirm']) || $_GET['confirm'] !== 'yes') {
    die('للتأكيد على تحديث قاعدة البيانات، يرجى إضافة ?confirm=yes إلى الرابط');
}

echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>تحديث جدول المستخدمين</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; direction: rtl; }
        .success { color: green; background: #d4edda; padding: 10px; margin: 10px 0; border-radius: 5px; }
        .error { color: red; background: #f8d7da; padding: 10px; margin: 10px 0; border-radius: 5px; }
        .info { color: blue; background: #d1ecf1; padding: 10px; margin: 10px 0; border-radius: 5px; }
        .warning { color: orange; background: #fff3cd; padding: 10px; margin: 10px 0; border-radius: 5px; }
    </style>
</head>
<body>";

echo "<h1>تحديث جدول المستخدمين</h1>";

try {
    // التحقق من وجود جدول المستخدمين
    $check_table = $conn->query("SHOW TABLES LIKE 'users'");
    if (!$check_table || $check_table->num_rows == 0) {
        echo "<div class='error'>❌ جدول المستخدمين غير موجود!</div>";
        exit;
    }

    echo "<div class='info'>✅ تم العثور على جدول المستخدمين</div>";

    // التحقق من الأعمدة الموجودة
    $columns_result = $conn->query("DESCRIBE users");
    $existing_columns = [];
    while ($row = $columns_result->fetch_assoc()) {
        $existing_columns[] = $row['Field'];
    }

    echo "<div class='info'>الأعمدة الموجودة: " . implode(', ', $existing_columns) . "</div>";

    // إضافة عمود password_hash إذا لم يكن موجوداً
    if (!in_array('password_hash', $existing_columns)) {
        echo "<div class='info'>🔄 إضافة عمود password_hash...</div>";
        $conn->query("ALTER TABLE users ADD COLUMN password_hash VARCHAR(255) AFTER password");
        echo "<div class='success'>✅ تم إضافة عمود password_hash</div>";
    } else {
        echo "<div class='info'>✅ عمود password_hash موجود بالفعل</div>";
    }

    // إضافة الأعمدة الأمنية المطلوبة
    $security_columns = [
        'failed_login_attempts' => 'INT DEFAULT 0',
        'locked_until' => 'TIMESTAMP NULL',
        'password_reset_token' => 'VARCHAR(255) NULL',
        'password_reset_expires' => 'TIMESTAMP NULL'
    ];

    foreach ($security_columns as $column => $definition) {
        if (!in_array($column, $existing_columns)) {
            echo "<div class='info'>🔄 إضافة عمود $column...</div>";
            $conn->query("ALTER TABLE users ADD COLUMN $column $definition");
            echo "<div class='success'>✅ تم إضافة عمود $column</div>";
        } else {
            echo "<div class='info'>✅ عمود $column موجود بالفعل</div>";
        }
    }

    // تحديث كلمات المرور غير المشفرة
    echo "<div class='info'>🔄 البحث عن كلمات المرور غير المشفرة...</div>";
    
    $users_result = $conn->query("SELECT user_id, username, password, password_hash FROM users");
    $updated_count = 0;
    
    while ($user = $users_result->fetch_assoc()) {
        // إذا كان password_hash فارغ أو null، نقوم بتشفير كلمة المرور
        if (empty($user['password_hash']) && !empty($user['password'])) {
            $hashed_password = password_hash($user['password'], PASSWORD_DEFAULT);
            
            $update_stmt = $conn->prepare("UPDATE users SET password_hash = ? WHERE user_id = ?");
            $update_stmt->bind_param("si", $hashed_password, $user['user_id']);
            
            if ($update_stmt->execute()) {
                echo "<div class='success'>✅ تم تشفير كلمة المرور للمستخدم: " . htmlspecialchars($user['username']) . "</div>";
                $updated_count++;
            } else {
                echo "<div class='error'>❌ فشل تشفير كلمة المرور للمستخدم: " . htmlspecialchars($user['username']) . "</div>";
            }
            $update_stmt->close();
        }
    }

    if ($updated_count == 0) {
        echo "<div class='info'>✅ جميع كلمات المرور مشفرة بالفعل</div>";
    } else {
        echo "<div class='success'>✅ تم تشفير $updated_count كلمة مرور</div>";
    }

    // إضافة فهارس للأداء
    echo "<div class='info'>🔄 إضافة الفهارس...</div>";
    
    $indexes = [
        "CREATE INDEX IF NOT EXISTS idx_username ON users(username)",
        "CREATE INDEX IF NOT EXISTS idx_user_type ON users(user_type)",
        "CREATE INDEX IF NOT EXISTS idx_is_active ON users(is_active)",
        "CREATE INDEX IF NOT EXISTS idx_password_reset_token ON users(password_reset_token)"
    ];

    foreach ($indexes as $index_sql) {
        try {
            $conn->query($index_sql);
        } catch (Exception $e) {
            // تجاهل الأخطاء إذا كان الفهرس موجود بالفعل
        }
    }
    echo "<div class='success'>✅ تم إضافة الفهارس</div>";

    // عرض معلومات المستخدمين المحدثة
    echo "<h2>معلومات المستخدمين المحدثة:</h2>";
    $users_result = $conn->query("SELECT user_id, username, full_name, user_type, is_active, 
                                         CASE WHEN password_hash IS NOT NULL AND password_hash != '' THEN 'مشفرة' ELSE 'غير مشفرة' END as password_status,
                                         created_at, last_login 
                                  FROM users ORDER BY user_id");
    
    echo "<table border='1' style='border-collapse: collapse; width: 100%;'>";
    echo "<tr style='background: #f0f0f0;'>
            <th>ID</th>
            <th>اسم المستخدم</th>
            <th>الاسم الكامل</th>
            <th>النوع</th>
            <th>الحالة</th>
            <th>حالة كلمة المرور</th>
            <th>تاريخ الإنشاء</th>
            <th>آخر دخول</th>
          </tr>";
    
    while ($user = $users_result->fetch_assoc()) {
        $status_color = $user['is_active'] ? 'green' : 'red';
        $password_color = $user['password_status'] == 'مشفرة' ? 'green' : 'red';
        
        echo "<tr>";
        echo "<td>" . $user['user_id'] . "</td>";
        echo "<td>" . htmlspecialchars($user['username']) . "</td>";
        echo "<td>" . htmlspecialchars($user['full_name']) . "</td>";
        echo "<td>" . htmlspecialchars($user['user_type']) . "</td>";
        echo "<td style='color: $status_color;'>" . ($user['is_active'] ? 'نشط' : 'غير نشط') . "</td>";
        echo "<td style='color: $password_color;'>" . $user['password_status'] . "</td>";
        echo "<td>" . $user['created_at'] . "</td>";
        echo "<td>" . ($user['last_login'] ?: 'لم يسجل دخول') . "</td>";
        echo "</tr>";
    }
    echo "</table>";

    echo "<div class='success'><h2>✅ تم تحديث جدول المستخدمين بنجاح!</h2></div>";
    echo "<div class='info'>يمكنك الآن تسجيل الدخول باستخدام:<br>";
    echo "- اسم المستخدم: admin<br>";
    echo "- كلمة المرور: 1234</div>";

} catch (Exception $e) {
    echo "<div class='error'>❌ حدث خطأ: " . htmlspecialchars($e->getMessage()) . "</div>";
    error_log("خطأ في تحديث جدول المستخدمين: " . $e->getMessage());
}

echo "</body></html>";
?>
