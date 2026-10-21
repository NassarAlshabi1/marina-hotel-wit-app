<?php
/**
 * نظام معالجة الأخطاء المحسن
 * يوفر معالجة شاملة للأخطاء وتسجيلها
 */

// تعيين معالج الأخطاء المخصص
set_error_handler('custom_error_handler');
set_exception_handler('custom_exception_handler');
register_shutdown_function('fatal_error_handler');

// إعدادات تسجيل الأخطاء
ini_set('log_errors', 1);
ini_set('error_log', __DIR__ . '/../logs/error.log');

// إنشاء مجلد السجلات إذا لم يكن موجوداً
$log_dir = __DIR__ . '/../logs';
if (!is_dir($log_dir)) {
    mkdir($log_dir, 0755, true);
}

/**
 * معالج الأخطاء المخصص
 */
function custom_error_handler($severity, $message, $file, $line) {
    // تجاهل الأخطاء المكبوتة بـ @
    if (!(error_reporting() & $severity)) {
        return false;
    }
    
    $error_types = [
        E_ERROR => 'خطأ فادح',
        E_WARNING => 'تحذير',
        E_PARSE => 'خطأ في التحليل',
        E_NOTICE => 'ملاحظة',
        E_CORE_ERROR => 'خطأ في النواة',
        E_CORE_WARNING => 'تحذير في النواة',
        E_COMPILE_ERROR => 'خطأ في التجميع',
        E_COMPILE_WARNING => 'تحذير في التجميع',
        E_USER_ERROR => 'خطأ من المستخدم',
        E_USER_WARNING => 'تحذير من المستخدم',
        E_USER_NOTICE => 'ملاحظة من المستخدم',
        E_STRICT => 'تحذير صارم',
        E_RECOVERABLE_ERROR => 'خطأ قابل للاسترداد',
        E_DEPRECATED => 'مهجور',
        E_USER_DEPRECATED => 'مهجور من المستخدم'
    ];
    
    $error_type = $error_types[$severity] ?? 'خطأ غير معروف';
    
    // تسجيل الخطأ
    $log_message = sprintf(
        "[%s] %s: %s في %s على السطر %d",
        date('Y-m-d H:i:s'),
        $error_type,
        $message,
        $file,
        $line
    );
    
    error_log($log_message);
    
    // عرض الخطأ للمطورين فقط
    if (defined('DEBUG_MODE') && DEBUG_MODE) {
        echo "<div style='background:#ffebee;border:1px solid #f44336;padding:10px;margin:10px;border-radius:5px;'>";
        echo "<strong>$error_type:</strong> $message<br>";
        echo "<small>الملف: $file على السطر $line</small>";
        echo "</div>";
    }
    
    // إيقاف التنفيذ للأخطاء الفادحة
    if ($severity == E_ERROR || $severity == E_CORE_ERROR || $severity == E_COMPILE_ERROR) {
        die();
    }
    
    return true;
}

/**
 * معالج الاستثناءات المخصص
 */
function custom_exception_handler($exception) {
    $log_message = sprintf(
        "[%s] استثناء غير معالج: %s في %s على السطر %d\nStack trace:\n%s",
        date('Y-m-d H:i:s'),
        $exception->getMessage(),
        $exception->getFile(),
        $exception->getLine(),
        $exception->getTraceAsString()
    );
    
    error_log($log_message);
    
    // عرض رسالة خطأ مناسبة للمستخدم
    if (defined('DEBUG_MODE') && DEBUG_MODE) {
        echo "<div style='background:#ffebee;border:1px solid #f44336;padding:15px;margin:10px;border-radius:5px;'>";
        echo "<h3>حدث خطأ في النظام</h3>";
        echo "<p><strong>الرسالة:</strong> " . htmlspecialchars($exception->getMessage()) . "</p>";
        echo "<p><strong>الملف:</strong> " . $exception->getFile() . "</p>";
        echo "<p><strong>السطر:</strong> " . $exception->getLine() . "</p>";
        echo "<details><summary>تفاصيل إضافية</summary><pre>" . $exception->getTraceAsString() . "</pre></details>";
        echo "</div>";
    } else {
        show_user_error("حدث خطأ في النظام. يرجى المحاولة مرة أخرى أو الاتصال بالدعم الفني.");
    }
}

/**
 * معالج الأخطاء الفادحة
 */
function fatal_error_handler() {
    $error = error_get_last();
    
    if ($error && in_array($error['type'], [E_ERROR, E_CORE_ERROR, E_COMPILE_ERROR, E_PARSE])) {
        $log_message = sprintf(
            "[%s] خطأ فادح: %s في %s على السطر %d",
            date('Y-m-d H:i:s'),
            $error['message'],
            $error['file'],
            $error['line']
        );
        
        error_log($log_message);
        
        // عرض صفحة خطأ مناسبة
        if (!defined('DEBUG_MODE') || !DEBUG_MODE) {
            show_user_error("حدث خطأ فادح في النظام. يرجى الاتصال بالدعم الفني.");
        }
    }
}

