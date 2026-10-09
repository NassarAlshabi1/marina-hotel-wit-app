<?php
/**
 * دوال مساعدة لنظام التقارير - فندق مارينا
 * Helper functions for reports system
 */

// منع الوصول المباشر
if (!defined('BASE_PATH')) {
    define('BASE_PATH', dirname(__DIR__));
}

/**
 * تنسيق التاريخ بالعربية
 * Format date in Arabic
 */
if (!function_exists('format_arabic_date')) {
    function format_arabic_date($date, $format = 'dd/mm/yyyy') {
        $months_arabic = [
            '01' => 'يناير', '02' => 'فبراير', '03' => 'مارس', '04' => 'أبريل',
            '05' => 'مايو', '06' => 'يونيو', '07' => 'يوليو', '08' => 'أغسطس',
            '09' => 'سبتمبر', '10' => 'أكتوبر', '11' => 'نوفمبر', '12' => 'ديسمبر'
        ];
        
        if (strpos($date, '-') !== false) {
            $date_parts = explode('-', $date);
            if (count($date_parts) == 3) {
                $year = $date_parts[0];
                $month = $date_parts[1];
                $day = $date_parts[2];
                
                // إزالة الأصفار البادئة
                $day = ltrim($day, '0');
                $month_num = ltrim($month, '0');
                
                // تنسيقات مختلفة
                switch ($format) {
                    case 'dd/mm/yyyy':
                        return sprintf('<span class="date-display date-medium">%02d/%02d/%s</span>', $day, $month_num, $year);
                    
                    case 'short':
                        return sprintf('<span class="date-display date-small">%d/%d/%s</span>', $day, $month_num, $year);
                    
                    case 'arabic':
                        return sprintf('<span class="date-display date-medium">%d %s %s</span>', $day, $months_arabic[$month], $year);
                    
                    case 'plain':
                        return sprintf('%02d/%02d/%s', $day, $month_num, $year);
                    
                    case 'filter':
                        return sprintf('<span class="date-filter">%02d/%02d/%s</span>', $day, $month_num, $year);
                    
                    case 'title':
                        return sprintf('<span class="report-title-date">%02d/%02d/%s</span>', $day, $month_num, $year);
                    
                    default:
                        return sprintf('<span class="date-display date-medium">%02d/%02d/%s</span>', $day, $month_num, $year);
                }
            }
        }
        
        // في حالة عدم وجود تنسيق صحيح، إرجاع التاريخ مع تكبير البنط
        return '<span style="font-size: 16px; font-weight: bold;">' . $date . '</span>';
    }
}

/**
 * تنسيق الأرقام
 * Format numbers
 */
if (!function_exists('format_number')) {
    function format_number($number, $decimals = 2) {
        return number_format($number, $decimals, '.', ',');
    }
}

/**
 * تنسيق العملة
 * Format currency
 */
if (!function_exists('format_currency')) {
    function format_currency($amount, $currency = 'ريال') {
        return format_number($amount) . ' ' . $currency;
    }
}

/**
 * التحقق من صحة التاريخ
 * Validate date
 */
if (!function_exists('validate_date')) {
    function validate_date($date, $format = 'Y-m-d') {
        $d = DateTime::createFromFormat($format, $date);
        return $d && $d->format($format) === $date;
    }
}

/**
 * تنظيف النص للأمان
 * Clean text for security
 */
if (!function_exists('clean_text')) {
    function clean_text($text) {
        return htmlspecialchars(strip_tags(trim($text)), ENT_QUOTES, 'UTF-8');
    }
}

/**
 * التحقق من صلاحيات المستخدم للتقارير
 * Check user permissions for reports
 */
if (!function_exists('check_report_permission')) {
    function check_report_permission($report_type = 'view_reports') {
        if (!isset($_SESSION['user_id'])) {
            return false;
        }
        
        $user_permissions = $_SESSION['permissions'] ?? [];
        
        return in_array($report_type, $user_permissions) || 
               in_array('admin', $user_permissions) || 
               $_SESSION['user_type'] === 'admin';
    }
}

/**
 * كتابة رسالة خطأ مُنسقة
 * Write formatted error message
 */
if (!function_exists('write_error')) {
    function write_error($message, $details = '') {
        echo '<div class="alert alert-danger" role="alert">';
        echo '<i class="fas fa-exclamation-triangle"></i> ';
        echo '<strong>خطأ:</strong> ' . clean_text($message);
        if ($details) {
            echo '<br><small>' . clean_text($details) . '</small>';
        }
        echo '</div>';
    }
}

/**
 * كتابة رسالة نجاح مُنسقة
 * Write formatted success message
 */
if (!function_exists('write_success')) {
    function write_success($message) {
        echo '<div class="alert alert-success" role="alert">';
        echo '<i class="fas fa-check-circle"></i> ';
        echo '<strong>نجح:</strong> ' . clean_text($message);
        echo '</div>';
    }
}

/**
 * إضافة CSS لتنسيق التواريخ في التقارير
 * Add CSS for date formatting in reports
 */
if (!function_exists('add_date_styles')) {
    function add_date_styles() {
        echo '<style>
            .date-display {
                font-size: 16px !important;
                font-weight: bold !important;
                color: #2c3e50;
                font-family: "Segoe UI", Arial, sans-serif;
                direction: ltr;
                display: inline-block;
            }
            .date-large {
                font-size: 18px !important;
                font-weight: 700 !important;
            }
            .date-medium {
                font-size: 16px !important;
                font-weight: 600 !important;
            }
            .date-small {
                font-size: 14px !important;
                font-weight: 600 !important;
            }
            .date-filter {
                font-size: 15px !important;
                font-weight: 600 !important;
                color: #495057;
            }
            .report-title-date {
                font-size: 20px !important;
                font-weight: bold !important;
                color: #1a472a;
            }
            /* تنسيق الجداول */
            table td .date-display,
            table th .date-display {
                font-size: 15px !important;
                font-weight: 600 !important;
            }
            /* تنسيق العناوين */
            h1 .date-display,
            h2 .date-display,
            h3 .date-display {
                font-size: 18px !important;
                font-weight: 700 !important;
            }
        </style>';
    }
}

/**
 * دالة محسنة لتنسيق التاريخ مع فئات CSS
 * Enhanced date formatting with CSS classes
 */
if (!function_exists('format_date_styled')) {
    function format_date_styled($date, $size = 'medium', $format = 'dd/mm/yyyy') {
        $formatted_date = format_arabic_date($date, 'plain');
        $css_class = 'date-display date-' . $size;
        
        return '<span class="' . $css_class . '">' . $formatted_date . '</span>';
    }
}

?>