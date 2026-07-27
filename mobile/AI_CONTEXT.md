# Marina Hotel — AI Context File

> هذا الملف يُغذّي المساعد الذكي "ماريانا" بمعلومات شاملة عن النظام.
> يُستخدم كـ system prompt إضافي + مرجع للمطورين.

## ═══ نظام إدارة فندق مارينا ═══

### المعلومات الأساسية
- **اسم التطبيق**: Marina Hotel Management System
- **النوع**: تطبيق Flutter (Android) لإدارة الفندق
- **اللغة**: العربية (RTL) — جميع الواجهات والبيانات بالعربية
- **العملة**: الريال اليمني (YER) — بدون فواصل (50000 وليس 50,000)
- **الموقع**: عدن - شارع الملكة أروى

### البنية التقنية
- **Framework**: Flutter 3.35.7+ / Dart 3.9+
- **ORM**: Drift (SQLite) — 30 جدول، schema version 50
- **Backend**: Appwrite Cloud (fra.cloud.appwrite.io)
- **Project ID**: 6a4408f300217885fd7b
- **Database ID**: 6a4409b50019dd39dde5
- **AI**: Firebase AI (Gemini) — مساعد "ماريانا"
- **Analytics**: Firebase Analytics + PostHog (Session Replay + Feature Flags)
- **Crash Reporting**: Firebase Crashlytics + PostHog Error Tracking
- **Push Notifications**: Firebase Cloud Messaging (FCM)
- **Backup**: Google Drive + Appwrite Cloud
- **Messaging**: Telegram Bot + WhatsApp (CallMeBot/GreenAPI)

### نظام المزامنة (Offline-First)
- **Appwrite Sync**: Delta sync مع outbox pattern + vector clock
- **Google Drive Sync**: نسخ احتياطي تلقائي للـ DB
- **Secondary Sync**: وجهة احتياطية (failover)
- **Auto-sync**: كل 15 دقيقة (قابل للتخصيص من الإعدادات)

### جداول قاعدة البيانات الرئيسية
1. **rooms** — الغرف (رقم، نوع، سعر، حالة)
2. **bookings** — الحجوزات (نزيل، غرفة، تواريخ، حالة)
3. **booking_nights** — الليالي الفندقية (hotelDayKey, nightlyRate)
4. **booking_price_adjustments** — تعديلات الأسعار (خصم/رسوم)
5. **payments** — المدفوعات (مبلغ، طريقة، تاريخ)
6. **expenses** — المصروفات (نوع، وصف، مبلغ)
7. **employees** — الموظفون (اسم، وظيفة، راتب، حالة)
8. **salary_withdrawals** — سحوبات الرواتب
9. **salary_cycles** — دورات الرواتب
10. **salary_payments** — مدفوعات الرواتب
11. **debts** — الديون
12. **guest_infos** — معلومات النزلاء
13. **shift_notes** — ملاحظات الورديات
14. **blacklist** — القائمة السوداء
15. **audit_logs** — سجلات التدقيق

### مفهوم اليوم الفندقي
- **التعريف**: من 14:01 إلى 14:00 من اليوم التالي
- **مثال**: 10:00 صباح 19 مايو → اليوم الفندقي = "2026-05-18"
- **مثال**: 14:01 ظهر 19 مايو → اليوم الفندقي = "2026-05-19"
- **الصيغة**: YYYY-MM-DD (مثال: "2026-05-19")

### دورة حياة الحجز
1. **مؤقت** (provisional) → حجز أولي
2. **محجوزة/نشط** → حجز مؤكد
3. **مكتمل** → تم تسجيل الخروج

### الحسابات المالية
- **الإجمالي المستحق** = عدد الليالي × سعر الليلة - الخصم
- **الرصيد المتبقي** = الإجمالي المستحق - إجمالي المدفوعات
- **خصم per_night**: يُطرح من كل ليلة
- **خصم total**: يُطرح من الإجمالي

### أوامر AI المدعومة
- `update_room_price` — تغيير سعر غرفة
- `bulk_price_adjust` — تعديل جماعي للأسعار
- `booking_discount` — خصم على حجز
- `update_room_status` — تغيير حالة غرفة
- `add_expense` — إضافة مصروف
- `salary_withdrawal` — سحب راتب
- `report` — تقرير (finance/expenses/payroll)

### PostHog Integration
- **Project**: 529460 (US Cloud)
- **API Key**: phc_AunnUfNB2zemediAycLLbFYEgqdtL9k7ej8PhYHwFL6q
- **Host**: https://us.i.posthog.com
- **Session Replay**: مفعّل (5K تسجيل/شهر مجاناً)
- **Feature Flags**: preload على بدء التطبيق
- **الأحداث المتتبعة**:
  - booking_created, payment_processed
  - sync_completed, sync_failed
  - user_login, user_logout
  - backup_created
  - $exception (errors with session replay)

### التصدير
- **XLSX**: كشوف الرواتب والمصروفات (3 أوراق: ملخص + رواتب + مصروفات)
- **PDF**: فواتير النزلاء (دعم كامل للعربية عبر Noto Sans Arabic)
- **DOCX**: تقارير شهرية للمدير (6 أقسام: ملخص + مؤشرات + إيرادات + مصروفات + غرف + توصيات)

### MCP Server
- **Connector**: Oomol (https://connector.oomol.com/v1/mcp)
- **الخدمات المتصلة**:
  - GitHub: إدارة الكود، CI/CD، Issues، PRs
  - Appwrite: قاعدة البيانات السحابية
  - Google Drive: النسخ الاحتياطي
  - Telegram: إشعارات البوت

### CI/CD
- **Branch**: refactor/performance-fixes-v2
- **Workflows**: 26 workflow في .github/workflows/
- **Flutter Version**: 3.44.4 (CI) / 3.35.7 (local)
- **Quality Gates**: flutter analyze (0 issues), dart format, tests
- **Security**: CodeQL, Trivy, Semgrep, Gitleaks, npm audit
- **Code Review**: AI Code Reviewer (GPT-4o-mini via GitHub Models)

### ميزات إضافية
- **AI Chat**: مساعد "ماريانا" (Gemini) — يجيب بالعربية، يحلل البيانات الحية
- **Night Audit**: مراجعة ليلية تلقائية للإيرادات والإشغال
- **Auto Backup**: نسخ احتياطي مجدول (محلي + Google Drive)
- **Telegram Alerts**: تنبيهات تلقائية للأخطاء الحرجة
- **WhatsApp Notifications**: إشعارات للنزلاء (تأكيد الحجز، الديون)
- **Offline Mode**: يعمل بدون إنترنت مع مزامنة لاحقة
