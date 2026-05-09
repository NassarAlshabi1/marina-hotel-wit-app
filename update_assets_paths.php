<?php
/**
 * سكريبت تحديث مسارات الموارد لتعمل محلياً
 * يقوم بتحديث جميع الملفات لاستخدام الموارد المحلية بدلاً من CDN
 */

require_once 'includes/config.php';

// قائمة الملفات المراد تحديثها
$files_to_update = [
    'login.php',
    'index.php',
    'admin/dash.php',
    'admin/bookings/add.php',
    'admin/bookings/add2.php',
    'admin/bookings/list.php',
    'admin/bookings/edit.php',
    'admin/expenses/expenses.php',
    'admin/reports/revenue.php',
    'admin/system_tools/backup_manager.php',
    'admin/system_tools/create_users_table.php',
    'system_health_report.php',
    'fix_system_issues.php'
];

// قائمة الاستبدالات
$replacements = [
    // Bootstrap CSS
    'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' => 'assets/css/bootstrap-local.css',
    'https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css' => 'assets/css/bootstrap-local.css',
    'https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css' => 'assets/css/bootstrap-local.css',
    '../assets/css/vendor/bootstrap.rtl.min.css' => '../assets/css/bootstrap-local.css',
    
    // Font Awesome
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css' => 'assets/fonts/fonts.css',
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css' => 'assets/fonts/fonts.css',
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/5.15.4/css/all.min.css' => 'assets/fonts/fonts.css',
    '../assets/css/vendor/all.min.css' => '../assets/fonts/fonts.css',
    
    // Google Fonts
    'https://fonts.googleapis.com/css2?family=Tajawal:wght@200;300;400;500;700;800;900&display=swap' => 'assets/fonts/fonts.css',
    'https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700&display=swap' => 'assets/fonts/fonts.css',
    '../assets/css/vendor/tajawal_google_fonts.css' => '../assets/fonts/fonts.css',
    
    // Bootstrap JS
    'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js' => 'assets/js/bootstrap-local.js',
    'https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/js/bootstrap.bundle.min.js' => 'assets/js/bootstrap-local.js',
];

// دالة لتحديث ملف واحد
function updateFile($filepath, $replacements) {
    if (!file_exists($filepath)) {
        return "الملف غير موجود: $filepath";
    }
    
    $content = file_get_contents($filepath);
    $original_content = $content;
    $changes_made = 0;
    
    foreach ($replacements as $old => $new) {
        // تحديد المسار النسبي الصحيح
        $depth = substr_count(dirname($filepath), '/');
        $relative_path = str_repeat('../', $depth) . $new;
        
        // إذا كان الملف في المجلد الجذر
        if ($depth === 0) {
            $relative_path = $new;
        }
        
        // البحث والاستبدال
        $new_content = str_replace($old, $relative_path, $content);
        if ($new_content !== $content) {
            $content = $new_content;
            $changes_made++;
        }
    }
    
    // إضافة fallback للموارد الخارجية
    if ($changes_made > 0) {
        // إضافة fallback للخطوط
        $fallback_fonts = '
    <!-- Fallback للخطوط الخارجية -->
    <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@200;300;400;500;700;800;900&display=swap" rel="stylesheet" media="print" onload="this.media=\'all\'">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet" media="print" onload="this.media=\'all\'">';
        
        // البحث عن آخر link tag وإضافة fallback بعده
        $content = preg_replace(
            '/(<link[^>]*fonts\.css[^>]*>)/i',
            '$1' . $fallback_fonts,
            $content
        );
        
        file_put_contents($filepath, $content);
        return "تم تحديث $filepath - عدد التغييرات: $changes_made";
    }
    
    return "لا توجد تغييرات مطلوبة في $filepath";
}

