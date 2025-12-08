# Marina Hotel App - Unified Keystore Configuration

## ✅ SHA Fingerprint الثابت - لا يتغير مع كل بناء

### **SHA-1 الثابت للجميع البناءات:**
```
67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C
```

### **SHA-256 الثابت:**
```
43:02:86:37:79:43:58:F9:FC:B2:74:C7:94:BE:66:0B:F0:44:F4:C6:29:EB:0B:CA:AD:19:EA:3A:EE:AB:8B:54
```

## Keystore Details
- **Location**: `mobile/android/app/release.keystore`
- **Key Properties**: `mobile/android/key.properties`
- **Type**: JKS (Java KeyStore)
- **Algorithm**: RSA-2048
- **Validity**: 10,000 days
- **Created**: October 26, 2025

## Unified Signing Configuration
- **Store Password**: `Marina2025SecureKey`
- **Key Alias**: `marina-hotel-app` (نفس الـ alias لجميع البناءات)
- **Key Password**: `Marina2025SecureKey`

## Certificate Subject
```
CN=Marina Hotel App, OU=IT, O=Marina Hotel, L=Riyadh, ST=Riyadh, C=SA
```

## Available Aliases (في نفس الـ keystore)
1. **marina-hotel-app** (الرئيسي - يُستخدم لجميع البناءات)
   - SHA-1: `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`
   
2. **marina-hotel-debug** (متاح للاستخدام المستقبلي)
   - SHA-1: `77:33:FE:C9:51:20:05:42:06:2C:16:8E:F3:12:57:C7:52:09:D0:39`
   
3. **marina-hotel-staging** (متاح للاستخدام المستقبلي)
   - SHA-1: `95:60:5D:89:63:32:5A:B3:03:B6:57:37:D6:42:69:E5:A3:31:4A:4F`

## Build Types
- **Debug APK**: `flutter build apk --debug` - يستخدم نفس الـ SHA الثابت
- **Staging APK**: `flutter build apk --release` - يستخدم نفس الـ SHA الثابت  
- **Release APK**: `flutter build apk --release` - يستخدم نفس الـ SHA الثابت

## للخدمات الخارجية
استخدم هذا الـ SHA-1 في:
- **Google Play Console**: `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`
- **Firebase**: `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`
- **Google APIs**: `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`
- **Facebook SDK**: `67:12:57:A2:9B:53:FA:71:AC:BC:0F:A8:C9:54:2F:3F:46:0B:A8:1C`

## GitHub Actions Workflows
- جميع workflows تستخدم الآن keystore واحد من الريبو
- لا حاجة لـ base64 decoding أو GitHub secrets
- الـ SHA ثابت لجميع الأصدارات (debug, staging, release)

## الفوائد
✅ **SHA ثابت**: لا يتغير مع كل بناء  
✅ **إعداد بسيط**: keystore واحد، alias واحد  
✅ **توافق كامل**: يعمل مع جميع الخدمات  
✅ **لا أسرار**: keystore محفوظ في الريبو بأمان  
✅ **Java 17 متوافق**: يعمل مع أحدث إصدارات Java