# تدفق المزامنة بين القاعدة المحلية، Outbox، Appwrite، وGoogle Drive

هذا المستند يشرح بصورة عملية كيف يعمل نظام المزامنة في تطبيق mobile، وكيف يتم الحفاظ على تكامل البيانات عبر:
- قاعدة البيانات المحلية (Drift/SQLite)
- طبقة Outbox لتسجيل العمليات
- Appwrite كمخزن سحابي للكيانات
- Google Drive كنسخ احتياطي كامل وقناة مزامنة بين الأجهزة
- آلية الحذف المتسلسل للضيف وكل البيانات المرتبطة به

## 1) القاعدة المحلية (Drift/SQLite)
الجداول الرئيسية المتعلقة بالإدارة اليومية موجودة في:
- `mobile/lib/services/local_db.dart`
  - Bookings, Payments, BookingNotes, CashTransactions, Debts, ...

كل الجداول المهمة تحتوي حقول مزامنة (SyncFields) مثل:
- `localUuid` معرف محلي فريد يستخدم كمفتاح للمزامنة مع Appwrite
- `serverId` معرف من الخادم إذا توفر
- `createdAt`, `updatedAt`, `deletedAt`, `lastModified`, `version`, `origin`

الحذف داخل التطبيق هو "soft-delete" عبر ضبط `deletedAt` بدلاً من الإزالة الفيزيائية مباشرة. هذا يسمح:
- بمتابعة المزامنة مع الخادم (Appwrite) لتطبيق الحذف هناك
- بإبقاء أثر منطقي للحذف حتى يكتمل دفع العملية للخارج

## 2) طبقة Outbox (تسجيل العمليات)
الغرض: تسجيل عمليات الإنشاء/التحديث/الحذف محلياً لكي تُدفع لاحقاً إلى Appwrite بشكل موحد وآمن.
- Outbox معرف في `local_db.dart` (جدول Outbox)
- كل DAO مسؤول عن الكيان يسجّل عملية في Outbox عند عدم كون العملية من الخادم (`origin != server`).

أمثلة مفعّلة:
- `mobile/lib/services/daos/bookings_dao.dart` (Bookins)
- `mobile/lib/services/daos/payments_dao.dart` (Payments)
- `mobile/lib/services/daos/booking_notes_dao.dart` (BookingNotes)
- `mobile/lib/services/daos/cash_transactions_dao.dart` (CashTransactions)
- `mobile/lib/services/daos/debts_dao.dart` (Debts) — تمت إضافة تكامل Outbox للديون لضمان المزامنة الكاملة

لكل عملية، يتم استدعاء `outboxDao.merge(entity, op, localUuid, serverId, payload, clientTs)` حيث:
- `entity`: اسم الكيان (مثلاً: `bookings`, `payments`, `booking_notes`, `cash_transactions`, `debts`)
- `op`: العملية (`create`/`update`/`delete`)
- `localUuid`: معرف السجل المحلي (مفتاح الربط مع Appwrite)
- `serverId`: إن وجد
- `payload`: الحقول المطلوبة لإنشاء/تحديث السجل على Appwrite

## 3) مدير المزامنة مع Appwrite
- الملف: `mobile/lib/services/appwrite_sync_manager.dart`
- يقوم بجلب Outbox وتطبيق العمليات على Appwrite:
  - عند `create/update`: يستعمل `upsert<Entity>(localUuid, payload)`
  - عند `delete`: يستعمل `delete<Entity>(localUuid)` مع تجاهل أخطاء Not Found بهدوء
- يعتمد على خدمات Appwrite:
  - `mobile/lib/services/appwrite_service.dart`
  - إعدادات المشروع في `mobile/lib/services/appwrite_config.dart`

الربط بين أسماء الكيانات في Outbox ومجموعات Appwrite موجود في مدير المزامنة عبر دوال مثل:
- `_processBookingEntry`, `_processPaymentEntry`, `_processDebtEntry`, ...
- ودوال تحويل الكيانات المحلية إلى نموذج Appwrite مثل: `_bookingToRemote`, `_paymentToRemote`, `_debtToRemote`

## 4) Google Drive: نسخ احتياطي ومزامنة بين الأجهزة
- توليد النسخ الاحتياطية واستعادتها عبر:
  - `mobile/lib/services/google_drive_backup_service.dart`
  - `mobile/lib/services/local_backup_service.dart`
- يتم تصدير جميع الجداول إلى JSON، بما فيها حقول `deletedAt`، لذلك ينتقل أثر الحذف عبر نسخ/دمج البيانات بين الأجهزة.
- المزامنة الذكية بين الأجهزة (Smart Sync) تراقب Google Drive لجلب المستجدات وتطبيقها محلياً.

ملحوظة: Google Drive لا يعمل كسجل عمليات؛ بل كحاوية نسخ كاملة. بينما Appwrite يستقبل عمليات دقيقة عبر Outbox.