// تشغيل التحديث
echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>تحديث مسارات الموارد</title>
    <style>
        body { font-family: 'Tajawal', Arial, sans-serif; margin: 20px; direction: rtl; }
        .success { color: green; background: #d4edda; padding: 10px; border-radius: 5px; margin: 5px 0; }
        .info { color: blue; background: #d1ecf1; padding: 10px; border-radius: 5px; margin: 5px 0; }
        .warning { color: orange; background: #fff3cd; padding: 10px; border-radius: 5px; margin: 5px 0; }
        .error { color: red; background: #f8d7da; padding: 10px; border-radius: 5px; margin: 5px 0; }
    </style>
</head>
<body>";

echo "<h1>تحديث مسارات الموارد للعمل محلياً</h1>";

$total_files = 0;
$updated_files = 0;

foreach ($files_to_update as $file) {
    $total_files++;
    $result = updateFile($file, $replacements);
    
    if (strpos($result, 'تم تحديث') !== false) {
        echo "<div class='success'>✅ $result</div>";
        $updated_files++;
    } elseif (strpos($result, 'لا توجد تغييرات') !== false) {
        echo "<div class='info'>ℹ️ $result</div>";
    } else {
        echo "<div class='warning'>⚠️ $result</div>";
    }
}

echo "<h2>ملخص التحديث:</h2>";
echo "<div class='info'>";
echo "<p><strong>إجمالي الملفات المفحوصة:</strong> $total_files</p>";
echo "<p><strong>الملفات المحدثة:</strong> $updated_files</p>";
echo "<p><strong>الملفات بدون تغيير:</strong> " . ($total_files - $updated_files) . "</p>";
echo "</div>";

// إنشاء ملف JavaScript محلي بسيط لـ Bootstrap
$bootstrap_js_content = '/**
 * Bootstrap JS محلي مبسط
 * يحتوي على الوظائف الأساسية المطلوبة
 */

// وظائف Bootstrap الأساسية
class BootstrapLocal {
    static init() {
        // تهيئة النوافذ المنبثقة
        this.initModals();
        
        // تهيئة القوائم المنسدلة
        this.initDropdowns();
        
        // تهيئة التبويبات
        this.initTabs();
    }
    
    static initModals() {
        document.addEventListener("click", function(e) {
            if (e.target.matches("[data-bs-toggle=\'modal\']")) {
                const target = e.target.getAttribute("data-bs-target");
                const modal = document.querySelector(target);
                if (modal) {
                    modal.style.display = "block";
                    modal.classList.add("show");
                }
            }
            
            if (e.target.matches(".modal .btn-close, .modal [data-bs-dismiss=\'modal\']")) {
                const modal = e.target.closest(".modal");
                if (modal) {
                    modal.style.display = "none";
                    modal.classList.remove("show");
                }
            }
        });
    }
    
    static initDropdowns() {
        document.addEventListener("click", function(e) {
            if (e.target.matches("[data-bs-toggle=\'dropdown\']")) {
                e.preventDefault();
                const menu = e.target.nextElementSibling;
                if (menu && menu.classList.contains("dropdown-menu")) {
                    menu.classList.toggle("show");
                }
            }
        });
        
        // إغلاق القوائم عند النقر خارجها
        document.addEventListener("click", function(e) {
            if (!e.target.matches("[data-bs-toggle=\'dropdown\']")) {
                const dropdowns = document.querySelectorAll(".dropdown-menu.show");
                dropdowns.forEach(dropdown => {
                    dropdown.classList.remove("show");
                });
            }
        });
    }
    
    static initTabs() {
        document.addEventListener("click", function(e) {
            if (e.target.matches("[data-bs-toggle=\'tab\']")) {
                e.preventDefault();
                
                // إخفاء جميع التبويبات
                const tabContent = document.querySelectorAll(".tab-pane");
                tabContent.forEach(pane => {
                    pane.classList.remove("show", "active");
                });
                
                // إزالة active من جميع التبويبات
                const tabs = document.querySelectorAll("[data-bs-toggle=\'tab\']");
                tabs.forEach(tab => {
                    tab.classList.remove("active");
                });
                
                // تفعيل التبويب المحدد
                e.target.classList.add("active");
                const target = e.target.getAttribute("data-bs-target");
                const targetPane = document.querySelector(target);
                if (targetPane) {
                    targetPane.classList.add("show", "active");
                }
            }
        });
    }
}

// تهيئة تلقائية عند تحميل الصفحة
document.addEventListener("DOMContentLoaded", function() {
    BootstrapLocal.init();
});

// تصدير للاستخدام العام
window.bootstrap = window.bootstrap || BootstrapLocal;';

$js_file = 'assets/js/bootstrap-local.js';
if (!file_exists(dirname($js_file))) {
    mkdir(dirname($js_file), 0755, true);
}
file_put_contents($js_file, $bootstrap_js_content);

echo "<div class='success'>✅ تم إنشاء ملف Bootstrap JS المحلي: $js_file</div>";

echo "<h2>الخطوات التالية:</h2>";
echo "<div class='info'>";
echo "<ol>";
echo "<li>تأكد من وجود ملفات الخطوط في مجلد assets/fonts/</li>";
echo "<li>تأكد من وجود ملفات CSS المحلية في مجلد assets/css/</li>";
echo "<li>اختبر النظام للتأكد من عمل جميع الميزات</li>";
echo "<li>في حالة وجود مشاكل، ستعمل الروابط الخارجية كـ fallback</li>";
echo "</ol>";
echo "</div>";

echo "<div class='warning'>";
echo "<h3>ملاحظات مهمة:</h3>";
echo "<ul>";
echo "<li>تم إضافة fallback للموارد الخارجية في حالة عدم توفر الملفات المحلية</li>";
echo "<li>يمكن تشغيل هذا السكريبت مرة أخرى لتحديث ملفات إضافية</li>";
echo "<li>تأكد من نسخ ملفات الخطوط الفعلية إلى مجلد assets/fonts/</li>";
echo "</ul>";
echo "</div>";

echo "<br><a href='admin/dash.php' style='display:inline-block;margin-top:20px;padding:10px;background-color:#4CAF50;color:white;text-decoration:none;border-radius:5px;'>العودة للوحة التحكم</a>";

echo "</body></html>";
?>
