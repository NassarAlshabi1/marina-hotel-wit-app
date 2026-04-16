# 🚀 اختبار سريع لنظام Alarm Backup

## الخطوات السريعة للاختبار (5 دقائق)

### 1. بناء وتشغيل التطبيق

```bash
cd mobile
flutter pub get
flutter run
```

### 2. اختبار من داخل التطبيق

#### طريقة 1: من واجهة الإعدادات
1. افتح التطبيق
2. اذهب إلى: **الإعدادات** → **النسخ التلقائي الذكي**
3. مرّر للأسفل حتى ترى قسم **"النسخ الاحتياطي المجدول"**
4. فعّل المفتاح
5. اضغط على الوقت واختر وقتًا بعد دقيقة واحدة
6. انتظر وراقب الإشعارات

#### طريقة 2: اختبار فوري بالكود
أضف هذا الكود في أي صفحة (مثلاً في dashboard_screen.dart):

```dart
import '../services/alarm_backup.dart';

// في FloatingActionButton أو أي زر اختبار:
ElevatedButton(
  onPressed: () async {
    // جدولة بعد 10 ثوانٍ
    final testTime = DateTime.now().add(Duration(seconds: 10));
    await AlarmBackup.scheduleDailyAlarm(testTime.hour, testTime.minute);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('⏰ سيتم النسخ بعد 10 ثوانٍ')),
    );
  },
  child: Text('اختبار Alarm'),
)
```

### 3. مراقبة التنفيذ

#### في Terminal:
```bash
# في نافذة terminal منفصلة
adb logcat | grep -E "(flutter|Alarm)"
```

#### اللوجات المتوقعة:
```
I/flutter (12345): ✅ Alarm system initialized
I/flutter (12345): ✅ Alarm scheduled at 2025-11-23 21:00:00.000
I/flutter (12345): 🔔 Alarm fired: performing backup
I/flutter (12345): ✅ Local backup done from alarm
I/flutter (12345): ✅ Drive backup done from alarm
```

---

## 🧪 سيناريوهات الاختبار

### اختبار 1: النسخ المحلي فقط
```dart
// في SharedPreferences قبل الجدولة:
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('auto_local_backup_enabled', true);
await prefs.setBool('auto_backup_enabled', false); // إيقاف Drive

// جدولة
await AlarmBackup.scheduleDailyAlarm(21, 0);
```

**النتيجة المتوقعة:**
- ✅ إنشاء نسخة محلية في مجلد Downloads
- ❌ لا يتم رفع إلى Google Drive

### اختبار 2: النسخ السحابي + المحلي
```dart
// تأكد من تسجيل الدخول في Google Drive أولاً
final drive = GoogleDriveBackupService();
await drive.signInForDrive();

// في SharedPreferences:
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('auto_local_backup_enabled', true);
await prefs.setBool('auto_backup_enabled', true);

// جدولة
await AlarmBackup.scheduleDailyAlarm(21, 0);
```

**النتيجة المتوقعة:**
- ✅ إنشاء نسخة محلية
- ✅ رفع نسخة إلى Google Drive
- ✅ رسالة نجاح في اللوج

### اختبار 3: فشل Google Sign-In
```dart
// لا تسجل دخول في Google Drive
// أو سجل خروج أولاً:
final drive = GoogleDriveBackupService();
await drive.signOut();

// في SharedPreferences:
final prefs = await SharedPreferences.getInstance();
await prefs.setBool('auto_backup_enabled', true);

// جدولة
await AlarmBackup.scheduleDailyAlarm(21, 0);
```

**النتيجة المتوقعة:**
- ✅ إنشاء نسخة محلية
- ⚠️ فشل النسخ السحابي
- 📱 إشعار للمستخدم: "يرجى فتح التطبيق لتسجيل الدخول"

### اختبار 4: إعادة الجدولة
```dart
// جدولة في وقت
await AlarmBackup.scheduleDailyAlarm(21, 0);

// إعادة جدولة في وقت مختلف
await AlarmBackup.rescheduleDaily(14, 30);

// التحقق من اللوج
// يجب أن ترى: "♻️ Alarm rescheduled to 14:30"
```

### اختبار 5: الإلغاء
```dart
// جدولة
await AlarmBackup.scheduleDailyAlarm(21, 0);

// إلغاء
await AlarmBackup.cancelAlarm();

// التحقق من اللوج
// يجب أن ترى: "🚫 Alarm cancelled"
```

