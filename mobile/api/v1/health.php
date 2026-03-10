<?php
/**
 * Health Check Endpoint
 * GET /api/v1/health.php
 */

require_once __DIR__ . '/config.php';

$health = [
    'status' => 'healthy',
    'timestamp' => time(),
    'version' => '1.0.0',
    'checks' => []
];

// Database check
try {
    $conn->query("SELECT 1");
    $health['checks']['database'] = [
        'status' => 'healthy',
        'latency_ms' => round((microtime(true) - API_START_TIME) * 1000, 2)
    ];
} catch (Exception $e) {
    $health['status'] = 'unhealthy';
    $health['checks']['database'] = [
        'status' => 'unhealthy',
        'error' => $e->getMessage()
    ];
}

// Disk space check
$freeSpace = disk_free_space('/');
$totalSpace = disk_total_space('/');
$usagePercent = round((($totalSpace - $freeSpace) / $totalSpace) * 100, 2);

$health['checks']['disk'] = [
    'status' => $usagePercent < 90 ? 'healthy' : 'warning',
    'usage_percent' => $usagePercent,
    'free_gb' => round($freeSpace / 1073741824, 2)
];

// Memory check
$memUsage = memory_get_usage(true);
$memLimit = ini_get('memory_limit');
$health['checks']['memory'] = [
    'status' => 'healthy',
    'usage_mb' => round($memUsage / 1048576, 2),
    'limit' => $memLimit
];

http_response_code($health['status'] === 'healthy' ? 200 : 503);
echo json_encode($health, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
