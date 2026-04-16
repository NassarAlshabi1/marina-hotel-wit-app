# تحليل شاشات تطبيق الموبايل (Flutter)

## الهيكل العام
- جميع الشاشات ضمن `lib/screens` مبنية باستخدام Flutter مع Riverpod (`ConsumerWidget` و `ConsumerStatefulWidget`).
- يتم الاعتماد على مزودي البيانات من مجلد `services/providers.dart` والمستودعات (repositories) للتعامل مع قاعدة البيانات المحلية drift.
- تستخدم الشاشات حوارات خاصة (دوال تبدأ بـ `_show`) وعناصر بناء فرعية (دوال تبدأ بـ `_build`) لتنظيم الواجهة.

## الحجوزات (bookings)
- **`booking_edit.dart`**: نموذج تعديل/إضافة حجز مع حقول ضيف، هاتف، غرفة، تواريخ، حالة. يستخدم `TextEditingController` لكل حقل و Validator `_req`.
- **`bookings_list.dart`**: شاشة إدارة الحجوزات الحالية؛ تحتوي حالات بحث (`_search`)، إخفاء الحجوزات المنتهية (`_hideEnded`)، تنسيقات مالية (`NumberFormat`). تعرض تنبيهات الملاحظات وتستدعي مزودي الحجوزات، الغرف، المدفوعات، الملاحظات، والمزامنة.

## لوحة التحكم والدخول
- **`dashboard_screen.dart`**: تجمع إحصاءات الحجوزات والغرف وتعرض إجراءات سريعة، مع استدعاء `syncServiceProvider` وموفري القوائم.
- **`login_screen.dart`**: نموذج تسجيل الدخول بحقول مستخدم وكلمة مرور، حالة تحميل `_loading`، والاعتماد على `authProvider`.

## المدفوعات والمالية
- **`payments_main_screen.dart`**: تبويب رئيسي بثلاث شاشات (نظرة عامة، معاملات، حجوزات نشطة) مع `TabController`. يحسب إحصاءات، يعرض رسوم `fl_chart`، ويستخدم مزودي المدفوعات والحجوزات.
- **`booking_payment_screen.dart`**: يحلل بيانات الحجز، يولد إيصالات وفواتير PDF، يدير طرق ووسائل الدفع، ويتكامل مع `payment_models.dart`.
- **`booking_checkout_screen.dart`**: إدارة إجراءات السداد النهائي مع حقول حالة `_isProcessing`.
- **`payment_history_screen.dart`**: فلاتر لأنواع الإيراد وطرق الدفع والتواريخ، مع وظائف `_applyFilters` و `_showPaymentDetails`.
- **`payments_list.dart`**: قائمة مبسطة للمدفوعات.
- **`finance_screen.dart`**: مجرد غلاف يعرض `PaymentsMainScreen`.

## المصروفات والموظفين
- **`expenses_list.dart`**: إدارة المصروفات مع حوار `_edit` يرتبط بمستودع المصروفات ومزود المزامنة.
- **`employees_list.dart`**: مشابه للمصروفات لكن مع مستودع الموظفين.

## الغرف
- **`rooms_main.dart`**: تبويب بين القائمة ولوحة التحكم باستخدام `TabController`.
- **`rooms_list.dart`**: إدارة الغرف، رفع صور عبر `ApiService` و`ImagePicker`، وحوار `_editRoom`.
- **`rooms_dashboard.dart`**: عرض الغرف حسب الأدوار، التنقل للحجوزات، واستدعاء مزودي الغرف والمزامنة.

## الملاحظات
- **`notes_screen.dart`**: تبويب للملاحظات مع بيانات تجريبية `ShiftNote`، وظائف للاطلاع، التعديل، الحذف، وتحديث الحالة.

## الإعدادات
- **`settings_screen.dart`**: إحصاءات سريعة وروابط لكل أقسام الإعدادات.
- **`settings_employees.dart`**: إدارة موظفين (إضافة، تعديل، سحب رواتب، تغيير الحالة).
- **`settings_guests.dart`**: تجميع الضيوف من الحجوزات، بحث، حوارات تفصيلية.
- **`settings_maintenance.dart`**: إجراءات صيانة (تنظيف، نسخ احتياطي، إعادة تعيين).
- **`settings_users.dart`**: إدارة المستخدمين (تغيير كلمة المرور، الصلاحيات، إضافة مستخدم).

## التقارير
- **`reports_screen.dart`**: إعداد بيانات رسومية عبر `fl_chart` باستخدام `dbProvider` و`syncProvider`.

## مزايا مشتركة
- استخدام `TabController` مع `SingleTickerProviderStateMixin` للشاشات متعددة التبويبات.
- الاعتماد على جداول drift التي تعكس بنية قاعدة البيانات (`Rooms`, `Bookings`, `Payments`, `Expenses`, ...).
- تنسيق التواريخ والألوان والرموز يتم عبر دوال مساعدة محلية في كل ملف.
