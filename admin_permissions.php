<?php
/**
 * إصلاح صلاحيات المدير
 * يقوم بتحديث صلاحيات المستخدم admin لإعطائه جميع الصلاحيات
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
    
    echo "<h2>إصلاح صلاحيات المدير</h2>";
    
    // تحديث نوع المستخدم admin إلى admin
    $stmt = $conn->prepare("UPDATE users SET user_type = 'admin' WHERE username = 'admin'");
    
    if ($stmt->execute()) {
        if ($stmt->affected_rows > 0) {
            echo "<p style='color: green;'>✓ تم تحديث صلاحيات المدير بنجاح!</p>";
        } else {
            echo "<p style='color: orange;'>المستخدم admin موجود بالفعل بصلاحيات صحيحة</p>";
        }
    } else {
        echo "<p style='color: red;'>خطأ في تحديث الصلاحيات: " . $stmt->error . "</p>";
    }
    
    $stmt->close();
    
    // عرض جميع المستخدمين وصلاحياتهم
    echo "<h3>المستخدمون وصلاحياتهم:</h3>";
    $result = $conn->query("SELECT username, user_type, full_name, is_active FROM users ORDER BY user_type, username");
    
    if ($result && $result->num_rows > 0) {
        echo "<table style='border-collapse: collapse; width: 100%; margin: 20px 0;'>";
        echo "<tr style='background: #f8f9fa;'>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>اسم المستخدم</th>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>النوع</th>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>الاسم الكامل</th>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>الحالة</th>";
        echo "<th style='border: 1px solid #ddd; padding: 10px; text-align: right;'>الصلاحيات</th>";
        echo "</tr>";
        
        while ($row = $result->fetch_assoc()) {
            $status_color = $row['is_active'] ? 'green' : 'red';
            $status_text = $row['is_active'] ? 'نشط' : 'غير نشط';
            
            // تحديد الصلاحيات حسب النوع
            $permissions = '';
            switch($row['user_type']) {
                case 'admin':
                    $permissions = 'جميع الصلاحيات';
                    break;
                case 'manager':
                    $permissions = 'إدارة الحجوزات، التقارير، الموظفين';
                    break;
                case 'employee':
                    $permissions = 'الحجوزات الأساسية';
                    break;
                default:
                    $permissions = 'غير محدد';
            }
            
            echo "<tr>";
            echo "<td style='border: 1px solid #ddd; padding: 10px;'>" . htmlspecialchars($row['username']) . "</td>";
            echo "<td style='border: 1px solid #ddd; padding: 10px;'>" . htmlspecialchars($row['user_type']) . "</td>";
            echo "<td style='border: 1px solid #ddd; padding: 10px;'>" . htmlspecialchars($row['full_name']) . "</td>";
            echo "<td style='border: 1px solid #ddd; padding: 10px; color: $status_color;'>$status_text</td>";
            echo "<td style='border: 1px solid #ddd; padding: 10px;'>$permissions</td>";
            echo "</tr>";
        }
        echo "</table>";
    }
    
    $conn->close();
    
} catch (Exception $e) {
    echo "<p style='color: red;'>خطأ: " . $e->getMessage() . "</p>";
}

echo "<div style='margin: 30px 0; text-align: center;'>";
echo "<a href='login.php' style='background: #007bff; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-size: 16px; margin: 10px;'>تسجيل الدخول</a>";
echo "<a href='admin/dash.php' style='background: #28a745; color: white; padding: 15px 30px; text-decoration: none; border-radius: 5px; font-size: 16px; margin: 10px;'>لوحة التحكم</a>";
echo "</div>";

echo "<div style='background: #e9ecef; padding: 15px; border-radius: 5px; margin: 20px 0;'>";
echo "<h4>ملاحظة مهمة:</h4>";
echo "<p>إذا كنت لا تزال تواجه مشاكل في الصلاحيات، تأكد من:</p>";
echo "<ul>";
echo "<li>تسجيل الدخول باستخدام المستخدم 'admin' وكلمة المرور '1234'</li>";
echo "<li>مسح ذاكرة التخزين المؤقت للمتصفح</li>";
echo "<li>تسجيل الخروج وإعادة تسجيل الدخول</li>";
echo "</ul>";
echo "</div>";
?>
