<?php
/**
 * API للمزامنة التلقائية عبر البريد الإلكتروني
 * Auto Email Sync API Endpoint
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-Requested-With');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    exit(0);
}

require_once '../includes/db.php';
require_once '../includes/email_sync.php';

// التحقق من الطلب
if (!isset($_SERVER['HTTP_X_REQUESTED_WITH']) || $_SERVER['HTTP_X_REQUESTED_WITH'] !== 'XMLHttpRequest') {
    // السماح بالوصول المباشر للاختبار فقط
    if (!isset($_GET['test'])) {
        http_response_code(403);
        echo json_encode(['success' => false, 'message' => 'غير مسموح بالوصول المباشر']);
        exit;
    }
}

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!$input) {
            throw new Exception('بيانات غير صحيحة');
        }
        
        $action = $input['action'] ?? '';
        
        switch ($action) {
            case 'sync_local_data':
                handleLocalDataSync($input['data'] ?? []);
                break;
                
            case 'manual_sync':
                performManualSync();
                break;
                
            case 'add_sync_event':
                addSyncEvent($input['type'] ?? '', $input['data'] ?? []);
                break;
                
            default:
                throw new Exception('إجراء غير معروف');
        }
        
    } elseif ($_SERVER['REQUEST_METHOD'] === 'GET') {
        $action = $_GET['action'] ?? 'status';
        
        switch ($action) {
            case 'status':
                getSyncStatus();
                break;
                
            case 'last_sync':
                getLastSyncTime();
                break;
                
            case 'test':
                testSync();
                break;
                
            case 'run_sync':
                performManualSync();
                break;
                
            default:
                throw new Exception('إجراء غير معروف');
        }
    }
    
} catch (Exception $e) {
    http_response_code(400);
    echo json_encode([
        'success' => false, 
        'message' => $e->getMessage(),
        'timestamp' => date('Y-m-d H:i:s')
    ]);
}

/**
 * معالجة مزامنة البيانات المحلية
 */
