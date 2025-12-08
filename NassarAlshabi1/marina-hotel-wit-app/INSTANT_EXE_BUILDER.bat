@echo off
chcp 65001
title Marina Hotel - منشئ EXE فوري
color 0A

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🚀 Marina Hotel - منشئ EXE فوري               ║
echo ║                        (بدون تحميل من الإنترنت)                 ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

:: إنشاء مجلد EXE
echo 📁 إنشاء مجلد النظام...
if not exist "MARINA_HOTEL_PORTABLE" mkdir "MARINA_HOTEL_PORTABLE"

echo 📋 نسخ ملفات النظام...
:: نسخ جميع الملفات PHP
xcopy "*.php" "MARINA_HOTEL_PORTABLE\" /Y /Q >nul 2>&1
xcopy "admin" "MARINA_HOTEL_PORTABLE\admin\" /S /E /I /Y /Q >nul 2>&1
xcopy "assets" "MARINA_HOTEL_PORTABLE\assets\" /S /E /I /Y /Q >nul 2>&1
xcopy "includes" "MARINA_HOTEL_PORTABLE\includes\" /S /E /I /Y /Q >nul 2>&1
xcopy "api" "MARINA_HOTEL_PORTABLE\api\" /S /E /I /Y /Q >nul 2>&1

:: إنشاء مجلدات مطلوبة
if not exist "MARINA_HOTEL_PORTABLE\uploads" mkdir "MARINA_HOTEL_PORTABLE\uploads"
if not exist "MARINA_HOTEL_PORTABLE\uploads\reports" mkdir "MARINA_HOTEL_PORTABLE\uploads\reports"
if not exist "MARINA_HOTEL_PORTABLE\data" mkdir "MARINA_HOTEL_PORTABLE\data"

:: نسخ قاعدة البيانات
if exist "hotel_db.sql" copy "hotel_db.sql" "MARINA_HOTEL_PORTABLE\" >nul 2>&1
if exist "setup_exe_database.php" copy "setup_exe_database.php" "MARINA_HOTEL_PORTABLE\" >nul 2>&1

echo ✅ تم نسخ ملفات النظام

:: إنشاء ملف PHP محمول
echo 🔧 إنشاء خادم PHP محمول...
(
echo @echo off
echo chcp 65001
echo title Marina Hotel - خادم PHP محمول
echo color 0B
echo cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🏨 Marina Hotel Management System             ║
echo ║                        نظام إدارة الفندق                        ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🚀 بدء تشغيل الخادم المحمول...
echo.
echo 🌐 النظام سيعمل على: http://localhost:8080
echo 💻 لا تغلق هذه النافذة أثناء استخدام النظام
echo.
echo 🔧 إعداد الخادم...
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                    📡 الخادم يعمل الآن                         ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🌐 فتح النظام في المتصفح...
echo timeout /t 2 /nobreak ^>nul
echo start http://localhost:8080/setup_exe_database.php
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║  لإيقاف الخادم: اضغط Ctrl+C أو أغلق هذه النافذة                 ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo REM تشغيل خادم PHP المدمج
echo php -S localhost:8080 -t .
echo.
echo pause
) > "MARINA_HOTEL_PORTABLE\Marina_Hotel_Server.bat"

