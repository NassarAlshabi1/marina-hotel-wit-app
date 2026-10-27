<?php
/**
 * ملف التحقق من صلاحيات المستخدم
 * يستخدم هذا الملف للتحقق من تسجيل دخول المستخدم وصلاحياته
 */

// التأكد من بدء الجلسة
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}

// التحقق من تسجيل دخول المستخدم
function is_logged_in() {
    return isset($_SESSION['user_id']) && !empty($_SESSION['user_id']);
}

// التحقق من صلاحية المستخدم
function check_permission($permission_code) {
    // إذا لم يكن المستخدم مسجل دخول، فليس لديه أي صلاحيات
    if (!is_logged_in()) {
        return false;
    }
    
    // إذا كان المستخدم مدير النظام، فلديه جميع الصلاحيات
    if ($_SESSION['user_type'] === 'admin') {
        return true;
    }
    
    // التحقق من وجود الصلاحية في مصفوفة صلاحيات المستخدم
    return isset($_SESSION['permissions']) && in_array($permission_code, $_SESSION['permissions']);
}

// إعادة توجيه المستخدم إلى صفحة تسجيل الدخول إذا لم يكن مسجل دخول
function redirect_if_not_logged_in() {
    if (!is_logged_in()) {
        header("Location: /login.php?error=يجب تسجيل الدخول للوصول إلى هذه الصفحة");
        exit;
    }
}

// التحقق من تسجيل دخول المستخدم وإعادة توجيهه إذا لم يكن مسجل دخول
redirect_if_not_logged_in();
?>
