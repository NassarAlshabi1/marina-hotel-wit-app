<?php
/**
 * ملف المزامنة التلقائية - يعمل كل دقيقتين
 * Auto Sync Cron Job - Runs every 2 minutes
 */

// منع الوصول المباشر من المتصفح
if (php_sapi_name() !== 'cli' && !isset($_GET['manual_run'])) {
    // السماح بالتشغيل اليدوي للاختبار فقط
    if (!isset($_GET['test'])) {
        die('هذا الملف مخصص للتشغيل التلقائي فقط');
    }
}

require_once 'includes/db.php';
require_once 'includes/email_sync.php';

// تسجيل بداية تشغيل المزامنة
$log_message = "[" . date('Y-m-d H:i:s') . "] بدء تشغيل المزامنة التلقائية\n";
file_put_contents('logs/sync.log', $log_message, FILE_APPEND | LOCK_EX);

try {
    // تشغيل المزامنة
    $result = runSync();
    
    if ($result) {
        $log_message = "[" . date('Y-m-d H:i:s') . "] تمت المزامنة بنجاح\n";
        echo "تمت المزامنة بنجاح\n";
    } else {
        $log_message = "[" . date('Y-m-d H:i:s') . "] فشل في المزامنة\n";
        echo "فشل في المزامنة\n";
    }
    
    file_put_contents('logs/sync.log', $log_message, FILE_APPEND | LOCK_EX);
    
} catch (Exception $e) {
    $error_message = "[" . date('Y-m-d H:i:s') . "] خطأ في المزامنة: " . $e->getMessage() . "\n";
    file_put_contents('logs/sync.log', $error_message, FILE_APPEND | LOCK_EX);
    echo "خطأ في المزامنة: " . $e->getMessage() . "\n";
}

// إنشاء ملف آخر تشغيل
file_put_contents('logs/last_sync.txt', date('Y-m-d H:i:s'));

/**
 * دالة لإنشاء مهمة مجدولة في Windows
 */
function createWindowsTask() {
    $script_path = __DIR__ . '/sync_cron.php';
    $task_name = 'HotelSyncTask';
    
    // إنشاء ملف batch للتشغيل
    $batch_content = "@echo off\nphp \"$script_path\"\n";
    file_put_contents('sync_task.bat', $batch_content);
    
    // أمر إنشاء المهمة المجدولة (يحتاج صلاحيات مدير)
    $command = "schtasks /create /tn \"$task_name\" /tr \"" . __DIR__ . "/sync_task.bat\" /sc minute /mo 2 /f";
    
    echo "لإنشاء مهمة مجدولة، قم بتشغيل الأمر التالي كمدير:\n";
    echo $command . "\n\n";
    
    echo "أو يمكنك إضافة المهمة يدوياً في Task Scheduler:\n";
    echo "1. افتح Task Scheduler\n";
    echo "2. اختر Create Basic Task\n";
    echo "3. اسم المهمة: Hotel Sync Task\n";
    echo "4. التكرار: Daily\n";
    echo "5. الوقت: كل دقيقتين\n";
    echo "6. Action: Start a program\n";
    echo "7. Program: php\n";
    echo "8. Arguments: \"$script_path\"\n";
}

/**
 * دالة لإنشاء cron job في Linux
 */
function createLinuxCron() {
    $script_path = __DIR__ . '/sync_cron.php';
    
    echo "لإنشاء cron job في Linux، أضف السطر التالي إلى crontab:\n";
    echo "*/2 * * * * /usr/bin/php $script_path\n\n";
    echo "لتحرير crontab، استخدم الأمر: crontab -e\n";
}

// إذا تم تشغيل الملف مع معامل setup
if (isset($_GET['setup']) || (isset($argv[1]) && $argv[1] === 'setup')) {
    echo "=== إعداد المزامنة التلقائية ===\n\n";
    
    if (PHP_OS_FAMILY === 'Windows') {
        createWindowsTask();
    } else {
        createLinuxCron();
    }
    
    echo "\nملاحظات مهمة:\n";
    echo "1. تأكد من أن PHP مثبت ومتاح في PATH\n";
    echo "2. تأكد من صحة إعدادات البريد الإلكتروني\n";
    echo "3. تأكد من وجود مجلد logs وأنه قابل للكتابة\n";
    echo "4. اختبر المزامنة يدوياً أولاً باستخدام: php sync_cron.php\n";
}

// إذا تم تشغيل الملف مع معامل test
if (isset($_GET['test']) || (isset($argv[1]) && $argv[1] === 'test')) {
    echo "=== اختبار المزامنة ===\n\n";
    
    // اختبار الاتصال بقاعدة البيانات
    if ($conn) {
        echo "✅ الاتصال بقاعدة البيانات: نجح\n";
    } else {
        echo "❌ الاتصال بقاعدة البيانات: فشل\n";
        exit(1);
    }
    
    // اختبار جمع البيانات
    $data = collectSyncData();
    echo "✅ جمع البيانات: " . (empty($data) ? "لا توجد بيانات جديدة" : "تم العثور على بيانات") . "\n";
    
    // اختبار إرسال البريد الإلكتروني
    $test_subject = "🧪 اختبار نظام المزامنة - " . date('H:i:s');
    $test_data = "<p>هذا اختبار لنظام المزامنة التلقائية</p>";
    
    if (sendSyncUpdate($test_subject, $test_data)) {
        echo "✅ إرسال البريد الإلكتروني: نجح\n";
    } else {
        echo "❌ إرسال البريد الإلكتروني: فشل\n";
    }
    
    echo "\nانتهى الاختبار\n";
}
?>
