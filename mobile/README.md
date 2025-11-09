# Marina Hotel Mobile App

A complete hotel management system built with Flutter.

## 📦 حجم التطبيق المحسّن

التطبيق محسّن للأجهزة الحديثة:
- ✅ معمارية ARM64 فقط
- ✅ حجم مخفّض 60% مقارنة بالبناء الافتراضي
- ✅ App Bundle محسّن للتوزيع

**الحجم المتوقع:**
- Release APK: 12-15 MB
- تنزيل من Play Store: 8-10 MB

**المتطلبات:**
- Android 5.0+ (API 21)
- معمارية ARM64-v8a (معظم الأجهزة الحديثة)

## Build Instructions

### للتوزيع عبر Google Play (موصى به):
```bash
cd mobile
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build appbundle --release
```

### للتثبيت المباشر:
```bash
cd mobile
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release --target-platform android-arm64
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
