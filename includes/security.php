<?php
/**
 * ملف الأمان المتقدم
 * يوفر حماية شاملة ضد التهديدات الأمنية المختلفة
 */

/**
 * فئة إدارة الأمان
 */
class SecurityManager {
    private $conn;
    private $session_timeout = SESSION_TIMEOUT;
    private $max_login_attempts = MAX_LOGIN_ATTEMPTS;
    private $lockout_time = LOCKOUT_TIME;
    
    public function __construct($connection) {
        $this->conn = $connection;
    }
    
    /**
     * توليد رمز CSRF
     */
    public function generateCSRFToken() {
        if (!isset($_SESSION['csrf_token'])) {
            $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
        }
        return $_SESSION['csrf_token'];
    }
    
    /**
     * التحقق من رمز CSRF
     */
    public function validateCSRFToken($token) {
        if (!isset($_SESSION['csrf_token']) || empty($token)) {
            return false;
        }
        
        return hash_equals($_SESSION['csrf_token'], $token);
    }
    
    /**
     * تنظيف البيانات المدخلة
     */
    public function sanitizeInput($input, $type = 'string') {
        if (is_array($input)) {
            return array_map(function($item) use ($type) {
                return $this->sanitizeInput($item, $type);
            }, $input);
        }
        
        // إزالة المسافات الزائدة
        $input = trim($input);
        
        switch ($type) {
            case 'email':
                return filter_var($input, FILTER_SANITIZE_EMAIL);
                
            case 'url':
                return filter_var($input, FILTER_SANITIZE_URL);
                
            case 'int':
                return filter_var($input, FILTER_SANITIZE_NUMBER_INT);
                
            case 'float':
                return filter_var($input, FILTER_SANITIZE_NUMBER_FLOAT, FILTER_FLAG_ALLOW_FRACTION);
                
            case 'html':
                return htmlspecialchars($input, ENT_QUOTES | ENT_HTML5, 'UTF-8');
                
            case 'sql':
                return $this->conn->real_escape_string($input);
                
            default: // string
                return htmlspecialchars(strip_tags($input), ENT_QUOTES | ENT_HTML5, 'UTF-8');
        }
    }
    
    /**
     * التحقق من قوة كلمة المرور
     */
    public function validatePasswordStrength($password) {
        $errors = [];
        
        if (strlen($password) < 8) {
            $errors[] = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
        }
        
        if (!preg_match('/[A-Z]/', $password)) {
            $errors[] = 'كلمة المرور يجب أن تحتوي على حرف كبير واحد على الأقل';
        }
        
        if (!preg_match('/[a-z]/', $password)) {
            $errors[] = 'كلمة المرور يجب أن تحتوي على حرف صغير واحد على الأقل';
        }
        
        if (!preg_match('/[0-9]/', $password)) {
            $errors[] = 'كلمة المرور يجب أن تحتوي على رقم واحد على الأقل';
        }
        
        if (!preg_match('/[^A-Za-z0-9]/', $password)) {
            $errors[] = 'كلمة المرور يجب أن تحتوي على رمز خاص واحد على الأقل';
        }
        
        return $errors;
    }
    
    /**
     * تشفير كلمة المرور
     */
    public function hashPassword($password) {
        return password_hash($password, PASSWORD_ARGON2ID, [
            'memory_cost' => 65536, // 64 MB
            'time_cost' => 4,       // 4 iterations
            'threads' => 3,         // 3 threads
        ]);
    }
    
    /**
     * التحقق من كلمة المرور
     */
    public function verifyPassword($password, $hash) {
        return password_verify($password, $hash);
    }
    
