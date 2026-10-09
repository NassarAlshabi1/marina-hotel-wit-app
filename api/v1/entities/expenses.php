<?php
require_once __DIR__ . '/../config.php';
$user = ApiMiddleware::authenticate($conn);
ApiMiddleware::rateLimit($user['id'], 120, 60);
$method = $_SERVER['REQUEST_METHOD'];
$pathInfo = $_SERVER['PATH_INFO'] ?? '';
$id = $pathInfo ? trim($pathInfo, '/') : null;

try {
    switch ($method) {
        case 'GET': ApiMiddleware::requirePermission($user, Permissions::EXPENSES_VIEW); $id ? getExpense($conn, $id) : listExpenses($conn); break;
        case 'POST': ApiMiddleware::requirePermission($user, Permissions::EXPENSES_CREATE); createExpense($conn, $user); break;
        case 'PUT': if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب'); ApiMiddleware::requirePermission($user, Permissions::EXPENSES_UPDATE); updateExpense($conn, $id, $user); break;
        case 'DELETE': if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب'); ApiMiddleware::requirePermission($user, Permissions::EXPENSES_DELETE); deleteExpense($conn, $id, $user); break;
        default: ApiResponse::error(ApiErrorCodes::REQUEST_METHOD_NOT_ALLOWED);
    }
} finally { ApiMiddleware::logRequest($user, API_START_TIME); }

function listExpenses($conn) {
    $page = max(1, (int)($_GET['page'] ?? 1)); $pageSize = min(100, max(1, (int)($_GET['page_size'] ?? 50)));
    $where = ["deleted_at IS NULL"]; $params = []; $types = '';
    $whereClause = implode(' AND ', $where);
    $countStmt = $conn->prepare("SELECT COUNT(*) as total FROM expenses WHERE $whereClause");
    if ($params) $countStmt->bind_param($types, ...$params);
    $countStmt->execute(); $total = $countStmt->get_result()->fetch_assoc()['total'];
    $params[] = $pageSize; $params[] = ($page - 1) * $pageSize; $types .= 'ii';
    $stmt = $conn->prepare("SELECT id as server_id, local_uuid, expense_type, description, amount, date, category_uuid, UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(updated_at) as updated_at FROM expenses WHERE $whereClause ORDER BY date DESC LIMIT ? OFFSET ?");
    $stmt->bind_param($types, ...$params); $stmt->execute(); $expenses = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    foreach ($expenses as &$expense) { $expense['server_id'] = (int)$expense['server_id']; $expense['amount'] = (float)$expense['amount']; $expense['created_at'] = (int)$expense['created_at']; $expense['updated_at'] = (int)$expense['updated_at']; }
    ApiResponse::success(['expenses' => recordsSnakeToCamel($expenses), 'pagination' => ['page' => $page, 'pageSize' => $pageSize, 'total' => (int)$total, 'totalPages' => ceil($total / $pageSize)]]);
}

function getExpense($conn, $id) {
    $stmt = $conn->prepare("SELECT id as server_id, local_uuid, expense_type, description, amount, date, category_uuid, UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(updated_at) as updated_at FROM expenses WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $stmt->bind_param('ss', $id, $id); $stmt->execute(); $expense = $stmt->get_result()->fetch_assoc();
    if (!$expense) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'المصروف غير موجود');
    $expense['server_id'] = (int)$expense['server_id']; $expense['amount'] = (float)$expense['amount']; $expense['created_at'] = (int)$expense['created_at']; $expense['updated_at'] = (int)$expense['updated_at'];
    ApiResponse::success(['expense' => snakeToCamel($expense)]);
}

function createExpense($conn, $user) {
    $input = getInput(); $localUuid = $input['local_uuid'] ?? generateUuid();
    $stmt = $conn->prepare("INSERT INTO expenses (local_uuid, expense_type, description, amount, date, category_uuid) VALUES (?, ?, ?, ?, ?, ?)");
    $stmt->bind_param('sssdss', $localUuid, $input['expense_type'], $input['description'] ?? null, $input['amount'], $input['date'] ?? date('Y-m-d'), $input['category_uuid'] ?? null);
    $stmt->execute(); $serverId = $conn->insert_id;
    ApiLogger::info("مصروف جديد: {$input['amount']} ريال", ['user_id' => $user['id'], 'expense_id' => $serverId]);
    ApiResponse::created(['serverId' => $serverId, 'localUuid' => $localUuid]);
}

function updateExpense($conn, $id, $user) {
    $input = getInput(); $checkStmt = $conn->prepare("SELECT id FROM expenses WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id); $checkStmt->execute(); $existing = $checkStmt->get_result()->fetch_assoc();
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'المصروف غير موجود');
    $sets = []; $params = []; $types = '';
    $allowedFields = ['expense_type' => 's', 'description' => 's', 'amount' => 'd', 'date' => 's', 'category_uuid' => 's'];
    foreach ($allowedFields as $field => $type) { if (isset($input[$field])) { $sets[] = "$field = ?"; $params[] = $input[$field]; $types .= $type; } }
    if (empty($sets)) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'لا توجد بيانات للتحديث');
    $params[] = $id; $params[] = $id; $types .= 'ss';
    $stmt = $conn->prepare("UPDATE expenses SET " . implode(', ', $sets) . " WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL");
    $stmt->bind_param($types, ...$params); $stmt->execute();
    ApiResponse::success(['affectedRows' => $stmt->affected_rows, 'message' => 'تم التحديث بنجاح']);
}

function deleteExpense($conn, $id, $user) {
    $checkStmt = $conn->prepare("SELECT id FROM expenses WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id); $checkStmt->execute(); $existing = $checkStmt->get_result()->fetch_assoc();
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'المصروف غير موجود');
    $stmt = $conn->prepare("UPDATE expenses SET deleted_at = NOW() WHERE id = ?"); $stmt->bind_param('i', $existing['id']); $stmt->execute();
    ApiResponse::success(['message' => 'تم الحذف بنجاح']);
}
