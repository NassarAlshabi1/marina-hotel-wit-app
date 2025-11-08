# إعدادات Ditto - المزامنة عبر الإنترنت فقط 🌐

## التغييرات الجديدة ✅

تم تعديل إعدادات Ditto لتعمل **فقط عبر الإنترنت** (Cloud Sync) بدون اتصالات P2P المباشرة.

---

## وضع المزامنة الحالي

### ✅ مُفعّل:
- **WebSocket to Big Peer** - المزامنة السحابية عبر الإنترنت
- **Cloud Sync** - المزامنة عبر خوادم Ditto

### ❌ مُعطّل:
- **Bluetooth LE** - الاتصال عبر البلوتوث بين الأجهزة
- **LAN Discovery** - الاتصال عبر WiFi Direct / LAN المحلية
- **AWDL** - بروتوكول Apple للاتصال المباشر (iOS)

---

## كيف يعمل الآن؟

### السيناريو 1: جهازان متصلان بالإنترنت
```
الجهاز 1 ←→ الإنترنت ←→ Big Peer (Cloud) ←→ الإنترنت ←→ الجهاز 2
```
✅ **تعمل المزامنة** - كلا الجهازين يتصلان بـ Big Peer ويتزامنان

### السيناريو 2: جهاز واحد متصل بالإنترنت
```
الجهاز 1 ←→ الإنترنت ←→ Big Peer (Cloud)
الجهاز 2 (offline) ❌
```
✅ **الجهاز 1 يتزامن مع السحابة**  
⏸️ **الجهاز 2 ينتظر الاتصال بالإنترنت**

### السيناريو 3: جهازان بدون إنترنت (في نفس المكان)
```
الجهاز 1 ❌ (offline)
الجهاز 2 ❌ (offline)
```
❌ **لا تعمل المزامنة** - لا يوجد اتصال بالإنترنت ولا P2P

---

## المزايا الجديدة

### 1. 🔋 توفير البطارية
- لا يوجد Bluetooth scanning مستمر
- لا يوجد WiFi discovery
- استهلاك أقل للطاقة

### 2. 🔒 أذونات أقل
- لا حاجة لأذونات Bluetooth
- لا حاجة لأذونات Location (المطلوبة لـ Bluetooth)
- لا حاجة لأذونات Nearby Devices

### 3. 📶 أبسط للمستخدم
- يعمل فقط مع الإنترنت
- لا حاجة لتفعيل Bluetooth
- لا حاجة لتفعيل Location

### 4. 🚀 أداء أفضل
- بدء أسرع للتطبيق (لا Bluetooth scanning)
- استهلاك أقل للذاكرة
- استقرار أكثر

---

## الكود المُطبّق

### `mobile/lib/utils/ditto_config.dart`

```dart
_instance!.updateTransportConfig((config) {
  // ⚠️ تعطيل جميع اتصالات P2P (Peer-to-Peer)
  // المزامنة فقط عبر الإنترنت (Cloud Sync)
  config.peerToPeer.bluetoothLE.isEnabled = false;
  config.peerToPeer.lan.isEnabled = false;
  config.peerToPeer.awdl.isEnabled = false;
  
  // فقط WebSocket للمزامنة السحابية
  config.connect = Connect(webSocketUrls: {bigPeerUrl});
});
```

---

## متى تحدث المزامنة؟

### ✅ تحدث فوراً عندما:
1. الجهاز متصل بالإنترنت
2. التطبيق مفتوح أو في الخلفية
3. يتم إجراء تغيير على البيانات

### ⏸️ تُؤجّل عندما:
1. الجهاز غير متصل بالإنترنت
2. التطبيق مغلق تماماً

### 🔄 تُستأنف تلقائياً عندما:
1. يعود الاتصال بالإنترنت
2. يُفتح التطبيق مرة أخرى

---

## الفرق بين الوضع السابق والحالي

| الميزة | الوضع السابق | الوضع الحالي |
|--------|---------------|---------------|
| **المزامنة عبر الإنترنت** | ✅ تعمل | ✅ تعمل |
| **المزامنة بدون إنترنت (P2P)** | ✅ تعمل | ❌ معطّلة |
| **استهلاك البطارية** | متوسط-عالي | منخفض |
| **الأذونات المطلوبة** | متعددة | قليلة |
| **سرعة البدء** | بطيئة | سريعة |
| **التعقيد** | معقد | بسيط |

---

## إعادة تفعيل P2P (إذا لزم الأمر)

إذا أردت إعادة تفعيل P2P مستقبلاً:

```dart
// في ditto_config.dart
_instance!.updateTransportConfig((config) {
  // تفعيل P2P
  config.peerToPeer.bluetoothLE.isEnabled = true;  // ✅
  config.peerToPeer.lan.isEnabled = true;          // ✅
  config.peerToPeer.awdl.isEnabled = true;         // ✅
  
  config.connect = Connect(webSocketUrls: {bigPeerUrl});
});
```

وأضف الأذونات في `AndroidManifest.xml`:
```xml
<!-- Bluetooth -->
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />

<!-- Location (مطلوب لـ Bluetooth في Android) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />

<!-- WiFi -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" />
```

---

## الاختبار

### 1. اختبار المزامنة عبر الإنترنت
```bash
# سيناريو:
1. افتح التطبيق على جهازين مختلفين
2. تأكد من اتصال كلا الجهازين بالإنترنت
3. أضف/عدّل بيانات على الجهاز 1
4. راقب الجهاز 2 - يجب أن تظهر التغييرات تلقائياً
```

### 2. اختبار عدم وجود P2P
```bash
# سيناريو:
1. ضع جهازين في نفس المكان (نفس الشبكة المحلية)
2. افصل الإنترنت عن كلا الجهازين
3. أضف/عدّل بيانات على الجهاز 1
4. الجهاز 2 لن يرى التغييرات ❌ (متوقع - لا P2P)
5. أعد الاتصال بالإنترنت
6. ستحدث المزامنة تلقائياً ✅
```

### 3. راقب Logs
```bash
adb logcat | grep -E "(Ditto|P2P|Big Peer)"
```

**المتوقع:**
```
🌐 Connected to Big Peer (Internet-only mode): wss://...
⚠️ P2P disabled: Bluetooth, LAN, and AWDL are off
```

---

## الخلاصة

✅ **تم بنجاح:**
- تعطيل جميع اتصالات P2P
- الإبقاء على المزامنة عبر الإنترنت فقط
- تقليل استهلاك البطارية
- تبسيط الأذونات

⚠️ **لاحظ:**
- الأجهزة بحاجة للإنترنت للمزامنة
- لا مزامنة مباشرة بين الأجهزة بدون إنترنت

---

**آخر تحديث:** 8 نوفمبر 2025  
**الفرع:** `capy/ditto-9df06d06`  
**Commit:** `1c1d222`
