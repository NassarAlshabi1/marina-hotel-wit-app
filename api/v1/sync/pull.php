<?php
/**
 * نقطة نهاية سحب التغييرات من السيرفر
 * GET /api/v1/sync/pull.php?since=timestamp
 * 
 * يقوم بجلب جميع السجلات المحدثة منذ آخر مزامنة
 * ويحول أسماء الحقول من snake_case إلى camelCase
 */

require_once __DIR__ . '/../config.php';

// التحقق من طريقة الطلب
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(false, null, 'طريقة الطلب غير مدعومة', 405);
}

// التحقق من المصادقة
$user = authenticateRequest();

// الحصول على معامل since
$since = isset($_GET['since']) ? (int)$_GET['since'] : 0;
$sinceDate = date('Y-m-d H:i:s', $since);

// تعريف الجداول والاستعلامات مع تطابق الحقول
$tables = [
    'rooms' => "
        SELECT 
            id as server_id,
            local_uuid,
            room_number,
            type as room_type,
            price,
            status,
            image_url,
            cleaning_status,
            last_cleaned_hotel_day,
            last_occupied_hotel_day,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM rooms 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'bookings' => "
        SELECT 
            booking_id as server_id,
            local_uuid,
            room_number,
            guest_name,
            guest_phone,
            guest_id_type,
            guest_id_number,
            guest_id_issue_date,
            guest_id_issue_place,
            guest_nationality,
            guest_email,
            guest_address,
            checkin_date,
            checkout_date,
            actual_checkout,
            status,
            payment_status,
            notes,
            expected_nights,
            calculated_nights,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(last_calculation) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM bookings 
        WHERE last_calculation > ? AND deleted_at IS NULL
    ",
    'booking_notes' => "
        SELECT 
            id as server_id,
            local_uuid,
            booking_id as booking_local_id,
            note_text,
            alert_type,
            UNIX_TIMESTAMP(alert_until) as alert_until_timestamp,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM booking_notes 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'employees' => "
        SELECT 
            id as server_id,
            local_uuid,
            name,
            position,
            basic_salary,
            phone,
            status,
            id_number,
            nationality,
            hire_date,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM employees 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'expenses' => "
        SELECT 
            id as server_id,
            local_uuid,
            expense_type,
            description,
            amount,
            UNIX_TIMESTAMP(date) as date_timestamp,
            category_uuid,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM expenses 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'expense_categories' => "
        SELECT 
            id as server_id,
            local_uuid,
            name,
            icon_name,
            color_hex,
            budget_limit,
            is_active,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM expense_categories 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'cash_transactions' => "
        SELECT 
            id as server_id,
            local_uuid,
            transaction_type,
            amount,
            reference_type,
            reference_id,
            description,
            balance_after,
            UNIX_TIMESTAMP(transaction_date) as date_timestamp,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM cash_transactions 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'payments' => "
        SELECT 
            id as server_id,
            local_uuid,
            booking_id as booking_local_id,
            amount,
            UNIX_TIMESTAMP(payment_date) as payment_date_timestamp,
            payment_method,
            revenue_type,
            description,
            notes,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM payments 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'shift_notes' => "
        SELECT 
            id as server_id,
            local_uuid,
            hotel_day_key,
            note_text,
            priority,
            category,
            is_completed,
            created_by as created_by_local_id,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM shift_notes 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'daily_closures' => "
        SELECT 
            id as server_id,
            local_uuid,
            hotel_day_key,
            total_income,
            total_expenses,
            total_bookings,
            total_checkouts,
            opening_balance,
            closing_balance,
            closed_by as closed_by_local_id,
            UNIX_TIMESTAMP(closed_at) as closed_at_timestamp,
            notes,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM daily_closures 
        WHERE updated_at > ? AND deleted_at IS NULL
    ",
    'hotel_day_ledger' => "
        SELECT 
            id as server_id,
            local_uuid,
            hotel_day_key,
            total_income,
            total_expenses,
            pending_balances,
            occupancy_rate,
            bookings_processed,
            payments_processed,
            debts_processed,
            expenses_processed,
            status,
            UNIX_TIMESTAMP(created_at) as created_at,
            UNIX_TIMESTAMP(updated_at) as updated_at,
            UNIX_TIMESTAMP(deleted_at) as deleted_at
        FROM hotel_day_ledger 
        WHERE updated_at > ? AND deleted_at IS NULL
    "
];

try {
    $data = [];
    
    // جلب السجلات المحدثة
    foreach ($tables as $name => $query) {
        $stmt = $conn->prepare($query);
        $stmt->bind_param('s', $sinceDate);
        $stmt->execute();
        $result = $stmt->get_result();
        $records = $result->fetch_all(MYSQLI_ASSOC);
        
        // تحويل القيم الرقمية والمنطقية
        foreach ($records as &$record) {
            // الأرقام العشرية
            $floatFields = ['price', 'amount', 'budget_limit', 'basic_salary', 'total_income', 'total_expenses', 'opening_balance', 'closing_balance', 'balance_after', 'pending_balances', 'occupancy_rate'];
            foreach ($floatFields as $field) {
                if (isset($record[$field])) {
                    $record[$field] = (float)$record[$field];
                }
            }
            
            // الأرقام الصحيحة
            $intFields = ['server_id', 'expected_nights', 'calculated_nights', 'total_bookings', 'total_checkouts', 'created_by_local_id', 'closed_by_local_id', 'booking_local_id', 'bookings_processed', 'payments_processed', 'debts_processed', 'expenses_processed'];
            foreach ($intFields as $field) {
                if (isset($record[$field]) && $record[$field] !== null) {
                    $record[$field] = (int)$record[$field];
                }
            }
            
            // القيم المنطقية
            $boolFields = ['is_active', 'is_completed'];
            foreach ($boolFields as $field) {
                if (isset($record[$field])) {
                    $record[$field] = (bool)$record[$field];
                }
            }
            
            // التواريخ null
            $nullableFields = ['deleted_at', 'alert_until_timestamp', 'closed_at_timestamp', 'actual_checkout', 'checkout_date'];
            foreach ($nullableFields as $field) {
                if (isset($record[$field]) && $record[$field] === 0) {
                    $record[$field] = null;
                }
            }
        }
        
        // تحويل إلى camelCase
        $data[$name] = recordsSnakeToCamel($records);
    }
    
    // جلب السجلات المحذوفة
    $deleted = [];
    foreach (array_keys($tables) as $table) {
        $delQuery = "
            SELECT local_uuid, UNIX_TIMESTAMP(deleted_at) as deleted_at 
            FROM $table 
            WHERE deleted_at > ? AND deleted_at IS NOT NULL
        ";
        $stmt = $conn->prepare($delQuery);
        $stmt->bind_param('s', $sinceDate);
        $stmt->execute();
        $result = $stmt->get_result();
        $deletedRecords = $result->fetch_all(MYSQLI_ASSOC);
        
        if (!empty($deletedRecords)) {
            // تحويل إلى camelCase
            $deleted[$table] = recordsSnakeToCamel($deletedRecords);
        }
    }
    
    jsonResponse(true, [
        'records' => $data,
        'deleted' => $deleted,
        'syncTimestamp' => time()
    ], null, 200);
    
} catch (Exception $e) {
    logError('خطأ في pull sync', [
        'error' => $e->getMessage(),
        'trace' => $e->getTraceAsString(),
        'user_id' => $user['id']
    ]);
    jsonResponse(false, null, 'حدث خطأ أثناء المزامنة', 500);
}
