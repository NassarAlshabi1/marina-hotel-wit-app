<?php
require_once __DIR__ . '/../bootstrap.php';
require_once __DIR__ . '/../middleware.php';
$auth = require_auth($CONFIG);

$since = isset($_GET['since']) ? (int)$_GET['since'] : 0;

$entities = [
    'rooms' => ['table' => 'rooms', 'pk' => 'room_number'],
    'bookings' => ['table' => 'bookings', 'pk' => 'booking_id'],
    'booking_notes' => ['table' => 'booking_notes', 'pk' => 'note_id'],
    'employees' => ['table' => 'employees', 'pk' => 'id'],
    'expenses' => ['table' => 'expenses', 'pk' => 'id'],
    'cash_transactions' => ['table' => 'cash_transactions', 'pk' => 'id'],
    'payments' => ['table' => 'payment', 'pk' => 'payment_id'],
];

$data = [];
$server_time = time();

foreach ($entities as $name => $cfg) {
    $table = $cfg['table'];
    $pk = $cfg['pk'];
    $hasUpdated = false; $hasDeleted = false;
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE 'updated_at'");
    if ($res && $res->num_rows > 0) $hasUpdated = true;
    $res = $conn->query("SHOW COLUMNS FROM `$table` LIKE 'deleted_at'");
    if ($res && $res->num_rows > 0) $hasDeleted = true;

    if ($hasUpdated) {
        $sql = "SELECT *, UNIX_TIMESTAMP(GREATEST(COALESCE(updated_at, created_at)" . ($hasDeleted ? ", COALESCE(deleted_at, '1970-01-01')" : "") . ")) AS ts FROM `$table` WHERE (COALESCE(updated_at, created_at) >= FROM_UNIXTIME(?))" . ($hasDeleted ? " OR (deleted_at IS NOT NULL AND deleted_at >= FROM_UNIXTIME(?))" : "");
        $stmt = $conn->prepare($sql);
        if ($hasDeleted) { $stmt->bind_param('ii', $since, $since); } else { $stmt->bind_param('i', $since); }
        $stmt->execute();
        $rs = $stmt->get_result();
    } else {
        $sql = "SELECT *, UNIX_TIMESTAMP(created_at) AS ts FROM `$table` WHERE created_at >= FROM_UNIXTIME(?)";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param('i', $since);
        $stmt->execute();
        $rs = $stmt->get_result();
    }

    while ($row = $rs->fetch_assoc()) {
        $isDelete = $hasDeleted && !empty($row['deleted_at']);
        $op = $isDelete ? 'delete' : 'upsert';
        if ($name === 'users') { unset($row['password']); unset($row['password_hash']); }
        $data[] = [
            'entity' => $name,
            'op' => $op,
            'server_id' => $row[$pk],
            'uuid' => null,
            'data' => $row,
            'server_ts' => (int)$row['ts'],
        ];
    }
    $stmt->close();
}

send_json(true, ['data' => $data, 'server_time' => $server_time], ['server_time' => $server_time, 'since' => $since]);
