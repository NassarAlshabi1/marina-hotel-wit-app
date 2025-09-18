# تقرير تحليل Bolt (marinahotel/bolt)

هذا التقرير يصف محتوى مجلد Bolt بعد استخراج الحزمة، ويحلل نقاط الدخول، تفاعلات قاعدة البيانات، تدفقات الميزات (المدفوعات والنزلاء والإشعارات)، والفروقات مع منطق الإدارة (Admin)، وجاهزية التكامل مع الأدوات المشتركة.

---

## أ) البنية (Structure)

هيكل المجلد (عمق حتى 3 مستويات):

```
marinahotel/bolt/
├── api/
│   ├── payments.php              ← API: دفعات وحساب المتبقي والخروج
│   ├── guests.php                ← API: قائمة/بحث النزلاء وإحصاءاتهم
│   ├── guest_history.php         ← API: تاريخ نزيل محدد
│   └── prepare_booking.php       ← API: تجهيز بيانات حجز جديدة
├── includes/
│   └── init.php                  ← Bootstrap للـ API: جلسة + DB + صلاحيات + JSON helpers
├── bolt/
│   ├── index.html                ← واجهة Bolt (PWA)
│   ├── sw.js                     ← Service Worker (Caching/Push UI)
│   ├── manifest.json             ← ملف PWA Manifest
│   ├── js/
│   │   ├── main.js, navigation.js, utils.js, ...
│   │   ├── payments.js           ← واجهة المدفوعات (محلية/بدون اتصال مباشر بـ API)
│   │   ├── pwa-manager.js        ← إدارة Service Worker و Push (عميل)
│   │   └── sync-manager.js       ← مزامنة محلية (محاكاة)
│   ├── styles/                   ← CSS
│   ├── docs/                     ← وثائق Bolt
│   ├── android/                  ← ملفات Android (Manifest ضمن المسار)
│   ├── package.json, package-lock.json
│   ├── build-android.js, script.js, page2.html, styles.css
└── README.md
```

- ملفات/إعدادات ملحوظة:
  - Service worker: `bolt/sw.js`
  - Manifest: `bolt/manifest.json`
  - لا توجد ملفات .env. يوجد `package.json` (للأدوات)، ولا توجد أُطر backend ضمن bolt UI.


## ب) نقاط الدخول والتهيئة (Entrypoints & Bootstrap)

- الواجهة الرئيسية: `bolt/index.html` (واجهة PWA تعتمد Tailwind/Chart.js وتتضمن أقسام: لوحة التحكم، الغرف، الحجوزات، المدفوعات، ...).
- لا يوجد Router أو إطار عمل SPA؛ التنقل يتم عبر دوال JS مثل `showSection()` ضمن الواجهة.
- Service Worker يُسجل من `bolt/js/pwa-manager.js` باستخدام المسار `/sw.js`، بينما الملف فعليًا في `marinahotel/bolt/bolt/sw.js` (مسار مطلق قد يحتاج ضبط عند النشر).
- لا توجد محملات تلقائية (autoloaders) أو أطر PHP؛ الجانب الخلفي لـ Bolt مُنفّذ عبر ملفات PHP في `marinahotel/bolt/api/*` التي تعتمد تضمين مشترك من `marinahotel/includes` عبر `includes/init.php`.

Bootstrap الخلفي:
- `includes/init.php` يقوم بـ:
  - `session_start` وتهيئة ترويس JSON
  - تضمين: `../../includes/db.php`, `../../includes/auth_check.php`, `../../includes/functions.php`
  - دالة `require_permission_any([...])` للتحقق من الصلاحيات
  - مرافق JSON: `json_ok`, `json_err`


## ج) تفاعلات قاعدة البيانات (Database Interactions)

الملاحظ: ملفات JS للواجهة لا تُجري استعلامات SQL مباشرة. كل SQL موجود ضمن `marinahotel/bolt/api`.

1) `api/payments.php`
- جلب الحجز مع السعر والمبالغ المدفوعة:
  - السطور 6–14:
```
SELECT b.booking_id, b.guest_name, b.guest_phone, b.room_number, b.checkin_date, b.checkout_date,
       r.price AS room_price,
       b.status,
       IFNULL((SELECT SUM(p.amount) FROM payment p WHERE p.booking_id = b.booking_id), 0) AS paid_amount
FROM bookings b
LEFT JOIN rooms r ON b.room_number = r.room_number
WHERE b.booking_id = ? LIMIT 1
```
  - الجداول: bookings, rooms, payment (مجموع فرعي).

