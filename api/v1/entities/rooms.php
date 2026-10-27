<?php
/**
 * نقطة نهاية إدارة الغرف
 * Rooms Entity API
 */

require_once __DIR__ . '/../config.php';

// التحقق من المصادقة
$user = ApiMiddleware::authenticate($conn);

// Rate Limiting
ApiMiddleware::rateLimit($user['id'], 120, 60);

$method = $_SERVER['REQUEST_METHOD'];
$pathInfo = $_SERVER['PATH_INFO'] ?? '';
$id = $pathInfo ? trim($pathInfo, '/') : null;

try {
    switch ($method) {
        case 'GET':
            if ($id) {
                ApiMiddleware::requirePermission($user, Permissions::ROOMS_VIEW);
                getRoom($conn, $id);
            } else {
                ApiMiddleware::requirePermission($user, Permissions::ROOMS_VIEW);
                listRooms($conn);
            }
            break;
            
        case 'POST':
            ApiMiddleware::requirePermission($user, Permissions::ROOMS_CREATE);
            createRoom($conn, $user);
            break;
            
        case 'PUT':
            if ($id) {
                ApiMiddleware::requirePermission($user, Permissions::ROOMS_UPDATE);
                updateRoom($conn, $id, $user);
            } else {
                ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب للتحديث');
            }
            break;
            
        case 'DELETE':
            if ($id) {
                ApiMiddleware::requirePermission($user, Permissions::ROOMS_DELETE);
                deleteRoom($conn, $id, $user);
            } else {
                ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب للحذف');
            }
            break;
            
        default:
            ApiResponse::error(ApiErrorCodes::REQUEST_METHOD_NOT_ALLOWED);
    }
} finally {
    // تسجيل الطلب
    ApiMiddleware::logRequest($user, API_START_TIME);
}

/**
 * قائمة الغرف مع فلترة وصفحات
 */
