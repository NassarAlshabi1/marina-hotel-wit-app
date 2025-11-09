# 🌐 دليل إعداد Ditto Cloud Sync

## 📋 نظرة عامة

تم إضافة نظام **Ditto Cloud Sync** للتطبيق كطبقة إضافية للمزامنة السحابية بجانب النظام الحالي المتطور. يستخدم **WebSocket فقط** للاتصال بـ Ditto Cloud بدون اتصال P2P محلي.

---

## 🚀 خطوات الإعداد

### 1. **إنشاء حساب Ditto Cloud**
```
1. اذهب إلى: https://cloud.ditto.live
2. أنشئ حساب جديد
3. أنشئ تطبيق جديد (New App)
4. احصل على App ID من لوحة التحكم
```

### 2. **إنشاء Playground Token**
```
1. في لوحة تحكم التطبيق، اذهب إلى "Authentication"
2. اختر "Playground" للتطوير
3. أنشئ Token جديد
4. انسخ Token للاستخدام
```

### 3. **تحديث إعدادات التطبيق**
```dart
// في mobile/lib/utils/ditto_config.dart

class DittoConfig {
  static const String appId = "YOUR_ACTUAL_APP_ID_HERE";
  static const String playgroundToken = "YOUR_ACTUAL_TOKEN_HERE";
  // باقي الإعدادات تبقى كما هي
}
```

### 4. **تشغيل build_runner**
```bash
cd mobile
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 🔧 الاستخدام العملي

### **الوصول لشاشة إدارة Ditto**
```dart
// من أي مكان في التطبيق:
Navigator.pushNamed(context, '/ditto-sync');

// أو مباشرة:
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => DittoManagementScreen()),
);
```

### **استخدام خدمة Ditto في الكود**
```dart
// في أي ConsumerWidget:
class MyScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // خدمة Ditto
    final dittoService = ref.watch(dittoCloudSyncProvider);
    
    // حالة المزامنة
    final syncStatus = ref.watch(dittoSyncStatusProvider);
    
    // الحجوزات المباشرة
    final liveBookings = ref.watch(dittoLiveBookingsProvider);
    
    return syncStatus.when(
      data: (status) {
        if (status['initialized']) {
          // Ditto جاهز للاستخدام
          return _buildMainContent(liveBookings);
        } else {
          // لم يتم تهيئة Ditto بعد
          return _buildInitializingState();
        }
      },
      loading: () => CircularProgressIndicator(),
      error: (e, _) => Text('خطأ: $e'),
    );
  }
}
```

---

## 📊 العمليات المتاحة

### **إنشاء حجز جديد**
```dart
final dittoService = ref.read(dittoCloudSyncProvider);

