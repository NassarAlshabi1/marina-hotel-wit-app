#!/bin/bash

# Marina Hotel Mobile APK Builder
# نظام المدفوعات المتقدم - الإصدار 1.0.0

echo "🏨 Marina Hotel Mobile - APK Builder"
echo "====================================="

# التحقق من Flutter
echo "📋 فحص Flutter..."
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter غير مثبت. يرجى تثبيت Flutter SDK أولاً"
    echo "   https://flutter.dev/docs/get-started/install"
    exit 1
fi

echo "✅ Flutter متوفر"
flutter --version

# التحقق من البيئة
echo ""
echo "📋 فحص بيئة التطوير..."
flutter doctor --android-licenses > /dev/null 2>&1

# الانتقال إلى مجلد المشروع
cd "$(dirname "$0")"

# تنظيف الـ cache
echo ""
echo "🧹 تنظيف cache..."
flutter clean

# تثبيت Dependencies
echo ""
echo "📦 تثبيت المكتبات المطلوبة..."
flutter pub get

# تشغيل build_runner
echo ""
echo "⚙️  إنشاء ملفات قاعدة البيانات..."
flutter packages pub run build_runner build --delete-conflicting-outputs

# فحص الكود
echo ""
echo "🔍 فحص الكود..."
# flutter analyze

# بناء APK Debug (سريع للاختبار)
echo ""
echo "🔨 بناء APK Debug..."
flutter build apk --debug --target-platform android-arm64

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ تم بناء APK Debug بنجاح!"
    echo "📁 الملف: build/app/outputs/flutter-apk/app-debug.apk"
    
    # عرض حجم الملف
    APK_SIZE=$(du -h build/app/outputs/flutter-apk/app-debug.apk | cut -f1)
    echo "📊 حجم الملف: $APK_SIZE"
else
    echo ""
    echo "❌ فشل في بناء APK Debug"
    exit 1
fi

# سؤال المستخدم إذا كان يريد بناء Release
echo ""
read -p "🤔 هل تريد بناء APK Release للإنتاج؟ (y/n): " BUILD_RELEASE

if [[ $BUILD_RELEASE =~ ^[Yy]$ ]]; then
    echo ""
    echo "🔨 بناء APK Release..."
    flutter build apk --release --target-platform android-arm64
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ تم بناء APK Release بنجاح!"
        echo "📁 الملف: build/app/outputs/flutter-apk/app-release.apk"
        
        # عرض حجم الملف
        APK_SIZE=$(du -h build/app/outputs/flutter-apk/app-release.apk | cut -f1)
        echo "📊 حجم الملف: $APK_SIZE"
        
        # نسخ الملف لمكان سهل الوصول
        cp build/app/outputs/flutter-apk/app-release.apk ./marina_hotel_v1.0.0_payments.apk
        echo "📋 تم نسخ الملف إلى: marina_hotel_v1.0.0_payments.apk"
    else
        echo ""
        echo "❌ فشل في بناء APK Release"
        exit 1
    fi
fi

echo ""
echo "🎉 اكتملت عملية البناء!"
echo ""
echo "📱 تعليمات الاختبار:"
echo "1. قم بنقل APK إلى جهاز Android"
echo "2. فعّل 'مصادر غير معروفة' في الإعدادات"
echo "3. ثبّت التطبيق واختبر نظام المدفوعات"
echo ""
echo "✨ مميزات نظام المدفوعات الجديد:"
echo "   • 5 طرق دفع متنوعة"
echo "   • إيصالات وفواتير PDF"
echo "   • سجل مدفوعات متقدم"
echo "   • نظام checkout شامل"
echo ""
echo "📞 للدعم: Marina Hotel Development Team"