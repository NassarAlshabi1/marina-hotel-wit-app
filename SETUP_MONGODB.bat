@echo off
chcp 65001 >nul
echo ============================================
echo    Marina Hotel - MongoDB Sync Setup
echo ============================================
echo.

cd api
echo [1/3] تثبيت MongoDB PHP Driver...
if exist composer.phar (
    php composer.phar install
) else (
    composer install
)

if errorlevel 1 (
    echo.
    echo ❌ فشل تثبيت Composer packages
    echo تأكد من تثبيت Composer:
    echo https://getcomposer.org/download/
    pause
    exit /b 1
)

echo.
echo [2/3] إنشاء مجلد السجلات...
cd ..
if not exist logs mkdir logs
echo OK

echo.
echo [3/3] اختبار الاتصال...
echo.
set /p MONGO_PASSWORD="أدخل كلمة مرور MongoDB: "

php mongodb_auto_sync.php

echo.
echo ============================================
echo ✅ تم الإعداد بنجاح!
echo ============================================
echo.
echo الآن يمكنك:
echo 1. تشغيل المزامنة يدوياً: php mongodb_auto_sync.php
echo 2. إعداد Cron Job لتشغيل تلقائي
echo 3. فتح التطبيق واستخدام شاشة المزامنة الفورية
echo.
pause
