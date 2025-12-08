<?php
/**
 * ملف إعادة تعيين كلمة مرور المدير
 * يقوم بتحديث كلمة مرور المدير إلى 1234
 */

require_once 'includes/config.php';

try {
    // الاتصال بقاعدة البيانات
    $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
    
    if ($conn->connect_error) {
        die("فشل الاتصال: " . $conn->connect_error);
    }
    
    // تعيين الترميز
    $conn->set_charset('utf8mb4');
    
    echo "<h2>إعادة تعيين كلمة مرور المدير</h2>";
    
    // كلمة المرور الجديدة
    $new_password = '1234';
    $password_hash = password_hash($new_password, PASSWORD_DEFAULT);
    
    // تحديث كلمة مرور المدير
    $stmt = $conn->prepare("UPDATE users SET password = ?, password_hash = ? WHERE username = 'admin'");
    $stmt->bind_param("ss", $new_password, $password_hash);
    
    if ($stmt->execute()) {
        if ($stmt->affected_rows > 0) {
            echo "<p style='color: green; font-size: 18px;'>✓ تم تحديث كلمة مرور المدير بنجاح!</p>";
            echo "<div style='background: #d4edda; border: 1px solid #c3e6cb; padding: 15px; border-radius: 5px; margin: 20px 0;'>";
            echo "<h3>بيانات تسجيل الدخول:</h3>";
            echo "<p><strong>اسم المستخدم:</strong> admin</p>";
            echo "<p><strong>كلمة المرور:</strong> 1234</p>";
            echo "</div>";
        } else {
            echo "<p style='color: orange;'>لم يتم العثور على مستخدم بالاسم 'admin'</p>";
            
            // إنشاء مستخدم admin جديد
            $stmt2 = $conn->prepare("INSERT INTO users (username, password, password_hash, user_type, full_name, email, is_active) VALUES ('admin', ?, ?, 'admin', 'مدير النظام', 'admin@marina.com', 1)");
            $stmt2->bind_param("ss", $new_password, $password_hash);
            
            if ($stmt2->execute()) {
                echo "<p style='color: green;'>✓ تم إنشاء مستخدم admin جديد بكلمة المرور: 1234</p>";
            } else {
                echo "<p style='color: red;'>خطأ في إنشاء المستخدم: " . $stmt2->error . "</p>";
            }
            $stmt2->close();
        }
    } else {
        echo "<p style='color: red;'>خطأ في تحديث كلمة المرور: " . $stmt->error . "</p>";
    }
    
    $stmt->close();
    
    // عرض جميع المستخدمين الموجودين
    echo "<h3>المستخدمون الموجودون في النظام:</h3>";
    $result = $conn->query("SELECT username, user_type, full_name, is_active FROM users ORDER BY user_type, username");
    
    if ($result && $result->num_rows > 0) {
        echo "<table style='border-collapse: collapse; width: 100%; margin: 20px 0;'>";
        echo "<tr style='background: #f8f9fa;'>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>اسم المستخدم</th>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>النوع</th>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>الاسم الكامل</th>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>الحالة</th>";
        echo "</tr>";
        
        while ($row = $result->fetch_assoc()) {
            $status_color = $row['is_active'] ? 'green' : 'red';
            $status_text = $row['is_active'] ? 'نشط' : 'غير نشط';
            
            echo "<tr>";
            echo "<td style='border: 1px solid #ddd; padding: 10px;'>" . htmlspecialchars($row['username']) . "</td>";
            echo "<td style='border: 1px solid #ddd; padding: 10px;'>" . htmlspecialchars($row['user_type']) . "</td>";
            echo "<td style='border: 1px solid #ddd; padding: 10px;'>" . htmlspecialchars($row['full_name']) . "</td>";
            echo "<td style='border: 1px solid #ddd; padding: 10px; color: $status_color;'>$status_text</td>";
            echo "</tr>";
        }
        echo "</table>";
    } else {
        echo "<p style='color: red;'>لا توجد مستخدمين في النظام</p>";
    }
    
    $conn->close();
    
} catch (Exception $e) {
    echo "<p style='color: red;'>خطأ: " . $e->getMessage() . "</p>";
}

echo "<div style='margin: 30px 0; text-align: center;'>";
echo "<a href='login.php' style='background: #007bff; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-size: 16px; margin: 10px;'>تسجيل الدخول</a>";
echo "<a href='index.php' style='background: #28a745; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-size: 16px; margin: 10px;'>الصفحة الرئيسية</a>";
echo "</div>";
?>
