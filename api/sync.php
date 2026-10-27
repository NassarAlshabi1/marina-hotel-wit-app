<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE');
header('Access-Control-Allow-Headers: Content-Type');

require_once '../includes/db.php';
require_once '../includes/auth_check.php';

// التحقق من طريقة الطلب
$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';

try {
    switch ($method) {
        case 'GET':
            handleGetRequest($conn, $action);
            break;
        case 'POST':
            handlePostRequest($conn);
            break;
        default:
            throw new Exception('طريقة غير مدعومة');
    }
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}

function handleGetRequest($conn, $action) {
    switch ($action) {
        case 'get_updates':
            getUpdates($conn);
            break;
        case 'get_status':
            getSystemStatus($conn);
            break;
        default:
            throw new Exception('إجراء غير مدعوم');
    }
}

function handlePostRequest($conn) {
    $input = json_decode(file_get_contents('php://input'), true);
    
    if (!$input) {
        throw new Exception('بيانات غير صحيحة');
    }
    
    // بدء معاملة قاعدة البيانات
    $conn->begin_transaction();
    
    try {
        $result = processSyncData($conn, $input);
        $conn->commit();
        
        echo json_encode([
            'success' => true,
            'data' => $result
        ]);
    } catch (Exception $e) {
        $conn->rollback();
        throw $e;
    }
}

function getUpdates($conn) {
    $since = $_GET['since'] ?? 0;
    $user_id = $_SESSION['user_id'];
    
    $updates = [];
    
    // جلب تحديثات الحجوزات
    $booking_query = "SELECT b.*, r.room_number, g.full_name as guest_name 
                     FROM bookings b 
                     JOIN rooms r ON b.room_id = r.room_id 
                     JOIN guests g ON b.guest_id = g.guest_id 
                     WHERE b.updated_at > FROM_UNIXTIME(?) 
                     ORDER BY b.updated_at DESC";
    
    $stmt = $conn->prepare($booking_query);
    $stmt->bind_param('i', $since);
    $stmt->execute();
    $bookings = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    
    foreach ($bookings as $booking) {
        $updates[] = [
            'type' => 'booking_update',
            'timestamp' => strtotime($booking['updated_at']),
            'data' => $booking
        ];
    }
    
    // جلب تحديثات حالة الغرف
    $room_query = "SELECT r.*, 
                   (SELECT COUNT(*) FROM bookings b WHERE b.room_id = r.room_id AND b.status = 'تم الدخول') as is_occupied
                   FROM rooms r 
                   WHERE r.updated_at > FROM_UNIXTIME(?)";
    
    $stmt = $conn->prepare($room_query);
    $stmt->bind_param('i', $since);
    $stmt->execute();
    $rooms = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    
    foreach ($rooms as $room) {
        $status = $room['is_occupied'] > 0 ? 'occupied' : 'available';
        $updates[] = [
            'type' => 'room_status_change',
            'timestamp' => strtotime($room['updated_at']),
            'data' => [
                'room_id' => $room['room_id'],
                'room_number' => $room['room_number'],
                'status' => $status
            ]
        ];
    }
    
    // جلب تحديثات المدفوعات
    $payment_query = "SELECT ct.*, b.booking_id 
                     FROM cash_transactions ct 
                     LEFT JOIN bookings b ON ct.reference_id = b.booking_id 
                     WHERE ct.transaction_time > FROM_UNIXTIME(?) 
                     AND ct.transaction_type = 'income'";
    
    $stmt = $conn->prepare($payment_query);
    $stmt->bind_param('i', $since);
    $stmt->execute();
    $payments = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    
    foreach ($payments as $payment) {
        $updates[] = [
            'type' => 'payment_received',
            'timestamp' => strtotime($payment['transaction_time']),
            'data' => $payment
        ];
    }
    
    // ترتيب التحديثات حسب الوقت
    usort($updates, function($a, $b) {
        return $b['timestamp'] - $a['timestamp'];
    });
    
    echo json_encode([
        'success' => true,
        'data' => $updates,
        'server_time' => time()
    ]);
}

function processSyncData($conn, $data) {
    $type = $data['type'] ?? '';
    $payload = $data['data'] ?? [];
    
    switch ($type) {
        case 'booking_create':
            return createBooking($conn, $payload);
        case 'booking_update':
            return updateBooking($conn, $payload);
        case 'payment_add':
            return addPayment($conn, $payload);
        case 'room_status_update':
            return updateRoomStatus($conn, $payload);
        case 'guest_create':
            return createGuest($conn, $payload);
        default:
            throw new Exception('نوع بيانات غير مدعوم: ' . $type);
    }
}

