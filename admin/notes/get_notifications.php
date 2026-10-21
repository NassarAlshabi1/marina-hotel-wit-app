<?php
require_once '../../includes/config.php';
require_once '../../includes/db.php';
require_once '../../includes/auth.php';

// التحقق من تسجيل الدخول
if (!is_logged_in()) {
    http_response_code(401);
    echo json_encode(['error' => 'غير مسموح']);
    exit();
}

// تحديد النوبة الحالية
$current_hour = date('H');
if ($current_hour >= 6 && $current_hour < 14) {
    $shift = 'morning';
} elseif ($current_hour >= 14 && $current_hour < 22) {
    $shift = 'evening';
} else {
    $shift = 'night';
}

// جلب الإشعارات غير المقروءة للنوبة الحالية
$stmt = $conn->prepare("
    SELECT COUNT(*) as unread_count 
    FROM shift_notes 
    WHERE status = 'active' 
    AND is_read = FALSE 
    AND (shift_type = ? OR shift_type = 'all')
    AND (expires_at IS NULL OR expires_at > NOW())
");
$stmt->bind_param("s", $shift);
$stmt->execute();
$result = $stmt->get_result();
$data = $result->fetch_assoc();
$stmt->close();

// جلب آخر 5 إشعارات
$stmt = $conn->prepare("
    SELECT n.id, n.title, n.priority, n.created_at, u.username as created_by_name
    FROM shift_notes n 
    LEFT JOIN users u ON n.created_by = u.id 
    WHERE n.status = 'active' 
    AND (n.shift_type = ? OR n.shift_type = 'all')
    AND (n.expires_at IS NULL OR n.expires_at > NOW())
    ORDER BY n.priority DESC, n.created_at DESC 
    LIMIT 5
");
$stmt->bind_param("s", $shift);
$stmt->execute();
$result = $stmt->get_result();

$notifications = [];
while ($row = $result->fetch_assoc()) {
    $notifications[] = $row;
}
$stmt->close();

header('Content-Type: application/json');
echo json_encode([
    'unread_count' => $data['unread_count'],
    'notifications' => $notifications
]);
?>
