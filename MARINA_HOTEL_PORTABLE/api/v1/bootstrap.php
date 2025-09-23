<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/../../includes/config.php';
require_once __DIR__ . '/../../includes/db.php';

function api_env($key, $default = null) {
    $val = getenv($key);
    if ($val === false || $val === null || $val === '') return $default;
    return $val;
}

function jwt_secret() {
    return api_env('JWT_SECRET', 'change-me');
}

function base64url_encode($data) {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}
function base64url_decode($data) {
    return base64_decode(strtr($data, '-_', '+/'));
}

function jwt_encode($payload, $secret, $alg = 'HS256') {
    $header = ['typ' => 'JWT', 'alg' => $alg];
    $segments = [base64url_encode(json_encode($header)), base64url_encode(json_encode($payload))];
    $signing_input = implode('.', $segments);
    $signature = hash_hmac('sha256', $signing_input, $secret, true);
    $segments[] = base64url_encode($signature);
    return implode('.', $segments);
}

function jwt_decode($jwt, $secret) {
    $parts = explode('.', $jwt);
    if (count($parts) !== 3) return null;
    list($h64, $p64, $s64) = $parts;
    $header = json_decode(base64url_decode($h64), true);
    $payload = json_decode(base64url_decode($p64), true);
    $sig = base64url_decode($s64);
    $expected = hash_hmac('sha256', $h64 . '.' . $p64, $secret, true);
    if (!hash_equals($expected, $sig)) return null;
    if (isset($payload['exp']) && time() >= (int)$payload['exp']) return null;
    return $payload;
}

