<?php
/**
 * نقطة نهاية رفع التغييرات إلى السيرفر
 * POST /api/v1/sync/push.php
 * 
 * يستقبل التغييرات من Flutter ويحولها من camelCase إلى snake_case
 */

require_once __DIR__ . '/../config.php';

// التحقق من طريقة الطلب
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(false, null, 'طريقة الطلب غير مدعومة', 405);
}

// التحقق من المصادقة
$user = authenticateRequest();

// الحصول على بيانات الإدخال
$input = getInput();
$changes = $input['changes'] ?? [];

if (empty($changes)) {
    jsonResponse(true, ['results' => []], null, 200);
}

$results = [];

try {
    $conn->begin_transaction();
    
    foreach ($changes as $change) {
        $entity = $change['entity'] ?? '';
        $action = $change['action'] ?? '';
        $data = $change['data'] ?? [];
        $localUuid = $change['local_uuid'] ?? '';
        
        if (empty($entity) || empty($action) || empty($localUuid)) {
            $results[] = [
                'localUuid' => $localUuid,
                'success' => false,
                'error' => 'بيانات غير كاملة'
            ];
            continue;
        }
        
        if (!isValidEntity($entity)) {
            $results[] = [
                'localUuid' => $localUuid,
                'success' => false,
                'error' => 'اسم كيان غير صالح: ' . $entity
            ];
            continue;
        }
        
        try {
            // تحويل البيانات من camelCase إلى snake_case
            $snakeData = camelToSnake($data);
            
            // تطبيق تحويلات خاصة بكل جدول
            $snakeData = applyEntityFieldMapping($entity, $snakeData);
            
            switch ($action) {
                case 'create':
                    $result = createRecord($conn, $entity, $snakeData, $localUuid);
                    break;
                case 'update':
                    $result = updateRecord($conn, $entity, $snakeData, $localUuid);
                    break;
                case 'delete':
                    $result = deleteRecord($conn, $entity, $localUuid);
                    break;
                default:
                    $result = [
                        'success' => false,
                        'error' => "إجراء غير معروف: $action"
                    ];
            }
            
            $results[] = array_merge([
                'localUuid' => $localUuid,
                'success' => $result['success']
            ], $result);
            
        } catch (Exception $e) {
            $results[] = [
                'localUuid' => $localUuid,
                'success' => false,
                'error' => $e->getMessage()
            ];
        }
    }
    
    $conn->commit();
    
    jsonResponse(true, ['results' => $results], null, 200);
    
} catch (Exception $e) {
    $conn->rollback();
    logError('خطأ في push sync', [
        'error' => $e->getMessage(),
        'trace' => $e->getTraceAsString(),
        'user_id' => $user['id']
    ]);
    jsonResponse(false, null, 'حدث خطأ أثناء المزامنة', 500);
}

/**
 * قائمة الكيانات المسموح بها (whitelist)
 */
function getValidEntities() {
    return [
        'rooms',
        'bookings',
        'booking_notes',
        'employees',
        'expenses',
        'expense_categories',
        'cash_transactions',
        'payments',
        'shift_notes',
        'daily_closures'
    ];
}

/**
 * التحقق من صحة اسم الكيان
 */
function isValidEntity($entity) {
    return in_array($entity, getValidEntities(), true);
}

/**
 * تطبيق تحويلات خاصة لحقول كل جدول
 */
