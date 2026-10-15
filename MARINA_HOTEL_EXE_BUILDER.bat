@echo off
chcp 65001
title Marina Hotel - EXE Builder
color 0A

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🏨 Marina Hotel Management System             ║
echo ║                        منشئ النظام التنفيذي                      ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo ⚡ هذا الإعداد سيقوم بإنشاء نظام تنفيذي سريع (EXE) للفندق
echo.
echo 📋 ما سيتم إنشاؤه:
echo    • نظام تنفيذي مستقل (لا يحتاج XAMPP)
echo    • قاعدة بيانات محلية سريعة
echo    • واجهة مستخدم محسنة
echo    • نظام إدارة كامل
echo.
echo 🚀 هل تريد المتابعة؟
pause

cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                        🔧 بدء الإعداد                          ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

:: إنشاء مجلد البناء
echo 📁 إنشاء مجلد البناء...
if not exist "MARINA_HOTEL_EXE" mkdir "MARINA_HOTEL_EXE"
cd "MARINA_HOTEL_EXE"

:: تحميل PHP Desktop
echo.
echo 📥 تحميل PHP Desktop... (قد يستغرق دقائق)
if not exist "php-desktop.zip" (
    echo    جاري التحميل...
    powershell -Command "& {$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri 'https://github.com/cztomczak/phpdesktop/releases/download/chrome-v57.0-rc/phpdesktop-chrome-57.0-rc-msvc2015.zip' -OutFile 'php-desktop.zip'}"
    if exist "php-desktop.zip" (
        echo    ✅ تم تحميل PHP Desktop بنجاح
    ) else (
        echo    ❌ فشل في التحميل، يرجى التحقق من الاتصال بالإنترنت
        pause
        exit /b 1
    )
)

:: استخراج الملفات
echo.
echo 📂 استخراج الملفات...
if not exist "phpdesktop-chrome" (
    powershell -Command "Expand-Archive -Path 'php-desktop.zip' -DestinationPath '.' -Force"
    echo    ✅ تم استخراج الملفات
)

:: تحضير مجلد التطبيق
echo.
echo 📋 تحضير ملفات التطبيق...
if not exist "phpdesktop-chrome\www" mkdir "phpdesktop-chrome\www"

:: نسخ الملفات الأساسية
echo    • نسخ الملفات الأساسية...
for %%f in (*.php) do (
    if exist "..\%%f" copy "..\%%f" "phpdesktop-chrome\www\" >nul 2>&1
)

:: نسخ المجلدات المطلوبة
echo    • نسخ مجلد الإدارة...
if exist "..\admin" xcopy "..\admin" "phpdesktop-chrome\www\admin\" /S /E /I /Y /Q >nul 2>&1

echo    • نسخ مجلد الأصول...
if exist "..\assets" xcopy "..\assets" "phpdesktop-chrome\www\assets\" /S /E /I /Y /Q >nul 2>&1

echo    • نسخ مجلد التضمينات...
if exist "..\includes" xcopy "..\includes" "phpdesktop-chrome\www\includes\" /S /E /I /Y /Q >nul 2>&1

echo    • نسخ مجلد API...
if exist "..\api" xcopy "..\api" "phpdesktop-chrome\www\api\" /S /E /I /Y /Q >nul 2>&1

echo    • إنشاء مجلد الرفع...
if not exist "phpdesktop-chrome\www\uploads" mkdir "phpdesktop-chrome\www\uploads"
if not exist "phpdesktop-chrome\www\uploads\reports" mkdir "phpdesktop-chrome\www\uploads\reports"

:: نسخ قاعدة البيانات
if exist "..\hotel_db.sql" (
    copy "..\hotel_db.sql" "phpdesktop-chrome\www\" >nul 2>&1
    echo    • تم نسخ قاعدة البيانات
)

:: نسخ ملف الإعداد
if exist "..\scripts\php\maintenance\setup_exe_database.php" (
    copy "..\scripts\php\maintenance\setup_exe_database.php" "phpdesktop-chrome\www\" >nul 2>&1
    echo    • تم نسخ ملف الإعداد
)

echo    ✅ تم نسخ جميع الملفات

:: إنشاء إعدادات التطبيق
echo.
echo ⚙️ إعداد التطبيق...
(
echo {
echo     "application": {
echo         "title": "Marina Hotel Management System",
echo         "width": 1400,
echo         "height": 900,
echo         "min_width": 1000,
echo         "min_height": 700,
echo         "start_url": "setup_exe_database.php",
echo         "chrome_command_line_switches": {
echo             "disable-web-security": true,
echo             "allow-running-insecure-content": true,
echo             "disable-features": "VizDisplayCompositor",
echo             "disable-extensions": true
echo         }
echo     },
echo     "debugging": {
echo         "show_console": false,
echo         "subprocess_show_console": false
echo     },
echo     "web_server": {
echo         "listen_on": ["127.0.0.1", 8080],
echo         "directory_index": ["setup_exe_database.php", "login.php"],
echo         "hidden_files": [".htaccess", "*.bat", "*.md"]
echo     }
echo }
) > "phpdesktop-chrome\settings.json"