function json_input() {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function send_json($success, $data = null, $meta = null, $status = 200) {
    http_response_code($status);
    $out = ['success' => (bool)$success, 'data' => $data];
    if ($meta !== null) $out['meta'] = $meta;
    echo json_encode($out, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function bearer_token() {
    $headers = getallheaders();
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (stripos($auth, 'Bearer ') === 0) return substr($auth, 7);
    return null;
}

function current_user_or_fail($required = true) {
    $token = bearer_token();
    if (!$token) {
        if ($required) send_json(false, ['error' => 'Unauthorized'], null, 401);
        return null;
    }
    $payload = jwt_decode($token, jwt_secret());
    if (!$payload) {
        if ($required) send_json(false, ['error' => 'Invalid or expired token'], null, 401);
        return null;
    }
    return $payload; // contains sub, username, permissions
}

function require_permissions($perm_codes = []) {
    if (!$perm_codes || count($perm_codes) === 0) return; // no specific requirements
    $user = current_user_or_fail(true);
    $userPerms = $user['permissions'] ?? [];
    foreach ($perm_codes as $p) {
        if (!in_array($p, $userPerms, true)) {
            send_json(false, ['error' => 'Forbidden'], null, 403);
        }
    }
}

function pagination_params() {
    $page = isset($_GET['page']) ? max(1, (int)$_GET['page']) : 1;
    $page_size = isset($_GET['page_size']) ? min(200, max(1, (int)$_GET['page_size'])) : 50;
    $offset = ($page - 1) * $page_size;
    return [$page, $page_size, $offset];
}

function since_param() {
    if (!isset($_GET['since'])) return null;
    $since = (int)$_GET['since'];
    if ($since <= 0) return null;
    return $since;
}

function sanitize_filter($conn, $filter) {
    // Very basic filter handling; endpoints can implement richer logic
    $filter = trim($filter);
    return $conn->real_escape_string($filter);
}

// Generic entity handler to reduce duplication
function handle_entity($config) {
    global $conn;
    current_user_or_fail(true);

    $table = $config['table'];
    $pk = $config['pk'];
    $select = $config['select'] ?? '*';
    $permissions = $config['permissions'] ?? ['view_dashboard'];
    $writable_fields = $config['writable'] ?? [];
    $extra_where = $config['where'] ?? '';

    $method = $_SERVER['REQUEST_METHOD'];

    if ($method === 'GET') {
        // Single item by id (supports path like .../rooms.php/101)
        $path = $_SERVER['PATH_INFO'] ?? '';
        $id = null;
        if (preg_match('#/(.+)$#', $path, $m)) {
            $id = $m[1];
        } elseif (isset($_GET['id'])) {
            $id = $_GET['id'];
        }

        if ($id !== null && $id !== '') {
            $stmt = $conn->prepare("SELECT $select FROM `$table` WHERE `$pk` = ? LIMIT 1");
            $stmt->bind_param('s', $id);
            $stmt->execute();
            $res = $stmt->get_result()->fetch_assoc();
            $stmt->close();
            send_json(true, $res);
        }

        list($page, $page_size, $offset) = pagination_params();
        $where = '1=1';
        if ($extra_where) $where .= ' AND (' . $extra_where . ')';

        $since = since_param();
        if ($since) {
            $where .= " AND ((`updated_at` >= FROM_UNIXTIME(?)) OR (`deleted_at` IS NOT NULL AND `deleted_at` >= FROM_UNIXTIME(?)))";
        } else {
            $where .= " AND (`deleted_at` IS NULL)"; // show only non-deleted by default
        }

        $filter = isset($_GET['filter']) ? sanitize_filter($conn, $_GET['filter']) : null;
        $filter_sql = '';
        if ($filter && !empty($config['filter_columns'])) {
            $parts = [];
            foreach ($config['filter_columns'] as $col) {
                $parts[] = "`$col` LIKE CONCAT('%', ?, '%')";
            }
            if ($parts) $filter_sql = ' AND (' . implode(' OR ', $parts) . ')';
        }

        $sql = "SELECT $select FROM `$table` WHERE $where $filter_sql ORDER BY `updated_at` DESC, `created_at` DESC LIMIT ? OFFSET ?";
        $stmt = $conn->prepare($sql);

        if ($since && $filter && !empty($config['filter_columns'])) {
            // bind since, since, filters..., limit, offset
            $types = 'ii' . str_repeat('s', count($config['filter_columns'])) . 'ii';
            $params = [$since, $since];
            foreach ($config['filter_columns'] as $_) $params[] = $filter;
            $params[] = $page_size; $params[] = $offset;
            $stmt->bind_param($types, ...$params);
        } elseif ($since) {
            $stmt->bind_param('iii', $since, $since, $page_size, $offset);
        } elseif ($filter && !empty($config['filter_columns'])) {
            $types = str_repeat('s', count($config['filter_columns'])) . 'ii';
            $params = [];
            foreach ($config['filter_columns'] as $_) $params[] = $filter;
            $params[] = $page_size; $params[] = $offset;
            $stmt->bind_param($types, ...$params);
        } else {
            $stmt->bind_param('ii', $page_size, $offset);
        }

        $stmt->execute();
        $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
        $stmt->close();

        // total count (approx; without filters/since count can be heavy, keep simple)
        $total = null;
        try {
            $count_sql = "SELECT COUNT(*) AS c FROM `$table` WHERE $where" . ($filter_sql ? $filter_sql : '');
            $cstmt = $conn->prepare($count_sql);
            if ($since && $filter && !empty($config['filter_columns'])) {
                $types = 'ii' . str_repeat('s', count($config['filter_columns']));
                $params = [$since, $since];
                foreach ($config['filter_columns'] as $_) $params[] = $filter;
                $cstmt->bind_param($types, ...$params);
            } elseif ($since) {
                $cstmt->bind_param('ii', $since, $since);
            } elseif ($filter && !empty($config['filter_columns'])) {
                $types = str_repeat('s', count($config['filter_columns']));
                $params = [];
                foreach ($config['filter_columns'] as $_) $params[] = $filter;
                $cstmt->bind_param($types, ...$params);
            }
            $cstmt->execute();
            $cres = $cstmt->get_result()->fetch_assoc();
            $total = (int)($cres['c'] ?? 0);
            $cstmt->close();
        } catch (Exception $e) {
            $total = null;
        }

        send_json(true, $rows, ['page' => $page, 'page_size' => $page_size, 'total' => $total, 'server_time' => time(), 'since' => $since]);
    }

    $payload = current_user_or_fail(true);

    if ($method === 'POST') {
        require_permissions($config['write_perm'] ?? []);
        $data = $_POST;
        if (empty($data)) $data = json_input();
        $cols = [];
        $vals = [];
        $types = '';
        foreach ($writable_fields as $col => $type) {
            if (array_key_exists($col, $data)) {
                $cols[] = "`$col`";
                $vals[] = $data[$col];
                $types .= $type;
            }
        }
        if (!$cols) send_json(false, ['error' => 'No valid fields'], null, 400);
        $placeholders = implode(',', array_fill(0, count($cols), '?'));
        $sql = "INSERT INTO `$table` (" . implode(',', $cols) . ") VALUES ($placeholders)";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param($types, ...$vals);
        $stmt->execute();
        $id = $stmt->insert_id;
        $stmt->close();
        send_json(true, ['id' => $id], ['server_time' => time()]);
    }

    if ($method === 'PUT') {
        require_permissions($config['write_perm'] ?? []);
        $path = $_SERVER['PATH_INFO'] ?? '';
        $id = null;
        if (preg_match('#/(.+)$#', $path, $m)) $id = $m[1];
        if ($id === null && isset($_GET['id'])) $id = $_GET['id'];
        if ($id === null) send_json(false, ['error' => 'Missing id'], null, 400);

        $data = json_input();
        $sets = [];
        $vals = [];
        $types = '';
        foreach ($writable_fields as $col => $type) {
            if (array_key_exists($col, $data)) {
                $sets[] = "`$col` = ?";
                $vals[] = $data[$col];
                $types .= $type;
            }
        }
        if (!$sets) send_json(false, ['error' => 'No valid fields'], null, 400);
        $sql = "UPDATE `$table` SET " . implode(',', $sets) . " WHERE `$pk` = ?";
        $types .= 's';
        $vals[] = $id;
        $stmt = $conn->prepare($sql);
        $stmt->bind_param($types, ...$vals);
        $stmt->execute();
        $stmt->close();
        send_json(true, ['id' => $id], ['server_time' => time()]);
    }

    if ($method === 'DELETE') {
        require_permissions($config['write_perm'] ?? []);
        $path = $_SERVER['PATH_INFO'] ?? '';
        $id = null;
        if (preg_match('#/(.+)$#', $path, $m)) $id = $m[1];
        if ($id === null && isset($_GET['id'])) $id = $_GET['id'];
        if ($id === null) send_json(false, ['error' => 'Missing id'], null, 400);
        $sql = "UPDATE `$table` SET `deleted_at` = CURRENT_TIMESTAMP WHERE `$pk` = ?";
        $stmt = $conn->prepare($sql);
        $stmt->bind_param('s', $id);
        $stmt->execute();
        $stmt->close();
        send_json(true, ['id' => $id], ['server_time' => time()]);
    }

    send_json(false, ['error' => 'Method not allowed'], null, 405);
}
