<?php

$__bootstrap = dirname(__DIR__) . '/bootstrap.php';
if (is_file($__bootstrap)) {
    require_once $__bootstrap;
} else {
    // The Windows builder also copies this file alone into a generated web root.
    if (!defined('MARINA_REPO_ROOT')) define('MARINA_REPO_ROOT', __DIR__);
    if (!defined('MARINA_WEB_ROOT')) define('MARINA_WEB_ROOT', '/');
    set_include_path(MARINA_REPO_ROOT . PATH_SEPARATOR . get_include_path());
    chdir(MARINA_REPO_ROOT);
}
// إعداد قاعدة البيانات السريع للنظام المحول إلى EXE
header('Content-Type: text/html; charset=UTF-8');

echo "<!DOCTYPE html>
<html dir='rtl' lang='ar'>
<head>
    <meta charset='UTF-8'>
    <title>إعداد قاعدة البيانات</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .success { color: #28a745; padding: 10px; background: #d4edda; border: 1px solid #c3e6cb; border-radius: 5px; margin: 10px 0; }
        .error { color: #dc3545; padding: 10px; background: #f8d7da; border: 1px solid #f5c6cb; border-radius: 5px; margin: 10px 0; }
        .info { color: #0c5460; padding: 10px; background: #d1ecf1; border: 1px solid #bee5eb; border-radius: 5px; margin: 10px 0; }
        .btn { padding: 10px 20px; background: #007bff; color: white; border: none; border-radius: 5px; cursor: pointer; }
        .btn:hover { background: #0056b3; }
        .step { margin: 20px 0; padding: 15px; background: #f8f9fa; border-left: 4px solid #007bff; }
        .progress { width: 100%; height: 20px; background: #e9ecef; border-radius: 10px; overflow: hidden; margin: 10px 0; }
        .progress-bar { height: 100%; background: #007bff; transition: width 0.3s ease; }
    </style>
</head>
<body>
    <div class='container'>
        <h1>🚀 إعداد Marina Hotel Database</h1>";

// التحقق من وجود مجلد البيانات
$dataDir = MARINA_REPO_ROOT . '/data';
if (!is_dir($dataDir)) {
    mkdir($dataDir, 0755, true);
    echo "<div class='info'>✅ تم إنشاء مجلد البيانات</div>";
}

// التحقق من وجود مجلد الرفع
$uploadDir = MARINA_REPO_ROOT . '/uploads';
if (!is_dir($uploadDir)) {
    mkdir($uploadDir, 0755, true);
    echo "<div class='info'>✅ تم إنشاء مجلد الرفع</div>";
}

// التحقق من وجود مجلد التقارير
$reportsDir = MARINA_REPO_ROOT . '/uploads/reports';
if (!is_dir($reportsDir)) {
    mkdir($reportsDir, 0755, true);
    echo "<div class='info'>✅ تم إنشاء مجلد التقارير</div>";
}

// إعداد قاعدة البيانات
$dbPath = $dataDir . '/marina_hotel.db';
$setupComplete = false;

try {
    // إنشاء قاعدة البيانات SQLite
    $db = new PDO('sqlite:' . $dbPath);
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    echo "<div class='step'>
            <h3>🔧 إعداد قاعدة البيانات</h3>
            <div class='progress'><div class='progress-bar' style='width: 25%'></div></div>
            <p>جاري إنشاء الجداول...</p>
          </div>";

    // قراءة ملف SQL إذا كان موجوداً
    $sqlFile = MARINA_REPO_ROOT . '/hotel_db.sql';
    if (file_exists($sqlFile)) {
        $sql = file_get_contents($sqlFile);
        
        // تحويل MySQL إلى SQLite
        $sql = str_replace('AUTO_INCREMENT', '', $sql);
        $sql = str_replace('ENGINE=InnoDB', '', $sql);
        $sql = str_replace('DEFAULT CHARSET=utf8', '', $sql);
        $sql = preg_replace('/INT\(\d+\)/', 'INTEGER', $sql);
        $sql = preg_replace('/TINYINT\(\d+\)/', 'INTEGER', $sql);
        $sql = str_replace('DATETIME', 'TEXT', $sql);
        $sql = str_replace('TIMESTAMP', 'TEXT', $sql);
        
        // تنفيذ الاستعلامات
        $statements = explode(';', $sql);
        foreach ($statements as $statement) {
            $statement = trim($statement);
            if (!empty($statement)) {
                try {
                    $db->exec($statement);
                } catch (Exception $e) {
                    // تجاهل الأخطاء البسيطة
                }
            }
        }
        
        echo "<div class='success'>✅ تم إنشاء الجداول من ملف SQL</div>";
    } else {
        // إنشاء جداول أساسية
        $tables = [
            'users' => "CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL,
                email TEXT,
                role TEXT DEFAULT 'user',
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )",
            'rooms' => "CREATE TABLE IF NOT EXISTS rooms (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                room_number TEXT UNIQUE NOT NULL,
                room_type TEXT NOT NULL,
                price REAL NOT NULL,
                status TEXT DEFAULT 'available',
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )",
            'bookings' => "CREATE TABLE IF NOT EXISTS bookings (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                guest_name TEXT NOT NULL,
                guest_phone TEXT,
                guest_email TEXT,
                room_id INTEGER,
                check_in TEXT NOT NULL,
                check_out TEXT NOT NULL,
                total_amount REAL NOT NULL,
                status TEXT DEFAULT 'confirmed',
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (room_id) REFERENCES rooms(id)
            )",
            'expenses' => "CREATE TABLE IF NOT EXISTS expenses (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                description TEXT NOT NULL,
                amount REAL NOT NULL,
                category TEXT,
                expense_date TEXT NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )"
        ];
        
        foreach ($tables as $tableName => $sql) {
            $db->exec($sql);
            echo "<div class='info'>✅ تم إنشاء جدول {$tableName}</div>";
        }
    }
    
    echo "<div class='step'>
            <h3>👤 إنشاء حساب الأدمين</h3>
            <div class='progress'><div class='progress-bar' style='width: 75%'></div></div>
          </div>";
    
    // إنشاء حساب أدمين افتراضي
    $adminCheck = $db->prepare("SELECT COUNT(*) FROM users WHERE role = 'admin'");
    $adminCheck->execute();
    
    if ($adminCheck->fetchColumn() == 0) {
        $adminPassword = password_hash('admin123', PASSWORD_DEFAULT);
        $createAdmin = $db->prepare("INSERT INTO users (username, password, email, role) VALUES (?, ?, ?, ?)");
        $createAdmin->execute(['admin', $adminPassword, 'admin@marinahotel.com', 'admin']);
        
        echo "<div class='success'>✅ تم إنشاء حساب الأدمين
                <br><strong>اسم المستخدم:</strong> admin
                <br><strong>كلمة المرور:</strong> admin123
              </div>";
    } else {
        echo "<div class='info'>ℹ️ يوجد حساب أدمين مسبقاً</div>";
    }
    
    // إضافة بيانات تجريبية
    echo "<div class='step'>
            <h3>📊 إضافة بيانات تجريبية</h3>
            <div class='progress'><div class='progress-bar' style='width: 100%'></div></div>
          </div>";
    
    // إضافة غرف تجريبية
    $roomCheck = $db->prepare("SELECT COUNT(*) FROM rooms");
    $roomCheck->execute();
    
    if ($roomCheck->fetchColumn() == 0) {
        $sampleRooms = [
            ['101', 'غرفة مفردة', 150.00],
            ['102', 'غرفة مزدوجة', 200.00],
            ['103', 'جناح', 350.00],
            ['201', 'غرفة مفردة', 150.00],
            ['202', 'غرفة مزدوجة', 200.00]
        ];
        
        $insertRoom = $db->prepare("INSERT INTO rooms (room_number, room_type, price) VALUES (?, ?, ?)");
        foreach ($sampleRooms as $room) {
            $insertRoom->execute($room);
        }
        
        echo "<div class='success'>✅ تم إضافة غرف تجريبية</div>";
    }
    
    $setupComplete = true;
    
} catch (Exception $e) {
    echo "<div class='error'>❌ خطأ في إعداد قاعدة البيانات: " . $e->getMessage() . "</div>";
}

if ($setupComplete) {
    echo "<div class='step'>
            <h2>🎉 تم إنشاء النظام بنجاح!</h2>
            <div class='success'>
                <h3>معلومات الدخول:</h3>
                <p><strong>اسم المستخدم:</strong> admin</p>
                <p><strong>كلمة المرور:</strong> admin123</p>
                <p><strong>رابط النظام:</strong> <a href='login.php'>تسجيل الدخول</a></p>
            </div>
            <div class='info'>
                <h3>ملاحظات مهمة:</h3>
                <ul>
                    <li>غير كلمة مرور الأدمين فوراً</li>
                    <li>ملف قاعدة البيانات: data/marina_hotel.db</li>
                    <li>النظام يعمل محلياً على http://localhost:8080</li>
                </ul>
            </div>
            <p style='text-align: center;'>
                <a href='login.php' class='btn'>🚀 بدء استخدام النظام</a>
            </p>
          </div>";
}

echo "</div>
</body>
</html>";
?>