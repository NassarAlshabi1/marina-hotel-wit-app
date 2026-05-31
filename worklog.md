---
Task ID: 1
Agent: Main Agent
Task: تشغيل الإصلاح الشامل تلقائياً بعد سحب البيانات من Appwrite عند التثبيت الأول

Work Log:
- قراءة وفهم تدفق سحب البيانات من Appwrite في tools_tab.dart
- تعديل _pullFullBackupFromAppwrite() لإضافة:
  - تشغيل runComprehensiveFix تلقائياً بعد سحب البيانات
  - تحديث نص حوار التأكيد ليوضح أن المعالجة ستتم تلقائياً
  - تغيير نص زر المتابعة من "سحب البيانات" إلى "متابعة"
  - عرض نتائج السحب والمعالجة في نافذة واحدة مع تفاصيل الإصلاح
- إضافة استيرادات local_db.dart و restore_fix_service.dart
- إضافة _buildFixChip helper widget لعرض نتائج الإصلاح
- تشغيل flutter analyze - لا أخطاء (0 errors)
- الدفع إلى فرع marina على GitHub

Stage Summary:
- تم التعديل على: mobile/lib/screens/settings/appwrite/tabs/tools_tab.dart
- عند الضغط على "متابعة" في شاشة سحب البيانات، يتم:
  1. سحب جميع البيانات من Appwrite Cloud
  2. تشغيل الإصلاح الشامل تلقائياً (runComprehensiveFix)
  3. إعادة حساب الليالي الفعلية بقاعدة 14:00
  4. إعادة حساب المدفوعات والمتبقي
  5. إعادة حساب الديون
  6. إعادة بناء سجلات booking_nights
  7. عرض نتيجة السحب والمعالجة في نافذة واحدة
- Commit: 090b22f3
- Pushed to origin/marina
