#!/usr/bin/env node

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

console.log('🚀 بدء بناء تطبيق الأندرويد...');

// Check if Capacitor is installed
try {
    execSync('npx cap --version', { stdio: 'ignore' });
} catch (error) {
    console.log('📦 تثبيت Capacitor...');
    execSync('npm install @capacitor/core @capacitor/cli @capacitor/android', { stdio: 'inherit' });
}

// Initialize Capacitor if not already done
if (!fs.existsSync('capacitor.config.ts')) {
    console.log('⚙️ تهيئة Capacitor...');
    execSync('npx cap init', { stdio: 'inherit' });
}

// Build the web app
console.log('🔨 بناء التطبيق الويب...');
execSync('npm run build', { stdio: 'inherit' });

// Add Android platform if not exists
if (!fs.existsSync('android')) {
    console.log('📱 إضافة منصة الأندرويد...');
    execSync('npx cap add android', { stdio: 'inherit' });
}

// Copy web assets to native project
console.log('📋 نسخ الملفات إلى المشروع الأصلي...');
execSync('npx cap copy android', { stdio: 'inherit' });

// Update native project
console.log('🔄 تحديث المشروع الأصلي...');
execSync('npx cap update android', { stdio: 'inherit' });

// Sync the project
console.log('🔄 مزامنة المشروع...');
execSync('npx cap sync android', { stdio: 'inherit' });

// Build APK
console.log('📦 بناء ملف APK...');
try {
    // Try to build release APK
    execSync('cd android && ./gradlew assembleRelease', { stdio: 'inherit' });
    console.log('✅ تم بناء APK الإنتاج بنجاح!');
    console.log('📍 الملف موجود في: android/app/build/outputs/apk/release/app-release.apk');
} catch (error) {
    console.log('⚠️ فشل بناء APK الإنتاج، جاري بناء APK التطوير...');
    try {
        execSync('cd android && ./gradlew assembleDebug', { stdio: 'inherit' });
        console.log('✅ تم بناء APK التطوير بنجاح!');
        console.log('📍 الملف موجود في: android/app/build/outputs/apk/debug/app-debug.apk');
    } catch (debugError) {
        console.error('❌ فشل في بناء APK:', debugError.message);
        process.exit(1);
    }
}

// Copy APK to root directory
try {
    const releaseApk = 'android/app/build/outputs/apk/release/app-release.apk';
    const debugApk = 'android/app/build/outputs/apk/debug/app-debug.apk';
    
    if (fs.existsSync(releaseApk)) {
        fs.copyFileSync(releaseApk, 'hotel-management-app.apk');
        console.log('📱 تم نسخ APK إلى: hotel-management-app.apk');
    } else if (fs.existsSync(debugApk)) {
        fs.copyFileSync(debugApk, 'hotel-management-app-debug.apk');
        console.log('📱 تم نسخ APK إلى: hotel-management-app-debug.apk');
    }
} catch (error) {
    console.log('⚠️ تعذر نسخ APK إلى المجلد الجذر');
}

console.log('\n🎉 تم الانتهاء من بناء تطبيق الأندرويد بنجاح!');
console.log('\n📋 الخطوات التالية:');
console.log('1. قم بتثبيت APK على جهاز الأندرويد');
console.log('2. تأكد من تفعيل "مصادر غير معروفة" في إعدادات الأمان');
console.log('3. افتح التطبيق واستمتع بالاستخدام!');