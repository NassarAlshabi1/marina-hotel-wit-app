<?php
require_once __DIR__ . '/../bootstrap.php';
require_once __DIR__ . '/../middleware.php';
$auth = require_auth($CONFIG);

$entities = [
    'rooms' => ['table' => 'rooms', 'pk' => 'room_number', 'pk_type' => 's', 'writable' => ['room_number'=>'s','type'=>'s','price'=>'d','status'=>'s','image_url'=>'s']],
    'bookings' => ['table' => 'bookings', 'pk' => 'booking_id', 'pk_type' => 'i', 'writable' => [
        'guest_id'=>'i','guest_name'=>'s','guest_id_type'=>'s','guest_id_number'=>'s','guest_id_issue_date'=>'s','guest_id_issue_place'=>'s','guest_phone'=>'s','guest_nationality'=>'s','guest_email'=>'s','guest_address'=>'s','room_number'=>'s','checkin_date'=>'s','checkout_date'=>'s','status'=>'s','notes'=>'s','expected_nights'=>'i','actual_checkout'=>'s','calculated_nights'=>'i'
    ]],
    'booking_notes' => ['table' => 'booking_notes', 'pk' => 'note_id', 'pk_type' => 'i', 'writable' => [
        'booking_id'=>'i','note_text'=>'s','alert_type'=>'s','alert_until'=>'s','is_active'=>'i','created_at'=>'s','created_by'=>'s'
    ]],
    'employees' => ['table' => 'employees', 'pk' => 'id', 'pk_type' => 'i', 'writable' => ['name'=>'s','basic_salary'=>'d','status'=>'s']],
    'expenses' => ['table' => 'expenses', 'pk' => 'id', 'pk_type' => 'i', 'writable' => ['expense_type'=>'s','related_id'=>'i','description'=>'s','amount'=>'d','date'=>'s','cash_transaction_id'=>'i']],
    'cash_transactions' => ['table' => 'cash_transactions', 'pk' => 'id', 'pk_type' => 'i', 'writable' => ['register_id'=>'i','transaction_type'=>'s','amount'=>'d','reference_type'=>'s','reference_id'=>'i','description'=>'s','transaction_time'=>'s','created_by'=>'i']],
    'payments' => ['table' => 'payment', 'pk' => 'payment_id', 'pk_type' => 'i', 'writable' => ['booking_id'=>'i','room_number'=>'i','amount'=>'d','payment_date'=>'s','notes'=>'s','payment_method'=>'s','revenue_type'=>'s','cash_transaction_id'=>'i']],
];

$body = json_input();
$changes = $body['changes'] ?? [];
if (!is_array($changes)) {
    send_json(false, ['error' => 'Invalid payload'], null, 400);
}

