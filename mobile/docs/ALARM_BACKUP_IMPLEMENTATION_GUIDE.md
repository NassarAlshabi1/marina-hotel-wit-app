# دليل تطبيق نظام النسخ الاحتياطي المجدول (Alarm-Based)

## 📋 ملخص التعديلات

تم تطبيق حل شامل وموثوق لمشكلة النسخ الاحتياطي التلقائي باستخدام `android_alarm_manager_plus` بدلاً من `workmanager` لضمان التنفيذ الدقيق حتى في وضع Doze.

---

## ✅ التعديلات المنفذة

### 1. إضافة الحزم الجديدة (pubspec.yaml)
```yaml
dependencies:
  android_alarm_manager_plus: ^3.0.0
  flutter_local_notifications: ^17.0.0
```

### 2. ملف جديد: alarm_backup.dart
**المسار:** `/lib/services/alarm_backup.dart`

**الميزات:**
- ✅ استخدام `AndroidAlarmManager.oneShotAt()` مع `exact: true`, `wakeup: true`, `allowWhileIdle: true`
- ✅ جدولة يومية تلقائية في وقت محدد (افتراضياً 21:00)
- ✅ إعادة جدولة تلقائية بعد كل تنفيذ
- ✅ دعم النسخ المحلي والسحابي (Google Drive)
- ✅ محاولة تسجيل الدخول الهادئ (`signInSilently`)
- ✅ إشعار للمستخدم إذا فشل تسجيل الدخول في الخلفية
- ✅ إلغاء وإعادة جدولة الإنذار

**الدوال الرئيسية:**
- `initAlarmSystem()` - تهيئة النظام في main()
- `scheduleDailyAlarm(hour, minute)` - جدولة إنذار يومي
- `rescheduleDaily(hour, minute)` - إعادة جدولة
- `cancelAlarm()` - إلغاء الجدولة
- `_alarmCallback()` - الكولباك الذي ينفذ عند الإنذار

### 3. تحسين GoogleDriveBackupService
**المسار:** `/lib/services/google_drive_backup_service.dart`

**التعديل:**
- ✅ إضافة دالة `signInSilentlyIfNeeded()` للاستخدام في الخلفية
```dart
Future<bool> signInSilentlyIfNeeded() async {
  try {
    if (_googleSignIn == null) _initializeGoogleSignIn();
    final account = await _googleSignIn!.signInSilently(suppressErrors: true);
    
    if (account != null) {
      final headers = await account.authHeaders;
      final client = GoogleAuthClient(headers);
      _driveApi = drive.DriveApi(client);
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}
```

### 4. تحديث AndroidManifest.xml
**المسار:** `/android/app/src/main/AndroidManifest.xml`

**الصلاحيات المضافة:**
```xml
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

**المكونات المضافة:**
```xml
<!-- Alarm Manager Broadcast Receiver -->
<service
    android:name="dev.fluttercommunity.plus.androidalarmmanager.AlarmService"
    android:permission="android.permission.BIND_JOB_SERVICE"
    android:exported="false"/>
<receiver
    android:name="dev.fluttercommunity.plus.androidalarmmanager.AlarmBroadcastReceiver"
    android:exported="false"/>
<receiver
    android:name="dev.fluttercommunity.plus.androidalarmmanager.RebootBroadcastReceiver"
    android:enabled="false"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
    </intent-filter>
</receiver>
```

### 5. تحديث main.dart
**المسار:** `/lib/main.dart`

**التعديل:**
```dart
import 'services/alarm_backup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة نظام Alarm للنسخ الاحتياطي
  await AlarmBackup.initAlarmSystem();
  
  // باقي التهيئة...
}
```

### 6. واجهة المستخدم - auto_backup_settings_screen.dart
**المسار:** `/lib/screens/settings/auto_backup_settings_screen.dart`

**الميزات المضافة:**
- ✅ بطاقة جديدة "النسخ الاحتياطي المجدول"
- ✅ مفتاح تفعيل/إلغاء الجدولة
- ✅ اختيار الوقت بواجهة سهلة
- ✅ عرض حالة الجدولة الحالية
- ✅ حفظ الإعدادات في SharedPreferences

---

## 🚀 خطوات التشغيل والاختبار

### 1. تنزيل الحزم
```bash
cd mobile
flutter pub get
```

### 2. بناء التطبيق
```bash
flutter build apk --release
# أو للتطوير:
flutter run
```

### 3. الاختبار السريع (10 ثوانٍ)
في أي مكان في التطبيق، يمكنك اختبار الجدولة خلال 10 ثوانٍ:

```dart
// للاختبار الفوري - جدولة بعد 10 ثوانٍ
final now = DateTime.now().add(Duration(seconds: 10));
await AlarmBackup.scheduleDailyAlarm(now.hour, now.minute);
```

### 4. مراقبة اللوج
```bash
# مراقبة logs Flutter
adb logcat | grep flutter

