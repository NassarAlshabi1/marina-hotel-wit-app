@echo off
chcp 65001 > nul
echo ========================================
echo    بناء APK مبسط لفندق مارينا
echo ========================================
echo.

echo إنشاء مشروع APK بسيط...

REM إنشاء مجلد المشروع
if not exist "simple_apk_project" mkdir "simple_apk_project"
cd "simple_apk_project"

REM إنشاء هيكل المشروع
if not exist "src\main\java\com\marinahotel\app" mkdir "src\main\java\com\marinahotel\app"
if not exist "src\main\res\layout" mkdir "src\main\res\layout"
if not exist "src\main\res\values" mkdir "src\main\res\values"
if not exist "src\main\res\drawable" mkdir "src\main\res\drawable"
if not exist "src\main\res\mipmap-hdpi" mkdir "src\main\res\mipmap-hdpi"
if not exist "src\main\res\xml" mkdir "src\main\res\xml"

echo نسخ الملفات...

REM نسخ ملفات Java
copy "..\simple_webview_apk\MainActivity.java" "src\main\java\com\marinahotel\app\"

REM نسخ ملفات XML
copy "..\simple_webview_apk\activity_main.xml" "src\main\res\layout\"
copy "..\simple_webview_apk\AndroidManifest.xml" "src\main\"
copy "..\simple_webview_apk\build.gradle" "."

echo إنشاء ملفات الموارد...

REM إنشاء strings.xml
echo ^<?xml version="1.0" encoding="utf-8"?^> > "src\main\res\values\strings.xml"
echo ^<resources^> >> "src\main\res\values\strings.xml"
echo     ^<string name="app_name"^>فندق مارينا^</string^> >> "src\main\res\values\strings.xml"
echo     ^<string name="loading"^>جاري التحميل...^</string^> >> "src\main\res\values\strings.xml"
echo ^</resources^> >> "src\main\res\values\strings.xml"

REM إنشاء styles.xml
echo ^<?xml version="1.0" encoding="utf-8"?^> > "src\main\res\values\styles.xml"
echo ^<resources^> >> "src\main\res\values\styles.xml"
echo     ^<style name="AppTheme" parent="Theme.AppCompat.Light.DarkActionBar"^> >> "src\main\res\values\styles.xml"
echo         ^<item name="colorPrimary"^>#3F51B5^</item^> >> "src\main\res\values\styles.xml"
echo         ^<item name="colorPrimaryDark"^>#303F9F^</item^> >> "src\main\res\values\styles.xml"
echo         ^<item name="colorAccent"^>#FF4081^</item^> >> "src\main\res\values\styles.xml"
echo     ^</style^> >> "src\main\res\values\styles.xml"
echo     ^<style name="AppTheme.NoActionBar"^> >> "src\main\res\values\styles.xml"
echo         ^<item name="windowActionBar"^>false^</item^> >> "src\main\res\values\styles.xml"
echo         ^<item name="windowNoTitle"^>true^</item^> >> "src\main\res\values\styles.xml"
echo     ^</style^> >> "src\main\res\values\styles.xml"
echo ^</resources^> >> "src\main\res\values\styles.xml"

REM إنشاء network_security_config.xml
echo ^<?xml version="1.0" encoding="utf-8"?^> > "src\main\res\xml\network_security_config.xml"
echo ^<network-security-config^> >> "src\main\res\xml\network_security_config.xml"
echo     ^<domain-config cleartextTrafficPermitted="true"^> >> "src\main\res\xml\network_security_config.xml"
echo         ^<domain includeSubdomains="true"^>10.0.0.57^</domain^> >> "src\main\res\xml\network_security_config.xml"
echo         ^<domain includeSubdomains="true"^>localhost^</domain^> >> "src\main\res\xml\network_security_config.xml"
echo     ^</domain-config^> >> "src\main\res\xml\network_security_config.xml"
echo ^</network-security-config^> >> "src\main\res\xml\network_security_config.xml"

echo إنشاء gradlew...
echo @echo off > gradlew.bat
echo java -jar gradle/wrapper/gradle-wrapper.jar %%* >> gradlew.bat

echo.
echo ========================================
echo ✅ تم إنشاء مشروع APK مبسط!
echo.
echo الملفات موجودة في مجلد: simple_apk_project
echo.
echo للبناء باستخدام Android Studio:
echo 1. افتح Android Studio
echo 2. اختر "Open an Existing Project"
echo 3. اختر مجلد simple_apk_project
echo 4. Build ^> Build Bundle(s) / APK(s) ^> Build APK(s)
echo.
echo أو استخدم خدمة البناء عبر الإنترنت:
echo - GitHub Actions
echo - AppCenter
echo - Firebase App Distribution
echo ========================================

pause