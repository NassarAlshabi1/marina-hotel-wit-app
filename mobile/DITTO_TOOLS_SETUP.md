# شاشة أدوات Ditto للمطورين

## نظرة عامة

تم إضافة شاشة شاملة لأدوات Ditto للمطورين تحتوي على جميع أدوات التشخيص والتصحيح من حزمة `ditto_flutter_tools`.

## الموقع

الشاشة متاحة في:
```
الإعدادات الرئيسية > إعدادات النظام > أدوات Ditto للمطورين
```

## الأدوات المتاحة

### 1. مراقبة الشبكة والمزامنة

#### الأجهزة المتصلة (PeerListView)
- عرض جميع الأجهزة المتصلة في شبكة P2P
- معلومات الجهاز المحلي (Local Peer)
- قائمة الأجهزة البعيدة (Remote Peers)
- تفاصيل الاتصال ونوعه
- حالة اتصال Cloud (متصل/غير متصل)
- تحديثات فورية عند انضمام أو مغادرة الأجهزة

#### حالة المزامنة مع الأجهزة (PeerSyncStatusView)
- مراقبة حالة المزامنة بين جهازك والأجهزة المتصلة
- تجميع الأجهزة حسب حالة الاتصال (متصل/غير متصل)
- التمييز بين Cloud Server و Peer Device
- عرض commit ID لكل جهاز
- توقيت آخر تحديث للمزامنة

#### حالة الاشتراكات (SyncStatusHelper)
- معلومات حول أداة `SyncStatusHelper`
- يتطلب تمرير قائمة subscriptions برمجياً
- مفيد لمراقبة حالة الاشتراكات المحددة

### 2. إدارة البيانات والنظام

#### استخدام القرص (DiskUsageView)
- عرض حجم قاعدة البيانات
- قائمة جميع الملفات والمجلدات
- تصدير قاعدة البيانات كملف ZIP
- تصدير سجلات Ditto
- استخدام Share API للمشاركة السهلة

#### محرر الاستعلامات DQL (QueryEditorView)
- تنفيذ استعلامات DQL مباشرة على قاعدة البيانات
- دعم SELECT, INSERT, UPDATE, DELETE
- عرض النتائج مع pagination
- تصدير النتائج كملف JSON
- معالجة الأخطاء بوضوح

#### إعدادات النظام (SystemSettingsView)
- عرض جميع إعدادات Ditto الداخلية
- استخدام `SHOW ALL` DQL statement
- بحث في الإعدادات
- عرض مفصل للقيم المعقدة
- نسخ القيم إلى الحافظة
- تحديث الإعدادات يدوياً

### 3. الصلاحيات والأذونات

#### حالة الصلاحيات (PermissionsHealthView)
- فحص صلاحيات Bluetooth
- حالة تفعيل Bluetooth
- حالة Wi-Fi P2P (WiFi Direct/AWDL)
- اكتشاف المحاكيات/Simulators
- التنقل إلى إعدادات الجهاز

## التثبيت

تم إضافة التبعية التالية إلى `pubspec.yaml`:

```yaml
dependencies:
  ditto_flutter_tools: ^2.0.0
```

## ملاحظات مهمة

### متطلبات التشغيل
- Ditto SDK 4.12.1 أو أحدث ✅ (المشروع يستخدم 4.12.4)
- الأدوات لا تدعم Flutter Web
- تعمل على iOS, Android, macOS, Linux

### إعدادات PermissionsHealthView
لتعمل أداة الصلاحيات بشكل كامل، يجب تعديل `ios/Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    # إضافة هذا الكود لدعم Bluetooth permission checking
    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_BLUETOOTH=1'
      ]
    end
  end
end
```

### تحذيرات الأمان
⚠️ **محرر الاستعلامات DQL**:
- يمكن تعديل وحذف البيانات
- استخدمه بحذر
- لا تستخدمه في بيئة الإنتاج بدون حماية

⚠️ **تصدير قاعدة البيانات**:
- قد يحتوي على بيانات حساسة
- تأكد من تأمين الملفات المصدرة

## استخدام برمجي

إذا أردت استخدام الأدوات برمجياً بدلاً من واجهة المستخدم:

```dart
import 'package:ditto_flutter_tools/ditto_flutter_tools.dart';

// مثال: SyncStatusHelper
final syncStatusHelper = SyncStatusHelper(
  ditto: DittoConfig.instance,
  subscriptions: [
    mySubscription1,
    mySubscription2,
  ],
);

// أو استخدام الاشتراكات النشطة
final helper = SyncStatusHelper.fromCurrentSubscriptions(
  ditto: DittoConfig.instance,
);

// الحصول على الحالة
print(helper.overallStatus);
print(helper.isConnected);
print(helper.lastConnectedAt);
```

## الموارد

- [Ditto Flutter Tools GitHub](https://github.com/getditto/ditto_flutter_tools)
- [Ditto Documentation](https://docs.ditto.live)
- [DQL Reference](https://docs.ditto.live/sdk/latest/crud/read)

## المساهمة

إذا وجدت مشكلة أو لديك اقتراح، يرجى التواصل مع:
- Ditto Support: support@ditto.live
