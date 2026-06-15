# إعداد خدمة الخلفية (Foreground Service)

## 1. إضافة للـ pubspec.yaml

```yaml
dependencies:
  flutter_background_service: ^5.0.0
  flutter_background_service_android: ^6.0.0
```

## 2. إضافة للـ AndroidManifest.xml

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<manifest>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    
    <application>
        <service
            android:name="com.blloc.flutter_background_service.IsolateService"
            android:foregroundServiceType="dataSync"
            android:exported="false" />
    </application>
</manifest>
```

## 3. تشغيل build_runner

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

## 4. آلية العمل

- الخدمة تبدأ تلقائياً عند تشغيل التطبيق
- تعمل مع إشعار دائم ("المزامنة نشطة")
- مزامنة دورية كل 5 دقائق
- تنظيف Outbox كل ساعة
- لا تتأثر بقيود Android 12+ على Background Execution