function applyEntityFieldMapping($entity, $data) {
    $mappings = [
        'rooms' => [
            'room_type' => 'type' // في MySQL نستخدم type
        ],
        'bookings' => [
            'guest_id_issue_date' => 'guest_id_issue_date',
            'guest_id_issue_place' => 'guest_id_issue_place'
        ],
        'booking_notes' => [
            'booking_local_id' => 'booking_id',
            'alert_until_timestamp' => 'alert_until'
        ],
        'cash_transactions' => [
            'date_timestamp' => 'transaction_date'
        ],
        'payments' => [
            'booking_local_id' => 'booking_id',
            'payment_date_timestamp' => 'payment_date'
        ],
        'expenses' => [
            'date_timestamp' => 'date'
        ],
        'shift_notes' => [
            'created_by_local_id' => 'created_by'
        ],
        'daily_closures' => [
            'closed_by_local_id' => 'closed_by',
            'closed_at_timestamp' => 'closed_at'
        ]
    ];
    
    if (isset($mappings[$entity])) {
        foreach ($mappings[$entity] as $from => $to) {
            if (isset($data[$from])) {
                $data[$to] = $data[$from];
                if ($from !== $to) {
                    unset($data[$from]);
                }
            }
        }
    }
    
    // تحويل timestamps إلى تواريخ MySQL
    $timestampFields = ['alert_until', 'transaction_date', 'payment_date', 'date', 'closed_at'];
    foreach ($timestampFields as $field) {
        if (isset($data[$field]) && is_numeric($data[$field]) && $data[$field] > 0) {
            $data[$field] = date('Y-m-d H:i:s', $data[$field]);
        }
    }
    
    return $data;
}

/**
 * إنشاء سجل جديد
 */
function createRecord($conn, $table, $data, $uuid) {
    // التحقق من وجود السجل مسبقًا
    $check = $conn->prepare("SELECT id FROM $table WHERE local_uuid = ? LIMIT 1");
    $check->bind_param('s', $uuid);
    $check->execute();
    $existing = $check->get_result();
    
    if ($existing->num_rows > 0) {
        // السجل موجود، قم بالتحديث بدلاً من الإنشاء
        return updateRecord($conn, $table, $data, $uuid);
    }
    
    // إضافة local_uuid إلى البيانات
    $data['local_uuid'] = $uuid;
    
    // تنظيف البيانات وإزالة الحقول غير المسموح بها
    $data = filterAllowedFields($table, $data);
    
    if (empty($data)) {
        return [
            'success' => false,
            'error' => 'لا توجد حقول صالحة للإدراج'
        ];
    }
    
    // إعداد الحقول والقيم
    $columns = [];
    $placeholders = [];
    $values = [];
    $types = '';
    
    foreach ($data as $key => $value) {
        $columns[] = $key;
        $placeholders[] = '?';
        $values[] = $value;
        
        // تحديد نوع البيانات
        if (is_int($value)) {
            $types .= 'i';
        } elseif (is_float($value)) {
            $types .= 'd';
        } elseif (is_bool($value)) {
            $types .= 'i';
            $values[count($values) - 1] = $value ? 1 : 0;
        } else {
            $types .= 's';
        }
    }
    
    $sql = sprintf(
        "INSERT INTO %s (%s) VALUES (%s)",
        $table,
        implode(', ', $columns),
        implode(', ', $placeholders)
    );
    
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return [
            'success' => false,
            'error' => 'فشل تحضير الاستعلام: ' . $conn->error
        ];
    }
    
    $stmt->bind_param($types, ...$values);
    $stmt->execute();
    
    if ($stmt->error) {
        return [
            'success' => false,
            'error' => 'فشل تنفيذ الاستعلام: ' . $stmt->error
        ];
    }
    
    return [
        'success' => true,
        'server_id' => $conn->insert_id,
        'status' => 'created'
    ];
}

/**
 * تحديث سجل موجود
 */
