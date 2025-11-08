# 🚀 دليل البدء السريع - Ditto
## Marina Hotel - Quick Start Guide

---

## 📱 التثبيت

### 1. تثبيت المكتبات
```bash
cd mobile
flutter pub get
```

### 2. التشغيل
```bash
flutter run
```

---

## ⚙️ الإعدادات

### بيانات حساب Ditto

تم تكوين التطبيق بالفعل ببيانات حسابك:

```dart
✅ App ID: 1507d904-d3ed-4ac3-824c-249c18170eee
✅ Playground Token: dbae5191-2cb5-4fb5-8aca-9f9d85e0409a
✅ Big Peer URL: wss://i83inp.cloud.dittolive.app/1507d904-d3ed-4ac3-824c-249c18170eee
```

---

## 🔄 كيف تعمل المزامنة؟

### 1. **عند تشغيل التطبيق**
```dart
✅ تهيئة Ditto تلقائياً
✅ الاتصال بـ Big Peer
✅ بدء Live Queries
✅ البحث عن أجهزة قريبة (P2P)
```

### 2. **عند إضافة/تعديل بيانات**
```dart
✅ حفظ في Drift (محلي)
✅ إضافة للـ Outbox
✅ المزامنة مع Ditto
✅ نشر للأجهزة الأخرى
```

### 3. **عند استلام تحديث**
```dart
✅ استلام من Ditto
✅ تطبيق على Drift
✅ تحديث UI تلقائياً
```

---

## 📊 مراقبة الاتصال

### من كود التطبيق:

```dart
// الحصول على حالة Ditto
final status = await DittoConfig.getDetailedStatus();
print('Status: $status');

// الحصول على الأجهزة المتصلة
final peers = await DittoConfig.getCurrentPeers();
print('Peers: ${peers.length}');
```

---

## 🎯 السيناريوهات المدعومة

### ✅ سيناريو 1: جهاز واحد + إنترنت
```
📱 جهازك ← Big Peer ← ☁️ Ditto Cloud
```

### ✅ سيناريو 2: جهازين + إنترنت
```
📱 جهاز 1 ← Big Peer ← 📱 جهاز 2
```

### ✅ سيناريو 3: جهازين + نفس الشبكة (بدون إنترنت)
```
📱 جهاز 1 ↔️ WiFi Direct ↔️ 📱 جهاز 2
```

### ✅ سيناريو 4: جهازين + Bluetooth
```
📱 جهاز 1 ↔️ Bluetooth LE ↔️ 📱 جهاز 2
```

---

## 🧪 اختبار المزامنة

### اختبار 1: المزامنة الأساسية

1. قم بتشغيل التطبيق على جهازين
2. أضف غرفة جديدة على الجهاز الأول
3. تحقق من ظهورها على الجهاز الثاني فوراً

### اختبار 2: Offline Mode

1. قم بإيقاف الإنترنت على الجهازين
2. ضعهما على نفس شبكة WiFi
3. أضف بيانات على أحد الجهازين
4. تحقق من المزامنة التلقائية عبر WiFi

### اختبار 3: Conflict Resolution

1. قم بإيقاف الإنترنت على الجهازين
2. عدّل نفس السجل على الجهازين بقيم مختلفة
3. وصّل الجهازين بالإنترنت
4. تحقق من حل التعارض تلقائياً

---

## 📈 مراقبة الأداء

### الإحصائيات المتاحة:

```dart
// إحصائيات Sync
final syncService = ref.read(dittoSyncServiceProvider);
final syncStats = syncService.getPerformanceStats();
print('Sync Stats: $syncStats');

// إحصائيات Realtime
final realtimeService = ref.read(dittoRealtimeServiceProvider);
final realtimeStats = realtimeService.getStats();
print('Realtime Stats: $realtimeStats');
```

---

## 🐛 حل المشاكل الشائعة

### المشكلة 1: "Ditto not initialized"

**الحل:**
```dart
await DittoConfig.initialize();
```

### المشكلة 2: "No peers connected"

**الأسباب المحتملة:**
- الأجهزة ليست على نفس الشبكة
- Bluetooth معطل
- الإنترنت معطل (إذا كان Big Peer مطلوب)

**الحل:**
- تحقق من الاتصال بالإنترنت
- تحقق من إذن Bluetooth
- تحقق من إذن الموقع (مطلوب لـ Bluetooth)

### المشكلة 3: "Sync not working"

**الحل:**
```dart
// مزامنة يدوية
final syncService = ref.read(dittoSyncServiceProvider);
await syncService.runSync();
```

---

## 📚 موارد إضافية

- [دليل التحويل الكامل](./DITTO_MIGRATION_GUIDE.md)
- [Ditto Documentation](https://docs.ditto.live)
- [Ditto Portal](https://portal.ditto.live)

---

## ✅ قائمة التحقق

قبل الانتشار (Production):

- [ ] تم اختبار المزامنة بين جهازين
- [ ] تم اختبار Offline Mode
- [ ] تم اختبار P2P Sync
- [ ] تم اختبار Conflict Resolution
- [ ] تم اختبار على شبكات مختلفة
- [ ] تم اختبار على Android و iOS
- [ ] تم التحقق من الأداء
- [ ] تم التحقق من استهلاك البطارية
- [ ] تم عمل نسخة احتياطية من البيانات
- [ ] تم توثيق التغييرات

---

**إصدار:** 2.0.0  
**التاريخ:** نوفمبر 2025  
**الحالة:** ✅ جاهز للاستخدام