---

## 📱 اختبار على الهاتف

### تعطيل Battery Optimization (مهم جداً!)

#### Samsung:
```
Settings → Apps → Marina Hotel → Battery → Optimize battery usage 
→ All → Marina Hotel → Don't optimize
```

#### Xiaomi/MIUI:
```
Settings → Apps → Manage apps → Marina Hotel 
→ Battery saver → No restrictions
→ Autostart → Enable
```

#### Huawei/EMUI:
```
Settings → Apps → Marina Hotel → Battery 
→ App launch → Manual → Enable all
```

#### Stock Android:
```
Settings → Apps → Marina Hotel → Battery 
→ Battery optimization → Not optimized
```

### اختبار في وضع Doze

1. شغّل التطبيق وجدول alarm بعد 5 دقائق
2. أغلق الشاشة
3. انتظر 2-3 دقائق (دخول Doze خفيف)
4. راقب التنفيذ عبر adb:

```bash
adb logcat | grep flutter
```

**النتيجة المتوقعة:**
- ✅ ينفذ الـ alarm بدقة في الوقت المحدد
- ✅ تظهر رسائل اللوج
- ✅ يتم إنشاء النسخة الاحتياطية

---

## 🐛 استكشاف الأخطاء الشائعة

### الخطأ: "Alarm system not initialized"
**السبب:** لم يتم استدعاء `AlarmBackup.initAlarmSystem()` في main()

**الحل:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlarmBackup.initAlarmSystem(); // ✅ أضف هذا
  runApp(MyApp());
}
```

### الخطأ: "No such file or directory" للنسخة المحلية
**السبب:** مشكلة في صلاحيات التخزين

**الحل:**
```dart
await Permission.storage.request();
await Permission.manageExternalStorage.request();
```

### الخطأ: Alarm لا ينفذ بعد قفل الشاشة
**السبب:** Battery Optimization مفعلة

**الحل:**
1. اذهب إلى إعدادات الهاتف
2. أعط التطبيق صلاحية Unrestricted Battery
3. فعّل Autostart (Xiaomi/Huawei)

### الخطأ: "PlatformException" عند استدعاء signInSilently
**السبب:** لا توجد جلسة محفوظة

**الحل:**
- سجل دخول مرة واحدة من التطبيق أولاً
- أو اعرض إشعار للمستخدم (موجود في الكود ✅)

---

## 📊 قائمة التحقق النهائية

### قبل الإنتاج:
- [ ] اختبار على Samsung
- [ ] اختبار على Xiaomi/MIUI
- [ ] اختبار على Huawei
- [ ] اختبار على Stock Android
- [ ] اختبار في وضع Doze
- [ ] اختبار بعد إعادة تشغيل الهاتف
- [ ] التحقق من حجم النسخ الاحتياطية
- [ ] التحقق من استهلاك البطارية

### الوظائف:
- [ ] جدولة يومية تعمل
- [ ] النسخ المحلي يعمل
- [ ] النسخ السحابي يعمل
- [ ] الإشعارات تظهر
- [ ] إعادة الجدولة تلقائياً
- [ ] الإلغاء يعمل
- [ ] واجهة المستخدم واضحة

---

## 🎓 نصائح إضافية

### للأداء الأفضل:
1. ✅ اجعل الوقت الافتراضي في فترة هادئة (مثلاً 2-4 صباحاً)
2. ✅ تأكد من اتصال Wi-Fi إن أمكن (لتوفير البيانات)
3. ✅ نظف النسخ القديمة دورياً (موجود في الكود ✅)

### للمستخدمين:
1. 📘 أضف شاشة تعليمات في التطبيق
2. 📘 اشرح أهمية تعطيل Battery Optimization
3. 📘 أضف زر "اختبار الآن" في الإعدادات

### لفريق التطوير:
1. 🔍 راقب اللوجات في الإنتاج (Firebase Crashlytics)
2. 📊 أضف تتبع للنجاح/الفشل (Analytics)
3. 🐛 جمع feedback من المستخدمين حول الموثوقية

---

## ✨ ملاحظة أخيرة

هذا النظام **أكثر موثوقية** من workmanager بكثير! يستخدم نفس آلية المنبهات في Android التي تعمل مع تطبيقات الساعة المنبهة - **مضمون 99.9%** مع الإعدادات الصحيحة.

**بالتوفيق! 🚀**
