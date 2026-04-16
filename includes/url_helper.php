<?php
/**
 * مساعد المسارات - لحل مشكلة تكرار /admin/ في المسارات
 */

/**
 * إنشاء مسار صحيح للنظام
 * @param string $path المسار المطلوب
 * @return string المسار الصحيح
 */
function admin_url($path = '') {
    // إزالة admin/ من بداية المسار إذا كان موجوداً
    $path = ltrim($path, '/');
    if (strpos($path, 'admin/') === 0) {
        $path = substr($path, 6); // إزالة admin/
    }
    
    // التأكد من أن BASE_URL لا ينتهي بـ admin/
    $base_url = rtrim(BASE_URL, '/');
    if (substr($base_url, -6) === '/admin') {
        $base_url = substr($base_url, 0, -6);
    }
    
    return $base_url . '/admin/' . $path;
}

/**
 * إنشاء مسار للجذر الرئيسي
 * @param string $path المسار المطلوب
 * @return string المسار الصحيح
 */
function site_url($path = '') {
    $path = ltrim($path, '/');
    $base_url = rtrim(BASE_URL, '/');
    
    // إزالة admin من BASE_URL إذا كان موجوداً
    if (substr($base_url, -6) === '/admin') {
        $base_url = substr($base_url, 0, -6);
    }
    
    return $base_url . '/' . $path;
}

/**
 * الحصول على المسار النسبي الصحيح للأصول
 * @param string $asset_path مسار الأصل
 * @return string المسار الصحيح للأصل
 */
function asset_url($asset_path = '') {
    $asset_path = ltrim($asset_path, '/');
    return site_url('assets/' . $asset_path);
}

/**
 * التحقق من المسار الحالي
 * @param string $path المسار للتحقق منه
 * @return bool
 */
function is_current_page($path) {
    $current_path = $_SERVER['REQUEST_URI'];
    return strpos($current_path, $path) !== false;
}

/**
 * إنشاء رابط نشط للتنقل
 * @param string $path المسار
 * @param string $text النص
 * @param string $class الكلاس الإضافي
 * @param bool $is_admin هل هو رابط admin
 * @return string HTML للرابط
 */
function nav_link($path, $text, $class = '', $is_admin = true) {
    $url = $is_admin ? admin_url($path) : site_url($path);
    $active_class = is_current_page($path) ? ' active' : '';
    $full_class = trim($class . $active_class);
    
    return sprintf(
        '<a href="%s" class="%s">%s</a>',
        htmlspecialchars($url),
        htmlspecialchars($full_class),
        $text
    );
}
?>
