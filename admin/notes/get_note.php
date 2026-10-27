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

if (!isset($_GET['id']) || !is_numeric($_GET['id'])) {
    http_response_code(400);
    echo json_encode(['error' => 'معرف غير صالح']);
    exit();
}

$id = (int)$_GET['id'];

$stmt = $conn->prepare("SELECT * FROM shift_notes WHERE id = ?");
$stmt->bind_param("i", $id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    http_response_code(404);
    echo json_encode(['error' => 'الملاحظة غير موجودة']);
    exit();
}

$note = $result->fetch_assoc();
$stmt->close();

header('Content-Type: application/json');
echo json_encode($note);
?>