function updateRecord($conn, $table, $data, $uuid) {
    // إزالة local_uuid من البيانات إذا كان موجودًا
    unset($data['local_uuid']);
    
    // تنظيف البيانات
    $data = filterAllowedFields($table, $data);
    
    if (empty($data)) {
        return [
            'success' => true,
            'status' => 'no_changes'
        ];
    }
    
    // إعداد الحقول والقيم
    $sets = [];
    $values = [];
    $types = '';
    
    foreach ($data as $key => $value) {
        $sets[] = "$key = ?";
        $values[] = $value;
        
        // تحديد نوع البيانات
        if (is_int($value)) {
            $types .= 'i';
        } elseif (is_float($value)) {
            $types .= 'd';
        } elseif (is_bool($value)) {
            $types .= 'i';
            $values[count($values) - 1] = $value ? 1 : 0;
        } else {
            $types .= 's';
        }
    }
    
    // إضافة local_uuid للشرط
    $values[] = $uuid;
    $types .= 's';
    
    $sql = sprintf(
        "UPDATE %s SET %s WHERE local_uuid = ?",
        $table,
        implode(', ', $sets)
    );
    
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        return [
            'success' => false,
            'error' => 'فشل تحضير الاستعلام: ' . $conn->error
        ];
    }
    
    $stmt->bind_param($types, ...$values);
    $stmt->execute();
    
    if ($stmt->error) {
        return [
            'success' => false,
            'error' => 'فشل تنفيذ الاستعلام: ' . $stmt->error
        ];
    }
    
    return [
        'success' => true,
        'status' => 'updated',
        'affected_rows' => $stmt->affected_rows
    ];
}

/**
 * حذف سجل (حذف ناعم)
 */
function deleteRecord($conn, $table, $uuid) {
    $stmt = $conn->prepare("UPDATE $table SET deleted_at = NOW() WHERE local_uuid = ?");
    if (!$stmt) {
        return [
            'success' => false,
            'error' => 'فشل تحضير الاستعلام: ' . $conn->error
        ];
    }
    
    $stmt->bind_param('s', $uuid);
    $stmt->execute();
    
    if ($stmt->error) {
        return [
            'success' => false,
            'error' => 'فشل تنفيذ الاستعلام: ' . $stmt->error
        ];
    }
    
    return [
        'success' => true,
        'status' => 'deleted',
        'affected_rows' => $stmt->affected_rows
    ];
}

/**
 * تصفية الحقول المسموح بها لكل جدول
 */
function filterAllowedFields($table, $data) {
    $allowedFields = [
        'rooms' => ['local_uuid', 'room_number', 'type', 'price', 'status', 'image_url', 'cleaning_status', 'last_cleaned_hotel_day', 'last_occupied_hotel_day'],
        'bookings' => ['local_uuid', 'room_number', 'guest_name', 'guest_phone', 'guest_id_type', 'guest_id_number', 'guest_id_issue_date', 'guest_id_issue_place', 'guest_nationality', 'guest_email', 'guest_address', 'checkin_date', 'checkout_date', 'actual_checkout', 'status', 'payment_status', 'notes', 'expected_nights', 'calculated_nights'],
        'booking_notes' => ['local_uuid', 'booking_id', 'note_text', 'alert_type', 'alert_until'],
        'employees' => ['local_uuid', 'name', 'position', 'basic_salary', 'phone', 'status', 'id_number', 'nationality', 'hire_date'],
        'expenses' => ['local_uuid', 'expense_type', 'description', 'amount', 'date', 'category_uuid'],
        'expense_categories' => ['local_uuid', 'name', 'icon_name', 'color_hex', 'budget_limit', 'is_active'],
        'cash_transactions' => ['local_uuid', 'transaction_type', 'amount', 'reference_type', 'reference_id', 'description', 'transaction_date', 'balance_after'],
        'payments' => ['local_uuid', 'booking_id', 'amount', 'payment_date', 'payment_method', 'revenue_type', 'description', 'notes'],
        'shift_notes' => ['local_uuid', 'hotel_day_key', 'note_text', 'priority', 'category', 'is_completed', 'created_by'],
        'daily_closures' => ['local_uuid', 'hotel_day_key', 'total_income', 'total_expenses', 'total_bookings', 'total_checkouts', 'opening_balance', 'closing_balance', 'closed_by', 'closed_at', 'notes']
    ];
    
    if (!isset($allowedFields[$table])) {
        return [];
    }
    
    $filtered = [];
    foreach ($data as $key => $value) {
        if (in_array($key, $allowedFields[$table])) {
            $filtered[$key] = $value;
        }
    }
    
    return $filtered;
}
