<?php
/**
 * ملف للتحقق من صلاحيات المستخدم الحالي
 * يستخدم لجلب صلاحيات المستخدم بتنسيق JSON
 */

include_once '../../includes/db.php';
session_start();

// التحقق من وجود معرف المستخدم في الطلب
if (!isset($_GET['user_id']) || empty($_GET['user_id'])) {
    echo json_encode(['success' => false, 'message' => 'معرف المستخدم مطلوب']);
    exit;
}

$user_id = $_GET['user_id'];

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    echo json_encode(['success' => false, 'message' => 'فشل الاتصال بقاعدة البيانات']);
    exit;
}

// جلب صلاحيات المستخدم
$query = "
    SELECT p.permission_id 
    FROM user_permissions up 
    JOIN permissions p ON up.permission_id = p.permission_id 
    WHERE up.user_id = ?
";

$stmt = $conn->prepare($query);
$stmt->bind_param("i", $user_id);
$stmt->execute();
$result = $stmt->get_result();

$permissions = [];
while ($row = $result->fetch_assoc()) {
    $permissions[] = $row['permission_id'];
}

echo json_encode(['success' => true, 'permissions' => $permissions]);

$stmt->close();
$conn->close();
?>
