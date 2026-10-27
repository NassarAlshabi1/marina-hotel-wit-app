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

REM إنشاء MainActivity.java
echo package com.marinahotel.app; > "src\main\java\com\marinahotel\app\MainActivity.java"
echo import android.app.Activity; >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo import android.os.Bundle; >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo import android.webkit.WebView; >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo import android.webkit.WebViewClient; >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo public class MainActivity extends Activity { >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo     @Override >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo     protected void onCreate^(Bundle savedInstanceState^) { >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo         super.onCreate^(savedInstanceState^); >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo         setContentView^(R.layout.activity_main^); >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo         WebView webView = findViewById^(R.id.webview^); >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo         webView.getSettings^(^).setJavaScriptEnabled^(true^); >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo         webView.setWebViewClient^(new WebViewClient^(^)^); >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo         webView.loadUrl^("file:///android_asset/index.html"^); >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo     } >> "src\main\java\com\marinahotel\app\MainActivity.java"
echo } >> "src\main\java\com\marinahotel\app\MainActivity.java"

REM إنشاء activity_main.xml
echo ^<?xml version="1.0" encoding="utf-8"?^> > "src\main\res\layout\activity_main.xml"
echo ^<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android" >> "src\main\res\layout\activity_main.xml"
echo     android:layout_width="match_parent" >> "src\main\res\layout\activity_main.xml"
echo     android:layout_height="match_parent"^> >> "src\main\res\layout\activity_main.xml"
echo     ^<WebView >> "src\main\res\layout\activity_main.xml"
echo         android:id="@+id/webview" >> "src\main\res\layout\activity_main.xml"
echo         android:layout_width="match_parent" >> "src\main\res\layout\activity_main.xml"
echo         android:layout_height="match_parent" /^> >> "src\main\res\layout\activity_main.xml"
echo ^</LinearLayout^> >> "src\main\res\layout\activity_main.xml"

REM إنشاء AndroidManifest.xml
echo ^<?xml version="1.0" encoding="utf-8"?^> > "src\main\AndroidManifest.xml"
echo ^<manifest xmlns:android="http://schemas.android.com/apk/res/android" >> "src\main\AndroidManifest.xml"
echo     package="com.marinahotel.app"^> >> "src\main\AndroidManifest.xml"
echo     ^<uses-permission android:name="android.permission.INTERNET" /^> >> "src\main\AndroidManifest.xml"
echo     ^<application >> "src\main\AndroidManifest.xml"
echo         android:allowBackup="true" >> "src\main\AndroidManifest.xml"
echo         android:label="@string/app_name" >> "src\main\AndroidManifest.xml"
echo         android:theme="@style/AppTheme"^> >> "src\main\AndroidManifest.xml"
echo         ^<activity android:name=".MainActivity" >> "src\main\AndroidManifest.xml"
echo             android:exported="true"^> >> "src\main\AndroidManifest.xml"
echo             ^<intent-filter^> >> "src\main\AndroidManifest.xml"
echo                 ^<action android:name="android.intent.action.MAIN" /^> >> "src\main\AndroidManifest.xml"
echo                 ^<category android:name="android.intent.category.LAUNCHER" /^> >> "src\main\AndroidManifest.xml"
echo             ^</intent-filter^> >> "src\main\AndroidManifest.xml"
echo         ^</activity^> >> "src\main\AndroidManifest.xml"
echo     ^</application^> >> "src\main\AndroidManifest.xml"
echo ^</manifest^> >> "src\main\AndroidManifest.xml"

REM إنشاء build.gradle
echo android { > "build.gradle"
echo     compileSdkVersion 33 >> "build.gradle"
echo     defaultConfig { >> "build.gradle"
echo         applicationId "com.marinahotel.app" >> "build.gradle"
echo         minSdkVersion 21 >> "build.gradle"
echo         targetSdkVersion 33 >> "build.gradle"
echo         versionCode 1 >> "build.gradle"
echo         versionName "1.0" >> "build.gradle"
echo     } >> "build.gradle"
echo } >> "build.gradle"

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