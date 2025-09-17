<?php
/**
 * نظام المصادقة الموحد
 * يوفر آلية آمنة للتحقق من المستخدمين وإدارة الجلسات
 */

// إعدادات الأمان للجلسة (يجب تعيينها قبل بدء الجلسة)
if (session_status() == PHP_SESSION_NONE) {
    ini_set('session.cookie_httponly', 1);
    ini_set('session.cookie_secure', 1);
    ini_set('session.use_strict_mode', 1);
    session_start();
}

// تجديد معرف الجلسة لمنع session fixation
if (!isset($_SESSION['initiated'])) {
    session_regenerate_id(true);
    $_SESSION['initiated'] = true;
}

// التحقق من انتهاء صلاحية الجلسة (30 دقيقة)
if (isset($_SESSION['last_activity']) && (time() - $_SESSION['last_activity'] > 1800)) {
    session_unset();
    session_destroy();
    header("Location: /login.php?error=انتهت صلاحية الجلسة");
    exit;
}
$_SESSION['last_activity'] = time();

// التحقق من تسجيل دخول المستخدم
function is_logged_in() {
    return isset($_SESSION['user_id']) && !empty($_SESSION['user_id']) &&
           isset($_SESSION['user_type']) && !empty($_SESSION['user_type']);
}

// التحقق من صلاحية المستخدم
function check_permission($permission_code) {
    if (!is_logged_in()) {
        return false;
    }

    // المدير لديه جميع الصلاحيات
    if ($_SESSION['user_type'] === 'admin') {
        return true;
    }

    // التحقق من الصلاحيات المحددة
    return isset($_SESSION['permissions']) && in_array($permission_code, $_SESSION['permissions']);
}

// إعادة توجيه المستخدم إذا لم يكن مسجل دخول
function redirect_if_not_logged_in() {
    if (!is_logged_in()) {
        // تحديد المسار الصحيح لصفحة تسجيل الدخول
        $current_path = $_SERVER['REQUEST_URI'];
        $path_depth = substr_count(dirname($_SERVER['SCRIPT_NAME']), '/') - 1;
        $login_path = str_repeat('../', max(0, $path_depth)) . 'login.php';

        header("Location: " . $login_path . "?error=يجب تسجيل الدخول للوصول إلى هذه الصفحة");
        exit;
    }
}

// تسجيل خروج آمن
function logout() {
    session_unset();
    session_destroy();

    // حذف ملفات تعريف الارتباط
    if (ini_get("session.use_cookies")) {
        $params = session_get_cookie_params();
        setcookie(session_name(), '', time() - 42000,
            $params["path"], $params["domain"],
            $params["secure"], $params["httponly"]
        );
    }

    header("Location: /login.php?message=تم تسجيل الخروج بنجاح");
    exit;
}

// التحقق من تسجيل دخول المستخدم
redirect_if_not_logged_in();
?>
