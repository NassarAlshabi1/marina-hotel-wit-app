<?php
/**
 * ملف إعداد قاعدة البيانات والمستخدمين
 * يقوم بإنشاء قاعدة البيانات والجداول والمستخدمين التجريبيين
 */

require_once 'includes/config.php';

// الاتصال بـ MySQL بدون تحديد قاعدة بيانات
$conn = new mysqli(DB_HOST, DB_USER, DB_PASS);

if ($conn->connect_error) {
    die("فشل الاتصال: " . $conn->connect_error);
}

// تعيين الترميز
$conn->set_charset('utf8mb4');

echo "<h2>إعداد قاعدة البيانات...</h2>";

// إنشاء قاعدة البيانات
$sql = "CREATE DATABASE IF NOT EXISTS `" . DB_NAME . "` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci";
if ($conn->query($sql) === TRUE) {
    echo "<p style='color: green;'>✓ تم إنشاء قاعدة البيانات بنجاح</p>";
} else {
    echo "<p style='color: red;'>خطأ في إنشاء قاعدة البيانات: " . $conn->error . "</p>";
}

// اختيار قاعدة البيانات
$conn->select_db(DB_NAME);

// إنشاء جدول المستخدمين
$users_table = "
CREATE TABLE IF NOT EXISTS `users` (
  `user_id` int(11) NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL UNIQUE,
  `password` varchar(255) DEFAULT NULL,
  `password_hash` varchar(255) DEFAULT NULL,
  `user_type` enum('admin','manager','employee') DEFAULT 'employee',
  `full_name` varchar(100) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `last_login` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`user_id`),
  KEY `idx_username` (`username`),
  KEY `idx_user_type` (`user_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
";

if ($conn->query($users_table) === TRUE) {
    echo "<p style='color: green;'>✓ تم إنشاء جدول المستخدمين بنجاح</p>";
} else {
    echo "<p style='color: red;'>خطأ في إنشاء جدول المستخدمين: " . $conn->error . "</p>";
}

// إنشاء جدول الغرف
$rooms_table = "
CREATE TABLE IF NOT EXISTS `rooms` (
  `room_id` int(11) NOT NULL AUTO_INCREMENT,
  `room_number` varchar(10) NOT NULL UNIQUE,
  `room_type` varchar(50) DEFAULT 'standard',
  `status` enum('شاغرة','محجوزة','صيانة','تنظيف') DEFAULT 'شاغرة',
  `price_per_night` decimal(10,2) DEFAULT 0.00,
  `max_guests` int(11) DEFAULT 2,
  `description` text,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`room_id`),
  KEY `idx_room_number` (`room_number`),
  KEY `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
";

if ($conn->query($rooms_table) === TRUE) {
    echo "<p style='color: green;'>✓ تم إنشاء جدول الغرف بنجاح</p>";
} else {
    echo "<p style='color: red;'>خطأ في إنشاء جدول الغرف: " . $conn->error . "</p>";
}

// إنشاء جدول الحجوزات
$bookings_table = "
CREATE TABLE IF NOT EXISTS `bookings` (
  `booking_id` int(11) NOT NULL AUTO_INCREMENT,
  `guest_name` varchar(100) NOT NULL,
  `guest_phone` varchar(20) DEFAULT NULL,
  `guest_id_number` varchar(50) DEFAULT NULL,
  `room_number` varchar(10) NOT NULL,
  `checkin_date` date NOT NULL,
  `checkout_date` date NOT NULL,
  `actual_checkin` datetime DEFAULT NULL,
  `actual_checkout` datetime DEFAULT NULL,
  `total_amount` decimal(10,2) DEFAULT 0.00,
  `paid_amount` decimal(10,2) DEFAULT 0.00,
  `status` enum('محجوز','وصل','غادر','ملغي') DEFAULT 'محجوز',
  `notes` text,
  `created_at` timestamp DEFAULT CURRENT_TIMESTAMP,
  `created_by` int(11) DEFAULT NULL,
  PRIMARY KEY (`booking_id`),
  KEY `idx_guest_name` (`guest_name`),
  KEY `idx_room_number` (`room_number`),
  KEY `idx_status` (`status`),
  KEY `idx_checkin_date` (`checkin_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
";

if ($conn->query($bookings_table) === TRUE) {
    echo "<p style='color: green;'>✓ تم إنشاء جدول الحجوزات بنجاح</p>";
} else {
    echo "<p style='color: red;'>خطأ في إنشاء جدول الحجوزات: " . $conn->error . "</p>";
}

echo "<h2>إنشاء المستخدمين التجريبيين...</h2>";

// التحقق من وجود مستخدمين
$check_users = $conn->query("SELECT COUNT(*) as count FROM users");
$user_count = $check_users->fetch_assoc()['count'];

if ($user_count == 0) {
    // إنشاء مستخدمين تجريبيين
    $test_users = [
        [
            'username' => 'admin',
            'password' => 'admin123',
            'user_type' => 'admin',
            'full_name' => 'مدير النظام',
            'email' => 'admin@marina.com'
        ],
        [
            'username' => 'manager',
            'password' => 'manager123',
            'user_type' => 'manager',
            'full_name' => 'مدير الفندق',
            'email' => 'manager@marina.com'
        ],
        [
            'username' => 'user',
            'password' => '123456',
            'user_type' => 'employee',
            'full_name' => 'موظف الاستقبال',
            'email' => 'user@marina.com'
        ]
    ];

    foreach ($test_users as $user) {
        // تشفير كلمة المرور
        $password_hash = password_hash($user['password'], PASSWORD_DEFAULT);
        
        $stmt = $conn->prepare("INSERT INTO users (username, password, password_hash, user_type, full_name, email, is_active) VALUES (?, ?, ?, ?, ?, ?, 1)");
        $stmt->bind_param("ssssss", 
            $user['username'], 
            $user['password'], // للتوافق مع النظام القديم
            $password_hash,    // النظام الجديد المشفر
            $user['user_type'], 
            $user['full_name'], 
            $user['email']
        );
        
        if ($stmt->execute()) {
            echo "<p style='color: green;'>✓ تم إنشاء المستخدم: {$user['username']} (كلمة المرور: {$user['password']})</p>";
        } else {
            echo "<p style='color: red;'>خطأ في إنشاء المستخدم {$user['username']}: " . $stmt->error . "</p>";
        }
        $stmt->close();
    }
} else {
    echo "<p style='color: blue;'>المستخدمون موجودون بالفعل ($user_count مستخدم)</p>";
}

echo "<h2>إنشاء غرف تجريبية...</h2>";

// التحقق من وجود غرف
$check_rooms = $conn->query("SELECT COUNT(*) as count FROM rooms");
$room_count = $check_rooms->fetch_assoc()['count'];

if ($room_count == 0) {
    // إنشاء غرف تجريبية
    $test_rooms = [
        ['101', 'standard', 'شاغرة', 150.00],
        ['102', 'standard', 'شاغرة', 150.00],
        ['103', 'deluxe', 'شاغرة', 200.00],
        ['201', 'standard', 'شاغرة', 150.00],
        ['202', 'standard', 'محجوزة', 150.00],
        ['203', 'suite', 'شاغرة', 300.00],
        ['301', 'standard', 'شاغرة', 150.00],
        ['302', 'deluxe', 'شاغرة', 200.00],
        ['303', 'suite', 'صيانة', 300.00]
    ];

    foreach ($test_rooms as $room) {
        $stmt = $conn->prepare("INSERT INTO rooms (room_number, room_type, status, price_per_night, max_guests) VALUES (?, ?, ?, ?, 2)");
        $stmt->bind_param("sssd", $room[0], $room[1], $room[2], $room[3]);
        
        if ($stmt->execute()) {
            echo "<p style='color: green;'>✓ تم إنشاء الغرفة: {$room[0]} ({$room[2]})</p>";
        } else {
            echo "<p style='color: red;'>خطأ في إنشاء الغرفة {$room[0]}: " . $stmt->error . "</p>";
        }
        $stmt->close();
    }
} else {
    echo "<p style='color: blue;'>الغرف موجودة بالفعل ($room_count غرفة)</p>";
}

$conn->close();

echo "<h2 style='color: green;'>تم الانتهاء من إعداد قاعدة البيانات!</h2>";
echo "<h3>بيانات تسجيل الدخول:</h3>";
echo "<ul>";
echo "<li><strong>المدير:</strong> admin / admin123</li>";
echo "<li><strong>المدير:</strong> manager / manager123</li>";
echo "<li><strong>الموظف:</strong> user / 123456</li>";
echo "</ul>";
echo "<p><a href='login.php' style='background: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;'>الذهاب لصفحة تسجيل الدخول</a></p>";
?>
