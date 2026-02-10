<?php
/**
 * Middleware للمصادقة والصلاحيات وRate Limiting
 */

class ApiMiddleware {
    /**
     * التحقق من المصادقة والحصول على بيانات المستخدم
     */
    public static function authenticate($conn) {
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
            ApiResponse::error(ApiErrorCodes::AUTH_TOKEN_MISSING);
        }
        
        // التحقق من التوكن في قاعدة البيانات
        $stmt = $conn->prepare("
            SELECT u.id, u.username, u.full_name, u.role, u.status, u.permissions
            FROM users u
            WHERE u.token = ? AND u.status = 'active'
            LIMIT 1
        ");
        
        $stmt->bind_param('s', $token);
        $stmt->execute();
        $result = $stmt->get_result();
        
        if ($result->num_rows === 0) {
            ApiResponse::error(ApiErrorCodes::AUTH_TOKEN_INVALID);
        }
        
        $user = $result->fetch_assoc();
        
        // تسجيل آخر نشاط
        $updateStmt = $conn->prepare("UPDATE users SET last_activity = NOW() WHERE id = ?");
        $updateStmt->bind_param('i', $user['id']);
        $updateStmt->execute();
        
        return $user;
    }
    
    /**
     * التحقق من الصلاحيات
     */
    public static function checkPermission($user, $permission) {
        // المدير لديه جميع الصلاحيات
        if ($user['role'] === 'admin') {
            return true;
        }
        
        // التحقق من الصلاحيات المخصصة
        if (isset($user['permissions'])) {
            $permissions = json_decode($user['permissions'], true) ?? [];
            if (in_array($permission, $permissions) || in_array('*', $permissions)) {
                return true;
            }
        }
        
        return false;
    }
    
    /**
     * طلب صلاحية معينة
     */
    public static function requirePermission($user, $permission) {
        if (!self::checkPermission($user, $permission)) {
            ApiResponse::error(
                ApiErrorCodes::AUTH_INSUFFICIENT_PERMISSIONS,
                "تحتاج صلاحية: $permission"
            );
        }
        
        return true;
    }
    
    /**
     * طلب أحد الصلاحيات
     */
    public static function requireAnyPermission($user, $permissions) {
        foreach ($permissions as $permission) {
            if (self::checkPermission($user, $permission)) {
                return true;
            }
        }
        
        ApiResponse::error(
            ApiErrorCodes::AUTH_INSUFFICIENT_PERMISSIONS,
            "تحتاج إحدى الصلاحيات: " . implode(', ', $permissions)
        );
    }
    
    /**
     * طلب جميع الصلاحيات
     */
    public static function requireAllPermissions($user, $permissions) {
        foreach ($permissions as $permission) {
            if (!self::checkPermission($user, $permission)) {
                ApiResponse::error(
                    ApiErrorCodes::AUTH_INSUFFICIENT_PERMISSIONS,
                    "تحتاج صلاحية: $permission"
                );
            }
        }
        
        return true;
    }
    
    /**
     * التحقق من الدور
     */
    public static function requireRole($user, $roles) {
        $roles = is_array($roles) ? $roles : [$roles];
        
        if (!in_array($user['role'], $roles)) {
            ApiResponse::error(
                ApiErrorCodes::AUTH_INSUFFICIENT_PERMISSIONS,
                "تحتاج دور: " . implode(' أو ', $roles)
            );
        }
        
        return true;
    }
    
    /**
     * Rate Limiting - منع الإفراط في الطلبات
     */
    public static function rateLimit($identifier, $maxRequests = 60, $timeWindow = 60) {
        $cacheFile = sys_get_temp_dir() . "/rate_limit_" . md5($identifier) . ".json";
        
        $now = time();
        $requests = [];
        
        // قراءة الطلبات السابقة
        if (file_exists($cacheFile)) {
            $data = json_decode(file_get_contents($cacheFile), true);
            if ($data && isset($data['requests'])) {
                // إزالة الطلبات القديمة
                $requests = array_filter($data['requests'], function($timestamp) use ($now, $timeWindow) {
                    return ($now - $timestamp) < $timeWindow;
                });
            }
        }
        
        // التحقق من تجاوز الحد
        if (count($requests) >= $maxRequests) {
            $oldestRequest = min($requests);
            $retryAfter = $timeWindow - ($now - $oldestRequest);
            
            header("Retry-After: $retryAfter");
            header("X-RateLimit-Limit: $maxRequests");
            header("X-RateLimit-Remaining: 0");
            header("X-RateLimit-Reset: " . ($oldestRequest + $timeWindow));
            
            ApiResponse::error(
                ApiErrorCodes::SYSTEM_RATE_LIMIT,
                "حاول مرة أخرى بعد $retryAfter ثانية"
            );
        }
        
        // إضافة الطلب الحالي
        $requests[] = $now;
        
        // حفظ الطلبات
        file_put_contents($cacheFile, json_encode(['requests' => $requests]), LOCK_EX);
        
        // إضافة headers للحد المتبقي
        header("X-RateLimit-Limit: $maxRequests");
        header("X-RateLimit-Remaining: " . ($maxRequests - count($requests)));
        header("X-RateLimit-Reset: " . ($now + $timeWindow));
        
        return true;
    }
    