## 5) الحذف المتسلسل للضيف (Cascade Delete)
عند الضغط على "حذف الضيف وجميع البيانات" في شاشة إدارة الضيوف:
- الملف: `mobile/lib/screens/settings/settings_guests.dart`
- المنطق:
  1. استرداد جميع حجوزات الضيف (Grouped عبر شاشة الضيوف).
  2. لكل حجز:
     - حذف ملاحظات الحجز (BookingNotes)
     - حذف المدفوعات (Payments):
       - إن كان لكل دفعة `cashTransactionLocalId` مرتبط، يتم حذف معاملة النقد المرتبطة.
     - حذف معاملات النقد المرتبطة بالحجز مباشرة عبر `referenceType='booking'` و`referenceId=bookingId` (listByReference)
     - حذف الديون المرتبطة (Debts)
     - حذف الحجز (Bookings)
- كل عملية حذف أعلاه تُسجَّل في Outbox (إن كانت من خلال DAO مُمكّن للـ Outbox) ليُدفع الحذف إلى Appwrite.
- بما أن Google Drive يحفظ نسخة كاملة، فإن حقول `deletedAt` ستظهر في النسخة، وبذلك تنتقل آثار الحذف عند الاستعادة/المزامنة بين الأجهزة.

## 6) ربط معاملات النقد بالحجز
- جدول `CashTransactions` يحتوي حقلي `referenceType` و`referenceId` لربط العملية الكاشية باستهداف معين.
- أضفنا في DAO/Repository دوال `listByReference(referenceType, referenceId)` لكي نسترجع ونحذف كل ما يخص الحجز مباشرة.

## 7) الهوية والربط بين الأنظمة
- الحقل `localUuid` هو المرجع الرئيسي بين السجل المحلي والسجل في Appwrite.
- عند الإنشاء محلياً:
  - يُولّد `localUuid` في DAO.
  - تُسجل العملية في Outbox.
  - يدفع AppwriteSyncManager العملية إلى Appwrite بترميز `localUuid` كـ Document ID؛ ما يضمن التطابق الدقيق.
- عند الحذف محلياً:
  - ضبط `deletedAt` وتسجيل العملية Delete في Outbox؛ ثم حذف الوثيقة في Appwrite بنفس `localUuid`.

## 8) التعامل مع الأخطاء والتكرار (Idempotency)
- عمليات `upsert` في Appwrite تجعل الإنشاء/التحديث متسامحاً مع التكرار.
- في الحذف، إن كانت الوثيقة غير موجودة، يتم تجاهل الخطأ بهدوء (`_deleteSilently`) لضمان عدم توقف الدفعات.

## 9) توسيع المزامنة لكيانات أخرى
لإضافة كيان جديد يتكامل مع Appwrite وOutbox:
1. تأكد أن للجدول `localUuid` وحقول sync الأساسية.
2. فعِّل تسجيل Outbox في DAO (create/update/delete) باستدعاء `outboxDao.merge`.
3. أضف معالج Outbox في `AppwriteSyncManager` (case جديد في switch والدوال المساعدة للتحويل).
4. أضف واجهات `upsert/delete/list` لخدمة Appwrite.
5. حدّث خدمات النسخ الاحتياطي Google Drive إذا لزم (تصدير/استيراد الجدول).

## 10) اختبار التكامل
- تحقق أن عمليات DAO تُضيف سجلاً في Outbox.
- فعّل مزامنة Appwrite وتأكد من إنشاء/تحديث/حذف الوثائق.
- أنشئ نسخة Google Drive واستعدها على جهاز آخر للتحقق من انتقال حالات `deletedAt`.

## 11) ملفات مرجعية
- قاعدة البيانات: `mobile/lib/services/local_db.dart`
- Outbox DAO: `mobile/lib/services/daos/outbox_dao.dart`
- مزامنة Appwrite: `mobile/lib/services/appwrite_sync_manager.dart`
- خدمات Appwrite: `mobile/lib/services/appwrite_service.dart`, `mobile/lib/services/appwrite_config.dart`
- النسخ الاحتياطي Google Drive: `mobile/lib/services/google_drive_backup_service.dart`
- إدارة الضيوف (حذف متسلسل): `mobile/lib/screens/settings/settings_guests.dart`
- نقدية (listByReference): `mobile/lib/services/daos/cash_transactions_dao.dart`, `mobile/lib/services/repositories/cash_repository.dart`
- ديون (Outbox): `mobile/lib/services/daos/debts_dao.dart`, `mobile/lib/services/repositories/debts_repository.dart`

---
بذلك نضمن تطابق الحالة بين القاعدة المحلية وAppwrite، مع استمرار Google Drive كنسخة احتياطية كاملة ومصدر مزامنة بين الأجهزة. وآلية الحذف المتسلسل تضمن نظافة البيانات واتساقها عبر النظام بأكمله.
