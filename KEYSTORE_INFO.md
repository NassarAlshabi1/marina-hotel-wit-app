# Keystore Setup Instructions (P0-1 FIX)

> ⚠️ **تنبيه أمني حرج**: في 2026-08-06، اكتُشف أن ملفات `release.keystore` و
> `key.properties` كانت ملتزمة في git بنص صريح. تم إزالتها من git tracking.
> **يجب تدوير keystore فوراً** قبل أي إصدار جديد.

## الخطوات المطلوبة

### 1. توليد keystore جديد

```bash
keytool -genkey -v -keystore release.keystore -alias release \
  -keyalg RSA -keysize 2048 -validity 36500 \
  -storepass <NEW_STRONG_PASSWORD> \
  -keypass <NEW_STRONG_PASSWORD> \
  -dname "CN=Marina Hotel, OU=Mobile, O=Aden Hotel, L=Aden, ST=Aden, C=YE"
```

### 2. إنشاء `key.properties`

```properties
storePassword=<NEW_STRONG_PASSWORD>
keyPassword=<NEW_STRONG_PASSWORD>
keyAlias=release
storeFile=release.keystore
```

### 3. وضع الملفات في الموقع الصحيح

```
mobile/android/app/release.keystore   ← keystore binary
mobile/android/key.properties          ← passwords (لا تُلتزم في git)
```

### 4. تحديث SHA-1 في Firebase Console

بعد توليد keystore جديد، احصل على SHA-1:

```bash
keytool -list -v -keystore release.keystore -alias release \
  -storepass <NEW_STRONG_PASSWORD> | grep SHA1
```

أضف SHA-1 الجديد إلى:
- Firebase Console → Project Settings → Your apps → Android app → SHA certificate fingerprint
- Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client IDs

### 5. CI/CD (GitHub Actions)

في GitHub repository، أضف secrets:
- `KEYSTORE_BASE64` — `base64 release.keystore`
- `KEYSTORE_PASSWORD` — كلمة مرور الـ keystore
- `KEY_ALIAS` — `release`
- `KEY_PASSWORD` — كلمة مرور المفتاح

في CI workflow، أضف خطوة لاستعادة الـ keystore:

```yaml
- name: Decode keystore
  run: |
    echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > mobile/android/app/release.keystore
    echo "storePassword=${{ secrets.KEYSTORE_PASSWORD }}" > mobile/android/key.properties
    echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> mobile/android/key.properties
    echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> mobile/android/key.properties
    echo "storeFile=release.keystore" >> mobile/android/key.properties
```

### 6. إجبار إعادة تثبيت التطبيق

تغيير الـ keystore يعني أن الـ APK الجديد لا يمكنه تحديث الـ APK القديم.
المستخدمون الحاليون يجب أن:
1. يُلغوا تثبيت التطبيق القديم
2. يُثبّتوا الـ APK الجديد

أو استخدم `applicationIdSuffix` مؤقتاً للإصدار الجديد للسماح بالتثبيت جنباً إلى جنب.

---

## التحقق

بعد تنفيذ الخطوات أعلاه، تأكد من:
- [ ] `git status` لا يُظهر `release.keystore` أو `key.properties`
- [ ] `flutter build apk --release` ينجح بالـ keystore الجديد
- [ ] SHA-1 الجديد مُسجّل في Firebase و Google Cloud
- [ ] CI/CD يحمّل الـ keystore من secrets