    /**
     * تسجيل محاولة تسجيل دخول فاشلة
     */
    public function logFailedLogin($username, $ip_address) {
        $stmt = $this->conn->prepare("
            INSERT INTO failed_logins (username, ip_address, attempt_time) 
            VALUES (?, ?, NOW())
        ");
        
        if ($stmt) {
            $stmt->bind_param("ss", $username, $ip_address);
            $stmt->execute();
            $stmt->close();
        }
        
        // تحديث عداد المحاولات الفاشلة للمستخدم
        $this->updateFailedAttempts($username);
    }
    
    /**
     * التحقق من حالة القفل للمستخدم
     */
    public function isUserLocked($username) {
        // التحقق من وجود الأعمدة المطلوبة أولاً
        $check_columns = $this->conn->query("SHOW COLUMNS FROM users LIKE 'failed_login_attempts'");

        if (!$check_columns || $check_columns->num_rows == 0) {
            // إذا لم تكن الأعمدة موجودة، أنشئها
            $this->addSecurityColumnsToUsers();
        }

        $stmt = $this->conn->prepare("
            SELECT failed_login_attempts, locked_until
            FROM users
            WHERE username = ?
        ");

        if (!$stmt) {
            return false;
        }

        $stmt->bind_param("s", $username);
        $stmt->execute();
        $result = $stmt->get_result();
        $user = $result->fetch_assoc();
        $stmt->close();

        if (!$user) {
            return false;
        }

        // التحقق من انتهاء فترة القفل
        if (isset($user['locked_until']) && $user['locked_until'] && strtotime($user['locked_until']) > time()) {
            return true;
        }

        // إعادة تعيين العداد إذا انتهت فترة القفل
        if (isset($user['locked_until']) && $user['locked_until'] && strtotime($user['locked_until']) <= time()) {
            $this->resetFailedAttempts($username);
        }

        return false;
    }
    
    /**
     * إضافة الأعمدة الأمنية لجدول المستخدمين
     */
    private function addSecurityColumnsToUsers() {
        try {
            // التحقق من وجود جدول المستخدمين
            $check_table = $this->conn->query("SHOW TABLES LIKE 'users'");
            if (!$check_table || $check_table->num_rows == 0) {
                // إنشاء جدول المستخدمين إذا لم يكن موجوداً
                $this->createSecurityTables();
                return;
            }

            // إضافة الأعمدة المفقودة
            $columns_to_add = [
                "ALTER TABLE users ADD COLUMN failed_login_attempts INT DEFAULT 0",
                "ALTER TABLE users ADD COLUMN locked_until TIMESTAMP NULL",
                "ALTER TABLE users ADD COLUMN last_login TIMESTAMP NULL"
            ];

            foreach ($columns_to_add as $sql) {
                // تنفيذ الاستعلام مع تجاهل الأخطاء إذا كان العمود موجود
                $result = $this->conn->query($sql);
                if (!$result && strpos($this->conn->error, "Duplicate column name") === false) {
                    error_log("خطأ في إضافة عمود: " . $this->conn->error);
                }
            }

        } catch (Exception $e) {
            // تجاهل الأخطاء إذا كانت الأعمدة موجودة بالفعل
            error_log("خطأ في إضافة أعمدة الأمان: " . $e->getMessage());
        }
    }

    /**
     * تحديث عداد المحاولات الفاشلة
     */
    private function updateFailedAttempts($username) {
        // التأكد من وجود الأعمدة المطلوبة
        $this->addSecurityColumnsToUsers();

        $stmt = $this->conn->prepare("
            UPDATE users
            SET failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1,
                locked_until = CASE
                    WHEN COALESCE(failed_login_attempts, 0) + 1 >= ? THEN DATE_ADD(NOW(), INTERVAL ? SECOND)
                    ELSE locked_until
                END
            WHERE username = ?
        ");

        if ($stmt) {
            $stmt->bind_param("iis", $this->max_login_attempts, $this->lockout_time, $username);
            $stmt->execute();
            $stmt->close();
        }
    }
    
    /**
     * إعادة تعيين عداد المحاولات الفاشلة
     */
    public function resetFailedAttempts($username) {
        // التأكد من وجود الأعمدة المطلوبة
        $this->addSecurityColumnsToUsers();

        $stmt = $this->conn->prepare("
            UPDATE users
            SET failed_login_attempts = 0, locked_until = NULL
            WHERE username = ?
        ");

        if ($stmt) {
            $stmt->bind_param("s", $username);
            $stmt->execute();
            $stmt->close();
        }
    }
    
    /**
     * التحقق من عنوان IP المشبوه
     */
    public function checkSuspiciousIP($ip_address) {
        $stmt = $this->conn->prepare("
            SELECT COUNT(*) as attempts 
            FROM failed_logins 
            WHERE ip_address = ? AND attempt_time > DATE_SUB(NOW(), INTERVAL 1 HOUR)
        ");
        
        if (!$stmt) {
            return false;
        }
        
        $stmt->bind_param("s", $ip_address);
        $stmt->execute();
        $result = $stmt->get_result();
        $data = $result->fetch_assoc();
        $stmt->close();
        
        return $data['attempts'] > 10; // أكثر من 10 محاولات في الساعة
    }
    
    /**
     * تسجيل نشاط المستخدم
     */
    public function logUserActivity($user_id, $action, $details = null) {
        $stmt = $this->conn->prepare("
            INSERT INTO user_activity_log (user_id, action, details, ip_address, user_agent, created_at) 
            VALUES (?, ?, ?, ?, ?, NOW())
        ");
        
        if ($stmt) {
            $ip_address = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
            $user_agent = $_SERVER['HTTP_USER_AGENT'] ?? 'unknown';
            
            $stmt->bind_param("issss", $user_id, $action, $details, $ip_address, $user_agent);
            $stmt->execute();
            $stmt->close();
        }
    }
    
    /**
     * التحقق من صحة الجلسة
     */
    public function validateSession() {
        // التحقق من انتهاء صلاحية الجلسة
        if (isset($_SESSION['last_activity']) && 
            (time() - $_SESSION['last_activity'] > $this->session_timeout)) {
            $this->destroySession();
            return false;
        }
        
        // التحقق من تطابق عنوان IP (اختياري)
        if (isset($_SESSION['ip_address']) && 
            $_SESSION['ip_address'] !== $_SERVER['REMOTE_ADDR']) {
            $this->destroySession();
            return false;
        }
        
        // تحديث وقت النشاط الأخير
        $_SESSION['last_activity'] = time();
        
        return true;
    }
    
    /**
     * تدمير الجلسة بشكل آمن
     */
    public function destroySession() {
        // تسجيل تسجيل الخروج
        if (isset($_SESSION['user_id'])) {
            $this->logUserActivity($_SESSION['user_id'], 'logout', 'Session destroyed');
        }
        
        // مسح جميع متغيرات الجلسة
        $_SESSION = [];
        
        // حذف ملف تعريف ارتباط الجلسة
        if (ini_get("session.use_cookies")) {
            $params = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000,
                $params["path"], $params["domain"],
                $params["secure"], $params["httponly"]
            );
        }
        
        // تدمير الجلسة
        session_destroy();
    }
    
    /**
     * إنشاء الجداول الأمنية المطلوبة
     */
    public function createSecurityTables() {
        $tables = [
            "CREATE TABLE IF NOT EXISTS failed_logins (
                id INT AUTO_INCREMENT PRIMARY KEY,
                username VARCHAR(50),
                ip_address VARCHAR(45),
                attempt_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_username (username),
                INDEX idx_ip_address (ip_address),
                INDEX idx_attempt_time (attempt_time)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4",
            
            "CREATE TABLE IF NOT EXISTS user_activity_log (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT,
                action VARCHAR(100),
                details TEXT,
                ip_address VARCHAR(45),
                user_agent TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_user_id (user_id),
                INDEX idx_action (action),
                INDEX idx_created_at (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
        ];
        
        foreach ($tables as $sql) {
            $this->conn->query($sql);
        }
    }
}

/**
 * دوال مساعدة للأمان
 */

/**
 * الحصول على عنوان IP الحقيقي للمستخدم
 */
function get_real_ip() {
    $ip_keys = ['HTTP_X_FORWARDED_FOR', 'HTTP_X_REAL_IP', 'HTTP_CLIENT_IP', 'REMOTE_ADDR'];
    
    foreach ($ip_keys as $key) {
        if (!empty($_SERVER[$key])) {
            $ip = $_SERVER[$key];
            if (strpos($ip, ',') !== false) {
                $ip = trim(explode(',', $ip)[0]);
            }
            if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
                return $ip;
            }
        }
    }
    
    return $_SERVER['REMOTE_ADDR'] ?? 'unknown';
}

/**
 * التحقق من صحة رمز CSRF في النماذج
 */
function verify_csrf_token() {
    global $conn;
    $security = new SecurityManager($conn);
    
    $token = $_POST['csrf_token'] ?? $_GET['csrf_token'] ?? '';
    
    if (!$security->validateCSRFToken($token)) {
        show_user_error("رمز الأمان غير صحيح. يرجى إعادة تحميل الصفحة والمحاولة مرة أخرى.");
    }
}

/**
 * إنشاء حقل CSRF مخفي للنماذج
 */
function csrf_field() {
    global $conn;
    $security = new SecurityManager($conn);
    $token = $security->generateCSRFToken();
    
    return "<input type='hidden' name='csrf_token' value='" . htmlspecialchars($token) . "'>";
}
?>
