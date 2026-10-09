<?php
/**
 * نقطة نهاية إدارة المدفوعات
 */

require_once __DIR__ . '/../config.php';

$user = ApiMiddleware::authenticate($conn);
ApiMiddleware::rateLimit($user['id'], 120, 60);

$method = $_SERVER['REQUEST_METHOD'];
$pathInfo = $_SERVER['PATH_INFO'] ?? '';
$id = $pathInfo ? trim($pathInfo, '/') : null;

try {
    switch ($method) {
        case 'GET':
            ApiMiddleware::requirePermission($user, Permissions::PAYMENTS_VIEW);
            $id ? getPayment($conn, $id) : listPayments($conn);
            break;
        case 'POST':
            ApiMiddleware::requirePermission($user, Permissions::PAYMENTS_CREATE);
            createPayment($conn, $user);
            break;
        case 'PUT':
            if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب');
            ApiMiddleware::requirePermission($user, Permissions::PAYMENTS_UPDATE);
            updatePayment($conn, $id, $user);
            break;
        case 'DELETE':
            if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب');
            ApiMiddleware::requirePermission($user, Permissions::PAYMENTS_DELETE);
            deletePayment($conn, $id, $user);
            break;
        default:
            ApiResponse::error(ApiErrorCodes::REQUEST_METHOD_NOT_ALLOWED);
    }
} finally {
    ApiMiddleware::logRequest($user, API_START_TIME);
}

function listPayments($conn) {
    $page = max(1, (int)($_GET['page'] ?? 1));
    $pageSize = min(100, max(1, (int)($_GET['page_size'] ?? 50)));
    $bookingId = $_GET['booking_id'] ?? null;
    $method = $_GET['payment_method'] ?? null;
    
    $where = ["deleted_at IS NULL"];
    $params = [];
    $types = '';
    
    if ($bookingId) {
        $where[] = "booking_id = ?";
        $params[] = $bookingId;
        $types .= 's';
    }
    if ($method) {
        $where[] = "payment_method = ?";
        $params[] = $method;
        $types .= 's';
    }
    
    $whereClause = implode(' AND ', $where);
    
    $countStmt = $conn->prepare("SELECT COUNT(*) as total FROM payments WHERE $whereClause");
    if ($params) $countStmt->bind_param($types, ...$params);
    $countStmt->execute();
    $total = $countStmt->get_result()->fetch_assoc()['total'];
    
    $params[] = $pageSize;
    $params[] = ($page - 1) * $pageSize;
    $types .= 'ii';
    
    $stmt = $conn->prepare("
        SELECT 
            id as server_id, local_uuid, booking_id, amount, payment_date, payment_method,
            revenue_type, description, notes,
            UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(updated_at) as updated_at
        FROM payments 
        WHERE $whereClause
        ORDER BY payment_date DESC
        LIMIT ? OFFSET ?
    ");
    
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $payments = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    
    foreach ($payments as &$payment) {
        $payment['server_id'] = (int)$payment['server_id'];
        $payment['amount'] = (float)$payment['amount'];
        $payment['created_at'] = (int)$payment['created_at'];
        $payment['updated_at'] = (int)$payment['updated_at'];
    }
    
    ApiResponse::success([
        'payments' => recordsSnakeToCamel($payments),
        'pagination' => ['page' => $page, 'pageSize' => $pageSize, 'total' => (int)$total, 'totalPages' => ceil($total / $pageSize)]
    ]);
}

function getPayment($conn, $id) {
    $stmt = $conn->prepare("
        SELECT 
            id as server_id, local_uuid, booking_id, amount, payment_date, payment_method,
            revenue_type, description, notes,
            UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(updated_at) as updated_at
        FROM payments 
        WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL
        LIMIT 1
    ");
    
    $stmt->bind_param('ss', $id, $id);
    $stmt->execute();
    $payment = $stmt->get_result()->fetch_assoc();
    
    if (!$payment) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الدفعة غير موجودة');
    
    $payment['server_id'] = (int)$payment['server_id'];
    $payment['amount'] = (float)$payment['amount'];
    $payment['created_at'] = (int)$payment['created_at'];
    $payment['updated_at'] = (int)$payment['updated_at'];
    
    ApiResponse::success(['payment' => snakeToCamel($payment)]);
}

function createPayment($conn, $user) {
    $input = getInput();
    ValidationRules::payments($input, $conn)->validate();
    
    $localUuid = $input['local_uuid'] ?? generateUuid();
    
    $stmt = $conn->prepare("
        INSERT INTO payments (local_uuid, booking_id, amount, payment_date, payment_method, revenue_type, description, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ");
    
    $stmt->bind_param('ssdsssss',
        $localUuid,
        $input['booking_id'],
        $input['amount'],
        $input['payment_date'] ?? date('Y-m-d'),
        $input['payment_method'],
        $input['revenue_type'] ?? 'room',
        $input['description'] ?? null,
        $input['notes'] ?? null
    );
    
    $stmt->execute();
    $serverId = $conn->insert_id;
    
    ApiLogger::info("دفعة جديدة: {$input['amount']} ريال", ['user_id' => $user['id'], 'payment_id' => $serverId]);
    
    ApiResponse::created(['serverId' => $serverId, 'localUuid' => $localUuid]);
}

function updatePayment($conn, $id, $user) {
    $input = getInput();
    
    $checkStmt = $conn->prepare("SELECT id FROM payments WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الدفعة غير موجودة');
    
    $sets = [];
    $params = [];
    $types = '';
    
    $allowedFields = ['amount' => 'd', 'payment_date' => 's', 'payment_method' => 's', 'revenue_type' => 's', 'description' => 's', 'notes' => 's'];
    
    foreach ($allowedFields as $field => $type) {
        if (isset($input[$field])) {
            $sets[] = "$field = ?";
            $params[] = $input[$field];
            $types .= $type;
        }
    }
    
    if (empty($sets)) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'لا توجد بيانات للتحديث');
    
    $params[] = $id;
    $params[] = $id;
    $types .= 'ss';
    
    $stmt = $conn->prepare("UPDATE payments SET " . implode(', ', $sets) . " WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL");
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    
    ApiLogger::info("دفعة تم تحديثها: رقم {$existing['id']}", ['user_id' => $user['id']]);
    
    ApiResponse::success(['affectedRows' => $stmt->affected_rows, 'message' => 'تم التحديث بنجاح']);
}

function deletePayment($conn, $id, $user) {
    $checkStmt = $conn->prepare("SELECT id, amount FROM payments WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الدفعة غير موجودة');
    
    $stmt = $conn->prepare("UPDATE payments SET deleted_at = NOW() WHERE id = ?");
    $stmt->bind_param('i', $existing['id']);
    $stmt->execute();
    
    ApiLogger::warning("دفعة تم حذفها: {$existing['amount']} ريال", ['user_id' => $user['id']]);
    
    ApiResponse::success(['message' => 'تم الحذف بنجاح']);
}