- جلب سجل الدفعات للحجز:
  - السطور 29–33: `SELECT payment_id, amount, payment_date, payment_method, notes FROM payment WHERE booking_id = ? ORDER BY payment_date DESC`
  - الجداول: payment

- إضافة دفعة:
  - السطور 61–63: `INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes, revenue_type) VALUES (?, ?, ?, ?, ?, 'room')`
  - الجداول: payment

- تسجيل المغادرة (Checkout) بشروط:
  - السطور 85–91: تحديث حالة الحجز والغرفة
```
UPDATE bookings SET status = 'شاغرة', actual_checkout = NOW() WHERE booking_id = ?
UPDATE rooms SET status = 'شاغرة' WHERE room_number = ?
```
  - الجداول: bookings, rooms

- إشعارات واتساب: السطور 67–72 تستدعي `send_yemeni_whatsapp()` من `includes/functions.php`.

2) `api/guests.php`
- وضع البحث:
  - السطور 10–24: تجميعي على bookings مع DISTINCT و GROUP BY وحسابات: `COUNT(*)`, `MAX(checkin_date) AS last_visit`, و `SUM(CASE WHEN status='محجوزة' THEN 1 ELSE 0 END) AS active_bookings`.
  - الجداول: bookings
- الوضع الافتراضي (بدون بحث) + LIMIT 50: السطور 33–48.
- إحصاءات عامة: السطور 51–55 (3 استعلامات على bookings: إجمالي النزلاء المميَّزين، النشطين، المتكررين).

3) `api/guest_history.php`
- قوائم حجوزات نزيل محدد مع مدفوعاته: السطور 6–16 (bookings JOIN rooms LEFT JOIN payment + GROUP BY b.booking_id).
- إحصاءات للنزيل: السطور 21–30 (COUNT و SUM لحالات محددة + MIN/MAX checkin_date) على bookings.
- إجمالي المدفوعات للنزيل: السطور 35–39 (LEFT JOIN payment).

4) `api/prepare_booking.php`
- لا استعلامات؛ تُجهّز حمولة بيانات أولية لإنشاء حجز جديد.

جداول تم لمسها ضمن bolt/api: bookings, rooms, payment. لا توجد مراجع لـ booking_notes, cash_register, cash_transactions, users, permissions من داخل API الحالية.


## د) تدفقات الميزات (Feature Flows)

1) المدفوعات (Payments) — مقارنة بمنطق الإدارة `admin/bookings/payment.php`:
- الحسابات:
  - حساب الليالي: فرق التواريخ بين checkout و checkin مع حد أدنى 1 ليلة (مطابق لـ admin سطور 35–41).
  - الإجمالي = سعر الغرفة × الليالي، المدفوع = SUM(payment.amount) للحجز، المتبقي = max(0, الإجمالي - المدفوع) — مطابق لمنطق الإدارة.
- إضافة دفعة:
  - تحقق المبلغ: 0 < amount ≤ remaining (مطابق لسطور 102–104 في admin).
  - الإدراج إلى جدول: `payment` بنفس الأعمدة الأساسية مع `revenue_type='room'`.
  - بعد النجاح: استدعاء `send_yemeni_whatsapp()` بنفس نص الرسالة (اسم النزيل، رقم الحجز، المبلغ، المتبقي) — مطابق لنمط الإدارة (سطور 112–126 من admin).
- تسجيل المغادرة (Checkout):
  - مسموح فقط عندما remaining == 0؛ تحديث `bookings.status='شاغرة'`, `bookings.actual_checkout=NOW()`, و `rooms.status='شاغرة'` داخل معاملة — مطابق لسلوك الإدارة (سطور 45–86 في admin).
- ملاحظات: لا يتم إدراج حركات في `cash_transactions` — وهذا يتوافق مع سلوك `admin/bookings/payment.php` الحالي.

2) النزلاء (Guests) — مقارنة بـ `admin/settings/guests.php`:
- القائمة/البحث: GROUP BY على (guest_name, guest_phone, guest_email) مع DISTINCT وإحصاءات: total_bookings, active_bookings, last_visit، مع LIMIT 50 افتراضيًا — مطابق لمنطق الإدارة (سطور 9–24 و31–48 في admin/guests.php).
- الإحصاءات: total_guests, active_guests, repeat_guests عبر استعلامات منفصلة — مطابق لقسم الإحصاءات (سطور 51–61).
- تاريخ النزيل: يقدم حجوزات النزيل مع إجمالي مدفوعاته وإحصاءات إضافية — مكافئ لوظيفة `guest_history.php` في الإدارة.

