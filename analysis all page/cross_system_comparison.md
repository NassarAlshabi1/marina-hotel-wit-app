# مقارنة بين شاشات الموبايل، واجهة الويب (PHP)، وقاعدة البيانات

## توافق الوظائف الأساسية
- **الحجوزات**: 
  - الموبايل يقدم شاشات `BookingsListScreen` و`BookingEditScreen` لإدارة الحجوزات مع نفس الحقول المستخدمة في PHP (`guest_name`, `guest_phone`, `room_number`, `checkin_date`, `checkout_date`, `status`).
  - سكربتات PHP (`add.php`, `edit.php`, `list.php`, `payment*.php`) تستخدم نفس الأعمدة من جدول `bookings` في `hotel_db.sql`، بما في ذلك تحديث حالة الغرفة وإدارة الملاحظات.
  - جدول `bookings` في قاعدة البيانات يدعم تلك الحقول بالإضافة إلى `calculated_nights` الذي يُعاد حسابه على الجانبين.

- **المدفوعات**:
  - شاشة الموبايل `BookingPaymentScreen` تدير طرق الدفع، إيصالات PDF، وتحديث حالة الحجز. تعتمد على جدول drift `Payments` الذي يشمل `amount`, `paymentDate`, `paymentMethod`, `revenueType`.
  - PHP (`payment.php` ومشتقاته) يسجل المدفوعات في جدول `payment` بنفس الحقول. كلا النظامين يستخدمان `payment_method` و`revenue_type`.

- **الملاحظات والتنبيهات**:
  - الموبايل يستخدم `BookingNotes` مع حقول `noteText`, `alertType`, `alertUntil`, `isActive`.
  - PHP يوفر `add_note.php` و`list.php` لإدارة جدول `booking_notes`. القيم (`high`, `medium`, `low`) متطابقة، مما يسمح بالمزامنة المباشرة.

- **الغرف**:
  - شاشة الموبايل `RoomsListScreen` تعرض رقم الغرفة، النوع، السعر، الحالة، وتتيح تعديلها.
  - PHP (`rooms/add.php`, `rooms/edit.php`, `rooms/list.php`) يدير نفس الحقول. جدول `rooms` في قاعدة البيانات يمتلك نفس الأعمدة، مما يضمن التطابق.

- **المصروفات والرواتب**:
  - في الموبايل `ExpensesListScreen` و`settings_employees.dart` تستخدم جداول drift `Expenses` و`Employees` و`CashTransactions`.
  - في PHP يتم تقديم الواجهات `expenses.php`, `add_expense.php`, `salary_withdrawals.php`. الجداول في `hotel_db.sql` (`expenses`, `expense_logs`, `salary_withdrawals`, `employees`) بنفس الحقول الأساسية (النوع، الوصف، المبلغ، التاريخ).

- **الصندوق النقدي**:
  - الموبايل يحتوي على مستودع `cash_repository` وجداول `CashTransactions` و`Payments`.
  - PHP يوفر `cash_register.php` و`cash_reports.php` يتعاملان مع `cash_register` و`cash_transactions`. الحقول (نوع الحركة، المبلغ، المرجع) متطابقة مع شبكة drift.

## فروقات ملحوظة
- **ملاحظات المناوبات (`shift_notes`)**: موجودة في PHP ضمن `admin/notes` لكنها غير ممثلة في قاعدة البيانات المستخدمة للموبايل (ليست ضمن `local_db.dart`).
- **إخفاء معلومات الضيف التفصيلية**: جدول `bookings` في MySQL يحتوي على حقول إضافية (الهوية، البريد، العنوان، الجنسية) بينما نسخة الموبايل الحالية تعتمد فقط على الاسم، الهاتف، الجنسية، البريد، العنوان. يمكن توسيع drift لإضافة حقول مطابقة إذا لزم الأمر.
- **جداول المستخدمين والصلاحيات**: مدعومة بالكامل في PHP (`users`, `permissions`) لكنها غير مدمجة في الموبايل؛ يعتمد الموبايل على مصادقة عبر `authProvider` بدون إدارة صلاحيات محلية.
- **حقول المزامنة**: drift يضيف أعمدة خاصة بالمزامنة (`localUuid`, `serverId`, `lastModified`) غير موجودة في MySQL. هذه الحقول لوجستية وغير مطلوبة في الويب.

## نقاط جاهزية التكامل
- البنية العامة للحجوزات، الغرف، المدفوعات، المصروفات، والموظفين متوافقة بين الأطراف الثلاثة، مما يسهل مزامنة البيانات أو تنفيذ API موحد.
- جدول `bookings` يحتوي Trigger وEvent في MySQL لضمان توافق حالة الغرفة وعدد الليالي؛ يجب التأكد من أن منطق الموبايل يأخذ هذه الحسابات بالحسبان عند التزامن.
- توافق أسماء الحقول في drift مع الأعمدة الموجودة في MySQL يعزز إمكانية الربط المباشر عبر API أو مزامنة مباشرة.
