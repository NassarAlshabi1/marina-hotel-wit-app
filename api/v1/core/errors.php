<?php
/**
 * Error Codes و Response Handler الموحد
 * يوفر أكواد خطأ موحدة ومعالجة احترافية للاستجابات
 */

class ApiErrorCodes {
    // أخطاء المصادقة (1000-1099)
    const AUTH_TOKEN_MISSING = 1001;
    const AUTH_TOKEN_INVALID = 1002;
    const AUTH_TOKEN_EXPIRED = 1003;
    const AUTH_LOGIN_FAILED = 1004;
    const AUTH_INSUFFICIENT_PERMISSIONS = 1005;
    
    // أخطاء التحقق من البيانات (1100-1199)
    const VALIDATION_REQUIRED_FIELD = 1101;
    const VALIDATION_INVALID_FORMAT = 1102;
    const VALIDATION_INVALID_TYPE = 1103;
    const VALIDATION_OUT_OF_RANGE = 1104;
    const VALIDATION_DUPLICATE_ENTRY = 1105;
    const VALIDATION_FOREIGN_KEY = 1106;
    
    // أخطاء الموارد (1200-1299)
    const RESOURCE_NOT_FOUND = 1201;
    const RESOURCE_ALREADY_EXISTS = 1202;
    const RESOURCE_DELETED = 1203;
    const RESOURCE_LOCKED = 1204;
    
    // أخطاء قاعدة البيانات (1300-1399)
    const DB_CONNECTION_FAILED = 1301;
    const DB_QUERY_FAILED = 1302;
    const DB_TRANSACTION_FAILED = 1303;
    const DB_CONSTRAINT_VIOLATION = 1304;
    
    // أخطاء المزامنة (1400-1499)
    const SYNC_CONFLICT = 1401;
    const SYNC_VERSION_MISMATCH = 1402;
    const SYNC_DATA_CORRUPTED = 1403;
    const SYNC_TIMEOUT = 1404;
    
    // أخطاء النظام (1500-1599)
    const SYSTEM_INTERNAL_ERROR = 1501;
    const SYSTEM_SERVICE_UNAVAILABLE = 1502;
    const SYSTEM_RATE_LIMIT = 1503;
    const SYSTEM_MAINTENANCE = 1504;
    
    // أخطاء الطلب (1600-1699)
    const REQUEST_METHOD_NOT_ALLOWED = 1601;
    const REQUEST_INVALID_JSON = 1602;
    const REQUEST_PAYLOAD_TOO_LARGE = 1603;
    const REQUEST_TIMEOUT = 1604;
    
    /**
     * الحصول على رسالة الخطأ بالعربية
     */
    public static function getMessage($code) {
        $messages = [
            // المصادقة
            self::AUTH_TOKEN_MISSING => 'التوكن مطلوب',
            self::AUTH_TOKEN_INVALID => 'التوكن غير صالح',
            self::AUTH_TOKEN_EXPIRED => 'التوكن منتهي الصلاحية',
            self::AUTH_LOGIN_FAILED => 'فشل تسجيل الدخول',
            self::AUTH_INSUFFICIENT_PERMISSIONS => 'صلاحيات غير كافية',
            
            // التحقق
            self::VALIDATION_REQUIRED_FIELD => 'حقل مطلوب غير موجود',
            self::VALIDATION_INVALID_FORMAT => 'صيغة البيانات غير صحيحة',
            self::VALIDATION_INVALID_TYPE => 'نوع البيانات غير صحيح',
            self::VALIDATION_OUT_OF_RANGE => 'القيمة خارج النطاق المسموح',
            self::VALIDATION_DUPLICATE_ENTRY => 'البيانات موجودة مسبقاً',
            self::VALIDATION_FOREIGN_KEY => 'مرجع غير موجود',
            
            // الموارد
            self::RESOURCE_NOT_FOUND => 'المورد غير موجود',
            self::RESOURCE_ALREADY_EXISTS => 'المورد موجود مسبقاً',
            self::RESOURCE_DELETED => 'المورد محذوف',
            self::RESOURCE_LOCKED => 'المورد مقفل',
            
            // قاعدة البيانات
            self::DB_CONNECTION_FAILED => 'فشل الاتصال بقاعدة البيانات',
            self::DB_QUERY_FAILED => 'فشل تنفيذ الاستعلام',
            self::DB_TRANSACTION_FAILED => 'فشلت العملية',
            self::DB_CONSTRAINT_VIOLATION => 'انتهاك قيد في قاعدة البيانات',
            
            // المزامنة
            self::SYNC_CONFLICT => 'تعارض في البيانات',
            self::SYNC_VERSION_MISMATCH => 'عدم تطابق الإصدار',
            self::SYNC_DATA_CORRUPTED => 'البيانات تالفة',
            self::SYNC_TIMEOUT => 'انتهت مهلة المزامنة',
            
            // النظام
            self::SYSTEM_INTERNAL_ERROR => 'خطأ داخلي في النظام',
            self::SYSTEM_SERVICE_UNAVAILABLE => 'الخدمة غير متاحة',
            self::SYSTEM_RATE_LIMIT => 'تجاوزت الحد المسموح من الطلبات',
            self::SYSTEM_MAINTENANCE => 'النظام تحت الصيانة',
            
            // الطلب
            self::REQUEST_METHOD_NOT_ALLOWED => 'طريقة الطلب غير مدعومة',
            self::REQUEST_INVALID_JSON => 'JSON غير صالح',
            self::REQUEST_PAYLOAD_TOO_LARGE => 'حجم البيانات كبير جداً',
            self::REQUEST_TIMEOUT => 'انتهت مهلة الطلب',
        ];
        
        return $messages[$code] ?? 'خطأ غير معروف';
    }
    
