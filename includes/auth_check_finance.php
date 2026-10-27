<?php
/**
 * ملف التحقق من صلاحيات المستخدم للإدارة المالية وأدوات النظام
 * هذا الملف مخصص للتحقق من صلاحيات المستخدم للوصول إلى الإدارة المالية وأدوات النظام
 */

// التأكد من بدء الجلسة مع إعدادات الأمان
if (session_status() == PHP_SESSION_NONE) {
    // تعديل إعدادات الجلسة لتحسين الأمان والاستمرارية (قبل بدء الجلسة)
    ini_set('session.cookie_httponly', 1);
    ini_set('session.use_only_cookies', 1);
    ini_set('session.cookie_path', '/');

    // بدء الجلسة
    session_start();
}

// التحقق من تسجيل دخول المستخدم
function is_logged_in() {
    return isset($_SESSION['user_id']) && !empty($_SESSION['user_id']);
}

// التحقق من صلاحية المستخدم للوصول إلى الإدارة المالية
function check_finance_permission() {
    // إذا لم يكن المستخدم مسجل دخول، فليس لديه أي صلاحيات
    if (!is_logged_in()) {
        return false;
    }
    
    // إذا كان المستخدم مدير النظام، فلديه جميع الصلاحيات
    if (isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'admin') {
        return true;
    }
    
    // التحقق من وجود صلاحيات الإدارة المالية
    $finance_permissions = ['manage_payments', 'manage_expenses', 'manage_cash', 'view_reports'];
    
    if (!isset($_SESSION['permissions']) || !is_array($_SESSION['permissions'])) {
        return false;
    }
    
    // التحقق من وجود أي صلاحية من صلاحيات الإدارة المالية
    foreach ($finance_permissions as $permission) {
        if (in_array($permission, $_SESSION['permissions'])) {
            return true;
        }
    }
    
    return false;
}

// التحقق من صلاحية المستخدم للوصول إلى أدوات النظام
function check_system_tools_permission() {
    // إذا لم يكن المستخدم مسجل دخول، فليس لديه أي صلاحيات
    if (!is_logged_in()) {
        return false;
    }
    
    // إذا كان المستخدم مدير النظام، فلديه جميع الصلاحيات
    if (isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'admin') {
        return true;
    }
    
    // التحقق من وجود صلاحيات أدوات النظام
    $system_permissions = ['manage_users', 'manage_settings'];
    
    if (!isset($_SESSION['permissions']) || !is_array($_SESSION['permissions'])) {
        return false;
    }
    
    // التحقق من وجود أي صلاحية من صلاحيات أدوات النظام
    foreach ($system_permissions as $permission) {
        if (in_array($permission, $_SESSION['permissions'])) {
            return true;
        }
    }
    
    return false;
}

// التحقق من صلاحية المستخدم
function check_permission($permission_code) {
    // إذا لم يكن المستخدم مسجل دخول، فليس لديه أي صلاحيات
    if (!is_logged_in()) {
        return false;
    }
    
    // إذا كان المستخدم مدير النظام، فلديه جميع الصلاحيات
    if (isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'admin') {
        return true;
    }
    
    // التحقق من وجود الصلاحية في مصفوفة صلاحيات المستخدم
    return isset($_SESSION['permissions']) && is_array($_SESSION['permissions']) && in_array($permission_code, $_SESSION['permissions']);
}

// إعادة توجيه المستخدم إلى صفحة تسجيل الدخول إذا لم يكن مسجل دخول
function redirect_if_not_logged_in() {
    if (!is_logged_in()) {
        // تسجيل الخطأ للتشخيص
        error_log("تم إعادة توجيه المستخدم: غير مسجل الدخول - " . $_SERVER['REQUEST_URI']);
        
        // تحديد المسار النسبي للوصول إلى صفحة تسجيل الدخول
        $current_path = $_SERVER['REQUEST_URI'];
        $path_depth = substr_count($current_path, '/') - 1;
        $login_path = str_repeat('../', $path_depth) . 'login.php';
        
        if ($path_depth <= 0) {
            $login_path = '/login.php';
        }
        
        header("Location: " . $login_path . "?error=يجب تسجيل الدخول للوصول إلى هذه الصفحة");
        exit;
    }
}

// التحقق من تسجيل دخول المستخدم وإعادة توجيهه إذا لم يكن مسجل دخول
redirect_if_not_logged_in();
?>