/**
 * عرض رسالة خطأ للمستخدم
 */
function show_user_error($message, $redirect_url = null) {
    // تنظيف أي مخرجات سابقة
    if (ob_get_level()) {
        ob_clean();
    }
    
    http_response_code(500);
    
    echo "<!DOCTYPE html>
    <html lang='ar' dir='rtl'>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>خطأ في النظام</title>
        <style>
            body {
                font-family: 'Tajawal', Arial, sans-serif;
                background-color: #f8f9fa;
                margin: 0;
                padding: 20px;
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
            }
            .error-container {
                background: white;
                padding: 40px;
                border-radius: 10px;
                box-shadow: 0 4px 6px rgba(0,0,0,0.1);
                text-align: center;
                max-width: 500px;
                width: 100%;
            }
            .error-icon {
                font-size: 4rem;
                color: #dc3545;
                margin-bottom: 20px;
            }
            .error-title {
                color: #dc3545;
                font-size: 1.5rem;
                margin-bottom: 15px;
            }
            .error-message {
                color: #666;
                margin-bottom: 30px;
                line-height: 1.6;
            }
            .error-actions {
                display: flex;
                gap: 10px;
                justify-content: center;
                flex-wrap: wrap;
            }
            .btn {
                padding: 10px 20px;
                border: none;
                border-radius: 5px;
                text-decoration: none;
                font-weight: bold;
                cursor: pointer;
                transition: background-color 0.3s;
            }
            .btn-primary {
                background-color: #007bff;
                color: white;
            }
            .btn-primary:hover {
                background-color: #0056b3;
            }
            .btn-secondary {
                background-color: #6c757d;
                color: white;
            }
            .btn-secondary:hover {
                background-color: #545b62;
            }
        </style>
    </head>
    <body>
        <div class='error-container'>
            <div class='error-icon'>⚠️</div>
            <h1 class='error-title'>حدث خطأ في النظام</h1>
            <p class='error-message'>" . htmlspecialchars($message) . "</p>
            <div class='error-actions'>
                <button onclick='history.back()' class='btn btn-secondary'>العودة للخلف</button>";
    
    if ($redirect_url) {
        echo "<a href='" . htmlspecialchars($redirect_url) . "' class='btn btn-primary'>الصفحة الرئيسية</a>";
    } else {
        echo "<a href='/login.php' class='btn btn-primary'>تسجيل الدخول</a>";
    }
    
    echo "      </div>
        </div>
        <script>
            // إعادة تحميل الصفحة بعد 30 ثانية
            setTimeout(function() {
                if (confirm('هل تريد إعادة تحميل الصفحة؟')) {
                    location.reload();
                }
            }, 30000);
        </script>
    </body>
    </html>";
    
    exit;
}

/**
 * تسجيل خطأ مخصص
 */
function log_custom_error($message, $context = []) {
    $log_message = sprintf(
        "[%s] خطأ مخصص: %s",
        date('Y-m-d H:i:s'),
        $message
    );
    
    if (!empty($context)) {
        $log_message .= " | السياق: " . json_encode($context, JSON_UNESCAPED_UNICODE);
    }
    
    error_log($log_message);
}

/**
 * معالجة أخطاء قاعدة البيانات
 */
function handle_db_error($conn, $operation = 'عملية قاعدة البيانات') {
    if ($conn->error) {
        $error_message = "خطأ في $operation: " . $conn->error;
        log_custom_error($error_message, [
            'mysql_error' => $conn->error,
            'mysql_errno' => $conn->errno,
            'operation' => $operation
        ]);
        
        if (defined('DEBUG_MODE') && DEBUG_MODE) {
            throw new Exception($error_message);
        } else {
            show_user_error("حدث خطأ في قاعدة البيانات. يرجى المحاولة مرة أخرى.");
        }
    }
}

/**
 * التحقق من صحة البيانات مع معالجة الأخطاء
 */
function validate_input($data, $rules) {
    $errors = [];
    
    foreach ($rules as $field => $rule_set) {
        $value = $data[$field] ?? null;
        
        foreach ($rule_set as $rule => $params) {
            switch ($rule) {
                case 'required':
                    if (empty($value)) {
                        $errors[$field][] = "حقل $field مطلوب";
                    }
                    break;
                    
                case 'min_length':
                    if (strlen($value) < $params) {
                        $errors[$field][] = "حقل $field يجب أن يكون على الأقل $params أحرف";
                    }
                    break;
                    
                case 'max_length':
                    if (strlen($value) > $params) {
                        $errors[$field][] = "حقل $field يجب أن يكون أقل من $params حرف";
                    }
                    break;
                    
                case 'email':
                    if (!filter_var($value, FILTER_VALIDATE_EMAIL)) {
                        $errors[$field][] = "حقل $field يجب أن يكون بريد إلكتروني صحيح";
                    }
                    break;
                    
                case 'numeric':
                    if (!is_numeric($value)) {
                        $errors[$field][] = "حقل $field يجب أن يكون رقم";
                    }
                    break;
            }
        }
    }
    
    return $errors;
}
?>
