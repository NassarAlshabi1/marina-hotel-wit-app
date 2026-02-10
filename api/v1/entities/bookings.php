<?php
/**
 * نقطة نهاية إدارة الحجوزات
 * Bookings Entity API
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
            ApiMiddleware::requirePermission($user, Permissions::BOOKINGS_VIEW);
            $id ? getBooking($conn, $id) : listBookings($conn);
            break;
        case 'POST':
            ApiMiddleware::requirePermission($user, Permissions::BOOKINGS_CREATE);
            createBooking($conn, $user);
            break;
        case 'PUT':
            if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب');
            ApiMiddleware::requirePermission($user, Permissions::BOOKINGS_UPDATE);
            updateBooking($conn, $id, $user);
            break;
        case 'DELETE':
            if (!$id) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'المعرف مطلوب');
            ApiMiddleware::requirePermission($user, Permissions::BOOKINGS_DELETE);
            deleteBooking($conn, $id, $user);
            break;
        default:
            ApiResponse::error(ApiErrorCodes::REQUEST_METHOD_NOT_ALLOWED);
    }
} finally {
    ApiMiddleware::logRequest($user, API_START_TIME);
}

function listBookings($conn) {
    $page = max(1, (int)($_GET['page'] ?? 1));
    $pageSize = min(100, max(1, (int)($_GET['page_size'] ?? 50)));
    $status = $_GET['status'] ?? null;
    $roomNumber = $_GET['room_number'] ?? null;
    $since = isset($_GET['since']) ? (int)$_GET['since'] : null;
    
    $where = ["deleted_at IS NULL"];
    $params = [];
    $types = '';
    
    if ($since) {
        $where[] = "last_calculation > ?";
        $params[] = date('Y-m-d H:i:s', $since);
        $types .= 's';
    }
    if ($status) {
        $where[] = "status = ?";
        $params[] = $status;
        $types .= 's';
    }
    if ($roomNumber) {
        $where[] = "room_number = ?";
        $params[] = $roomNumber;
        $types .= 's';
    }
    
    $whereClause = implode(' AND ', $where);
    
    $countStmt = $conn->prepare("SELECT COUNT(*) as total FROM bookings WHERE $whereClause");
    if ($params) $countStmt->bind_param($types, ...$params);
    $countStmt->execute();
    $total = $countStmt->get_result()->fetch_assoc()['total'];
    
    $params[] = $pageSize;
    $params[] = ($page - 1) * $pageSize;
    $types .= 'ii';
    
    $stmt = $conn->prepare("
        SELECT 
            booking_id as server_id, local_uuid, room_number, guest_name, guest_phone,
            guest_id_type, guest_id_number, guest_id_issue_date, guest_id_issue_place,
            guest_nationality, guest_email, guest_address, checkin_date, checkout_date,
            actual_checkout, status, payment_status, notes, expected_nights, calculated_nights,
            UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(last_calculation) as updated_at
        FROM bookings 
        WHERE $whereClause
        ORDER BY checkin_date DESC
        LIMIT ? OFFSET ?
    ");
    
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $bookings = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    
    foreach ($bookings as &$booking) {
        $booking['server_id'] = (int)$booking['server_id'];
        $booking['expected_nights'] = (int)$booking['expected_nights'];
        $booking['calculated_nights'] = (int)$booking['calculated_nights'];
        $booking['created_at'] = (int)$booking['created_at'];
        $booking['updated_at'] = (int)$booking['updated_at'];
    }
    
    ApiResponse::success([
        'bookings' => recordsSnakeToCamel($bookings),
        'pagination' => ['page' => $page, 'pageSize' => $pageSize, 'total' => (int)$total, 'totalPages' => ceil($total / $pageSize)]
    ]);
}

function getBooking($conn, $id) {
    $stmt = $conn->prepare("
        SELECT 
            booking_id as server_id, local_uuid, room_number, guest_name, guest_phone,
            guest_id_type, guest_id_number, guest_id_issue_date, guest_id_issue_place,
            guest_nationality, guest_email, guest_address, checkin_date, checkout_date,
            actual_checkout, status, payment_status, notes, expected_nights, calculated_nights,
            UNIX_TIMESTAMP(created_at) as created_at, UNIX_TIMESTAMP(last_calculation) as updated_at
        FROM bookings 
        WHERE (booking_id = ? OR local_uuid = ?) AND deleted_at IS NULL
        LIMIT 1
    ");
    
    $stmt->bind_param('ss', $id, $id);
    $stmt->execute();
    $booking = $stmt->get_result()->fetch_assoc();
    
    if (!$booking) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الحجز غير موجود');
    
    $booking['server_id'] = (int)$booking['server_id'];
    $booking['expected_nights'] = (int)$booking['expected_nights'];
    $booking['calculated_nights'] = (int)$booking['calculated_nights'];
    $booking['created_at'] = (int)$booking['created_at'];
    $booking['updated_at'] = (int)$booking['updated_at'];
    
    ApiResponse::success(['booking' => snakeToCamel($booking)]);
}

function createBooking($conn, $user) {
    $input = getInput();
    ValidationRules::bookings($input, $conn)->validate();
    
    $localUuid = $input['local_uuid'] ?? generateUuid();
    
    $conn->begin_transaction();
    try {
        $stmt = $conn->prepare("
            INSERT INTO bookings (
                local_uuid, room_number, guest_name, guest_phone, guest_id_type, guest_id_number,
                guest_id_issue_date, guest_id_issue_place, guest_nationality, guest_email,
                guest_address, checkin_date, checkout_date, status, payment_status, notes, expected_nights
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ");
        
        $stmt->bind_param('ssssssssssssssssi',
            $localUuid,
            $input['room_number'],
            $input['guest_name'],
            $input['guest_phone'],
            $input['guest_id_type'] ?? 'بطاقة شخصية',
            $input['guest_id_number'] ?? '',
            $input['guest_id_issue_date'] ?? null,
            $input['guest_id_issue_place'] ?? null,
            $input['guest_nationality'] ?? '',
            $input['guest_email'] ?? null,
            $input['guest_address'] ?? null,
            $input['checkin_date'],
            $input['checkout_date'] ?? null,
            $input['status'],
            $input['payment_status'] ?? 'pending',
            $input['notes'] ?? null,
            $input['expected_nights'] ?? 1
        );
        
        $stmt->execute();
        $serverId = $conn->insert_id;
        
        // تحديث حالة الغرفة
        $updateRoom = $conn->prepare("UPDATE rooms SET status = ? WHERE room_number = ?");
        $updateRoom->bind_param('ss', $input['status'], $input['room_number']);
        $updateRoom->execute();
        
        $conn->commit();
        
        ApiLogger::info("حجز جديد: {$input['guest_name']} - غرفة {$input['room_number']}", [
            'user_id' => $user['id'], 'booking_id' => $serverId
        ]);
        
        ApiResponse::created(['serverId' => $serverId, 'localUuid' => $localUuid]);
        
    } catch (Exception $e) {
        $conn->rollback();
        throw $e;
    }
}

function updateBooking($conn, $id, $user) {
    $input = getInput();
    
    $checkStmt = $conn->prepare("SELECT booking_id, room_number FROM bookings WHERE (booking_id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الحجز غير موجود');
    
    ValidationRules::bookings($input, $conn, true)->validate();
    
    $sets = [];
    $params = [];
    $types = '';
    
    $allowedFields = [
        'guest_name', 'guest_phone', 'guest_id_type', 'guest_id_number', 'guest_id_issue_date',
        'guest_id_issue_place', 'guest_nationality', 'guest_email', 'guest_address',
        'checkout_date', 'actual_checkout', 'status', 'payment_status', 'notes', 'expected_nights'
    ];
    
    foreach ($allowedFields as $field) {
        if (isset($input[$field])) {
            $sets[] = "$field = ?";
            $params[] = $input[$field];
            $types .= in_array($field, ['expected_nights']) ? 'i' : 's';
        }
    }
    
    if (empty($sets)) ApiResponse::error(ApiErrorCodes::VALIDATION_REQUIRED_FIELD, 'لا توجد بيانات للتحديث');
    
    $params[] = $id;
    $params[] = $id;
    $types .= 'ss';
    
    $stmt = $conn->prepare("UPDATE bookings SET " . implode(', ', $sets) . " WHERE (booking_id = ? OR local_uuid = ?) AND deleted_at IS NULL");
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    
    ApiLogger::info("حجز تم تحديثه: رقم {$existing['booking_id']}", ['user_id' => $user['id']]);
    
    ApiResponse::success(['affectedRows' => $stmt->affected_rows, 'message' => 'تم التحديث بنجاح']);
}

function deleteBooking($conn, $id, $user) {
    $checkStmt = $conn->prepare("SELECT booking_id, room_number FROM bookings WHERE (booking_id = ? OR local_uuid = ?) AND deleted_at IS NULL LIMIT 1");
    $checkStmt->bind_param('ss', $id, $id);
    $checkStmt->execute();
    $existing = $checkStmt->get_result()->fetch_assoc();
    
    if (!$existing) ApiResponse::error(ApiErrorCodes::RESOURCE_NOT_FOUND, 'الحجز غير موجود');
    
    $stmt = $conn->prepare("UPDATE bookings SET deleted_at = NOW(), status = 'ملغي' WHERE booking_id = ?");
    $stmt->bind_param('i', $existing['booking_id']);
    $stmt->execute();
    
    // تحديث حالة الغرفة إلى شاغرة
    $updateRoom = $conn->prepare("UPDATE rooms SET status = 'شاغرة' WHERE room_number = ?");
    $updateRoom->bind_param('s', $existing['room_number']);
    $updateRoom->execute();
    
    ApiLogger::warning("حجز تم حذفه: رقم {$existing['booking_id']}", ['user_id' => $user['id']]);
    
    ApiResponse::success(['message' => 'تم الحذف بنجاح']);
}
