<?php
require_once 'includes/config.php';
require_once 'includes/db.php';

// إنشاء جدول الملاحظات
$sql = "CREATE TABLE IF NOT EXISTS shift_notes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    priority ENUM('low', 'medium', 'high') DEFAULT 'medium',
    created_by INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_read BOOLEAN DEFAULT FALSE,
    shift_type ENUM('morning', 'evening', 'night', 'all') DEFAULT 'all',
    expires_at DATETIME NULL,
    status ENUM('active', 'archived') DEFAULT 'active'
)";

if ($conn->query($sql) === TRUE) {
    echo "تم إنشاء جدول الملاحظات بنجاح<br>";
} else {
    echo "خطأ في إنشاء الجدول: " . $conn->error . "<br>";
}

// إضافة بعض الملاحظات التجريبية
$sample_notes = array(
    array(
        'title' => 'تنبيه مهم - صيانة المصعد',
        'content' => 'المصعد الرئيسي خارج الخدمة حتى الساعة 3 مساءً',
        'priority' => 'high',
        'shift_type' => 'all'
    ),
    array(
        'title' => 'حجز VIP - الغرفة 101',
        'content' => 'ضيف مهم سيصل اليوم في الساعة 6 مساءً',
        'priority' => 'medium',
        'shift_type' => 'evening'
    )
);

foreach ($sample_notes as $note) {
    $stmt = $conn->prepare("INSERT INTO shift_notes (title, content, priority, created_by, shift_type) VALUES (?, ?, ?, 1, ?)");
    $stmt->bind_param("ssss", $note['title'], $note['content'], $note['priority'], $note['shift_type']);
    
    if ($stmt->execute()) {
        echo "تم إضافة الملاحظة: " . $note['title'] . "<br>";
    } else {
        echo "خطأ في إضافة الملاحظة: " . $stmt->error . "<br>";
    }
    $stmt->close();
}

echo "<br><strong>تم إعداد نظام الملاحظات بنجاح!</strong><br>";
echo "<a href='admin/dash.php'>العودة للوحة التحكم</a>";

$conn->close();
?>