function handleLocalDataSync($data) {
    if (empty($data)) {
        echo json_encode(['success' => true, 'message' => 'لا توجد بيانات للمزامنة']);
        return;
    }
    
    $synced_count = 0;
    $errors = [];
    
    foreach ($data as $item) {
        try {
            $type = $item['type'] ?? '';
            $item_data = $item['data'] ?? [];
            
            // إضافة البيانات إلى قائمة انتظار المزامنة
            addSyncEvent($type, $item_data);
            $synced_count++;
            
        } catch (Exception $e) {
            $errors[] = "خطأ في مزامنة {$type}: " . $e->getMessage();
        }
    }
    
    echo json_encode([
        'success' => true,
        'synced_count' => $synced_count,
        'total_items' => count($data),
        'errors' => $errors,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
}

/**
 * إضافة حدث مزامنة جديد
 */
function addSyncEvent($type, $data) {
    global $conn;
    
    $event_data = json_encode($data, JSON_UNESCAPED_UNICODE);
    $timestamp = date('Y-m-d H:i:s');
    
    // إنشاء جدول أحداث المزامنة إذا لم يكن موجوداً
    $create_table = "CREATE TABLE IF NOT EXISTS sync_events (
        id INT AUTO_INCREMENT PRIMARY KEY,
        event_type VARCHAR(50) NOT NULL,
        event_data TEXT,
        timestamp DATETIME NOT NULL,
        synced TINYINT(1) DEFAULT 0,
        sync_timestamp DATETIME NULL,
        INDEX idx_event_type (event_type),
        INDEX idx_timestamp (timestamp),
        INDEX idx_synced (synced)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    $conn->query($create_table);
    
    $sql = "INSERT INTO sync_events (event_type, event_data, timestamp) VALUES (?, ?, ?)";
    $stmt = $conn->prepare($sql);
    
    if ($stmt) {
        $stmt->bind_param("sss", $type, $event_data, $timestamp);
        $result = $stmt->execute();
        $stmt->close();
        
        if ($result) {
            echo json_encode([
                'success' => true,
                'message' => 'تم إضافة حدث المزامنة بنجاح',
                'timestamp' => $timestamp
            ]);
        } else {
            throw new Exception('فشل في إضافة حدث المزامنة');
        }
    } else {
        throw new Exception('خطأ في قاعدة البيانات');
    }
}

/**
 * الحصول على حالة المزامنة
 */
function getSyncStatus() {
    $last_sync = file_exists('../logs/last_sync.txt') ? 
                 file_get_contents('../logs/last_sync.txt') : 
                 'غير محدد';
    
    $sync_log_exists = file_exists('../logs/sync.log');
    $recent_errors = [];
    
    if ($sync_log_exists) {
        $log_content = file_get_contents('../logs/sync.log');
        $log_lines = array_slice(explode("\n", $log_content), -10);
        
        foreach ($log_lines as $line) {
            if (strpos($line, 'خطأ') !== false || strpos($line, 'فشل') !== false) {
                $recent_errors[] = trim($line);
            }
        }
    }
    
    // عدد الأحداث المعلقة
    global $conn;
    $pending_events = 0;
    $result = $conn->query("SELECT COUNT(*) as count FROM sync_events WHERE synced = 0");
    if ($result) {
        $row = $result->fetch_assoc();
        $pending_events = $row['count'];
    }
    
    echo json_encode([
        'success' => true,
        'last_sync' => $last_sync,
        'sync_enabled' => SYNC_ENABLED,
        'sync_interval' => SYNC_INTERVAL . ' ثانية',
        'pending_events' => $pending_events,
        'recent_errors' => array_slice($recent_errors, -3),
        'timestamp' => date('Y-m-d H:i:s')
    ]);
}

/**
 * الحصول على وقت آخر مزامنة
 */
function getLastSyncTime() {
    $last_sync = file_exists('../logs/last_sync.txt') ? 
                 file_get_contents('../logs/last_sync.txt') : 
                 null;
    
    echo json_encode([
        'success' => true,
        'last_sync' => $last_sync,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
}

/**
 * تشغيل مزامنة يدوية
 */
function performManualSync() {
    $result = runSync();
    
    echo json_encode([
        'success' => $result,
        'message' => $result ? 'تمت المزامنة بنجاح' : 'فشل في المزامنة',
        'timestamp' => date('Y-m-d H:i:s')
    ]);
}

/**
 * اختبار نظام المزامنة
 */
function testSync() {
    $tests = [];
    
    // اختبار الاتصال بقاعدة البيانات
    global $conn;
    $tests['database'] = $conn ? 'نجح' : 'فشل';
    
    // اختبار إعدادات البريد الإلكتروني
    $tests['email_config'] = defined('SYNC_EMAIL') ? 'نجح' : 'فشل';
    
    // اختبار مجلد السجلات
    if (!is_dir('../logs')) {
        mkdir('../logs', 0755, true);
    }
    $tests['logs_directory'] = is_writable('../logs') ? 'نجح' : 'فشل';
    
    // اختبار جمع البيانات
    try {
        $data = collectSyncData();
        $tests['data_collection'] = 'نجح';
        $tests['data_found'] = !empty($data) ? 'يوجد بيانات جديدة' : 'لا توجد بيانات جديدة';
    } catch (Exception $e) {
        $tests['data_collection'] = 'فشل: ' . $e->getMessage();
    }
    
    // اختبار إرسال بريد إلكتروني تجريبي
    try {
        $test_subject = "🧪 اختبار نظام المزامنة - " . date('H:i:s');
        $test_data = "<p>هذا اختبار لنظام المزامنة التلقائية</p><p>الوقت: " . date('Y-m-d H:i:s') . "</p>";
        
        $email_result = sendSyncUpdate($test_subject, $test_data);
        $tests['email_sending'] = $email_result ? 'نجح' : 'فشل';
    } catch (Exception $e) {
        $tests['email_sending'] = 'فشل: ' . $e->getMessage();
    }
    
    echo json_encode([
        'success' => true,
        'tests' => $tests,
        'timestamp' => date('Y-m-d H:i:s')
    ]);
}

$conn->close();
?>