    /**
     * CORS Middleware
     */
    public static function cors() {
        // السماح بجميع المصادر في التطوير (غير موصى به في الإنتاج)
        if (isset($_SERVER['HTTP_ORIGIN'])) {
            header("Access-Control-Allow-Origin: {$_SERVER['HTTP_ORIGIN']}");
            header('Access-Control-Allow-Credentials: true');
            header('Access-Control-Max-Age: 3600');
        }
        
        if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
            if (isset($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_METHOD'])) {
                header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS");
            }
            
            if (isset($_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS'])) {
                header("Access-Control-Allow-Headers: {$_SERVER['HTTP_ACCESS_CONTROL_REQUEST_HEADERS']}");
            }
            
            exit(0);
        }
    }
    
    /**
     * التحقق من صيانة النظام
     */
    public static function checkMaintenance() {
        $maintenanceFile = __DIR__ . '/../../maintenance.json';
        
        if (file_exists($maintenanceFile)) {
            $data = json_decode(file_get_contents($maintenanceFile), true);
            
            if ($data && isset($data['enabled']) && $data['enabled'] === true) {
                $message = $data['message'] ?? 'النظام تحت الصيانة';
                $expectedEnd = $data['expected_end'] ?? null;
                
                ApiResponse::error(
                    ApiErrorCodes::SYSTEM_MAINTENANCE,
                    [
                        'message' => $message,
                        'expected_end' => $expectedEnd
                    ]
                );
            }
        }
    }
    
    /**
     * تسجيل الطلب
     */
    public static function logRequest($user = null, $startTime = null) {
        $endpoint = $_SERVER['REQUEST_URI'] ?? '';
        $method = $_SERVER['REQUEST_METHOD'] ?? '';
        $userId = $user['id'] ?? null;
        $duration = $startTime ? round((microtime(true) - $startTime) * 1000, 2) : null;
        
        ApiLogger::logRequest($endpoint, $method, $userId, $duration);
    }
    
    /**
     * التحقق من حجم البيانات
     */
    public static function checkPayloadSize($maxSize = 5242880) { // 5MB default
        $contentLength = $_SERVER['CONTENT_LENGTH'] ?? 0;
        
        if ($contentLength > $maxSize) {
            ApiResponse::error(
                ApiErrorCodes::REQUEST_PAYLOAD_TOO_LARGE,
                "حجم البيانات يجب ألا يتجاوز " . round($maxSize / 1048576, 2) . " MB"
            );
        }
    }
    
    /**
     * التحقق من صحة JSON
     */
    public static function validateJson() {
        if ($_SERVER['REQUEST_METHOD'] === 'POST' || $_SERVER['REQUEST_METHOD'] === 'PUT') {
            $input = file_get_contents('php://input');
            
            if (!empty($input)) {
                json_decode($input);
                
                if (json_last_error() !== JSON_ERROR_NONE) {
                    ApiResponse::error(
                        ApiErrorCodes::REQUEST_INVALID_JSON,
                        json_last_error_msg()
                    );
                }
            }
        }
    }
}

/**
 * صلاحيات النظام المُعرفة مسبقاً
 */
class Permissions {
    // صلاحيات الغرف
    const ROOMS_VIEW = 'rooms.view';
    const ROOMS_CREATE = 'rooms.create';
    const ROOMS_UPDATE = 'rooms.update';
    const ROOMS_DELETE = 'rooms.delete';
    
    // صلاحيات الحجوزات
    const BOOKINGS_VIEW = 'bookings.view';
    const BOOKINGS_CREATE = 'bookings.create';
    const BOOKINGS_UPDATE = 'bookings.update';
    const BOOKINGS_DELETE = 'bookings.delete';
    const BOOKINGS_CHECKOUT = 'bookings.checkout';
    
    // صلاحيات الموظفين
    const EMPLOYEES_VIEW = 'employees.view';
    const EMPLOYEES_CREATE = 'employees.create';
    const EMPLOYEES_UPDATE = 'employees.update';
    const EMPLOYEES_DELETE = 'employees.delete';
    const EMPLOYEES_SALARY = 'employees.salary';
    
    // صلاحيات المصروفات
    const EXPENSES_VIEW = 'expenses.view';
    const EXPENSES_CREATE = 'expenses.create';
    const EXPENSES_UPDATE = 'expenses.update';
    const EXPENSES_DELETE = 'expenses.delete';
    
    // صلاحيات المدفوعات
    const PAYMENTS_VIEW = 'payments.view';
    const PAYMENTS_CREATE = 'payments.create';
    const PAYMENTS_UPDATE = 'payments.update';
    const PAYMENTS_DELETE = 'payments.delete';
    
    // صلاحيات التقارير
    const REPORTS_VIEW = 'reports.view';
    const REPORTS_FINANCIAL = 'reports.financial';
    const REPORTS_EXPORT = 'reports.export';
    
    // صلاحيات النظام
    const SYSTEM_SETTINGS = 'system.settings';
    const SYSTEM_USERS = 'system.users';
    const SYSTEM_BACKUP = 'system.backup';
    
    // صلاحية المدير الكامل
    const ADMIN_ALL = '*';
    
    /**
     * الحصول على جميع الصلاحيات
     */
    public static function all() {
        $reflection = new ReflectionClass(__CLASS__);
        return array_values($reflection->getConstants());
    }
    
    /**
     * الحصول على صلاحيات حسب الفئة
     */
    public static function byCategory($category) {
        $all = self::all();
        return array_filter($all, function($permission) use ($category) {
            return strpos($permission, $category . '.') === 0;
        });
    }
}