# مراقبة logs Alarm
adb logcat | grep Alarm
```

**اللوجات المتوقعة:**
```
✅ Alarm system initialized
✅ Alarm scheduled at 2025-11-23 21:00:00.000
🔔 Alarm fired: performing backup
✅ Local backup done from alarm
✅ Drive backup done from alarm
```

### 5. الاستخدام الفعلي

#### أ) من واجهة الإعدادات:
1. افتح التطبيق
2. اذهب إلى: **الإعدادات** → **النسخ التلقائي الذكي**
3. مرّر للأسفل إلى قسم **"النسخ الاحتياطي المجدول"**
4. فعّل المفتاح
5. اضغط على **"وقت النسخ الاحتياطي"** لتغيير الوقت
6. احفظ الإعدادات

#### ب) برمجياً:
```dart
// جدولة نسخ يومي في الساعة 21:00
await AlarmBackup.rescheduleDaily(21, 0);

// إلغاء الجدولة
await AlarmBackup.cancelAlarm();
```

---

## 🔧 استكشاف الأخطاء

### المشكلة: الإنذار لا ينفذ
**الحلول:**
1. ✅ تأكد من إعطاء صلاحية Battery Optimization:
   ```dart
   // في settings أو عند أول استخدام
   Permission.ignoreBatteryOptimizations.request();
   ```

2. ✅ تحقق من إعدادات الهاتف:
   - Settings → Apps → Marina Hotel → Battery → Unrestricted

3. ✅ تحقق من الصلاحيات في AndroidManifest.xml

### المشكلة: Google Sign-In فشل في الخلفية
**الحل:**
- ✅ النظام يعرض إشعار للمستخدم تلقائياً
- ✅ سيتم إنشاء النسخة المحلية فقط
- ✅ عند فتح التطبيق يمكن المحاولة مجدداً

### المشكلة: الإنذار لا يعاد جدولته بعد إعادة التشغيل
**الحل:**
- ✅ تأكد من `rescheduleOnReboot: true` في الكود (موجود ✅)
- ✅ تأكد من RebootBroadcastReceiver في AndroidManifest (موجود ✅)

---

## 📊 المقارنة بين الحلول

| الميزة | workmanager | android_alarm_manager_plus |
|--------|-------------|----------------------------|
| دقة التوقيت | ❌ تقريبية (±15 دقيقة) | ✅ دقيقة (±دقيقة) |
| العمل في Doze | ❌ قد يتأخر | ✅ مضمون مع allowWhileIdle |
| Google Sign-In | ❌ صعب في isolate | ✅ يعمل مع signInSilently |
| سهولة الاستخدام | ✅ سهل | ✅ سهل |
| الصيانة | ❌ قد يتطلب إعادة جدولة | ✅ إعادة جدولة تلقائية |

---

## 🎯 نقاط مهمة

### ✅ ما تم إنجازه:
1. نظام alarm موثوق يعمل في Doze
2. جدولة يومية تلقائية
3. دعم النسخ المحلي والسحابي
4. واجهة مستخدم سهلة لإدارة الجدولة
5. إشعارات في حالة فشل تسجيل الدخول
6. إعادة جدولة تلقائية بعد التنفيذ وبعد إعادة التشغيل

### ⚠️ ملاحظات مهمة:
1. **Google Sign-In في الخلفية**: يعمل فقط مع `signInSilently()` إذا كان المستخدم سجل دخوله مسبقاً
2. **Battery Optimization**: يجب إعطاء التطبيق صلاحية Unrestricted للعمل بشكل مثالي
3. **Android 12+**: تتطلب صلاحية `SCHEDULE_EXACT_ALARM` (مضافة ✅)
4. **الاختبار**: استخدم جدولة بعد 10-30 ثانية للاختبار الفوري

### 🔄 التكامل مع الأنظمة الموجودة:
- ✅ لا يتعارض مع `workmanager` الموجود
- ✅ يستخدم نفس خدمات النسخ الاحتياطي الموجودة
- ✅ يحفظ الإعدادات في SharedPreferences
- ✅ متوافق مع جميع شاشات الإعدادات الحالية

---

## 📝 التوصيات

### للاستخدام الفوري:
1. ✅ نفذ `flutter pub get`
2. ✅ ابنِ APK جديد
3. ✅ اختبر بجدولة بعد 10 ثوانٍ
4. ✅ راقب اللوجات للتأكد من التنفيذ

### للإنتاج:
1. ✅ اطلب من المستخدمين تعطيل Battery Optimization
2. ✅ أضف شاشة تعليمات لشرح الجدولة
3. ✅ فعّل الإشعارات للتنبيه عن نجاح/فشل النسخ
4. ✅ اختبر على أجهزة مختلفة (Samsung, Xiaomi, Huawei)

---

## 📞 الدعم

إذا واجهت أي مشاكل:
1. ✅ تحقق من اللوجات أولاً (`adb logcat`)
2. ✅ تأكد من الصلاحيات في الإعدادات
3. ✅ جرب الاختبار الفوري (10 ثوانٍ)
4. ✅ تحقق من تسجيل الدخول في Google Drive

---

**تم التطبيق بنجاح ✅**
**تاريخ التنفيذ: 23 نوفمبر 2025**
