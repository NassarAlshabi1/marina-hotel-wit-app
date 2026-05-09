# Appwrite Rooms Import Script

استيراد جميع الغرف إلى Appwrite وإنشاء mapping بين `localUuid` و `serverId`.

## ✅ Setup

```bash
npm install node-appwrite
```

## 🔑 Get API Key

1. افتح [Appwrite Console](https://cloud.appwrite.io/console/project-690ff0da0025518570c1)
2. اذهب إلى **Settings** → **API Keys**
3. أنشئ مفتاح جديد بالصلاحيات التالية:
   - `databases.read`
   - `databases.write`
   - Scopes: `hotel_db.rooms`

## 🚀 Run Import

```bash
APPWRITE_API_KEY=your_api_key_here node scripts/appwrite_import_rooms.js
```

## 📤 Output Files

- `scripts/rooms_mapping.json` - الـ mapping بين `localUuid` → `serverId`
- `scripts/rooms_import_errors.json` - الأخطاء إن وجدت

## 📊 Expected Result

```
✅ Success: 19/19
❌ Failed: 0/19

🎉 All rooms imported successfully!
```

## 🔄 Next Steps After Import

1. استخدم `rooms_mapping.json` لتحديث قاعدة البيانات المحلية:
   ```sql
   UPDATE rooms SET serverId = ? WHERE localUuid = ?
   ```
2. إعادة تشغيل المزامنة من التطبيق
3. التحقق من اختفاء أخطاء 404

## ⚠️ Notes

- السكربت يستخدم `createDocument` فقط (لا يوجد update)
- الـ Document IDs سيتم إنشاؤها تلقائياً
- `localUuid` سيُخزن كحقل داخل المستند
