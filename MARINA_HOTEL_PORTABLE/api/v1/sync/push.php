<?php
require_once __DIR__ . '/../bootstrap.php';

current_user_or_fail(true);

$entities = [
    'rooms' => ['table' => 'rooms', 'pk' => 'room_number', 'pk_type' => 's', 'writable' => ['room_number'=>'s','type'=>'s','price'=>'d','status'=>'s']],
    'bookings' => ['table' => 'bookings', 'pk' => 'booking_id', 'pk_type' => 'i', 'writable' => [
        'guest_id'=>'i','guest_name'=>'s','guest_id_type'=>'s','guest_id_number'=>'s','guest_id_issue_date'=>'s','guest_id_issue_place'=>'s','guest_phone'=>'s','guest_nationality'=>'s','guest_email'=>'s','guest_address'=>'s','room_number'=>'s','checkin_date'=>'s','checkout_date'=>'s','status'=>'s','notes'=>'s','expected_nights'=>'i','actual_checkout'=>'s','calculated_nights'=>'i'
    ]],
    'booking_notes' => ['table' => 'booking_notes', 'pk' => 'note_id', 'pk_type' => 'i', 'writable' => [
        'booking_id'=>'i','note_text'=>'s','alert_type'=>'s','alert_until'=>'s','is_active'=>'i','created_at'=>'s','created_by'=>'s'
    ]],
    'employees' => ['table' => 'employees', 'pk' => 'id', 'pk_type' => 'i', 'writable' => ['name'=>'s','basic_salary'=>'d','status'=>'s']],
    'expenses' => ['table' => 'expenses', 'pk' => 'id', 'pk_type' => 'i', 'writable' => ['expense_type'=>'s','related_id'=>'i','description'=>'s','amount'=>'d','date'=>'s']],
    'cash_transactions' => ['table' => 'cash_transactions', 'pk' => 'id', 'pk_type' => 'i', 'writable' => ['register_id'=>'i','transaction_type'=>'s','amount'=>'d','reference_type'=>'s','reference_id'=>'i','description'=>'s','transaction_time'=>'s']],
    'suppliers' => ['table' => 'suppliers', 'pk' => 'id', 'pk_type' => 'i', 'writable' => ['name'=>'s']],
    'users' => ['table' => 'users', 'pk' => 'user_id', 'pk_type' => 'i', 'writable' => ['username'=>'s','full_name'=>'s','email'=>'s','phone'=>'s','user_type'=>'s','is_active'=>'i']]
];

$body = json_input();
$changes = $body['changes'] ?? [];
if (!is_array($changes)) {
    send_json(false, ['error' => 'Invalid payload'], null, 400);
}

$results = [];

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

    try {
        if ($op === 'create') {
            $cols = [];$vals=[];$types='';
            foreach ($cfg['writable'] as $col=>$t) {
                if (array_key_exists($col, $data)) { $cols[] = "`$col`"; $vals[]=$data[$col]; $types.=$t; }
            }
            if (!$cols) throw new Exception('No fields to insert');
            $place = implode(',', array_fill(0, count($cols), '?'));
            $sql = "INSERT INTO `$table` (".implode(',', $cols).") VALUES ($place)";
            $stmt = $conn->prepare($sql);
            $stmt->bind_param($types, ...$vals);
            $stmt->execute();
            $new_id = $pk_type==='i' ? $stmt->insert_id : ($data[$pk] ?? null);
            $stmt->close();
            $results[] = ['uuid'=>$uuid, 'success'=>true, 'server_id'=>$new_id];
        } elseif ($op === 'update') {
            // Identify target row
            $id_val = $server_id;
            if ($id_val === null && isset($data[$pk])) $id_val = $data[$pk];
            if ($id_val === null) throw new Exception('Missing server_id or pk');

            // conflict check (last-write-wins)
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
            foreach ($cfg['writable'] as $col=>$t) {
                if (array_key_exists($col, $data) && $col!==$pk) { $sets[]="`$col`=?"; $vals[]=$data[$col]; $types.=$t; }
            }
            if (!$sets) throw new Exception('No fields to update');
            $sql = "UPDATE `$table` SET ".implode(',', $sets)." WHERE `$pk`=?";
            $types.=$pk_type; $vals[]=$id_val;
            $stmt = $conn->prepare($sql);
            $stmt->bind_param($types, ...$vals);
            $stmt->execute();
            $stmt->close();
            $results[] = ['uuid'=>$uuid, 'success'=>true, 'server_id'=>$id_val];
        } elseif ($op === 'delete') {
            $id_val = $server_id;
            if ($id_val === null && isset($data[$pk])) $id_val = $data[$pk];
            if ($id_val === null) throw new Exception('Missing server_id or pk');
            $stmt = $conn->prepare("UPDATE `$table` SET `deleted_at` = CURRENT_TIMESTAMP WHERE `$pk`=?");
            $stmt->bind_param($pk_type, $id_val);
            $stmt->execute();
            $stmt->close();
            $results[] = ['uuid'=>$uuid, 'success'=>true, 'server_id'=>$id_val];
        } else {
            throw new Exception('Unsupported op');
        }
    } catch (Exception $e) {
        $results[] = ['uuid'=>$uuid, 'success'=>false, 'error'=>$e->getMessage()];
    }
}

send_json(true, ['results'=>$results], ['server_time'=>time()]);