:: إنشاء ملف بديل للأنظمة التي لا تحتوي على PHP
echo 🔧 إنشاء ملف HTML لفتح النظام...
(
echo ^<!DOCTYPE html^>
echo ^<html dir="rtl" lang="ar"^>
echo ^<head^>
echo ^<meta charset="UTF-8"^>
echo ^<meta name="viewport" content="width=device-width, initial-scale=1.0"^>
echo ^<title^>Marina Hotel System^</title^>
echo ^<style^>
echo body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: linear-gradient^(135deg, #667eea 0%%, #764ba2 100%%^); color: white; text-align: center; }
echo .container { max-width: 600px; margin: 0 auto; padding: 40px; background: rgba^(255,255,255,0.1^); border-radius: 15px; backdrop-filter: blur^(10px^); }
echo h1 { font-size: 2.5em; margin-bottom: 30px; }
echo .btn { display: inline-block; padding: 15px 30px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; margin: 10px; font-size: 1.1em; transition: all 0.3s; }
echo .btn:hover { background: #0056b3; transform: translateY^(-2px^); }
echo .info { background: rgba^(255,255,255,0.2^); padding: 20px; border-radius: 10px; margin: 20px 0; text-align: right; }
echo .warning { background: rgba^(255,193,7,0.2^); padding: 15px; border-radius: 10px; margin: 20px 0; }
echo ^</style^>
echo ^</head^>
echo ^<body^>
echo ^<div class="container"^>
echo ^<h1^>🏨 Marina Hotel Management System^</h1^>
echo ^<p^>نظام إدارة الفندق المحمول^</p^>
echo ^<div class="info"^>
echo ^<h3^>📋 طرق تشغيل النظام:^</h3^>
echo ^<p^>^<strong^>الطريقة الأولى (الأسرع):^</strong^>^</p^>
echo ^<p^>شغل ملف: Marina_Hotel_Server.bat^</p^>
echo ^<br^>
echo ^<p^>^<strong^>الطريقة الثانية:^</strong^>^</p^>
echo ^<p^>استخدم XAMPP أو WAMP واربط المجلد^</p^>
echo ^</div^>
echo ^<div class="warning"^>
echo ^<h3^>⚠️ متطلبات التشغيل:^</h3^>
echo ^<p^>• PHP 7.4 أو أحدث^</p^>
echo ^<p^>• أو برنامج XAMPP/WAMP^</p^>
echo ^</div^>
echo ^<div class="info"^>
echo ^<h3^>🔐 معلومات الدخول:^</h3^>
echo ^<p^>اسم المستخدم: admin^</p^>
echo ^<p^>كلمة المرور: admin123^</p^>
echo ^</div^>
echo ^<p^>^<a href="Marina_Hotel_Server.bat" class="btn"^>🚀 تشغيل النظام^</a^>^</p^>
echo ^<p^>^<a href="setup_exe_database.php" class="btn"^>⚙️ إعداد قاعدة البيانات^</a^>^</p^>
echo ^</div^>
echo ^</body^>
echo ^</html^>
) > "MARINA_HOTEL_PORTABLE\index.html"

:: إنشاء ملف تعليمات
echo 📖 إنشاء ملف التعليمات...
(
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                Marina Hotel Management System                  ║
echo ║                   نظام إدارة الفندق المحمول                     ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🎯 نظام إدارة فندق محمول وسريع
echo.
echo 📋 طرق التشغيل:
echo.
echo 🚀 الطريقة الأولى ^(الأسرع^):
echo    1. شغل ملف: Marina_Hotel_Server.bat
echo    2. انتظر فتح المتصفح تلقائياً
echo    3. إذا لم يفتح، اذهب إلى: http://localhost:8080
echo.
echo 🌐 الطريقة الثانية ^(باستخدام XAMPP^):
echo    1. شغل XAMPP
echo    2. انسخ مجلد MARINA_HOTEL_PORTABLE إلى htdocs
echo    3. اذهب إلى: http://localhost/MARINA_HOTEL_PORTABLE
echo.
echo 🔧 الإعداد الأول:
echo    • اذهب إلى: setup_exe_database.php
echo    • اتبع التعليمات لإعداد قاعدة البيانات
echo    • اسم المستخدم: admin
echo    • كلمة المرور: admin123
echo.
echo 📁 هيكل الملفات:
echo    • data/               - قاعدة البيانات
echo    • uploads/            - الملفات المرفوعة
echo    • uploads/reports/    - التقارير
echo    • admin/              - لوحة التحكم
echo    • assets/             - الأصول ^(CSS, JS, الصور^)
echo    • includes/           - ملفات PHP المساعدة
echo    • api/                - واجهات API
echo.
echo 🎨 المميزات:
echo    ✅ إدارة الحجوزات والغرف
echo    ✅ إدارة الموظفين والمالية
echo    ✅ التقارير الشاملة
echo    ✅ نظام المدفوعات
echo    ✅ إدارة المصروفات
echo    ✅ نظام الأمان المتقدم
echo    ✅ واجهة عربية محسنة
echo.
echo 🆘 في حالة المشاكل:
echo    • تأكد من تثبيت PHP
echo    • تأكد من عدم استخدام المنفذ 8080
echo    • شغل كمسؤول إذا لزم الأمر
echo.
echo 📞 الدعم:
echo    • تأكد من وجود جميع الملفات
echo    • راجع ملف setup_exe_database.php للإعداد
echo    • استخدم XAMPP كبديل آمن
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                     🎉 النظام جاهز!                           ║
echo ╚════════════════════════════════════════════════════════════════╝
) > "MARINA_HOTEL_PORTABLE\README.txt"

:: إنشاء ملف إعداد سريع
echo 🛠️ إنشاء ملف الإعداد السريع...
(
echo @echo off
echo chcp 65001
echo title Marina Hotel - إعداد سريع
echo color 0E
echo cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🔧 Marina Hotel - إعداد سريع                 ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 📋 فحص النظام...
echo.
echo 🔍 فحص PHP...
echo php --version ^>nul 2^>^&1
echo if %%errorlevel%% == 0 ^(
echo     echo ✅ تم العثور على PHP
echo     echo.
echo     echo 🚀 بدء تشغيل الخادم...
echo     echo.
echo     echo 🌐 النظام سيعمل على: http://localhost:8080
echo     echo 💻 لا تغلق هذه النافذة
echo     echo.
echo     timeout /t 3 /nobreak ^>nul
echo     start http://localhost:8080/setup_exe_database.php
echo     echo.
echo     echo ╔════════════════════════════════════════════════════════════════╗
echo     echo ║                    📡 الخادم يعمل الآن                         ║
echo     echo ╚════════════════════════════════════════════════════════════════╝
echo     echo.
echo     php -S localhost:8080 -t .
echo ^) else ^(
echo     echo ❌ لم يتم العثور على PHP
echo     echo.
echo     echo 📋 الحلول البديلة:
echo     echo    1. تثبيت PHP من: https://www.php.net/downloads
echo     echo    2. استخدام XAMPP من: https://www.apachefriends.org
echo     echo    3. نسخ المجلد إلى htdocs في XAMPP
echo     echo.
echo     echo 🌐 بعد تثبيت XAMPP:
echo     echo    • انسخ هذا المجلد إلى: C:\xampp\htdocs\
echo     echo    • اذهب إلى: http://localhost/MARINA_HOTEL_PORTABLE
echo     echo.
echo     pause
echo ^)
) > "MARINA_HOTEL_PORTABLE\تشغيل_سريع.bat"

:: النتيجة النهائية
cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                🎉 تم إنشاء النظام المحمول بنجاح!             ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 📁 مجلد النظام: MARINA_HOTEL_PORTABLE
echo.
echo 🚀 ملفات التشغيل:
echo    • Marina_Hotel_Server.bat      (الخادم المحمول)
echo    • تشغيل_سريع.bat              (الإعداد السريع)
echo    • index.html                    (الصفحة الرئيسية)
echo.
echo 📖 ملفات إضافية:
echo    • README.txt                   (دليل مفصل)
echo    • setup_exe_database.php       (إعداد قاعدة البيانات)
echo.
echo 🔐 معلومات الدخول:
echo    • اسم المستخدم: admin
echo    • كلمة المرور: admin123
echo.
echo 🌐 بعد التشغيل: http://localhost:8080
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                   🎯 النظام جاهز للاستخدام!                   ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 💡 يمكنك الآن:
echo    • تشغيل النظام من المجلد
echo    • نسخ المجلد إلى أي مكان
echo    • نسخه إلى فلاشة ونقله لأي جهاز
echo.
echo 🚀 هل تريد تشغيل النظام الآن؟
echo.
set /p choice="اكتب Y للتشغيل أو N للخروج: "
if /i "%choice%"=="Y" (
    echo.
    echo 🚀 بدء التشغيل...
    cd "MARINA_HOTEL_PORTABLE"
    call "تشغيل_سريع.bat"
) else (
    echo.
    echo 💡 يمكنك تشغيل النظام لاحقاً من: MARINA_HOTEL_PORTABLE
    echo.
    pause
)

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                         🏆 تم بنجاح!                          ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.@echo off
chcp 65001
title Marina Hotel - منشئ EXE فوري
color 0A

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🚀 Marina Hotel - منشئ EXE فوري               ║
echo ║                        (بدون تحميل من الإنترنت)                 ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.

:: إنشاء مجلد EXE
echo 📁 إنشاء مجلد النظام...
if not exist "MARINA_HOTEL_PORTABLE" mkdir "MARINA_HOTEL_PORTABLE"

echo 📋 نسخ ملفات النظام...
:: نسخ جميع الملفات PHP
xcopy "*.php" "MARINA_HOTEL_PORTABLE\" /Y /Q >nul 2>&1
xcopy "admin" "MARINA_HOTEL_PORTABLE\admin\" /S /E /I /Y /Q >nul 2>&1
xcopy "assets" "MARINA_HOTEL_PORTABLE\assets\" /S /E /I /Y /Q >nul 2>&1
xcopy "includes" "MARINA_HOTEL_PORTABLE\includes\" /S /E /I /Y /Q >nul 2>&1
xcopy "api" "MARINA_HOTEL_PORTABLE\api\" /S /E /I /Y /Q >nul 2>&1

:: إنشاء مجلدات مطلوبة
if not exist "MARINA_HOTEL_PORTABLE\uploads" mkdir "MARINA_HOTEL_PORTABLE\uploads"
if not exist "MARINA_HOTEL_PORTABLE\uploads\reports" mkdir "MARINA_HOTEL_PORTABLE\uploads\reports"
if not exist "MARINA_HOTEL_PORTABLE\data" mkdir "MARINA_HOTEL_PORTABLE\data"

:: نسخ قاعدة البيانات
if exist "hotel_db.sql" copy "hotel_db.sql" "MARINA_HOTEL_PORTABLE\" >nul 2>&1
if exist "setup_exe_database.php" copy "setup_exe_database.php" "MARINA_HOTEL_PORTABLE\" >nul 2>&1

echo ✅ تم نسخ ملفات النظام

:: إنشاء ملف PHP محمول
echo 🔧 إنشاء خادم PHP محمول...
(
echo @echo off
echo chcp 65001
echo title Marina Hotel - خادم PHP محمول
echo color 0B
echo cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🏨 Marina Hotel Management System             ║
echo ║                        نظام إدارة الفندق                        ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🚀 بدء تشغيل الخادم المحمول...
echo.
echo 🌐 النظام سيعمل على: http://localhost:8080
echo 💻 لا تغلق هذه النافذة أثناء استخدام النظام
echo.
echo 🔧 إعداد الخادم...
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                    📡 الخادم يعمل الآن                         ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🌐 فتح النظام في المتصفح...
echo timeout /t 2 /nobreak ^>nul
echo start http://localhost:8080/setup_exe_database.php
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║  لإيقاف الخادم: اضغط Ctrl+C أو أغلق هذه النافذة                 ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo REM تشغيل خادم PHP المدمج
echo php -S localhost:8080 -t .
echo.
echo pause
) > "MARINA_HOTEL_PORTABLE\Marina_Hotel_Server.bat"

:: إنشاء ملف بديل للأنظمة التي لا تحتوي على PHP
echo 🔧 إنشاء ملف HTML لفتح النظام...
(
echo ^<!DOCTYPE html^>
echo ^<html dir="rtl" lang="ar"^>
echo ^<head^>
echo ^<meta charset="UTF-8"^>
echo ^<meta name="viewport" content="width=device-width, initial-scale=1.0"^>
echo ^<title^>Marina Hotel System^</title^>
echo ^<style^>
echo body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: linear-gradient^(135deg, #667eea 0%%, #764ba2 100%%^); color: white; text-align: center; }
echo .container { max-width: 600px; margin: 0 auto; padding: 40px; background: rgba^(255,255,255,0.1^); border-radius: 15px; backdrop-filter: blur^(10px^); }
echo h1 { font-size: 2.5em; margin-bottom: 30px; }
echo .btn { display: inline-block; padding: 15px 30px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; margin: 10px; font-size: 1.1em; transition: all 0.3s; }
echo .btn:hover { background: #0056b3; transform: translateY^(-2px^); }
echo .info { background: rgba^(255,255,255,0.2^); padding: 20px; border-radius: 10px; margin: 20px 0; text-align: right; }
echo .warning { background: rgba^(255,193,7,0.2^); padding: 15px; border-radius: 10px; margin: 20px 0; }
echo ^</style^>
echo ^</head^>
echo ^<body^>
echo ^<div class="container"^>
echo ^<h1^>🏨 Marina Hotel Management System^</h1^>
echo ^<p^>نظام إدارة الفندق المحمول^</p^>
echo ^<div class="info"^>
echo ^<h3^>📋 طرق تشغيل النظام:^</h3^>
echo ^<p^>^<strong^>الطريقة الأولى (الأسرع):^</strong^>^</p^>
echo ^<p^>شغل ملف: Marina_Hotel_Server.bat^</p^>
echo ^<br^>
echo ^<p^>^<strong^>الطريقة الثانية:^</strong^>^</p^>
echo ^<p^>استخدم XAMPP أو WAMP واربط المجلد^</p^>
echo ^</div^>
echo ^<div class="warning"^>
echo ^<h3^>⚠️ متطلبات التشغيل:^</h3^>
echo ^<p^>• PHP 7.4 أو أحدث^</p^>
echo ^<p^>• أو برنامج XAMPP/WAMP^</p^>
echo ^</div^>
echo ^<div class="info"^>
echo ^<h3^>🔐 معلومات الدخول:^</h3^>
echo ^<p^>اسم المستخدم: admin^</p^>
echo ^<p^>كلمة المرور: admin123^</p^>
echo ^</div^>
echo ^<p^>^<a href="Marina_Hotel_Server.bat" class="btn"^>🚀 تشغيل النظام^</a^>^</p^>
echo ^<p^>^<a href="setup_exe_database.php" class="btn"^>⚙️ إعداد قاعدة البيانات^</a^>^</p^>
echo ^</div^>
echo ^</body^>
echo ^</html^>
) > "MARINA_HOTEL_PORTABLE\index.html"

:: إنشاء ملف تعليمات
echo 📖 إنشاء ملف التعليمات...
(
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                Marina Hotel Management System                  ║
echo ║                   نظام إدارة الفندق المحمول                     ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 🎯 نظام إدارة فندق محمول وسريع
echo.
echo 📋 طرق التشغيل:
echo.
echo 🚀 الطريقة الأولى ^(الأسرع^):
echo    1. شغل ملف: Marina_Hotel_Server.bat
echo    2. انتظر فتح المتصفح تلقائياً
echo    3. إذا لم يفتح، اذهب إلى: http://localhost:8080
echo.
echo 🌐 الطريقة الثانية ^(باستخدام XAMPP^):
echo    1. شغل XAMPP
echo    2. انسخ مجلد MARINA_HOTEL_PORTABLE إلى htdocs
echo    3. اذهب إلى: http://localhost/MARINA_HOTEL_PORTABLE
echo.
echo 🔧 الإعداد الأول:
echo    • اذهب إلى: setup_exe_database.php
echo    • اتبع التعليمات لإعداد قاعدة البيانات
echo    • اسم المستخدم: admin
echo    • كلمة المرور: admin123
echo.
echo 📁 هيكل الملفات:
echo    • data/               - قاعدة البيانات
echo    • uploads/            - الملفات المرفوعة
echo    • uploads/reports/    - التقارير
echo    • admin/              - لوحة التحكم
echo    • assets/             - الأصول ^(CSS, JS, الصور^)
echo    • includes/           - ملفات PHP المساعدة
echo    • api/                - واجهات API
echo.
echo 🎨 المميزات:
echo    ✅ إدارة الحجوزات والغرف
echo    ✅ إدارة الموظفين والمالية
echo    ✅ التقارير الشاملة
echo    ✅ نظام المدفوعات
echo    ✅ إدارة المصروفات
echo    ✅ نظام الأمان المتقدم
echo    ✅ واجهة عربية محسنة
echo.
echo 🆘 في حالة المشاكل:
echo    • تأكد من تثبيت PHP
echo    • تأكد من عدم استخدام المنفذ 8080
echo    • شغل كمسؤول إذا لزم الأمر
echo.
echo 📞 الدعم:
echo    • تأكد من وجود جميع الملفات
echo    • راجع ملف setup_exe_database.php للإعداد
echo    • استخدم XAMPP كبديل آمن
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                     🎉 النظام جاهز!                           ║
echo ╚════════════════════════════════════════════════════════════════╝
) > "MARINA_HOTEL_PORTABLE\README.txt"

:: إنشاء ملف إعداد سريع
echo 🛠️ إنشاء ملف الإعداد السريع...
(
echo @echo off
echo chcp 65001
echo title Marina Hotel - إعداد سريع
echo color 0E
echo cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                  🔧 Marina Hotel - إعداد سريع                 ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 📋 فحص النظام...
echo.
echo 🔍 فحص PHP...
echo php --version ^>nul 2^>^&1
echo if %%errorlevel%% == 0 ^(
echo     echo ✅ تم العثور على PHP
echo     echo.
echo     echo 🚀 بدء تشغيل الخادم...
echo     echo.
echo     echo 🌐 النظام سيعمل على: http://localhost:8080
echo     echo 💻 لا تغلق هذه النافذة
echo     echo.
echo     timeout /t 3 /nobreak ^>nul
echo     start http://localhost:8080/setup_exe_database.php
echo     echo.
echo     echo ╔════════════════════════════════════════════════════════════════╗
echo     echo ║                    📡 الخادم يعمل الآن                         ║
echo     echo ╚════════════════════════════════════════════════════════════════╝
echo     echo.
echo     php -S localhost:8080 -t .
echo ^) else ^(
echo     echo ❌ لم يتم العثور على PHP
echo     echo.
echo     echo 📋 الحلول البديلة:
echo     echo    1. تثبيت PHP من: https://www.php.net/downloads
echo     echo    2. استخدام XAMPP من: https://www.apachefriends.org
echo     echo    3. نسخ المجلد إلى htdocs في XAMPP
echo     echo.
echo     echo 🌐 بعد تثبيت XAMPP:
echo     echo    • انسخ هذا المجلد إلى: C:\xampp\htdocs\
echo     echo    • اذهب إلى: http://localhost/MARINA_HOTEL_PORTABLE
echo     echo.
echo     pause
echo ^)
) > "MARINA_HOTEL_PORTABLE\تشغيل_سريع.bat"

:: النتيجة النهائية
cls
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                🎉 تم إنشاء النظام المحمول بنجاح!             ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 📁 مجلد النظام: MARINA_HOTEL_PORTABLE
echo.
echo 🚀 ملفات التشغيل:
echo    • Marina_Hotel_Server.bat      (الخادم المحمول)
echo    • تشغيل_سريع.bat              (الإعداد السريع)
echo    • index.html                    (الصفحة الرئيسية)
echo.
echo 📖 ملفات إضافية:
echo    • README.txt                   (دليل مفصل)
echo    • setup_exe_database.php       (إعداد قاعدة البيانات)
echo.
echo 🔐 معلومات الدخول:
echo    • اسم المستخدم: admin
echo    • كلمة المرور: admin123
echo.
echo 🌐 بعد التشغيل: http://localhost:8080
echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                   🎯 النظام جاهز للاستخدام!                   ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.
echo 💡 يمكنك الآن:
echo    • تشغيل النظام من المجلد
echo    • نسخ المجلد إلى أي مكان
echo    • نسخه إلى فلاشة ونقله لأي جهاز
echo.
echo 🚀 هل تريد تشغيل النظام الآن؟
echo.
set /p choice="اكتب Y للتشغيل أو N للخروج: "
if /i "%choice%"=="Y" (
    echo.
    echo 🚀 بدء التشغيل...
    cd "MARINA_HOTEL_PORTABLE"
    call "تشغيل_سريع.bat"
) else (
    echo.
    echo 💡 يمكنك تشغيل النظام لاحقاً من: MARINA_HOTEL_PORTABLE
    echo.
    pause
)

echo.
echo ╔════════════════════════════════════════════════════════════════╗
echo ║                         🏆 تم بنجاح!                          ║
echo ╚════════════════════════════════════════════════════════════════╝
echo.