function listRooms($conn) {
    $page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
    $pageSize = isset($_GET['page_size']) ? min(100, max(1, (int)$_GET['page_size'])) : 50;
    $since = isset($_GET['since']) ? (int)$_GET['since'] : null;
    $filter = isset($_GET['filter']) ? sanitizeInput($_GET['filter']) : null;
    $status = isset($_GET['status']) ? sanitizeInput($_GET['status']) : null;
    $type = isset($_GET['type']) ? sanitizeInput($_GET['type']) : null;
    $cleaningStatus = isset($_GET['cleaning_status']) ? sanitizeInput($_GET['cleaning_status']) : null;
    
    $offset = ($page - 1) * $pageSize;
    
    $where = ["deleted_at IS NULL"];
    $params = [];
    $types = '';
    
    if ($since) {
        $sinceDate = date('Y-m-d H:i:s', $since);
        $where[] = "updated_at > ?";
        $params[] = $sinceDate;
        $types .= 's';
    }
    
    if ($status) {
        $where[] = "status = ?";
        $params[] = $status;
        $types .= 's';
    }
    
    if ($type) {
        $where[] = "type = ?";
        $params[] = $type;
        $types .= 's';
    }
    
    if ($cleaningStatus) {
        $where[] = "cleaning_status = ?";
        $params[] = $cleaningStatus;
        $types .= 's';
    }
    
    if ($filter) {
        $where[] = "(room_number LIKE ? OR type LIKE ? OR status LIKE ?)";
        $filterParam = "%$filter%";
        $params[] = $filterParam;
        $params[] = $filterParam;
        $params[] = $filterParam;
        $types .= 'sss';
    }
    
    $whereClause = implode(' AND ', $where);
    
    // عد السجلات
    $countSql = "SELECT COUNT(*) as total FROM rooms WHERE $whereClause";
    $countStmt = $conn->prepare($countSql);
    if (!empty($params)) {
        $countStmt->bind_param($types, ...$params);
    }
    $countStmt->execute();
    $total = $countStmt->get_result()->fetch_assoc()['total'];
    
    // جلب السجلات
    $params[] = $pageSize;
    $params[] = $offset;
    $types .= 'ii';
    
    $stmt = $conn->prepare("
        SELECT 
            id as server_id,
            local_uuid,
            room_number,
            type,
            price,
            status,
            image_url,
            cleaning_status,
            last_cleaned_hotel_day,
            last_occupied_hotel_day,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at
        FROM rooms 
        WHERE $whereClause
        ORDER BY CAST(room_number AS UNSIGNED) ASC
        LIMIT ? OFFSET ?
    ");
    
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $result = $stmt->get_result();
    $rooms = $result->fetch_all(MYSQLI_ASSOC);
    
    // تحويل القيم
    foreach ($rooms as &$room) {
        $room['price'] = (float)$room['price'];
        $room['server_id'] = (int)$room['server_id'];
        $room['created_at'] = (int)$room['created_at'];
        $room['updated_at'] = (int)$room['updated_at'];
    }
    
    // تحويل إلى camelCase
    $rooms = recordsSnakeToCamel($rooms);
    
    ApiResponse::success([
        'rooms' => $rooms,
        'pagination' => [
            'page' => $page,
            'pageSize' => $pageSize,
            'total' => (int)$total,
            'totalPages' => ceil($total / $pageSize)
        ]
    ]);
}

/**
 * تفاصيل غرفة واحدة
 */
function getRoom($conn, $id) {
    $stmt = $conn->prepare("
        SELECT 
            id as server_id,
            local_uuid,
            room_number,
            type,
            price,
            status,
            image_url,
            cleaning_status,
            last_cleaned_hotel_day,
            last_occupied_hotel_day,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at
        FROM rooms 
        WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL
        LIMIT 1
    ");
    
    $stmt->bind_param('ss', $id, $id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الغرفة غير موجودة');
    }
    
    $room = $result->fetch_assoc();
    $room['price'] = (float)$room['price'];
    $room['server_id'] = (int)$room['server_id'];
    $room['created_at'] = (int)$room['created_at'];
    $room['updated_at'] = (int)$room['updated_at'];
    
    // تحويل إلى camelCase
    $room = snakeToCamel($room);
    
    ApiResponse::success(['room' => $room]);
}

/**
 * إنشاء غرفة جديدة
 */
function createRoom($conn, $user) {
    $input = getInput();
    
    // التحقق من البيانات
    $validator = ValidationRules::rooms($input, $conn, false);
    $validator->validate();
    
    $localUuid = $input['local_uuid'] ?? generateUuid();
    $roomNumber = sanitizeInput($input['room_number']);
    $type = sanitizeInput($input['type']);
    $price = (float)$input['price'];
    $status = sanitizeInput($input['status']);
    $imageUrl = isset($input['image_url']) ? sanitizeInput($input['image_url']) : null;
    $cleaningStatus = isset($input['cleaning_status']) ? sanitizeInput($input['cleaning_status']) : 'clean';
    
    try {
        $stmt = $conn->prepare("
            INSERT INTO rooms (local_uuid, room_number, type, price, status, image_url, cleaning_status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ");
        
        $stmt->bind_param('sssdsss', $localUuid, $roomNumber, $type, $price, $status, $imageUrl, $cleaningStatus);
        $stmt->execute();
        
        $serverId = $conn->insert_id;
        
        ApiLogger::info("غرفة جديدة تم إنشاؤها: $roomNumber", [
            'user_id' => $user['id'],
            'room_id' => $serverId
        ]);
        
        ApiResponse::created([
            'serverId' => $serverId,
            'localUuid' => $localUuid,
            'roomNumber' => $roomNumber
        ]);
        
    } catch (mysqli_sql_exception $e) {
        if ($e->getCode() === 1062) { // Duplicate entry
            ApiResponse::error(ApiErrorCodes::VALIDATION_DUPLICATE_ENTRY, 'رقم الغرفة موجود مسبقاً');
        }
        throw $e;
    }
}

/**
 * تحديث غرفة موجودة
 */
function updateRoom($conn, $id, $user) {
    $input = getInput();
    
    // التحقق من وجود الغرفة
    $checkStmt = $conn->prepare("SELECT id, room_number FROM rooms WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) {
        ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الغرفة غير موجودة');
    }
    
    // التحقق من البيانات
    $validator = ValidationRules::rooms($input, $conn, true, $existing['id']);
    $validator->validate();
    
    $sets = [];
    $params = [];
    $types = '';
    
    $allowedFields = [
        'room_number' => 's',
        'type' => 's',
        'price' => 'd',
        'status' => 's',
        'image_url' => 's',
        'cleaning_status' => 's',
        'last_cleaned_hotel_day' => 's',
        'last_occupied_hotel_day' => 's'
    ];
    
    foreach ($allowedFields as $field => $type) {
        if (isset($input[$field])) {
            $sets[] = "$field = ?";
            $value = $field === 'price' ? (float)$input[$field] : sanitizeInput($input[$field]);
            $params[] = $value;
            $types .= $type;
        }
    }
    
    if (empty($sets)) {
        ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'لا توجد بيانات للتحديث');
    }
    
    $params[] = $id;
    $params[] = $id;
    $types .= 'ss';
    
    $sql = "UPDATE rooms SET " . implode(', ', $sets) . " WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL";
    
    try {
        $stmt = $conn->prepare($sql);
        $stmt->bind_param($types, ...$params);
        $stmt->execute();
        
        ApiLogger::info("غرفة تم تحديثها: {$existing['room_number']}", [
            'user_id' => $user['id'],
            'room_id' => $existing['id'],
            'changes' => array_keys($input)
        ]);
        
        ApiResponse::success([
            'affectedRows' => $stmt->affected_rows,
            'message' => 'تم التحديث بنجاح'
        ]);
        
    } catch (mysqli_sql_exception $e) {
        if ($e->getCode() === 1062) {
            ApiResponse::error(ApiErrorCodes::VALIDATION_DUPLICATE_ENTRY, 'رقم الغرفة موجود مسبقاً');
        }
        throw $e;
    }
}

/**
 * حذف غرفة (حذف ناعم)
 */
function deleteRoom($conn, $id, $user) {
    // التحقق من وجود الغرفة
    $checkStmt = $conn->prepare("SELECT id, room_number, status FROM rooms WHERE (id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) {
        ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الغرفة غير موجودة');
    }
    
    // التحقق من عدم وجود حجوزات نشطة
    $bookingStmt = $conn->prepare("SELECT COUNT(*) as count FROM bookings WHERE room_number = (SELECT room_number FROM rooms WHERE id = ?) AND status = 'محجوزة' AND deleted_at IS NULL");
    $bookingStmt->bind_param('i', $existing['id']);
    $bookingStmt->execute();
    $bookingCount = $bookingStmt->get_result()->fetch_assoc()['count'];
    
    if ($bookingCount > 0) {
        ApiResponse::error(ApiErrorCodes::DB_CONSTRAINT_VIOLATION, 'لا يمكن حذف غرفة بها حجوزات نشطة');
    }
    
    $stmt = $conn->prepare("UPDATE rooms SET deleted_at = NOW() WHERE id = ?");
    $stmt->bind_param('i', $existing['id']);
    $stmt->execute();
    
    ApiLogger::warning("غرفة تم حذفها: {$existing['room_number']}", [
        'user_id' => $user['id'],
        'room_id' => $existing['id']
    ]);
    
    ApiResponse::success([
        'message' => 'تم الحذف بنجاح',
        'affectedRows' => $stmt->affected_rows
    ]);
}
