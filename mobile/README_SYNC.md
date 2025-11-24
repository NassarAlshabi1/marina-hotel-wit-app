# دليل مزامنة Google Drive + FCM (عربي)

هذا الدليل يشرح كيفية تفعيل نظام المزامنة ثنائي الاتجاه شبه اللحظي بين أجهزة الأندرويد لتطبيق **Marina Hotel** باستخدام Google Drive (appDataFolder) ورسائل Firebase Cloud Messaging (FCM). يعتمد النظام على قاعدة بيانات Drift محلية ويضمن عدم فقدان البيانات مع أولوية للأداء دون التضحية بوضع عدم الاتصال.

## 1. المتطلبات المسبقة
- حساب Google Cloud مفعّل مع إمكانية إنشاء OAuth Client.
- حساب Firebase مفعّل لمشروع أندرويد.
- Android Studio / Flutter SDK محدث (Flutter 3.24+ ، Dart 3.4+).
- حزمة `workmanager` مفعّلة (موجودة مسبقًا في `pubspec.yaml`).

## 2. تفعيل Google Drive API والوصول إلى appDataFolder
1. من [Google Cloud Console](https://console.cloud.google.com/)، أنشئ مشروعًا جديدًا أو اختر مشروعًا قائمًا.
2. من **APIs & Services → Library**، فعّل **Google Drive API**.
3. من **Credentials**:
   - أنشئ OAuth client جديد من نوع **Android**.
   - استخدم الحزمة (Package Name) والتوقيع (SHA-1) الخاصة بالتطبيق.
   - حمّل ملف `credentials.json` للاحتفاظ به في الأرشيف (لا يدرج في التطبيق مباشرًا).
4. تأكد من إضافة نطاق `https://www.googleapis.com/auth/drive.appdata` إلى قائمة Scopes المصرّح بها.

> **ملاحظة أمنية:** نظام المزامنة يرفع الملفات إلى `appDataFolder` بحيث لا يمكن للمستخدم رؤيتها في Google Drive، وهذا يزيد الخصوصية مقارنةً بالمجلدات العادية.

## 3. إعداد Google Sign-In في Flutter
- الحزم `google_sign_in` و `googleapis` مضافة بالفعل إلى المشروع.
- ضمّن `google-services.json` في المسار `android/app/` (راجع قسم FCM أدناه).
- عند تشغيل التطبيق لأول مرة، استدعِ:
  ```dart
  final syncManager = SyncManager(
    db: DatabaseManager.instance,
    driveService: GoogleDriveSyncService(),
  );
  await syncManager.initSyncService(enableEncryption: true, encryptionKey: secureKey);
  ```
- تأكد من التعامل مع حالات فشل تسجيل الدخول (مثلاً انقطاع الإنترنت) بإعادة المحاولة المناسبة.

## 4. إعداد Firebase Cloud Messaging (FCM)
1. أنشئ مشروع Firebase أو استخدم مشروعًا قائمًا.
2. أضف تطبيق أندرويد بنفس Package Name المستعمل في Google Cloud.
3. حمّل ملف `google-services.json` وضعه داخل `mobile/android/app/`.
4. حدّث ملف `android/build.gradle` إذا لزم لإضافة `classpath 'com.google.gms:google-services:...`.
5. في `android/app/build.gradle` أضف `apply plugin: 'com.google.gms.google-services'` في نهاية الملف.
6. داخل التطبيق، استخدم خدمة الإشعارات لإرسال رسائل بيانات بصيغة:
   ```json
   {
     "type": "SYNC_TRIGGER",
     "sourceDevice": "<device-id>",
     "syncId": "<sync-event-id>"
   }
   ```
7. عند استلام الرسالة في التطبيق، استدع `syncManager.pullAndMerge()` مباشرةً لضمان التحديث الفوري.

> **تنبيه:** Google Drive وحده غير كافٍ للتزامن اللحظي. يجب استخدام FCM لتوليد إشعار السحب فور تعديل البيانات من جهاز آخر. في حالة فشل الإشعار، سيتكفل `AutoSyncTask` بمراقبة التغييرات عبر WorkManager مع تراجع أسي.

## 5. تحديث AndroidManifest
أضف الأذونات التالية (إن لم تكن موجودة):
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
```
ضمن وسم `<application>` أضف تعريف WorkManager الافتراضي عند الحاجة:
```xml
<meta-data
    android:name="androidx.work.impl.WorkManagerInitializer"
    android:value="androidx.startup" />
```
وإذا استخدمت Workers مخصّصة، عرّفها داخل ملف Manifest أو عبر `WorkManager.initialize` في التطبيق.

## 6. تهيئة AutoSyncTask مع WorkManager
1. في `main.dart` أو أثناء تهيئة الخدمات، نفّذ:
   ```dart
   await AutoSyncTask.initialize();
   await AutoSyncTask.schedulePeriodicSync(const Duration(minutes: 30));
   ```
2. عند اكتشاف تغييرات محلية كبيرة، استخدم:
   ```dart
   await AutoSyncTask.scheduleImmediateSync();
   ```
   سيتم استخدام Debounce داخليًا لمنع جدولة مهمات متتالية في أقل من 10 ثوانٍ.
3. عند تشغيل التطبيق في المقدمة، استهلك العلامة المخزنة:
   ```dart
   await AutoSyncTask.consumePendingAndSync(syncManager, force: true);
   ```

## 7. حماية مفتاح التشفير
- عند تمرير `encryptionKey` إلى `initSyncService` يجب حفظ المفتاح باستخدام `flutter_secure_storage` أو Keystore/Keychain الخاصة بالنظام.
- يوصى بإنشاء مفتاح 32 بايت (Base64) وتخزينه عند أول تشغيل، ثم إعادة استخدامه في جميع عمليات المزامنة على نفس الجهاز.
- لا تقم بحفظ المفتاح في كود المصدر أو ملفات الإعدادات العامة.

## 8. أفضل ممارسات التشغيل
- قبل أي عملية رفع، يستدعي `SyncManager` دالة `compareChecksum()` لتحديد الحاجة لإعادة الرفع، مما يقلّل استهلاك البيانات.
- الحقل `lastDeviceId` في `SyncMetadata` يُستخدم لمنع الحلقات (Loop) عند إعادة استيراد نسخة أنتجها نفس الجهاز.
- `SyncAuditDao` يوفّر سجلاً كاملاً للتغييرات والتضاربات، مما يسمح بالاسترجاع أو التدقيق عند الحاجة.
- حافظ على تزامن توقيت الأجهزة (UTC ISO) لأن الخوارزمية تعتمد على `updatedAt` و `deletedAt`.

## 9. اختبار وإطلاق
1. اختبر على جهازين مختلفين مع حساب Google واحد للتأكد من تدفق المزامنة (رفع → إشعار FCM → سحب).
2. راقب السجلات (`SyncAuditDao.fetchRecentLogs`) للتأكد من أن الدمج يعمل من دون تضارب غير محسوب.
3. عند إطلاق التطبيق، تأكد من:
   - تمكين Play Integrity أو SafetyNet عند الضرورة.
   - تحديث سياسات الخصوصية لإيضاح تخزين البيانات على Google Drive.

باتباع الخطوات أعلاه ستحصل على نظام مزامنة آمن وفعال يعتمد على Google Drive و FCM ويعمل في وضع عدم الاتصال مع ضمان عدم فقد البيانات. حرصنا على أن يكون الدليل عربيًا بالكامل لتسهيل الدمج والصيانة داخل بيئة Marina Hotel. بالتوفيق!🥇