    /**
     * الحصول على HTTP status code المناسب
     */
    public static function getHttpCode($code) {
        if ($code >= 1000 && $code < 1100) return 401; // Auth errors
        if ($code >= 1100 && $code < 1200) return 400; // Validation errors
        if ($code >= 1200 && $code < 1300) return 404; // Resource errors
        if ($code >= 1300 && $code < 1400) return 500; // Database errors
        if ($code >= 1400 && $code < 1500) return 409; // Sync errors
        if ($code >= 1500 && $code < 1600) return 500; // System errors
        if ($code >= 1600 && $code < 1700) return 400; // Request errors
        
        return 500; // Default
    }
}

/**
 * Response Handler الموحد
 */
class ApiResponse {
    /**
     * استجابة نجاح
     */
    public static function success($data = null, $message = null, $meta = []) {
        http_response_code(200);
        echo json_encode([
            'success' => true,
            'data' => $data,
            'message' => $message,
            'meta' => $meta,
            'server_time' => time(),
            'timestamp' => date('Y-m-d H:i:s')
        ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        exit();
    }
    
    /**
     * استجابة نجاح الإنشاء
     */
    public static function created($data = null, $message = 'تم الإنشاء بنجاح') {
        http_response_code(201);
        echo json_encode([
            'success' => true,
            'data' => $data,
            'message' => $message,
            'server_time' => time(),
            'timestamp' => date('Y-m-d H:i:s')
        ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        exit();
    }
    
    /**
     * استجابة خطأ
     */
    public static function error($errorCode, $details = null, $httpCode = null) {
        $message = ApiErrorCodes::getMessage($errorCode);
        $httpCode = $httpCode ?? ApiErrorCodes::getHttpCode($errorCode);
        
        http_response_code($httpCode);
        echo json_encode([
            'success' => false,
            'error' => [
                'code' => $errorCode,
                'message' => $message,
                'details' => $details
            ],
            'server_time' => time(),
            'timestamp' => date('Y-m-d H:i:s')
        ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        
        // تسجيل الخطأ
        ApiLogger::error($message, [
            'error_code' => $errorCode,
            'details' => $details,
            'http_code' => $httpCode
        ]);
        
        exit();
    }
    
    /**
     * استجابة خطأ مخصص
     */
    public static function customError($message, $httpCode = 400, $details = null) {
        http_response_code($httpCode);
        echo json_encode([
            'success' => false,
            'error' => [
                'message' => $message,
                'details' => $details
            ],
            'server_time' => time(),
            'timestamp' => date('Y-m-d H:i:s')
        ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
        
        ApiLogger::error($message, ['details' => $details, 'http_code' => $httpCode]);
        
        exit();
    }
}

/**
 * Logger محترف
 */
class ApiLogger {
    private static $logPath;
    
    public static function init() {
        self::$logPath = defined('LOGS_PATH') ? LOGS_PATH : __DIR__ . '/../../logs';
        if (!is_dir(self::$logPath)) {
            mkdir(self::$logPath, 0755, true);
        }
    }
    
    /**
     * تسجيل معلومة
     */
    public static function info($message, $context = []) {
        self::log('INFO', $message, $context);
    }
    
    /**
     * تسجيل تحذير
     */
    public static function warning($message, $context = []) {
        self::log('WARNING', $message, $context);
    }
    
    /**
     * تسجيل خطأ
     */
    public static function error($message, $context = []) {
        self::log('ERROR', $message, $context);
    }
    
    /**
     * تسجيل خطأ خطير
     */
    public static function critical($message, $context = []) {
        self::log('CRITICAL', $message, $context);
    }
    
    /**
     * تسجيل طلب API
     */
    public static function logRequest($endpoint, $method, $userId = null, $duration = null) {
        self::log('REQUEST', "API Request: $method $endpoint", [
            'user_id' => $userId,
            'duration_ms' => $duration,
            'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? 'unknown'
        ]);
    }
    
    /**
     * وظيفة التسجيل الأساسية
     */
    private static function log($level, $message, $context = []) {
        if (!self::$logPath) {
            self::init();
        }
        
        $date = date('Y-m-d');
        $logFile = self::$logPath . "/api_{$date}.log";
        
        $logEntry = [
            'timestamp' => date('Y-m-d H:i:s'),
            'level' => $level,
            'message' => $message,
            'context' => $context,
            'request_uri' => $_SERVER['REQUEST_URI'] ?? '',
            'method' => $_SERVER['REQUEST_METHOD'] ?? '',
            'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown'
        ];
        
        $logLine = json_encode($logEntry, JSON_UNESCAPED_UNICODE) . PHP_EOL;
        
        file_put_contents($logFile, $logLine, FILE_APPEND | LOCK_EX);
        
        // إذا كان خطأ خطير، أرسل إشعار (يمكن تطويره لاحقاً)
        if ($level === 'CRITICAL') {
            self::notifyCriticalError($message, $context);
        }
    }
    
    /**
     * إشعار بخطأ خطير (يمكن تطويره لإرسال email أو Slack)
     */
    private static function notifyCriticalError($message, $context) {
        // TODO: إرسال إشعار للمسؤولين
        // يمكن إضافة email أو Slack webhook هنا
    }
}

// تهيئة Logger
ApiLogger::init();