$results = [];
$warnings = [];
$conn->begin_transaction();
try {
    foreach ($changes as $ch) {
        $entity = $ch['entity'] ?? null;
        $op = $ch['op'] ?? null;
        $uuid = $ch['uuid'] ?? null;
        $server_id = $ch['server_id'] ?? null;
        $data = $ch['data'] ?? [];
        $client_ts = isset($ch['client_ts']) ? (int)$ch['client_ts'] : null;

        if (!$entity || !isset($entities[$entity]) || !$op) {
            $results[] = ['uuid'=>$uuid, 'success'=>false, 'error'=>'Unknown entity/op'];
            continue;
        }
        $cfg = $entities[$entity];
        $table = $cfg['table'];
        $pk = $cfg['pk'];
        $pk_type = $cfg['pk_type'];

        if ($op === 'create') {
            $cols = [];$vals=[];$types='';
            foreach ($cfg['writable'] as $col=>$t) {
                if (array_key_exists($col, $data)) { $cols[] = "`$col`"; $vals[]=$data[$col]; $types.=$t; }
            }
            if (!$cols) { $results[] = ['uuid'=>$uuid,'success'=>false,'error'=>'No fields']; continue; }
            $sql = "INSERT INTO `$table` (".implode(',', $cols).") VALUES (".implode(',', array_fill(0,count($cols),'?')).")";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param($types, ...$vals);
            $stmt->execute();
            $new_id = $pk_type==='i' ? $stmt->insert_id : ($data[$pk] ?? null);
            $stmt->close();
            $results[] = ['entity'=>$entity,'op'=>$op,'uuid'=>$uuid,'server_id'=>$new_id,'server_ts'=>time(),'success'=>true];
        } elseif ($op === 'update') {
            $id_val = $server_id;
            if ($id_val === null && isset($data[$pk])) $id_val = $data[$pk];
            if ($id_val === null) { $results[] = ['uuid'=>$uuid,'success'=>false,'error'=>'Missing id']; continue; }

            if ($client_ts) {
                $stmt = $conn->prepare("SELECT UNIX_TIMESTAMP(COALESCE(updated_at, created_at)) AS ts FROM `$table` WHERE `$pk`=? LIMIT 1");
                $stmt->bind_param($pk_type, $id_val);
                $stmt->execute();
                $row = $stmt->get_result()->fetch_assoc();
                $stmt->close();
                if ($row && (int)$row['ts'] > $client_ts) {
                    $results[] = ['uuid'=>$uuid, 'success'=>false, 'conflict'=>true, 'server_id'=>$id_val];
                    continue;
                }
            }
            $sets=[];$vals=[];$types='';
            foreach ($cfg['writable'] as $col=>$t) { if (array_key_exists($col, $data) && $col!==$pk) { $sets[]="`$col`=?"; $vals[]=$data[$col]; $types.=$t; } }
            if (!$sets) { $results[] = ['uuid'=>$uuid,'success'=>false,'error'=>'No fields']; continue; }
            $sql = "UPDATE `$table` SET ".implode(',', $sets).", `updated_at`=CURRENT_TIMESTAMP WHERE `$pk`=?";
            $types.=$pk_type; $vals[]=$id_val;
            $stmt = $conn->prepare($sql);
            $stmt->bind_param($types, ...$vals);
            $stmt->execute();
            $stmt->close();
            $results[] = ['entity'=>$entity,'op'=>$op,'uuid'=>$uuid,'server_id'=>$id_val,'server_ts'=>time(),'success'=>true];
        } elseif ($op === 'delete') {
            $id_val = $server_id;
            if ($id_val === null && isset($data[$pk])) $id_val = $data[$pk];
            if ($id_val === null) { $results[] = ['uuid'=>$uuid,'success'=>false,'error'=>'Missing id']; continue; }
            $hasDeleted = false;
            $chk = $conn->prepare("SHOW COLUMNS FROM `$table` LIKE 'deleted_at'");
            $chk->execute(); $hasDeleted = $chk->get_result()->num_rows>0; $chk->close();
            if ($hasDeleted) {
                $stmt = $conn->prepare("UPDATE `$table` SET `deleted_at` = CURRENT_TIMESTAMP WHERE `$pk`=?");
                $stmt->bind_param($pk_type, $id_val);
                $stmt->execute();
                $stmt->close();
            } else {
                $stmt = $conn->prepare("DELETE FROM `$table` WHERE `$pk`=?");
                $stmt->bind_param($pk_type, $id_val);
                $stmt->execute();
                $stmt->close();
                $warnings[] = "$table has no deleted_at; hard-deleted";
            }
            $results[] = ['entity'=>$entity,'op'=>$op,'uuid'=>$uuid,'server_id'=>$id_val,'server_ts'=>time(),'success'=>true];
        } else {
            $results[] = ['uuid'=>$uuid,'success'=>false,'error'=>'Unsupported op'];
        }
    }
    $conn->commit();
} catch (Exception $e) {
    $conn->rollback();
    send_json(false, ['error'=>$e->getMessage()], ['server_time'=>time()]);
}

send_json(true, ['results'=>$results], ['server_time'=>time(),'warnings'=>$warnings]);
