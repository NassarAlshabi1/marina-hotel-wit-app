# Master/Slave Sync — مزامنة متعددة العناوين

## 📋 نظرة عامة

النظام يسمح بإرسال البيانات إلى أكثر من عنوان Appwrite:

- **Master**: نقطة النهاية الرئيسية — تتم عليها المزامنة الكاملة (إرسال + سحب)
- **Slaves**: نقاط نهاية احتياطية — يتم الإرسال إليها فقط (push-only backup)

## 🗂️ الملفات المضافة

| الملف | الوظيفة |
|-------|---------|
| `lib/services/appwrite_backup_endpoint.dart` | نموذج بيانات نقطة النهاية الاحتياطية |
| `lib/services/appwrite_backup_endpoints_manager.dart` | حفظ وتحميل نقاط النهاية من SharedPreferences |
| `lib/services/appwrite_backup_sync_service.dart` | خدمة الإرسال إلى نقاط النهاية الاحتياطية |
| `lib/screens/settings/appwrite_backup_endpoints_screen.dart` | شاشة إدارة نقاط النهاية |

## 🔄 آلية العمل

```
مستخدم → تعديل بيانات ← Outbox
                                    ↓
                            _pushAllEntities()
                                    ↓
                     ┌─── Master Appwrite ────✓
                     │
                     └─── Slaves Appwrite ────✓ (push only)
```

1. التعديلات المحلية تُسجل في `sync_outbox`
2. `_pushAllEntities()` ترسل البيانات إلى **Master** Appwrite (كالمعتاد)
3. بعد نجاح كل دفعة، تُرسل نفس البيانات إلى جميع **Slaves** Appwrite
4. Slaves **لا تسحب** بيانات — فقط push
5. إذا فشل Slaves، يكمل Master عمله دون تأثر

## 🔧 الإعداد

1. افتح التطبيق → الإعدادات → Appwrite
2. اختر **"نقاط النهاية الاحتياطية (Master/Slave)"**
3. أضف نقطة نهاية جديدة:
   - **الاسم**: تسمية توضيحية (مثل: خادم احتياطي)
   - **Endpoint URL**: رابط خادم Appwrite
   - **Project ID**: معرّف المشروع
   - **Database ID**: معرّف قاعدة البيانات
   - **API Key**: مفتاح API (اختياري)
4. اختبر الاتصال قبل الحفظ

## ⚙️ التفاصيل التقنية

- البيانات ترسل بنفس تنسيق Master (نفس `_process*Entry` methods)
- إذا لم يكن المستند موجوداً في Slave، يتم إنشاؤه (upsert)
- العمليات المدعومة: `create`, `update`, `delete`
- فشل Slave لا يؤثر على Master — error handling منفصل
- كل نقطة نهاية يمكن إيقافها/تفعيلها بشكل مستقل
