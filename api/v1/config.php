<?php
/**
 * ملف الإعدادات الرئيسي لـ API v1
 * يوفر الإعدادات والوظائف المشتركة بين جميع نقاط النهاية
 */

// تسجيل وقت البداية للقياس
define('API_START_TIME', microtime(true));

// إعداد الترويسات للـ CORS و JSON
header('Content-Type: application/json; charset=utf-8');

// تضمين ملفات الإعدادات والاتصال
require_once __DIR__ . '/../../includes/config.php';
require_once __DIR__ . '/../../includes/db.php';

// تضمين الملفات الأساسية للـ API
require_once __DIR__ . '/core/errors.php';
require_once __DIR__ . '/core/validator.php';
require_once __DIR__ . '/core/middleware.php';

// تطبيق CORS middleware
ApiMiddleware::cors();

// التحقق من صيانة النظام
ApiMiddleware::checkMaintenance();

// التحقق من صحة JSON
ApiMiddleware::validateJson();

// التحقق من حجم البيانات
ApiMiddleware::checkPayloadSize();

/**
 * إرجاع استجابة JSON موحدة
 * 
 * @param bool $success حالة النجاح
 * @param mixed $data البيانات المراد إرجاعها
 * @param string|null $error رسالة الخطأ
 * @param int $httpCode كود HTTP
 */
