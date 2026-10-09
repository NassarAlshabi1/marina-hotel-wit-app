<?php
/**
 * نقطة نهاية إدارة الموظفين
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
            ApiMiddleware::requirePermission($user, Permissions::EMPLOYEES_VIEW);
            $id ? getEmployee($conn, $id) : listEmployees($conn);
            break;
        case 'POST':
            ApiMiddleware::requirePermission($user, Permissions::EMPLOYEES_CREATE);
            createEmployee($conn, $user);
            break;
        case 'PUT':
            if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب');
            ApiMiddleware::requirePermission($user, Permissions::EMPLOYEES_UPDATE);
            updateEmployee($conn, $id, $user);
            break;
        case 'DELETE':
            if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب');
            ApiMiddleware::requirePermission($user, Permissions::EMPLOYEES_DELETE);
            deleteEmployee($conn, $id, $user);
            break;
        default:
            ApiResponse::error(ApiErrorCodes::REQUEST_METHOD_NOT_ALLOWED);
    }
} finally {
    ApiMiddleware::logRequest($user, API_START_TIME);
}

function listEmployees($conn) {
    $page = max(1, (int)($_GET['page'] ?? 1));
    $pageSize = min(100, max(1, (int)($_GET['page_size'] ?? 50)));
    $status = $_GET['status'] ?? null;
    
    $where = ["deleted_at IS NULL"];
    $params = [];
    $types = '';
    
    if ($status) {
        $where[] = "status = ?";
        $params[] = $status;
        $types .= 's';
    }
    
    $whereClause = implode(' AND ', $where);
    
    $countStmt = $conn->prepare("SELECT COUNT(*) as total FROM employees WHERE $whereClause");
    if ($params) $countStmt->bind_param($types, ...$params);
    $countStmt->execute();
    $total = $countStmt->get_result()->fetch_assoc()['total'];
    
    $params[] = $pageSize;
    $params[] = ($page - 1) * $pageSize;
    $types .= 'ii';
    
    $stmt = $conn->prepare("
        SELECT 
            id as server_id, local_uuid, name, position, basic_salary, phone, status,
            id_number, nationality, hire_date,
            UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(updated_at) as updated_at
        FROM employees 
        WHERE $whereClause
        ORDER BY name ASC
        LIMIT ? OFFSET ?
    ");
    
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $employees = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    
    foreach ($employees as &$employee) {
        $employee['server_id'] = (int)$employee['server_id'];
        $employee['basic_salary'] = (float)$employee['basic_salary'];
        $employee['created_at'] = (int)$employee['created_at'];
        $employee['updated_at'] = (int)$employee['updated_at'];
    }
    
    ApiResponse::success([
        'employees' => recordsSnakeToCamel($employees),
        'pagination' => ['page' => $page, 'pageSize' => $pageSize, 'total' => (int)$total, 'totalPages' => ceil($total / $pageSize)]
    ]);
}

function getEmployee($conn, $id) {
    $stmt = $conn->prepare("
        SELECT 
            id as server_id, local_uuid, name, position, basic_salary, phone, status,
            id_number, nationality, hire_date,
            UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(updated_at) as updated_at
        FROM employees 
        WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL
        LIMIT 1
    ");
    
    $stmt->bind_param('ss', $id, $id);
    $stmt->execute();
    $employee = $stmt->get_result()->fetch_assoc();
    
    if (!$employee) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الموظف غير موجود');
    
    $employee['server_id'] = (int)$employee['server_id'];
    $employee['basic_salary'] = (float)$employee['basic_salary'];
    $employee['created_at'] = (int)$employee['created_at'];
    $employee['updated_at'] = (int)$employee['updated_at'];
    
    ApiResponse::success(['employee' => snakeToCamel($employee)]);
}

function createEmployee($conn, $user) {
    $input = getInput();
    ValidationRules::employees($input, $conn)->validate();
    
    $localUuid = $input['local_uuid'] ?? generateUuid();
    
    $stmt = $conn->prepare("
        INSERT INTO employees (local_uuid, name, position, basic_salary, phone, status, id_number, nationality, hire_date)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ");
    
    $stmt->bind_param('sssdsssss',
        $localUuid,
        $input['name'],
        $input['position'],
        $input['basic_salary'],
        $input['phone'] ?? null,
        $input['status'] ?? 'active',
        $input['id_number'] ?? null,
        $input['nationality'] ?? null,
        $input['hire_date'] ?? date('Y-m-d')
    );
    
    $stmt->execute();
    $serverId = $conn->insert_id;
    
    ApiLogger::info("موظف جديد: {$input['name']}", ['user_id' => $user['id'], 'employee_id' => $serverId]);
    
    ApiResponse::created(['serverId' => $serverId, 'localUuid' => $localUuid]);
}

function updateEmployee($conn, $id, $user) {
    $input = getInput();
    
    $checkStmt = $conn->prepare("SELECT id, name FROM employees WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الموظف غير موجود');
    
    ValidationRules::employees($input, $conn, true)->validate();
    
    $sets = [];
    $params = [];
    $types = '';
    
    $allowedFields = ['name' => 's', 'position' => 's', 'basic_salary' => 'd', 'phone' => 's', 'status' => 's', 'id_number' => 's', 'nationality' => 's', 'hire_date' => 's'];
    
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
    
    $stmt = $conn->prepare("UPDATE employees SET " . implode(', ', $sets) . " WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL");
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    
    ApiLogger::info("موظف تم تحديثه: {$existing['name']}", ['user_id' => $user['id']]);
    
    ApiResponse::success(['affectedRows' => $stmt->affected_rows, 'message' => 'تم التحديث بنجاح']);
}

function deleteEmployee($conn, $id, $user) {
    $checkStmt = $conn->prepare("SELECT id, name FROM employees WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الموظف غير موجود');
    
    $stmt = $conn->prepare("UPDATE employees SET deleted_at = NOW(), status = 'inactive' WHERE id = ?");
    $stmt->bind_param('i', $existing['id']);
    $stmt->execute();
    
    ApiLogger::warning("موظف تم حذفه: {$existing['name']}", ['user_id' => $user['id']]);
    
    ApiResponse::success(['message' => 'تم الحذف بنجاح']);
}