:: إنشاء ملف تشغيل سريع
echo.
echo 🚀 إنشاء ملف التشغيل...
(
echo @echo off
echo chcp 65001
echo title Marina Hotel Management System
echo color 0B
echo cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🏨 Marina Hotel Management System             ║
echo ║                        نظام إدارة الفندق                        ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🌐 النظام يعمل على: http://localhost:8080
echo 💻 تأكد من عدم استخدام منفذ 8080 من برنامج آخر
echo.
echo 🚀 بدء تشغيل النظام...
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║  لإغلاق النظام: أغلق هذه النافذة أو اضغط Ctrl+C                ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo start phpdesktop-chrome.exe
echo pause
) > "Marina_Hotel_System.bat"

:: إنشاء ملف README
echo.
echo 📖 إنشاء دليل الاستخدام...
(
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                Marina Hotel Management System                  ║
echo ║                      دليل الاستخدام السريع                      ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🎯 نظام إدارة فندق متكامل وسريع
echo.
echo 📋 متطلبات التشغيل:
echo    • Windows 7 أو أحدث
echo    • لا يتطلب تثبيت برامج إضافية
echo    • لا يحتاج اتصال إنترنت للعمل
echo.
echo 🚀 طريقة التشغيل:
echo    1. شغل ملف: Marina_Hotel_System.bat
echo    2. أو شغل مباشرة: phpdesktop-chrome.exe
echo    3. النظام سيفتح تلقائياً
echo.
echo 🔧 الإعداد الأول:
echo    • سيتم إعداد قاعدة البيانات تلقائياً
echo    • اسم المستخدم: admin
echo    • كلمة المرور: admin123
echo    • غير كلمة المرور فوراً بعد تسجيل الدخول
echo.
echo 🌐 روابط مهمة:
echo    • النظام: http://localhost:8080
echo    • تسجيل الدخول: http://localhost:8080/login.php
echo    • لوحة التحكم: http://localhost:8080/admin/dash.php
echo.
echo 📁 ملفات النظام:
echo    • قاعدة البيانات: data/marina_hotel.db
echo    • الملفات المرفوعة: uploads/
echo    • التقارير: uploads/reports/
echo.
echo 🆘 في حالة المشاكل:
echo    • تأكد من عدم استخدام المنفذ 8080
echo    • شغل كمسؤول إذا لزم الأمر
echo    • تأكد من عدم وجود برامج حماية تحجب النظام
echo.
echo 📞 المميزات:
echo    ✅ إدارة الحجوزات
echo    ✅ إدارة الغرف
echo    ✅ إدارة الموظفين
echo    ✅ التقارير المالية
echo    ✅ إدارة المصروفات
echo    ✅ نظام المدفوعات
echo    ✅ التقارير الشاملة
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                   🎉 مبروك! النظام جاهز                       ║
echo ╚════════════════════════════════════════════════════════════════╝
) > "README.txt"

:: إنشاء ملف إعداد سريع
echo.
echo 🛠️ إنشاء ملف الإعداد السريع...
(
echo @echo off
echo chcp 65001
echo title Marina Hotel - إعداد سريع
echo color 0E
echo cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                     🔧 إعداد سريع للنظام                       ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 📋 سيتم إعداد النظام تلقائياً...
echo.
echo 🚀 بدء التشغيل...
echo start phpdesktop-chrome.exe
echo.
echo ⏳ انتظار تشغيل النظام...
echo timeout /t 5 /nobreak ^>nul
echo.
echo 🌐 فتح النظام في المتصفح...
echo start http://localhost:8080/setup_exe_database.php
echo.
echo ✅ تم! النظام جاهز للاستخدام
echo.
echo pause
) > "إعداد_سريع.bat"

:: تخصيص الأيقونة
if exist "..\assets\icons\icon.ico" (
    copy "..\assets\icons\icon.ico" "phpdesktop-chrome\phpdesktop-chrome.exe.ico" >nul 2>&1
    echo    ✅ تم تخصيص الأيقونة
)

:: النتيجة النهائية
cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                    🎉 تم إنشاء النظام بنجاح!                  ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 📁 مجلد النظام: MARINA_HOTEL_EXE
echo.
echo 🚀 ملفات التشغيل:
echo    • Marina_Hotel_System.bat      (الملف الرئيسي)
echo    • إعداد_سريع.bat              (للإعداد السريع)
echo    • phpdesktop-chrome.exe        (التشغيل المباشر)
echo.
echo 📖 ملفات إضافية:
echo    • README.txt                   (دليل الاستخدام)
echo.
echo 🔐 معلومات الدخول:
echo    • اسم المستخدم: admin
echo    • كلمة المرور: admin123
echo.
echo 🌐 الرابط: http://localhost:8080
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║              🎯 النظام جاهز للاستخدام فوراً!                  ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🚀 هل تريد تشغيل النظام الآن؟
echo.
set /p choice="اكتب Y للتشغيل أو N للخروج: "
if /i "%choice%"=="Y" (
    echo.
    echo 🚀 بدء التشغيل...
    cd "phpdesktop-chrome"
    start phpdesktop-chrome.exe
    echo.
    echo ✅ تم تشغيل النظام!
    echo 🌐 سيفتح تلقائياً على: http://localhost:8080
    echo.
    pause
) else (
    echo.
    echo 💡 يمكنك تشغيل النظام لاحقاً من مجلد: MARINA_HOTEL_EXE
    echo.
    pause
)

cd ..
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                        🏆 تم بنجاح!                          ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.