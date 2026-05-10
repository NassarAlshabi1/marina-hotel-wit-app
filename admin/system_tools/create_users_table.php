<?php
/**
 * إنشاء جدول المستخدمين ونظام الصلاحيات
 */

require_once '../../includes/db.php';
require_once '../../includes/auth.php';

// التحقق من صلاحيات المدير
if (!isset($_SESSION['user_type']) || $_SESSION['user_type'] !== 'admin') {
    die("ليس لديك صلاحية للوصول إلى هذه الصفحة");
}

echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>إنشاء جداول النظام</title>
    <style>
        body { font-family: 'Tajawal', Arial, sans-serif; margin: 20px; }
        .success { color: green; background: #d4edda; padding: 10px; border-radius: 5px; margin: 10px 0; }
        .error { color: red; background: #f8d7da; padding: 10px; border-radius: 5px; margin: 10px 0; }
        .info { color: blue; background: #d1ecf1; padding: 10px; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>";

echo "<h1>إنشاء جداول النظام</h1>";

try {
    // إنشاء جدول المستخدمين
    $create_users_table = "
    CREATE TABLE IF NOT EXISTS users (
        user_id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password_hash VARCHAR(255),
        user_type ENUM('admin', 'manager', 'employee', 'receptionist') DEFAULT 'employee',
        full_name VARCHAR(100) NOT NULL,
        email VARCHAR(100),
        phone VARCHAR(20),
        is_active TINYINT(1) DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        last_login TIMESTAMP NULL,
        failed_login_attempts INT DEFAULT 0,
        locked_until TIMESTAMP NULL,
        INDEX idx_username (username),
        INDEX idx_user_type (user_type),
        INDEX idx_is_active (is_active)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    if ($conn->query($create_users_table)) {
        echo "<div class='success'>✅ تم إنشاء جدول المستخدمين بنجاح</div>";
    } else {
        echo "<div class='error'>❌ خطأ في إنشاء جدول المستخدمين: " . $conn->error . "</div>";
    }
    
    // إنشاء جدول الصلاحيات
    $create_permissions_table = "
    CREATE TABLE IF NOT EXISTS permissions (
        permission_id INT AUTO_INCREMENT PRIMARY KEY,
        permission_code VARCHAR(50) UNIQUE NOT NULL,
        permission_name VARCHAR(100) NOT NULL,
        description TEXT,
        category VARCHAR(50) DEFAULT 'general',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_permission_code (permission_code),
        INDEX idx_category (category)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    if ($conn->query($create_permissions_table)) {
        echo "<div class='success'>✅ تم إنشاء جدول الصلاحيات بنجاح</div>";
    } else {
        echo "<div class='error'>❌ خطأ في إنشاء جدول الصلاحيات: " . $conn->error . "</div>";
    }
    
    // إنشاء جدول ربط المستخدمين بالصلاحيات
    $create_user_permissions_table = "
    CREATE TABLE IF NOT EXISTS user_permissions (
        user_id INT,
        permission_id INT,
        granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        granted_by INT,
        PRIMARY KEY (user_id, permission_id),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        FOREIGN KEY (permission_id) REFERENCES permissions(permission_id) ON DELETE CASCADE,
        FOREIGN KEY (granted_by) REFERENCES users(user_id) ON DELETE SET NULL,
        INDEX idx_user_id (user_id),
        INDEX idx_permission_id (permission_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    if ($conn->query($create_user_permissions_table)) {
        echo "<div class='success'>✅ تم إنشاء جدول صلاحيات المستخدمين بنجاح</div>";
    } else {
        echo "<div class='error'>❌ خطأ في إنشاء جدول صلاحيات المستخدمين: " . $conn->error . "</div>";
    }
    
    // إدراج المستخدم الافتراضي (admin)
    $check_admin = $conn->query("SELECT COUNT(*) as count FROM users WHERE username = 'admin'");
    if ($check_admin && $check_admin->fetch_assoc()['count'] == 0) {
        $admin_password = password_hash('1234', PASSWORD_DEFAULT);
        $insert_admin = "INSERT INTO users (username, password_hash, user_type, full_name, email) 
                        VALUES ('admin', ?, 'admin', 'مدير النظام', 'admin@hotel.com')";
        
        $stmt = $conn->prepare($insert_admin);
        $stmt->bind_param("s", $admin_password);
        
        if ($stmt->execute()) {
            echo "<div class='success'>✅ تم إنشاء المستخدم الافتراضي (admin) بنجاح</div>";
        } else {
            echo "<div class='error'>❌ خطأ في إنشاء المستخدم الافتراضي: " . $conn->error . "</div>";
        }
        $stmt->close();
    } else {
        echo "<div class='info'>ℹ️ المستخدم الافتراضي (admin) موجود بالفعل</div>";
    }
    
    // إدراج الصلاحيات الأساسية
    $basic_permissions = [
        ['bookings_view', 'عرض الحجوزات', 'صلاحية عرض قائمة الحجوزات', 'bookings'],
        ['bookings_add', 'إضافة حجز', 'صلاحية إضافة حجز جديد', 'bookings'],
        ['bookings_edit', 'تعديل الحجوزات', 'صلاحية تعديل الحجوزات الموجودة', 'bookings'],
        ['bookings_delete', 'حذف الحجوزات', 'صلاحية حذف الحجوزات', 'bookings'],
        ['rooms_view', 'عرض الغرف', 'صلاحية عرض قائمة الغرف', 'rooms'],
        ['rooms_manage', 'إدارة الغرف', 'صلاحية إدارة الغرف وحالاتها', 'rooms'],
        ['finance_view', 'عرض المالية', 'صلاحية عرض التقارير المالية', 'finance'],
        ['finance_manage', 'إدارة المالية', 'صلاحية إدارة المعاملات المالية', 'finance'],
        ['reports_view', 'عرض التقارير', 'صلاحية عرض التقارير', 'reports'],
        ['system_settings', 'إعدادات النظام', 'صلاحية الوصول إلى إعدادات النظام', 'system'],
        ['user_management', 'إدارة المستخدمين', 'صلاحية إدارة المستخدمين والصلاحيات', 'system']
    ];
    
    $insert_permission = $conn->prepare("INSERT IGNORE INTO permissions (permission_code, permission_name, description, category) VALUES (?, ?, ?, ?)");
    
    foreach ($basic_permissions as $permission) {
        $insert_permission->bind_param("ssss", $permission[0], $permission[1], $permission[2], $permission[3]);
        $insert_permission->execute();
    }
    
    echo "<div class='success'>✅ تم إدراج الصلاحيات الأساسية بنجاح</div>";
    
    echo "<h2>ملخص الجداول المنشأة:</h2>";
    echo "<ul>";
    echo "<li>جدول المستخدمين (users)</li>";
    echo "<li>جدول الصلاحيات (permissions)</li>";
    echo "<li>جدول ربط المستخدمين بالصلاحيات (user_permissions)</li>";
    echo "</ul>";
    
    echo "<div class='info'>
        <h3>معلومات تسجيل الدخول:</h3>
        <p><strong>اسم المستخدم:</strong> admin</p>
        <p><strong>كلمة المرور:</strong> 1234</p>
        <p><em>يرجى تغيير كلمة المرور بعد تسجيل الدخول</em></p>
    </div>";
    
} catch (Exception $e) {
    echo "<div class='error'>❌ حدث خطأ: " . $e->getMessage() . "</div>";
}

echo "<br><a href='../dash.php' style='display:inline-block;margin-top:20px;padding:10px;background-color:#4CAF50;color:white;text-decoration:none;border-radius:5px;'>العودة للوحة التحكم</a>";

echo "</body></html>";
?>
