<?php
/**
 * إنشاء/تحديث مستخدم Admin لـ XAMPP
 * افتح هذا الملف في المتصفح مرة واحدة لإنشاء المستخدم
 */

require_once __DIR__ . '/../includes/config.php';
require_once __DIR__ . '/../includes/db.php';

header('Content-Type: text/html; charset=utf-8');

echo "<!DOCTYPE html><html><head><meta charset='utf-8'><title>إنشاء مستخدم Admin</title>";
echo "<style>body{font-family:Arial,sans-serif;max-width:800px;margin:50px auto;padding:20px;direction:rtl;}";
echo ".success{color:green;padding:15px;border:2px solid green;background:#e7f7e7;margin:15px 0;border-radius:5px;}";
echo ".error{color:red;padding:15px;border:2px solid red;background:#ffe7e7;margin:15px 0;border-radius:5px;}";
echo ".info{color:blue;padding:15px;border:2px solid blue;background:#e7f0ff;margin:15px 0;border-radius:5px;}";
echo "code{background:#f4f4f4;padding:2px 6px;border-radius:3px;font-family:monospace;}";
echo "</style></head><body>";

echo "<h1>🔐 إنشاء مستخدم Admin</h1>";

try {
    // إنشاء جدول users إذا لم يكن موجوداً
    $createUsersTable = "
    CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        password VARCHAR(255) NOT NULL,
        full_name VARCHAR(100) NOT NULL,
        role VARCHAR(20) DEFAULT 'user',
        status VARCHAR(20) DEFAULT 'active',
        token VARCHAR(64) NULL,
        permissions TEXT NULL,
        last_activity TIMESTAMP NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_username (username),
        INDEX idx_token (token),
        INDEX idx_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";
    
    $conn->query($createUsersTable);
    
    // إنشاء جدول failed_logins
    $createFailedLoginsTable = "
    CREATE TABLE IF NOT EXISTS failed_logins (
        id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) NOT NULL,
        ip_address VARCHAR(45) NOT NULL,
        attempt_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_username (username),
        INDEX idx_ip (ip_address),
        INDEX idx_time (attempt_time)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";
    
    $conn->query($createFailedLoginsTable);
    
    // إنشاء جدول user_activity_log
    $createActivityLogTable = "
    CREATE TABLE IF NOT EXISTS user_activity_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        action VARCHAR(50) NOT NULL,
        details TEXT NULL,
        ip_address VARCHAR(45) NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user (user_id),
        INDEX idx_action (action),
        INDEX idx_time (created_at),
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ";
    
    $conn->query($createActivityLogTable);
    
    echo "<div class='success'>✅ تم إنشاء جداول المستخدمين بنجاح</div>";
    
    // التحقق من وجود مستخدم admin
    $checkAdmin = $conn->query("SELECT id, username FROM users WHERE username = 'admin'");
    
    if ($checkAdmin->num_rows > 0) {
        echo "<div class='info'>ℹ️ مستخدم admin موجود مسبقاً</div>";
        
        // تحديث كلمة المرور
        $username = 'admin';
        $password = 'admin123';
        $hashedPassword = password_hash($password, PASSWORD_DEFAULT);
        
        $stmt = $conn->prepare("UPDATE users SET password = ?, updated_at = NOW() WHERE username = 'admin'");
        $stmt->bind_param('s', $hashedPassword);
        $stmt->execute();
        
        echo "<div class='success'>";
        echo "<h3>✅ تم تحديث كلمة مرور المستخدم admin</h3>";
        echo "<p><strong>اسم المستخدم:</strong> <code>admin</code></p>";
        echo "<p><strong>كلمة المرور:</strong> <code>admin123</code></p>";
        echo "</div>";
        
    } else {
        // إنشاء مستخدم admin جديد
        $username = 'admin';
        $password = 'admin123';
        $fullName = 'مدير النظام';
        $role = 'admin';
        $status = 'active';
        $permissions = json_encode(['*']); // جميع الصلاحيات
        
        $hashedPassword = password_hash($password, PASSWORD_DEFAULT);
        
        $stmt = $conn->prepare("
            INSERT INTO users (username, password, full_name, role, status, permissions)
            VALUES (?, ?, ?, ?, ?, ?)
        ");
        
        $stmt->bind_param('ssssss', $username, $hashedPassword, $fullName, $role, $status, $permissions);
        $stmt->execute();
        
        echo "<div class='success'>";
        echo "<h3>✅ تم إنشاء مستخدم admin جديد بنجاح!</h3>";
        echo "<p><strong>اسم المستخدم:</strong> <code>admin</code></p>";
        echo "<p><strong>كلمة المرور:</strong> <code>admin123</code></p>";
        echo "<p><strong>الدور:</strong> مدير النظام (جميع الصلاحيات)</p>";
        echo "</div>";
    }
    
    echo "<div class='info'>";
    echo "<h3>📝 الخطوات التالية:</h3>";
    echo "<ol>";
    echo "<li>استخدم بيانات تسجيل الدخول أعلاه للوصول إلى API</li>";
    echo "<li><strong>مهم:</strong> غير كلمة المرور بعد أول تسجيل دخول</li>";
    echo "<li>اختبر تسجيل الدخول عبر: <a href='../api/v1/auth/login.php'>Login API</a></li>";
    echo "</ol>";
    echo "</div>";
    
    echo "<div class='info'>";
    echo "<h3>🧪 اختبار سريع</h3>";
    echo "<p>استخدم curl أو Postman:</p>";
    echo "<pre style='background:#f4f4f4;padding:15px;border-radius:5px;direction:ltr;text-align:left;'>";
    echo "curl -X POST http://localhost/marina-hotel-wit-app/api/v1/auth/login.php \\\n";
    echo "  -H \"Content-Type: application/json\" \\\n";
    echo "  -d '{\"username\":\"admin\",\"password\":\"admin123\"}'";
    echo "</pre>";
    echo "</div>";
    
    echo "<div class='success'>";
    echo "<h3>🎉 جاهز للاستخدام!</h3>";
    echo "<p>يمكنك الآن:</p>";
    echo "<ul>";
    echo "<li>تسجيل الدخول عبر API</li>";
    echo "<li>اختبار جميع Endpoints</li>";
    echo "<li>استخدام Postman Collection</li>";
    echo "<li>ربط Flutter App</li>";
    echo "</ul>";
    echo "</div>";
    
} catch (Exception $e) {
    echo "<div class='error'>";
    echo "<h3>❌ حدث خطأ</h3>";
    echo "<p>" . htmlspecialchars($e->getMessage()) . "</p>";
    echo "</div>";
    
    echo "<div class='info'>";
    echo "<h3>💡 حلول مقترحة:</h3>";
    echo "<ul>";
    echo "<li>تأكد من تشغيل MySQL في XAMPP</li>";
    echo "<li>تأكد من وجود قاعدة البيانات hotel_db</li>";
    echo "<li>تحقق من إعدادات الاتصال في includes/config.php</li>";
    echo "</ul>";
    echo "</div>";
}

echo "</body></html>";
