<?php
require_once __DIR__ . '/../bootstrap.php';
require_once __DIR__ . '/../middleware.php';
$u = require_auth($CONFIG);
send_json(true, ['user' => $u], ['server_time' => time()]);
