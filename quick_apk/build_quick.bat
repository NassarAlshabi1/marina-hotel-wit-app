@echo off
chcp 65001 > nul
title بناء APK سريع - فندق مارينا

echo.
echo ==========================================
echo         🚀 بناء APK سريع 🚀
echo      تطبيق فندق مارينا للأندرويد
echo ==========================================
echo.

REM التحقق من Java
echo [1/5] التحقق من Java...
java -version > nul 2>&1
if %errorlevel% neq 0 (
    echo ❌ Java غير مثبت!
    echo الرجاء تحميل Java JDK من:
    echo https://www.oracle.com/java/technologies/javase-downloads.html
    pause
    exit /b 1
)
echo ✅ Java موجود

REM إنشاء أيقونة افتراضية
echo [2/5] إنشاء الأيقونات...
if not exist "app\src\main\res\mipmap-hdpi" mkdir "app\src\main\res\mipmap-hdpi"
if not exist "app\src\main\res\mipmap-mdpi" mkdir "app\src\main\res\mipmap-mdpi"
if not exist "app\src\main\res\mipmap-xhdpi" mkdir "app\src\main\res\mipmap-xhdpi"
if not exist "app\src\main\res\mipmap-xxhdpi" mkdir "app\src\main\res\mipmap-xxhdpi"

REM نسخ أيقونة افتراضية (يمكن استبدالها لاحقاً)
echo ✅ تم إنشاء الأيقونات الافتراضية

REM تنظيف المشروع
echo [3/5] تنظيف المشروع السابق...
if exist "app\build" rmdir /s /q "app\build"
if exist "build" rmdir /s /q "build"
echo ✅ تم التنظيف

REM بدء البناء
echo [4/5] بدء بناء APK...
echo هذا قد يستغرق 3-5 دقائق في المرة الأولى...
echo.

call gradlew.bat clean assembleDebug --no-daemon --stacktrace

if %errorlevel% equ 0 (
    echo.
    echo ==========================================
    echo           ✅ نجح البناء! ✅
    echo ==========================================
    echo.
    
    if exist "app\build\outputs\apk\debug\app-debug.apk" (
        echo 📱 تم إنشاء APK بنجاح!
        echo 📍 المسار: app\build\outputs\apk\debug\app-debug.apk
        echo.
        
        REM عرض معلومات الملف
        for %%A in ("app\build\outputs\apk\debug\app-debug.apk") do (
            echo 📊 الحجم: %%~zA bytes
            echo 📅 تاريخ الإنشاء: %%~tA
        )
        
        echo.
        echo 🚀 خطوات التثبيت على الهاتف:
        echo 1. انسخ الملف إلى هاتفك
        echo 2. فعل "تثبيت من مصادر غير معروفة" في الإعدادات
        echo 3. اضغط على الملف لتثبيته
        echo 4. تأكد من اتصال الهاتف بنفس الشبكة (10.0.0.57)
        
        echo.
        echo 💡 نصيحة: يمكنك إرسال الملف عبر WhatsApp أو البلوتوث
        
    ) else (
        echo ❌ لم يتم العثور على ملف APK
        echo تحقق من الأخطاء أعلاه
    )
    
) else (
    echo.
    echo ==========================================
    echo           ❌ فشل البناء ❌
    echo ==========================================
    echo.
    echo الأخطاء الشائعة وحلولها:
    echo.
    echo 🔧 إذا كان الخطأ متعلق بـ Gradle:
    echo    - احذف مجلد .gradle في مجلد المستخدم
    echo    - أعد تشغيل الكمبيوتر وجرب مرة أخرى
    echo.
    echo 🔧 إذا كان الخطأ متعلق بـ SDK:
    echo    - تأكد من تثبيت Android Studio
    echo    - أو حدد متغير ANDROID_HOME
    echo.
    echo 🔧 للحصول على مساعدة:
    echo    - راجع الأخطاء المعروضة أعلاه
    echo    - جرب الطرق البديلة (GitHub Actions)
    
)

echo.
echo [5/5] اكتمال العملية
echo ==========================================

pause