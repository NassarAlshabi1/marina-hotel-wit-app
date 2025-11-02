<?php
include 'includes/db.php';

$password = 'YOUR_MONGODB_PASSWORD_HERE';

$syncUrl = "http://localhost/marina-hotel-wit-app/api/mongodb_sync.php?action=sync_all&password=" . urlencode($password);

$ch = curl_init($syncUrl);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 30);

$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

$timestamp = date('Y-m-d H:i:s');

if ($httpCode == 200 && $response) {
    $result = json_decode($response, true);
    
    if ($result && isset($result['success']) && $result['success']) {
        $guestsCount = $result['guests']['synced_count'] ?? 0;
        $bookingsCount = $result['bookings']['synced_count'] ?? 0;
        
        $logMessage = "[$timestamp] ✅ مزامنة ناجحة: $guestsCount نزيل، $bookingsCount حجز\n";
        echo $logMessage;
        
        file_put_contents('logs/mongodb_sync.log', $logMessage, FILE_APPEND);
        file_put_contents('logs/last_mongo_sync.txt', $timestamp);
    } else {
        $error = $result['error'] ?? 'خطأ غير معروف';
        $logMessage = "[$timestamp] ❌ فشل في المزامنة: $error\n";
        echo $logMessage;
        
        file_put_contents('logs/mongodb_sync_error.log', $logMessage, FILE_APPEND);
    }
} else {
    $error = curl_error($ch) ?: "HTTP $httpCode";
    $logMessage = "[$timestamp] ❌ خطأ في الاتصال: $error\n";
    echo $logMessage;
    
    file_put_contents('logs/mongodb_sync_error.log', $logMessage, FILE_APPEND);
}
?>
