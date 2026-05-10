@echo off
echo =================================
echo      Marina Hotel System
echo      تحويل إلى EXE
echo =================================

:: إنشاء مجلد البناء
if not exist "exe_build" mkdir exe_build
cd exe_build

:: تحميل PHP Desktop
echo تحميل PHP Desktop...
if not exist "php-desktop.zip" (
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/cztomczak/phpdesktop/releases/download/chrome-v57.0-rc/phpdesktop-chrome-57.0-rc-msvc2015.zip' -OutFile 'php-desktop.zip'"
)

:: استخراج الملفات
echo استخراج الملفات...
if not exist "phpdesktop-chrome" (
    powershell -Command "Expand-Archive -Path 'php-desktop.zip' -DestinationPath '.'"
)

:: نسخ ملفات التطبيق
echo نسخ ملفات التطبيق...
xcopy "..\*" "phpdesktop-chrome\www\" /E /Y /I /Q

:: إنشاء إعدادات PHP Desktop
echo إنشاء إعدادات التطبيق...
(
echo {
echo     "application": {
echo         "title": "Marina Hotel Management System",
echo         "width": 1200,
echo         "height": 800,
echo         "min_width": 800,
echo         "min_height": 600,
echo         "start_url": "login.php",
echo         "chrome_command_line_switches": {
echo             "disable-web-security": true,
echo             "allow-running-insecure-content": true
echo         }
echo     },
echo     "debugging": {
echo         "show_console": false,
echo         "subprocess_show_console": false
echo     },
echo     "web_server": {
echo         "listen_on": ["127.0.0.1", 8080],
echo         "directory_index": ["index.php", "login.php"]
echo     }
echo }
) > "phpdesktop-chrome\settings.json"

:: تخصيص الأيقونة
echo تخصيص التطبيق...
if exist "..\assets\icons\icon.ico" (
    copy "..\assets\icons\icon.ico" "phpdesktop-chrome\phpdesktop-chrome.exe.ico"
)

:: إنشاء قاعدة البيانات المحلية
echo إعداد قاعدة البيانات...
if exist "..\hotel_db.sql" (
    copy "..\hotel_db.sql" "phpdesktop-chrome\www\hotel_db.sql"
)

:: إنشاء ملف التشغيل السريع
(
echo @echo off
echo echo تشغيل Marina Hotel System...
echo cd "phpdesktop-chrome"
echo start phpdesktop-chrome.exe
echo exit
) > "Marina_Hotel_System.bat"

echo =================================
echo تم إنشاء ملف EXE بنجاح!
echo =================================
echo يمكنك الآن تشغيل النظام من:
echo exe_build\phpdesktop-chrome\phpdesktop-chrome.exe
echo =================================
pause