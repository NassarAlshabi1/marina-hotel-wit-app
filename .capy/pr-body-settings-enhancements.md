# تحسينات شاشة الإعدادات (mobile)

هذا الفرع يضيف تحسينات مطلوبة دون تعديل شاشة المستخدمين:

- ربط عداد المستخدمين بمصدر بيانات فعلي من AuthLocalStore بدل القيمة الثابتة.
- إضافة تبديل المظهر الداكن مع حفظ الحالة في SharedPreferences وتطبيقه على مستوى التطبيق.
- تحسين نافذة "تقارير النظام" لعرض حالة النسخ الاحتياطي وحجم قاعدة البيانات وآخر أوقات النسخ (محلي/سحابي).
- إضافة زر "حذف الضيف وجميع البيانات" داخل إدارة الضيوف مع حذف متسلسل لكل ما يرتبط بالضيف (حجوزات، مدفوعات، ملاحظات، ديون).

## التغييرات الرئيسية

- mobile/lib/services/auth_local_store.dart
  - إضافة دوال getAllUsernames و getUsersCount لاستخراج عدد المستخدمين من الحسابات الثابتة + أي مستخدمين محفوظين في الصلاحيات.
- mobile/lib/services/providers.dart
  - إضافة usersCountProvider لتمرير العدد إلى الواجهة.
- mobile/lib/screens/settings/settings_screen.dart
  - استبدال قيمة المستخدمين الثابتة بقراءة usersCountProvider.
  - تفعيل نافذة إعدادات التطبيق لتغيير المظهر الداكن عبر themeSettingsProvider.
  - تطوير نافذة "تقارير النظام" لتعرض: حالة تسجيل Google Drive، عدد النسخ، آخر نسخ (محلي/سحابي)، وحجم قاعدة البيانات.
- mobile/lib/providers/theme_provider.dart (جديد)
  - StateNotifier<bool> مع حفظ في SharedPreferences لإدارة الوضع الداكن.
- mobile/lib/utils/theme.dart
  - إضافة buildDarkTheme مع سمة داكنة متناسقة.
- mobile/lib/main.dart
  - تطبيق themeMode ديناميكياً (Light/Dark) استناداً إلى themeSettingsProvider.
- mobile/lib/screens/settings/settings_guests.dart
  - إضافة زر حذف الضيف وجميع البيانات.
  - تنفيذ حذف متسلسل: ملاحظات الحجز (BookingNotes) ثم المدفوعات (Payments) ثم الديون (Debts) ثم الحجز نفسه (Bookings).
  - تحذير واضح عند وجود حجوزات نشطة وإتمام الحذف بعد تأكيد المستخدم.
- mobile/lib/services/daos/debts_dao.dart
  - إضافة listByBookingLocalId لقراءة الديون المرتبطة بحجز محدد.
- mobile/lib/services/repositories/debts_repository.dart
  - إضافة listByBookingLocalId للوصول من شاشة الضيوف.

## الملاحظات

- لم يتم إجراء أي تعديل على شاشة المستخدمين (SettingsUsersScreen) احتراماً للطلب.
- لم يتم حذف معاملات النقد CashTransactions بشكل صريح لأن الربط غير مباشر عبر Payments؛ حذف المدفوعات يتم بآلية soft-delete عبر Outbox. يمكن توسيع الحذف لاحقاً إذا لزم.

## لماذا هذا التغيير؟

- عداد المستخدمين يعكس الحالة الفعلية بدلاً من placeholder.
- توفير وضع داكن يحسّن تجربة الاستخدام والراحة البصرية.
- نافذة تقارير النظام أصبحت مفيدة عملياً في التشخيص والمتابعة.
- تمكين الإدارة من حذف ضيف بكافة آثاره في قاعدة البيانات المحلية بسهولة وأمان (مع التأكيد).

## الأثر

- لا تغييرات على مخطط قاعدة البيانات.
- التغييرات محصورة في طبقة العرض وموفرات الحالة وواجهات المستودعات.
- عمليات الحذف تستخدم soft-delete حسب طبقة الـ DAO للحفاظ على تكامل Outbox للمزامنة.
