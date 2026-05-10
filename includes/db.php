<?php
/**
 * ملف الاتصال بقاعدة البيانات المحسن
 * يوفر اتصال آمن ومحسن بقاعدة البيانات مع معالجة الأخطاء
 */

require_once 'config.php';

// إعدادات الاتصال بقاعدة البيانات
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

try {
    // الاتصال بقاعدة البيانات مع دعم UTF-8
    $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);

    // تعيين الترميز إلى UTF-8 لدعم العربية
    $conn->set_charset(DB_CHARSET);

    // تعيين وضع SQL الصارم (مع التحقق من الإصدار)
    $version = $conn->server_version;
    if ($version >= 50700) { // MySQL 5.7+
        $conn->query("SET sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'");
    } else {
        $conn->query("SET sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'");
    }

    // تعيين المنطقة الزمنية لقاعدة البيانات
    $conn->query("SET time_zone = '+03:00'"); // توقيت عدن

    // تحسين الأداء (مع التحقق من توفر query cache)
    $cache_result = $conn->query("SHOW VARIABLES LIKE 'query_cache_type'");
    if ($cache_result && $cache_result->num_rows > 0) {
        $cache_row = $cache_result->fetch_assoc();
        if ($cache_row['Value'] !== 'OFF') {
            $conn->query("SET SESSION query_cache_type = ON");
        }
    }

} catch (mysqli_sql_exception $e) {
    // تسجيل خطأ الاتصال
    error_log("فشل الاتصال بقاعدة البيانات: " . $e->getMessage());

    if (DEBUG_MODE) {
        die("فشل الاتصال بقاعدة البيانات: " . $e->getMessage());
    } else {
        // عرض صفحة خطأ مناسبة للمستخدمين
        show_user_error("عذراً، النظام غير متاح حالياً. يرجى المحاولة مرة أخرى لاحقاً.");
    }
}

/**
 * دالة لتنفيذ استعلام آمن مع معالجة الأخطاء
 */
function safe_query($conn, $query, $params = [], $types = '') {
    try {
        if (empty($params)) {
            $result = $conn->query($query);
            handle_db_error($conn, 'تنفيذ الاستعلام');
            return $result;
        } else {
            $stmt = $conn->prepare($query);
            if (!$stmt) {
                handle_db_error($conn, 'تحضير الاستعلام');
                return false;
            }

            if (!empty($types) && !empty($params)) {
                $stmt->bind_param($types, ...$params);
            }

            $stmt->execute();
            handle_db_error($conn, 'تنفيذ الاستعلام المحضر');

            $result = $stmt->get_result();
            $stmt->close();

            return $result;
        }
    } catch (Exception $e) {
        log_custom_error("خطأ في تنفيذ الاستعلام", [
            'query' => $query,
            'error' => $e->getMessage()
        ]);

        if (DEBUG_MODE) {
            throw $e;
        } else {
            return false;
        }
    }
}

/**
 * دالة للحصول على صف واحد من النتائج
 */
function get_single_row($conn, $query, $params = [], $types = '') {
    $result = safe_query($conn, $query, $params, $types);
    if ($result && $result->num_rows > 0) {
        return $result->fetch_assoc();
    }
    return null;
}

/**
 * دالة للحصول على جميع الصفوف
 */
function get_all_rows($conn, $query, $params = [], $types = '') {
    $result = safe_query($conn, $query, $params, $types);
    if ($result) {
        return $result->fetch_all(MYSQLI_ASSOC);
    }
    return [];
}

/**
 * دالة لتنفيذ استعلام INSERT/UPDATE/DELETE
 */
function execute_query($conn, $query, $params = [], $types = '') {
    $result = safe_query($conn, $query, $params, $types);
    return $result !== false;
}
?>

