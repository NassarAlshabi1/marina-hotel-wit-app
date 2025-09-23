<?php
require_once __DIR__ . '/../bootstrap.php';

current_user_or_fail(true);

$since = isset($_GET['since']) ? (int)$_GET['since'] : null;
if (!$since) $since = 0;

$entities = [
    'rooms' => ['table' => 'rooms', 'pk' => 'room_number'],
    'bookings' => ['table' => 'bookings', 'pk' => 'booking_id'],
    'booking_notes' => ['table' => 'booking_notes', 'pk' => 'note_id'],
    'employees' => ['table' => 'employees', 'pk' => 'id'],
    'expenses' => ['table' => 'expenses', 'pk' => 'id'],
    'cash_transactions' => ['table' => 'cash_transactions', 'pk' => 'id'],
    'suppliers' => ['table' => 'suppliers', 'pk' => 'id'],
    'users' => ['table' => 'users', 'pk' => 'user_id']
];

$data = [];
$server_time = time();

foreach ($entities as $name => $cfg) {
    $sql = "SELECT *, UNIX_TIMESTAMP(GREATEST(COALESCE(updated_at, created_at), COALESCE(deleted_at, '1970-01-01'))) AS ts
            FROM `{$cfg['table']}`
            WHERE (COALESCE(updated_at, created_at) >= FROM_UNIXTIME(?)) OR (deleted_at IS NOT NULL AND deleted_at >= FROM_UNIXTIME(?))";
    try {
        $stmt = $conn->prepare($sql);
        $stmt->bind_param('ii', $since, $since);
        $stmt->execute();
        $res = $stmt->get_result();
        while ($row = $res->fetch_assoc()) {
            $op = ($row['deleted_at'] !== null) ? 'delete' : 'update';
            // strip sensitive fields for users
            if ($name === 'users') {
                unset($row['password']); unset($row['password_hash']);
            }
            $data[] = [
                'entity' => $name,
                'op' => $op,
                'server_id' => $row[$cfg['pk']],
                'uuid' => null,
                'data' => $row,
                'server_ts' => (int)$row['ts']
            ];
        }
        $stmt->close();
    } catch (Exception $e) {
        // skip entity on error
    }
}

send_json(true, ['data' => $data, 'server_time' => $server_time], ['server_time' => $server_time, 'since' => $since]);
