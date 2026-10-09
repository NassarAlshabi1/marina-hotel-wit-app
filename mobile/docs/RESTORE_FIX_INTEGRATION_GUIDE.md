# دليل تكامل خدمة الإصلاح التلقائي للنسخة الاحتياطية
## Post-Restore Auto-Fix Integration Guide

---

## نظرة عامة

خدمة `RestoreFixService` هي خدمة قوية ومتكاملة تعمل تلقائياً بعد استعادة أي نسخة احتياطية لضمان اتساق البيانات. تقوم الخدمة بإعادة حساب الليالي، تحديث حالات الغرف، والتحقق من المدفوعات تلقائياً.

### المشاكل التي تحلها الخدمة:
- **عدم اتساق الليالي**: إعادة حساب دقيق للليالي وفقاً لقاعدة الساعة 14:00
- **حالات الغرف الخاطئة**: تحديث حالة الغرف بناءً على الحجوزات النشطة
- **عدم تطابق المدفوعات**: اكتشاف الفروق بين المدفوع والمطلوب دون تعديل تلقائي
- **فقدان البيانات**: آلية حماية متقدمة مع لقطات احتياطية آمنة

---

## متى يتم تشغيل الخدمة

### 1. التشغيل التلقائي
تعمل الخدمة تلقائياً بعد العمليات التالية:

```dart
// في BackupStatusNotifier - بعد استعادة نسخة Google Drive
await _backupService.restoreFromBackup(downloaded);
final fixService = RestoreFixService(DatabaseManager.instance);
final fixReport = await fixService.runAutoFixAfterRestore();

// في BackupStatusNotifier - بعد استعادة نسخة محلية
await _localBackupService.restoreFromLocalBackup(filePath);
final fixService = RestoreFixService(DatabaseManager.instance);
final fixReport = await fixService.runAutoFixAfterRestore();

// في BackupStatusNotifier - بعد استعادة ملف SQLite
await SqliteBackupRestore.restoreDatabase(sourcePath);
final fixService = RestoreFixService(DatabaseManager.instance);
final fixReport = await fixService.runAutoFixAfterRestore();
```

### 2. التشغيل اليدوي
يمكن تشغيل الخدمة يدوياً من شاشة الإعدادات:

```dart
// إنشاء مثيل الخدمة
final service = RestoreFixService(DatabaseManager.instance);

// تشغيل الإصلاح
final report = await service.runAutoFixAfterRestore();

// فحص النتيجة
if (report.success) {
  print('✅ نجح الإصلاح: ${report.bookingsFixed} حجز، ${report.roomsUpdated} غرفة');
} else {
  print('❌ فشل الإصلاح: ${report.error}');
}
```

---

## كيفية الوصول للواجهة اليدوية

### 1. إضافة الشاشة للتطبيق

```dart
// في ملف routes/app_router.dart أو main.dart
import 'package:marina_hotel_mobile/screens/settings/restore_fix_screen.dart';

// إضافة المسار
MaterialPageRoute(
  builder: (context) => const RestoreFixScreen(),
)
```

### 2. إضافة زر في قائمة الإعدادات

```dart
// في screens/settings/settings_screen.dart
ListTile(
  leading: const Icon(Icons.build_circle, color: Colors.blue),
  title: const Text('الإصلاح التلقائي للنسخة الاحتياطية'),
  subtitle: const Text('تشغيل وعرض سجلات الإصلاح'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RestoreFixScreen()),
    );
  },
)
```

### 3. استخدام المقدمات (Providers)

```dart
// في الملف الرئيسي أو providers/core_providers.dart
import 'package:marina_hotel_mobile/screens/settings/restore_fix_screen.dart';

// استخدام المقدمات
final restoreFixService = ref.read(restoreFixServiceProvider);
final lastReport = ref.watch(lastFixReportProvider);
final fixLogs = ref.watch(fixLogsProvider);
```

---

## عرض سجلات الإصلاح

### 1. عرض السجلات في الواجهة

```dart
class FixLogsWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fixLogsAsyncValue = ref.watch(fixLogsProvider);
    
    return fixLogsAsyncValue.when(
      data: (logs) => ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) {
          final log = logs[index];
          return ListTile(
            title: Text(log.reason),
            subtitle: Text('${log.targetTable} - ${log.fieldName}'),
            trailing: Text(_formatDateTime(
              DateTime.fromMillisecondsSinceEpoch(log.executedAt * 1000)
            )),
          );
        },
      ),
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => Text('خطأ: $error'),
    );
  }
}
```

### 2. تصدير السجلات كـ JSON