function createBooking($conn, $data) {
    $required_fields = ['guest_id', 'room_id', 'check_in_date', 'check_out_date', 'total_amount'];
    
    foreach ($required_fields as $field) {
        if (!isset($data[$field])) {
            throw new Exception("الحقل مطلوب: $field");
        }
    }
    
    $query = "INSERT INTO bookings (guest_id, room_id, check_in_date, check_out_date, 
              total_amount, status, created_by, created_at, updated_at) 
              VALUES (?, ?, ?, ?, ?, 'محجوز', ?, NOW(), NOW())";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param('iissdi', 
        $data['guest_id'],
        $data['room_id'],
        $data['check_in_date'],
        $data['check_out_date'],
        $data['total_amount'],
        $_SESSION['user_id']
    );
    
    if (!$stmt->execute()) {
        throw new Exception('فشل في إنشاء الحجز: ' . $stmt->error);
    }
    
    $booking_id = $conn->insert_id;
    
    // إضافة سجل في الصندوق إذا كان هناك دفعة مقدمة
    if (isset($data['advance_payment']) && $data['advance_payment'] > 0) {
        addCashTransaction($conn, [
            'amount' => $data['advance_payment'],
            'transaction_type' => 'income',
            'description' => "دفعة مقدمة للحجز رقم $booking_id",
            'reference_id' => $booking_id,
            'reference_type' => 'booking'
        ]);
    }
    
    return ['booking_id' => $booking_id];
}

function updateBooking($conn, $data) {
    if (!isset($data['booking_id'])) {
        throw new Exception('معرف الحجز مطلوب');
    }
    
    $updates = [];
    $params = [];
    $types = '';
    
    $allowed_fields = ['status', 'check_in_date', 'check_out_date', 'total_amount', 'notes'];
    
    foreach ($allowed_fields as $field) {
        if (isset($data[$field])) {
            $updates[] = "$field = ?";
            $params[] = $data[$field];
            $types .= 's';
        }
    }
    
    if (empty($updates)) {
        throw new Exception('لا توجد بيانات للتحديث');
    }
    
    $updates[] = "updated_at = NOW()";
    $params[] = $data['booking_id'];
    $types .= 'i';
    
    $query = "UPDATE bookings SET " . implode(', ', $updates) . " WHERE booking_id = ?";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param($types, ...$params);
    
    if (!$stmt->execute()) {
        throw new Exception('فشل في تحديث الحجز: ' . $stmt->error);
    }
    
    return ['affected_rows' => $stmt->affected_rows];
}

function addPayment($conn, $data) {
    return addCashTransaction($conn, $data);
}

function addCashTransaction($conn, $data) {
    $required_fields = ['amount', 'transaction_type', 'description'];
    
    foreach ($required_fields as $field) {
        if (!isset($data[$field]) || empty($data[$field])) {
            throw new Exception("الحقل مطلوب: $field");
        }
    }
    
    $query = "INSERT INTO cash_transactions (amount, transaction_type, description, 
              reference_id, reference_type, created_by, transaction_time) 
              VALUES (?, ?, ?, ?, ?, ?, NOW())";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param('dssssi',
        $data['amount'],
        $data['transaction_type'],
        $data['description'],
        $data['reference_id'] ?? null,
        $data['reference_type'] ?? null,
        $_SESSION['user_id']
    );
    
    if (!$stmt->execute()) {
        throw new Exception('فشل في إضافة المعاملة: ' . $stmt->error);
    }
    
    return ['transaction_id' => $conn->insert_id];
}

function updateRoomStatus($conn, $data) {
    if (!isset($data['room_id'])) {
        throw new Exception('معرف الغرفة مطلوب');
    }
    
    $query = "UPDATE rooms SET updated_at = NOW() WHERE room_id = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param('i', $data['room_id']);
    
    if (!$stmt->execute()) {
        throw new Exception('فشل في تحديث حالة الغرفة: ' . $stmt->error);
    }
    
    return ['affected_rows' => $stmt->affected_rows];
}

function createGuest($conn, $data) {
    $required_fields = ['full_name', 'phone'];
    
    foreach ($required_fields as $field) {
        if (!isset($data[$field])) {
            throw new Exception("الحقل مطلوب: $field");
        }
    }
    
    $query = "INSERT INTO guests (full_name, phone, email, id_number, nationality, 
              created_at, updated_at) 
              VALUES (?, ?, ?, ?, ?, NOW(), NOW())";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param('sssss',
        $data['full_name'],
        $data['phone'],
        $data['email'] ?? null,
        $data['id_number'] ?? null,
        $data['nationality'] ?? null
    );
    
    if (!$stmt->execute()) {
        throw new Exception('فشل في إنشاء النزيل: ' . $stmt->error);
    }
    
    return ['guest_id' => $conn->insert_id];
}

function getSystemStatus($conn) {
    $status = [
        'server_time' => time(),
        'database_status' => 'connected',
        'active_users' => getActiveUsersCount($conn),
        'pending_sync_items' => 0 // يمكن تطويرها لاحق
    ];
    
    echo json_encode([
        'success' => true,
        'data' => $status
    ]);
}

function getActiveUsersCount($conn) {
    // عدد المستخدمين النشطين في آخر 30 دقيقة
    $query = "SELECT COUNT(*) as count FROM user_sessions 
              WHERE last_activity > DATE_SUB(NOW(), INTERVAL 30 MINUTE)";
    
    $result = $conn->query($query);
    if ($result) {
        $row = $result->fetch_assoc();
        return $row['count'];
    }
    
    return 0;
}
?>

