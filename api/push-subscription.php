<?php
header('Content-Type: application/json');
require_once '../includes/db.php';
require_once '../includes/auth_check.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'طريقة غير مدعومة']);
    exit;
}

$input = json_decode(file_get_contents('php://input'), true);

if (!$input) {
    http_response_code(400);
    echo json_encode(['error' => 'بيانات غير صحيحة']);
    exit;
}

try {
    $user_id = $_SESSION['user_id'];
    $endpoint = $input['endpoint'];
    $p256dh = $input['keys']['p256dh'];
    $auth = $input['keys']['auth'];
    
    // حفظ الاشتراك في قاعدة البيانات
    $query = "INSERT INTO push_subscriptions (user_id, endpoint, p256dh_key, auth_key, created_at) 
              VALUES (?, ?, ?, ?, NOW()) 
              ON DUPLICATE KEY UPDATE 
              p256dh_key = VALUES(p256dh_key), 
              auth_key = VALUES(auth_key), 
              updated_at = NOW()";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param('isss', $user_id, $endpoint, $p256dh, $auth);
    
    if ($stmt->execute()) {
        echo json_encode(['success' => true]);
    } else {
        throw new Exception('فشل في حفظ الاشتراك');
    }
    
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
}
?>