```dart
// تصدير ومشاركة السجلات
Future<void> exportAndShareLogs() async {
  final service = RestoreFixService(DatabaseManager.instance);
  final jsonData = await service.exportFixLogsAsJson();
  
  final directory = await getApplicationCacheDirectory();
  final file = File('${directory.path}/fix_logs.json');
  await file.writeAsString(jsonEncode(jsonData));
  
  await Share.shareXFiles([XFile(file.path)]);
}
```

### 3. البحث في السجلات بحسب معرف الإصلاح

```dart
// عرض سجلات عملية إصلاح محددة
Future<List<RestoreFixLogData>> getFixLogsByFixId(String fixId) async {
  final service = RestoreFixService(DatabaseManager.instance);
  return await service.getFixLogs(fixId: fixId);
}
```

---

## استكشاف المشاكل الشائعة

### 1. فشل تحديث الليالي

**المشكلة**: الليالي لا تتحدث بشكل صحيح

**الحلول**:
```dart
// التحقق من صيغة التاريخ
final checkinDate = DateTime.parse(booking.checkinDate); // قد يفشل
```

**الحل الأمثل**:
```dart
// استخدام دالة آمنة لتحليل التاريخ
DateTime? parseDate(String? dateString) {
  if (dateString == null || dateString.isEmpty) return null;
  try {
    return DateTime.parse(dateString);
  } catch (e) {
    debugPrint('خطأ في تحليل التاريخ: $dateString');
    return null;
  }
}
```

### 2. خطأ في الوصول لقاعدة البيانات

**المشكلة**: 
```
DatabaseException: database is locked
```

**الحل**:
```dart
// استخدم DatabaseManager لإدارة الاتصالات
final db = DatabaseManager.instance; // ✅ صحيح
// بدلاً من
final db = AppDatabase(); // ❌ خطأ - اتصال جديد
```

### 3. نفاد المساحة أثناء إنشاء اللقطة

**المشكلة**: 
```
FileSystemException: No space left on device
```

**الحل**:
```dart
// فحص المساحة المتاحة قبل الإنشاء
Future<bool> hasEnoughSpace() async {
  final directory = await getApplicationCacheDirectory();
  final stat = await directory.stat();
  return stat.size < 100 * 1024 * 1024; // 100 MB
}
```

### 4. بطء في الأداء مع بيانات كبيرة

**المشكلة**: الإصلاح يستغرق وقتاً طويلاً

**الحل الأمثل**:
```dart
// معالجة البيانات على دفعات
Future<void> processBookingsInBatches(List<Booking> bookings) async {
  const batchSize = 50;
  for (int i = 0; i < bookings.length; i += batchSize) {
    final batch = bookings.skip(i).take(batchSize);
    await _processBatch(batch);
    
    // إعطاء فرصة للواجهة للتحديث
    await Future.delayed(const Duration(milliseconds: 10));
  }
}
```

### 5. تضارب في التحديثات المتزامنة

**المشكلة**: 
```
UNIQUE constraint failed: bookings.local_uuid
```

**الحل**:
```dart
// استخدم المعاملات لضمان الاتساق
await db.transaction(() async {
  // جميع العمليات هنا ذرية
  await _fixBookingDatesAndNights(booking);
  await _updateRoomStatus(booking.roomNumber);
});
```

---

## توقعات الأداء

### المعايير المستهدفة:
- **< 5 ثوان** لـ 1000 حجز
- **< 50 MB** استخدام ذاكرة إضافية
- **> 80%** تغطية اختبارات
- **0%** فقدان بيانات

### نصائح الأداء:

#### 1. تحسين الاستعلامات
```dart
// ✅ محسن - فهرسة وتصفية
final query = db.select(db.bookings)
  ..where((b) => b.deletedAt.isNull())
  ..where((b) => b.status.isIn(['محجوزة', 'active']))
  ..limit(100);

// ❌ بطيء - تحميل جميع البيانات
final allBookings = await db.select(db.bookings).get();
final filtered = allBookings.where((b) => b.deletedAt == null);
```

#### 2. المعالجة المتوازية (عند الإمكان)
```dart
// معالجة متوازية للعمليات المستقلة
await Future.wait([
  _updateRoomStatuses(),
  _validatePayments(),
  _cleanupOldLogs(),
]);
```

#### 3. تنظيف الذاكرة
```dart
// تنظيف دوري للملفات المؤقتة
Future<void> cleanupTempFiles() async {
  final directory = await getApplicationCacheDirectory();
  final files = directory.listSync()
    .where((file) => file.path.contains('restore_snapshot'))
    .where((file) => file.statSync().modified
      .isBefore(DateTime.now().subtract(const Duration(hours: 24))));
  
  for (final file in files) {
    await file.delete();
  }
}
```

---

## مثال كامل للتكامل

### ملف: `lib/services/backup_integration.dart`