final bookingId = await dittoService.createBooking(
  guestName: 'أحمد محمد',
  roomNumber: '101',
  checkinDate: DateTime.now().toIso8601String(),
  checkoutDate: DateTime.now().add(Duration(days: 2)).toIso8601String(),
  totalAmount: 600.0,
  notes: 'حجز عادي',
);
```

### **تحديث حالة حجز**
```dart
await dittoService.updateBookingStatus('booking_123', 'تم الدخول');
```

### **إضافة دفعة**
```dart
final paymentId = await dittoService.createPayment(
  bookingId: 'booking_123',
  amount: 300.0,
  paymentMethod: 'نقدي',
  notes: 'دفعة جزئية',
);
```

### **تحديث حالة غرفة**
```dart
await dittoService.updateRoomStatus('101', 'محجوزة');
```

### **مراقبة البيانات الحية**
```dart
// الحجوزات في الوقت الفعلي
Consumer(
  builder: (context, ref, child) {
    final bookingsStream = ref.watch(dittoLiveBookingsProvider);
    
    return bookingsStream.when(
      data: (bookings) => ListView.builder(
        itemCount: bookings.length,
        itemBuilder: (context, index) {
          final booking = bookings[index];
          return ListTile(
            title: Text(booking['guest_name']),
            subtitle: Text('غرفة ${booking['room_number']}'),
            trailing: Text('${booking['total_amount']} ر.س'),
          );
        },
      ),
      loading: () => CircularProgressIndicator(),
      error: (e, _) => Text('خطأ: $e'),
    );
  },
)
```

---

## 🎛️ إعدادات التكوين

### **إعدادات الأساسية**
```dart
// في DittoConfig
static const bool enableCloudSync = true;     // تفعيل المزامنة السحابية
static const bool enableP2PSync = false;      // تعطيل الاتصال المحلي
static const bool isDevelopment = true;       // وضع التطوير
static const bool enableDebugLogs = true;     // سجلات التشخيص
```

### **إعدادات الأداء**
```dart
static const int syncTimeoutSeconds = 30;      // مهلة المزامنة
static const int maxRetryAttempts = 3;         // محاولات الإعادة
static const int heartbeatIntervalSeconds = 60; // فترة فحص الاتصال
```

### **WebSocket مخصص**
```dart
// إذا كنت تستخدم خادم Ditto خاص
static const String webSocketUrl = "wss://your-custom-ditto-server.com";
```

---

## 🔍 استكشاف الأخطاء

### **خطأ: "Ditto غير مهيء"**
```
السبب: لم يتم استدعاء initialize() بعد
الحل: تأكد من استدعاء dittoService.initialize() في بداية التطبيق
```

### **خطأ: "REPLACE_WITH_YOUR_APP_ID"**
```
السبب: لم يتم تحديث إعدادات DittoConfig
الحل: راجع خطوة 3 في الإعداد واستبدل القيم الصحيحة
```

### **خطأ في الاتصال بـ WebSocket**
```
السبب: مشكلة في الشبكة أو إعدادات Ditto Cloud
الحل: 
1. تحقق من اتصال الإنترنت
2. تأكد من صحة App ID و Token
3. راجع حالة Ditto Cloud Status
```

### **البيانات لا تتزامن**
```
السبب: مشكلة في إعداد الجهاز أو الصلاحيات
الحل:
1. استخدم forceSyncNow() للمزامنة اليدوية
2. تحقق من سجلات التشخيص
3. تأكد من أن جميع الأجهزة تستخدم نفس App ID
```

---

## 📱 اختبار النظام

### **1. اختبار الإعداد**
```
1. افتح التطبيق واذهب إلى شاشة Ditto Management (/ditto-sync)
2. تحقق من أن الحالة تظهر "مُهيّأ: ✅ نعم"
3. تحقق من معرف الجهاز وعنوان WebSocket
```

### **2. اختبار المزامنة**
```
1. اضغط "إنشاء حجز تجريبي"
2. تحقق من ظهور الحجز في القائمة
3. افتح التطبيق على جهاز آخر
4. تحقق من ظهور نفس الحجز
```

### **3. اختبار الوقت الفعلي**
```
1. افتح التطبيق على جهازين
2. أضف حجز من الجهاز الأول
3. يجب أن يظهر الحجز فوراً في الجهاز الثاني بدون refresh
```

---

## ⚖️ مقارنة مع النظام الحالي

| الميزة | النظام الحالي | Ditto Cloud |
|--------|---------------|-------------|
| **المزامنة** | API + Google Drive | WebSocket Cloud |
| **الوقت الفعلي** | ❌ محدود | ✅ مباشر |
| **الاستعلامات** | SQL محلي | DQL (Ditto Query Language) |
| **التضارب** | حل يدوي | ✅ تلقائي |
| **الشبكة** | HTTP REST | WebSocket |
| **التعقيد** | متوسط | بسيط |

---

## 🎯 الخلاصة

✅ **تم الإعداد بنجاح:** نظام Ditto جاهز للاستخدام كطبقة إضافية  
✅ **WebSocket فقط:** لا يوجد اتصال P2P محلي كما طلبت  
✅ **مزامنة حية:** البيانات تتحدث في الوقت الفعلي بين الأجهزة  
✅ **سهولة الاستخدام:** APIs بسيطة ومباشرة  
✅ **متوافق مع النظام الحالي:** يعمل بجانب النظام الموجود بدون تضارب  

🚀 **الآن يمكنك الاستفادة من قوة Ditto Cloud للمزامنة الفورية!**