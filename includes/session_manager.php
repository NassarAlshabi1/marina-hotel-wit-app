<?php
/**
 * مدير الجلسات الموحد
 * يوفر إدارة آمنة وموحدة للجلسات في جميع أنحاء النظام
 */

/**
 * بدء الجلسة مع إعدادات الأمان
 * يجب استدعاء هذه الدالة قبل أي استخدام للجلسة
 */
function start_secure_session() {
    // التحقق من أن الجلسة لم تبدأ بعد
    if (session_status() === PHP_SESSION_NONE) {
        // تعيين إعدادات الأمان قبل بدء الجلسة
        ini_set('session.cookie_httponly', 1);
        ini_set('session.cookie_secure', 1);
        ini_set('session.use_strict_mode', 1);
        ini_set('session.use_only_cookies', 1);
        ini_set('session.cookie_path', '/');
        
        // تعيين مدة انتهاء صلاحية الجلسة
        ini_set('session.gc_maxlifetime', SESSION_TIMEOUT);
        ini_set('session.cookie_lifetime', SESSION_TIMEOUT);
        
        // بدء الجلسة
        session_start();
        
        // تجديد معرف الجلسة لمنع session fixation
        if (!isset($_SESSION['initiated'])) {
            session_regenerate_id(true);
            $_SESSION['initiated'] = true;
            $_SESSION['created_at'] = time();
        }
        
        // تحديث وقت النشاط الأخير
        $_SESSION['last_activity'] = time();
    }
}

/**
 * التحقق من صحة الجلسة
 * @return bool true إذا كانت الجلسة صحيحة، false إذا انتهت صلاحيتها
 */
function validate_session() {
    // التحقق من وجود الجلسة
    if (session_status() !== PHP_SESSION_ACTIVE) {
        return false;
    }
    
    // التحقق من انتهاء صلاحية الجلسة
    if (isset($_SESSION['last_activity']) && 
        (time() - $_SESSION['last_activity'] > SESSION_TIMEOUT)) {
        destroy_secure_session();
        return false;
    }
    
    // التحقق من عمر الجلسة الإجمالي (4 ساعات كحد أقصى)
    if (isset($_SESSION['created_at']) && 
        (time() - $_SESSION['created_at'] > 14400)) {
        destroy_secure_session();
        return false;
    }
    
    // تحديث وقت النشاط الأخير
    $_SESSION['last_activity'] = time();
    
    return true;
}

/**
 * تدمير الجلسة بشكل آمن
 */
function destroy_secure_session() {
    if (session_status() === PHP_SESSION_ACTIVE) {
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
}

/**
 * التحقق من تسجيل دخول المستخدم
 * @return bool
 */
function is_user_logged_in() {
    return isset($_SESSION['user_id']) && 
           !empty($_SESSION['user_id']) &&
           isset($_SESSION['user_type']) && 
           !empty($_SESSION['user_type']);
}

/**
 * تسجيل دخول المستخدم
 * @param array $user_data بيانات المستخدم
 */
function login_user($user_data) {
    // تجديد معرف الجلسة لمنع session fixation
    session_regenerate_id(true);
    
    // حفظ بيانات المستخدم في الجلسة
    $_SESSION['user_id'] = $user_data['user_id'];
    $_SESSION['username'] = $user_data['username'];
    $_SESSION['user_type'] = $user_data['user_type'];
    $_SESSION['full_name'] = $user_data['full_name'] ?? '';
    $_SESSION['last_activity'] = time();
    $_SESSION['initiated'] = true;
    $_SESSION['ip_address'] = get_real_ip();
    
    // إضافة الصلاحيات إذا كانت متوفرة
    if (isset($user_data['permissions'])) {
        $_SESSION['permissions'] = $user_data['permissions'];
    }
}

/**
 * تسجيل خروج المستخدم
 * @param string $redirect_url رابط إعادة التوجيه (اختياري)
 */
function logout_user($redirect_url = '/login.php') {
    destroy_secure_session();
    
    // إعادة التوجيه
    header("Location: $redirect_url?message=تم تسجيل الخروج بنجاح");
    exit;
}

/**
 * إعادة توجيه المستخدم إذا لم يكن مسجل دخول
 * @param string $login_url رابط صفحة تسجيل الدخول
 */
function redirect_if_not_logged_in($login_url = '/login.php') {
    if (!validate_session() || !is_user_logged_in()) {
        // تحديد المسار النسبي للوصول إلى صفحة تسجيل الدخول
        $current_path = $_SERVER['REQUEST_URI'];
        $path_depth = substr_count($current_path, '/') - 1;
        
        if ($path_depth > 0) {
            $login_url = str_repeat('../', $path_depth) . 'login.php';
        }
        
        header("Location: $login_url?error=يجب تسجيل الدخول للوصول إلى هذه الصفحة");
        exit;
    }
}

/**
 * التحقق من صلاحية المستخدم
 * @param string $permission_code كود الصلاحية
 * @return bool
 */
function check_user_permission($permission_code) {
    if (!is_user_logged_in()) {
        return false;
    }
    
    // المدير لديه جميع الصلاحيات
    if ($_SESSION['user_type'] === 'admin') {
        return true;
    }
    
    // التحقق من الصلاحيات المحددة
    return isset($_SESSION['permissions']) && 
           is_array($_SESSION['permissions']) && 
           in_array($permission_code, $_SESSION['permissions']);
}

/**
 * توليد رمز CSRF
 * @return string
 */
function generate_csrf_token() {
    if (!isset($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

/**
 * التحقق من رمز CSRF
 * @param string $token الرمز المرسل
 * @return bool
 */
function validate_csrf_token($token) {
    return isset($_SESSION['csrf_token']) && 
           !empty($token) && 
           hash_equals($_SESSION['csrf_token'], $token);
}

/**
 * الحصول على عنوان IP الحقيقي للمستخدم
 * @return string
 */
function get_real_ip() {
    $ip_keys = ['HTTP_X_FORWARDED_FOR', 'HTTP_X_REAL_IP', 'HTTP_CLIENT_IP', 'REMOTE_ADDR'];
    
    foreach ($ip_keys as $key) {
        if (!empty($_SERVER[$key])) {
            $ip = $_SERVER[$key];
            // في حالة وجود عدة عناوين IP، أخذ الأول
            if (strpos($ip, ',') !== false) {
                $ip = trim(explode(',', $ip)[0]);
            }
            // التحقق من صحة عنوان IP
            if (filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE)) {
                return $ip;
            }
        }
    }
    
    return $_SERVER['REMOTE_ADDR'] ?? '0.0.0.0';
}

// بدء الجلسة الآمنة تلقائياً عند تضمين هذا الملف
start_secure_session();
?>
