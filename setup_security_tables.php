<?php
/**
 * إعداد جداول الأمان المطلوبة للنظام
 * يقوم بإضافة الأعمدة المفقودة لجدول المستخدمين وإنشاء الجداول الأمنية
 */

require_once 'includes/config.php';
require_once 'includes/db.php';

echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>إعداد جداول الأمان</title>
    <style>
        body { font-family: 'Tajawal', Arial, sans-serif; margin: 20px; direction: rtl; }
        .success { color: green; background: #d4edda; padding: 10px; border-radius: 5px; margin: 10px 0; }
        .error { color: red; background: #f8d7da; padding: 10px; border-radius: 5px; margin: 10px 0; }
        .info { color: blue; background: #d1ecf1; padding: 10px; border-radius: 5px; margin: 10px 0; }
        .warning { color: orange; background: #fff3cd; padding: 10px; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>";

echo "<h1>إعداد جداول الأمان</h1>";

try {
    // 1. التحقق من وجود جدول المستخدمين
    $check_users_table = $conn->query("SHOW TABLES LIKE 'users'");
    
    if (!$check_users_table || $check_users_table->num_rows == 0) {
        echo "<div class='info'>📋 إنشاء جدول المستخدمين...</div>";
        
        // إنشاء جدول المستخدمين
        $create_users_table = "
        CREATE TABLE users (
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
            
            // إضافة المستخدم الافتراضي
            $admin_password = password_hash('1234', PASSWORD_DEFAULT);
            $insert_admin = "INSERT INTO users (username, password_hash, user_type, full_name, email) 
                            VALUES ('admin', ?, 'admin', 'مدير النظام', 'admin@hotel.com')";
            
            $stmt = $conn->prepare($insert_admin);
            $stmt->bind_param("s", $admin_password);
            
            if ($stmt->execute()) {
                echo "<div class='success'>✅ تم إنشاء المستخدم الافتراضي (admin) بنجاح</div>";
            }
            $stmt->close();
        } else {
            echo "<div class='error'>❌ خطأ في إنشاء جدول المستخدمين: " . $conn->error . "</div>";
        }
    } else {
        echo "<div class='info'>ℹ️ جدول المستخدمين موجود بالفعل</div>";
        
        // 2. التحقق من الأعمدة المطلوبة وإضافتها إذا لم تكن موجودة
        $required_columns = [
            'failed_login_attempts' => 'INT DEFAULT 0',
            'locked_until' => 'TIMESTAMP NULL',
            'last_login' => 'TIMESTAMP NULL'
        ];
        
        foreach ($required_columns as $column => $definition) {
            $check_column = $conn->query("SHOW COLUMNS FROM users LIKE '$column'");
            
            if (!$check_column || $check_column->num_rows == 0) {
                echo "<div class='info'>📋 إضافة العمود: $column</div>";
                
                $add_column = "ALTER TABLE users ADD COLUMN $column $definition";
                if ($conn->query($add_column)) {
                    echo "<div class='success'>✅ تم إضافة العمود: $column</div>";
                } else {
                    echo "<div class='error'>❌ خطأ في إضافة العمود $column: " . $conn->error . "</div>";
                }
            } else {
                echo "<div class='info'>ℹ️ العمود $column موجود بالفعل</div>";
            }
        }
    }
    
    // 3. إنشاء جدول سجل المحاولات الفاشلة
    echo "<h2>إنشاء جداول الأمان الإضافية:</h2>";
    
    $create_failed_logins = "
    CREATE TABLE IF NOT EXISTS failed_logins (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50),
        ip_address VARCHAR(45),
        attempt_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_username (username),
        INDEX idx_ip_address (ip_address),
        INDEX idx_attempt_time (attempt_time)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    if ($conn->query($create_failed_logins)) {
        echo "<div class='success'>✅ تم إنشاء جدول سجل المحاولات الفاشلة</div>";
    } else {
        echo "<div class='error'>❌ خطأ في إنشاء جدول المحاولات الفاشلة: " . $conn->error . "</div>";
    }
    
    // 4. إنشاء جدول سجل أنشطة المستخدمين
    $create_activity_log = "
    CREATE TABLE IF NOT EXISTS user_activity_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT,
        action VARCHAR(100),
        details TEXT,
        ip_address VARCHAR(45),
        user_agent TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user_id (user_id),
        INDEX idx_action (action),
        INDEX idx_created_at (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    if ($conn->query($create_activity_log)) {
        echo "<div class='success'>✅ تم إنشاء جدول سجل الأنشطة</div>";
    } else {
        echo "<div class='error'>❌ خطأ في إنشاء جدول سجل الأنشطة: " . $conn->error . "</div>";
    }
    
    // 5. إنشاء جدول الصلاحيات
    $create_permissions = "
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
    
    if ($conn->query($create_permissions)) {
        echo "<div class='success'>✅ تم إنشاء جدول الصلاحيات</div>";
        
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
        
        echo "<div class='success'>✅ تم إدراج الصلاحيات الأساسية</div>";
        $insert_permission->close();
        
    } else {
        echo "<div class='error'>❌ خطأ في إنشاء جدول الصلاحيات: " . $conn->error . "</div>";
    }
    
    // 6. إنشاء جدول ربط المستخدمين بالصلاحيات
    $create_user_permissions = "
    CREATE TABLE IF NOT EXISTS user_permissions (
        user_id INT,
        permission_id INT,
        granted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        granted_by INT,
        PRIMARY KEY (user_id, permission_id),
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
        FOREIGN KEY (permission_id) REFERENCES permissions(permission_id) ON DELETE CASCADE,
        INDEX idx_user_id (user_id),
        INDEX idx_permission_id (permission_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    if ($conn->query($create_user_permissions)) {
        echo "<div class='success'>✅ تم إنشاء جدول صلاحيات المستخدمين</div>";
    } else {
        echo "<div class='error'>❌ خطأ في إنشاء جدول صلاحيات المستخدمين: " . $conn->error . "</div>";
    }
    
    // 7. التحقق النهائي
    echo "<h2>التحقق النهائي من الجداول:</h2>";
    
    $tables_to_check = ['users', 'failed_logins', 'user_activity_log', 'permissions', 'user_permissions'];
    
    foreach ($tables_to_check as $table) {
        $check = $conn->query("SHOW TABLES LIKE '$table'");
        if ($check && $check->num_rows > 0) {
            echo "<div class='success'>✅ الجدول $table موجود</div>";
        } else {
            echo "<div class='error'>❌ الجدول $table غير موجود</div>";
        }
    }
    
    echo "<div class='success'>";
    echo "<h2>🎉 تم إعداد جداول الأمان بنجاح!</h2>";
    echo "<p>يمكنك الآن استخدام النظام بأمان محسن.</p>";
    echo "<p><strong>معلومات تسجيل الدخول:</strong></p>";
    echo "<ul>";
    echo "<li><strong>اسم المستخدم:</strong> admin</li>";
    echo "<li><strong>كلمة المرور:</strong> 1234</li>";
    echo "</ul>";
    echo "<p><em>يرجى تغيير كلمة المرور بعد تسجيل الدخول الأول</em></p>";
    echo "</div>";
    
} catch (Exception $e) {
    echo "<div class='error'>❌ حدث خطأ: " . $e->getMessage() . "</div>";
}

echo "<br><a href='login.php' style='display:inline-block;margin-top:20px;padding:10px;background-color:#4CAF50;color:white;text-decoration:none;border-radius:5px;'>تسجيل الدخول</a>";
echo " <a href='admin/dash.php' style='display:inline-block;margin-top:20px;padding:10px;background-color:#007bff;color:white;text-decoration:none;border-radius:5px;margin-right:10px;'>لوحة التحكم</a>";

echo "</body></html>";
?>