```dart
import 'package:flutter/foundation.dart';
import 'local_db.dart';
import 'restore_fix_service.dart';

class BackupIntegration {
  static Future<void> runPostRestoreFix({
    required String context, // 'google_drive', 'local', 'sqlite'
    DateTime? backupTimestamp,
  }) async {
    debugPrint('🔄 بدء الإصلاح التلقائي - السياق: $context');
    
    try {
      final service = RestoreFixService(DatabaseManager.instance);
      final report = await service.runAutoFixAfterRestore(
        backupTimestamp: backupTimestamp,
      );
      
      if (report.success) {
        debugPrint('✅ اكتمل الإصلاح بنجاح');
        debugPrint('📊 النتائج:');
        debugPrint('   - الحجوزات: ${report.bookingsFixed}');
        debugPrint('   - الغرف: ${report.roomsUpdated}');
        debugPrint('   - المدفوعات: ${report.paymentsRecalculated}');
        debugPrint('   - المدة: ${report.durationMs}ms');
        
        // إرسال تحليلات (اختياري)
        _sendAnalytics('restore_fix_success', {
          'context': context,
          'bookings_fixed': report.bookingsFixed,
          'duration_ms': report.durationMs,
        });
        
      } else {
        debugPrint('❌ فشل الإصلاح: ${report.error}');
        
        // تسجيل خطأ تفصيلي
        _logError('restore_fix_failed', report.error, {
          'context': context,
          'duration_ms': report.durationMs,
        });
      }
      
    } catch (e, stack) {
      debugPrint('💥 خطأ حرج في الإصلاح التلقائي: $e');
      debugPrint('Stack trace: $stack');
      
      // تسجيل خطأ حرج
      _logError('restore_fix_critical', e.toString(), {
        'context': context,
        'stack_trace': stack.toString(),
      });
    }
  }
  
  static void _sendAnalytics(String event, Map<String, dynamic> parameters) {
    // تنفيذ إرسال التحليلات حسب الحاجة
    debugPrint('📊 Analytics: $event - $parameters');
  }
  
  static void _logError(String error, String? message, Map<String, dynamic> context) {
    // تنفيذ تسجيل الأخطاء حسب الحاجة
    debugPrint('🚨 Error Log: $error - $message - $context');
  }
}
```

### الاستخدام في الكود:

```dart
// في backup_provider.dart
await _backupService.restoreFromBackup(downloaded);

// استدعاء الإصلاح التلقائي
await BackupIntegration.runPostRestoreFix(
  context: 'google_drive',
  backupTimestamp: backupMetadata.createdAt,
);
```

---

## قائمة التحقق للتكامل

### قبل الإنتاج:
- [ ] تشغيل `dart run build_runner build` لتوليد كود Drift
- [ ] تشغيل الاختبارات: `flutter test test/restore_fix_service_test.dart`
- [ ] فحص تغطية الاختبارات > 80%
- [ ] اختبار مع بيانات حقيقية كبيرة (>1000 حجز)
- [ ] التحقق من أداء الذاكرة والسرعة
- [ ] اختبار آلية الاستعادة عند الفشل
- [ ] اختبار التشغيل اليدوي من الواجهة
- [ ] التحقق من ترجمة الرسائل والتسميات
- [ ] فحص التوافق مع إصدارات مختلفة من قاعدة البيانات

### بعد النشر:
- [ ] مراقبة أداء الخدمة في الإنتاج
- [ ] تحليل تقارير الأخطاء والاستثناءات
- [ ] جمع ملاحظات المستخدمين
- [ ] تحديث التوثيق بناء على التجربة الفعلية

---

## الدعم والصيانة

### ملفات لوج مهمة:
- `fix_logs_*.json` - سجلات الإصلاح المصدرة
- `restore_snapshot_*.json` - اللقطات الاحتياطية
- `flutter_logs` - سجلات التطبيق العامة

### الاتصال والدعم:
لأي مشاكل أو استفسارات، يرجى:
1. فحص السجلات أولاً
2. تشغيل الاختبارات للتحقق من سلامة الكود  
3. إنشاء تقرير مفصل يتضمن:
   - خطوات إعادة المشكلة
   - سجلات الأخطاء
   - بيئة التشغيل (إصدار التطبيق، نوع الجهاز، إلخ)

### تحديثات مستقبلية:
- تحسين خوارزمية حساب الليالي
- إضافة خيارات تخصيص قواعد الإصلاح
- تحسين واجهة عرض السجلات
- إضافة تقارير تحليلية متقدمة

---

**تاريخ التحديث الأخير**: نوفمبر 2024
**إصدار التوثيق**: 1.0.0
**التوافق**: Flutter 3.24.0+, Drift 2.20.0+