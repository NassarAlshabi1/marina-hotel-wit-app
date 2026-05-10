@echo off
chcp 65001
echo ========================================
echo     🚀 Marina Hotel - تحويل سريع لـ EXE
echo ========================================

:: إنشاء مجلد البناء
if not exist "MARINA_HOTEL_EXE" (
    mkdir "MARINA_HOTEL_EXE"
    echo ✅ تم إنشاء مجلد البناء
)

cd "MARINA_HOTEL_EXE"

:: تحميل PHP Desktop (نسخة محمولة)
echo 📥 تحميل PHP Desktop...
if not exist "php-desktop.zip" (
    echo تحميل الملفات...
    powershell -Command "& {[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/cztomczak/phpdesktop/releases/download/chrome-v57.0-rc/phpdesktop-chrome-57.0-rc-msvc2015.zip' -OutFile 'php-desktop.zip'}"
    echo ✅ تم تحميل PHP Desktop
)

:: استخراج الملفات
echo 📂 استخراج الملفات...
if not exist "phpdesktop-chrome" (
    powershell -Command "Expand-Archive -Path 'php-desktop.zip' -DestinationPath '.'"
    echo ✅ تم استخراج الملفات
)

:: نسخ ملفات التطبيق (باستثناء الملفات غير المطلوبة)
echo 📋 نسخ ملفات التطبيق...
if not exist "phpdesktop-chrome\www" mkdir "phpdesktop-chrome\www"

:: نسخ الملفات الأساسية
robocopy ".." "phpdesktop-chrome\www" *.php /S /XD "exe_build" "MARINA_HOTEL_EXE" "tests" ".git" ".vscode" ".zencoder" "backups" "android_app" "quick_apk" "simple_apk_project" "simple_webview_apk" /XF "*.bat" "*.md" "*.json" "*.ts" "*.config*" /NFL /NDL /NJH /NJS

:: نسخ المجلدات المطلوبة
robocopy "..\admin" "phpdesktop-chrome\www\admin" /S /NFL /NDL /NJH /NJS
robocopy "..\assets" "phpdesktop-chrome\www\assets" /S /NFL /NDL /NJH /NJS
robocopy "..\includes" "phpdesktop-chrome\www\includes" /S /NFL /NDL /NJH /NJS
robocopy "..\api" "phpdesktop-chrome\www\api" /S /NFL /NDL /NJH /NJS
robocopy "..\uploads" "phpdesktop-chrome\www\uploads" /S /NFL /NDL /NJH /NJS

:: نسخ قاعدة البيانات
if exist "..\hotel_db.sql" copy "..\hotel_db.sql" "phpdesktop-chrome\www\"

echo ✅ تم نسخ ملفات التطبيق

:: إنشاء إعدادات PHP Desktop
echo ⚙️ إعداد التطبيق...
(
echo {
echo     "application": {
echo         "title": "Marina Hotel Management System",
echo         "width": 1400,
echo         "height": 900,
echo         "min_width": 1000,
echo         "min_height": 700,
echo         "start_url": "login.php",
echo         "chrome_command_line_switches": {
echo             "disable-web-security": true,
echo             "allow-running-insecure-content": true,
echo             "disable-features": "VizDisplayCompositor"
echo         }
echo     },
echo     "debugging": {
echo         "show_console": false,
echo         "subprocess_show_console": false
echo     },
echo     "web_server": {
echo         "listen_on": ["127.0.0.1", 8080],
echo         "directory_index": ["login.php", "index.php"],
echo         "hidden_files": [".htaccess", "*.bat", "*.md"]
echo     }
echo }
) > "phpdesktop-chrome\settings.json"

:: إنشاء ملف بداية سريع
(
echo ^<?php
echo // إعداد سريع لقاعدة البيانات
echo require_once 'includes/config.php';
echo require_once 'includes/db.php';
echo 
echo // إعداد قاعدة البيانات إذا لم تكن موجودة
echo if ^(!file_exists^('data/marina_hotel.db'^)^) {
echo     if ^(!is_dir^('data'^)^) mkdir^('data', 0755, true^);
echo     
echo     // إنشاء قاعدة البيانات من SQL
echo     if ^(file_exists^('hotel_db.sql'^)^) {
echo         $sql = file_get_contents^('hotel_db.sql'^);
echo         // تحويل إلى SQLite إذا لزم الأمر
echo     }
echo }
echo 
echo // إعادة توجيه إلى صفحة تسجيل الدخول
echo header^('Location: login.php'^);
echo exit;
echo ?^>
) > "phpdesktop-chrome\www\index.php"

:: إنشاء ملف تشغيل سريع
(
echo @echo off
echo chcp 65001
echo cls
echo ========================================
echo     🏨 Marina Hotel Management System
echo ========================================
echo.
echo 🚀 بدء تشغيل النظام...
echo.
echo النظام يعمل على: http://localhost:8080
echo.
echo 💡 لإغلاق النظام: أغلق هذه النافذة
echo ========================================
echo.
echo start phpdesktop-chrome.exe
echo exit
) > "Marina_Hotel_System.bat"

:: تخصيص الأيقونة إذا توفرت
if exist "..\assets\icons\icon.ico" (
    copy "..\assets\icons\icon.ico" "phpdesktop-chrome\phpdesktop-chrome.exe.ico"
    echo ✅ تم تخصيص الأيقونة
)

:: إنشاء ملف README
(
echo ========================================
echo     Marina Hotel Management System
echo     دليل التشغيل السريع
echo ========================================
echo.
echo 📋 متطلبات التشغيل:
echo    - Windows 7 أو أحدث
echo    - لا يتطلب تثبيت برامج إضافية
echo.
echo 🚀 طريقة التشغيل:
echo    1. شغل ملف: phpdesktop-chrome.exe
echo    2. أو شغل: Marina_Hotel_System.bat
echo.
echo 🌐 النظام يعمل على:
echo    http://localhost:8080
echo.
echo 🔧 في حالة المشاكل:
echo    - تأكد من عدم استخدام المنفذ 8080
echo    - شغل كمسؤول إذا لزم الأمر
echo.
echo 📁 ملفات النظام:
echo    - البيانات: data/marina_hotel.db
echo    - الملفات المرفوعة: uploads/
echo    - التقارير: uploads/reports/
echo.
echo ========================================
) > "README.txt"

echo.
echo ========================================
echo ✅ تم إنشاء النظام بنجاح!
echo ========================================
echo.
echo 📁 مجلد النظام: MARINA_HOTEL_EXE
echo 🚀 ملف التشغيل: Marina_Hotel_System.bat
echo 💻 أو شغل مباشرة: phpdesktop-chrome.exe
echo.
echo 🌟 النظام جاهز للاستخدام!
echo ========================================
echo.
pause