function jsonResponse($success, $data = null, $error = null, $httpCode = null) {
    if ($httpCode) {
        http_response_code($httpCode);
    } elseif (!$success) {
        http_response_code(400);
    }
    
    $response = [
        'success' => $success,
        'data' => $data,
        'error' => $error,
        'server_time' => time(),
        'timestamp' => date('Y-m-d H:i:s')
    ];
    
    echo json_encode($response, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit();
}

/**
 * الحصول على بيانات الإدخال من الطلب
 * 
 * @return array بيانات الإدخال
 */
function getInput() {
    $input = file_get_contents('php://input');
    $decoded = json_decode($input, true);
    
    if (json_last_error() !== JSON_ERROR_NONE) {
        return [];
    }
    
    return $decoded ?? [];
}

/**
 * التحقق من التوكن والمصادقة
 * 
 * @return array|null بيانات المستخدم أو null
 */
function authenticateRequest() {
    $headers = getallheaders();
    $token = null;
    
    // البحث عن التوكن في الترويسات
    if (isset($headers['Authorization'])) {
        $auth = $headers['Authorization'];
        if (preg_match('/Bearer\s+(.+)/', $auth, $matches)) {
            $token = $matches[1];
        }
    }
    
    if (!$token) {
        jsonResponse(false, null, 'غير مصرح - التوكن مطلوب', 401);
    }
    
    global $conn;
    
    // التحقق من التوكن في قاعدة البيانات
    $stmt = $conn->prepare("
        SELECT u.id, u.username, u.full_name, u.role, u.status
        FROM users u
        WHERE u.token = ? AND u.status = 'active'
        LIMIT 1
    ");
    
    $stmt->bind_param('s', $token);
    $stmt->execute();
    $result = $stmt->get_result();
    
    if ($result->num_rows === 0) {
        jsonResponse(false, null, 'غير مصرح - توكن غير صالح', 401);
    }
    
    return $result->fetch_assoc();
}

/**
 * تنظيف وتأمين المدخلات
 * 
 * @param mixed $data البيانات المراد تنظيفها
 * @return mixed البيانات المنظفة
 */
function sanitizeInput($data) {
    if (is_array($data)) {
        return array_map('sanitizeInput', $data);
    }
    
    if (is_string($data)) {
        return trim(htmlspecialchars($data, ENT_QUOTES, 'UTF-8'));
    }
    
    return $data;
}

/**
 * التحقق من الحقول المطلوبة
 * 
 * @param array $data البيانات
 * @param array $required الحقول المطلوبة
 * @return bool
 */
function validateRequired($data, $required) {
    foreach ($required as $field) {
        if (!isset($data[$field]) || $data[$field] === '' || $data[$field] === null) {
            jsonResponse(false, null, "الحقل المطلوب غير موجود: $field");
        }
    }
    return true;
}

/**
 * توليد UUID فريد
 * 
 * @return string UUID
 */
function generateUuid() {
    return sprintf(
        '%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
        mt_rand(0, 0xffff), mt_rand(0, 0xffff),
        mt_rand(0, 0xffff),
        mt_rand(0, 0x0fff) | 0x4000,
        mt_rand(0, 0x3fff) | 0x8000,
        mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
    );
}

/**
 * تسجيل الأخطاء
 * 
 * @param string $message رسالة الخطأ
 * @param array $context السياق
 */
function logError($message, $context = []) {
    $logFile = LOGS_PATH . '/api_errors_' . date('Y-m-d') . '.log';
    $logEntry = [
        'timestamp' => date('Y-m-d H:i:s'),
        'message' => $message,
        'context' => $context,
        'request_uri' => $_SERVER['REQUEST_URI'] ?? '',
        'method' => $_SERVER['REQUEST_METHOD'] ?? ''
    ];
    
    file_put_contents(
        $logFile,
        json_encode($logEntry, JSON_UNESCAPED_UNICODE) . PHP_EOL,
        FILE_APPEND
    );
}

/**
 * تحويل مصفوفة من snake_case إلى camelCase
 * لإرسال البيانات من MySQL إلى Flutter
 * 
 * @param array $array المصفوفة بصيغة snake_case
 * @return array المصفوفة بصيغة camelCase
 */
function snakeToCamel($array) {
    if (!is_array($array)) {
        return $array;
    }
    
    $result = [];
    foreach ($array as $key => $value) {
        // تحويل snake_case إلى camelCase
        $camelKey = lcfirst(str_replace('_', '', ucwords($key, '_')));
        
        // إذا كانت القيمة مصفوفة، نقوم بالتحويل المتكرر
        if (is_array($value)) {
            $result[$camelKey] = snakeToCamel($value);
        } else {
            $result[$camelKey] = $value;
        }
    }
    return $result;
}

/**
 * تحويل مصفوفة من camelCase إلى snake_case
 * لاستقبال البيانات من Flutter وإرسالها إلى MySQL
 * 
 * @param array $array المصفوفة بصيغة camelCase
 * @return array المصفوفة بصيغة snake_case
 */
function camelToSnake($array) {
    if (!is_array($array)) {
        return $array;
    }
    
    $result = [];
    foreach ($array as $key => $value) {
        // تحويل camelCase إلى snake_case
        $snakeKey = strtolower(preg_replace('/(?<!^)[A-Z]/', '_$0', $key));
        
        // إذا كانت القيمة مصفوفة، نقوم بالتحويل المتكرر
        if (is_array($value)) {
            $result[$snakeKey] = camelToSnake($value);
        } else {
            $result[$snakeKey] = $value;
        }
    }
    return $result;
}

/**
 * تحويل جدول من مصفوفات من snake_case إلى camelCase
 * 
 * @param array $records مصفوفة من السجلات
 * @return array المصفوفة المحولة
 */
function recordsSnakeToCamel($records) {
    if (!is_array($records)) {
        return $records;
    }
    
    $result = [];
    foreach ($records as $record) {
        $result[] = snakeToCamel($record);
    }
    return $result;
}

/**
 * تحويل التواريخ من timestamp إلى Unix epoch
 * 
 * @param array $record السجل
 * @param array $dateFields حقول التاريخ
 * @return array السجل المحول
 */
function convertDatesToEpoch($record, $dateFields = []) {
    foreach ($dateFields as $field) {
        if (isset($record[$field]) && $record[$field] !== null) {
            // إذا كان التاريخ بصيغة Y-m-d H:i:s
            if (is_string($record[$field])) {
                $record[$field] = strtotime($record[$field]);
            }
        }
    }
    return $record;
}