3) الإشعارات (Notifications):
- واتساب: يتم استخدام `includes/functions.php::send_yemeni_whatsapp()` كما في الإدارة؛ النتائج تُعالج بنفس الرسائل.
- Web Push (الواجهة): `bolt/js/pwa-manager.js` يجهّز التسجيل على `pushManager`، لكن الدالة `sendSubscriptionToServer()` مجرد Stub (طباعة إلى الـ console). لا توجد مكالمات مباشرة للـ backend. يمكن ربطها بـ `marinahotel/api/push-subscription.php` بسهولة.
- Service Worker: `bolt/sw.js` يتعامل مع التخزين المؤقت و Push UI فقط؛ لا يطلق إشعارات من السيرفر.


## هـ) الفروقات مقارنة بالإدارة (Differences vs Admin)

- أسماء الجداول: يستخدم `payment` (مفرد) تمامًا كما في المخطط `marinahotel/database.sql`. لا توجد تسميات بديلة (مثل payments) في الـ API.
- الحسابات: الليالي/المتبقي/الإجمالي تتبع نفس قواعد `admin/bookings/payment.php`.
- الآثار الجانبية:
  - لا إدراج في `cash_transactions` ضمن API — مطابق لسلوك صفحة الإدارة الحالية.
  - رسائل واتساب تُستخدم بنفس دالة الإدارة وبنفس الرسالة.
- الواجهة الأمامية في Bolt تعتمد بيانات محلية (Local Storage) في ملفات مثل `payments.js` و `data-manager.js` ولا تتصل مباشرة بواجهات الـ PHP — هذا اختلاف وظيفي على مستوى الواجهة، لكنه لا يمنع التكافؤ في منطق الخلفية.
- Push: في Bolt الأمامي لا يتم إرسال الاشتراك إلى الخادم، بينما في النظام توجد واجهة `api/push-subscription.php` لاستقبال الاشتراكات. هذا يحتاج توصيل بسيط إذا رغبت الواجهة.

عناصر مطابقة للمخطط (hotel_db-(12).sql / database.sql):
- الجداول المستعملة: bookings, rooms, payment — كما في قاعدة الحقيقة.
- عدم تغيير أسماء الأعمدة أو إضافة أعمدة جديدة.


## و) جاهزية التكامل (Integration Readiness)

- تم بالفعل ربط الـ API بـ `marinahotel/includes`:
  - `db.php` لاتصال قاعدة البيانات
  - `auth_check.php` لإجبار تسجيل الدخول والتحقق من الصلاحيات (جلسة/صلاحيات)
  - `functions.php` لاستخدام `send_yemeni_whatsapp()` و `format_yemeni_phone()`
- الصلاحيات المطلوبة:
  - `api/payments.php`:
    - إضافة دفعة: أي من `manage_payments` أو `finance_manage`
    - تسجيل المغادرة: أي من `manage_bookings` أو `bookings_edit` أو `rooms_manage`
  - `api/guests.php` و `api/guest_history.php`: قراءة فقط — تتطلب جلسة دخول عبر `auth_check.php`
  - `api/prepare_booking.php`: أي من `manage_bookings` أو `bookings_add`
- تعارض الأسماء/النطاقات: لا يوجد. ملفات Bolt الأمامية لا تعرف دوال PHP. دوال الصلاحيات تأتي من `includes/auth_check.php` وتستخدم نفس مخطط `permissions/user_permissions`.
- توصية للتكامل مع Push:
  - تعديل `bolt/js/pwa-manager.js` في `sendSubscriptionToServer()` لإرسال JSON إلى `marinahotel/api/push-subscription.php` بصيغة Web Push (endpoint, keys.p256dh, keys.auth) كما هو معرف.
- ملاحظة مسار Service Worker:
  - التسجيل يستخدم `/sw.js` (جذر الموقع) بينما الملف تحت `marinahotel/bolt/bolt/sw.js`. عند النشر يجب ضبط المسارات أو توفير alias في الجذر.


## ملاحق: إشارات مقارنة بالمراجع

- مرجع الإدارة (للمطابقة):
  - `admin/bookings/payment.php` — الحسابات، القيود، واتساب، Checkout
  - `admin/settings/guests.php` — قوائم النزلاء وإحصاءاتهم
  - `includes/functions.php` — `send_yemeni_whatsapp`
  - `api/push-subscription.php` — تخزين اشتراكات Push

- ملفات Bolt ذات صلة:
  - `api/payments.php`, `api/guests.php`, `api/guest_history.php`, `api/prepare_booking.php`
  - `includes/init.php`
  - `bolt/js/pwa-manager.js`, `bolt/sw.js`, `bolt/index.html`
