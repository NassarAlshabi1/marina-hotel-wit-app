# تقرير تحليل إعادة الهيكلة وتحسين الأداء — Marina Hotel (Flutter)

**التاريخ:** 2026-07-12
**النطاق:** `mobile/lib` — 370 ملف Dart، ‎~217,000 سطر.
**القاعدة الملتزم بها:** إعادة هيكلة وتحسين أداء فقط، بدون أي تغيير في منطق الأعمال أو سلوك التطبيق أو مخطط قاعدة البيانات.

---

## ملخص تنفيذي (اقرأ هذا أولاً)

1. **المشروع ليس مشروعًا جديدًا.** هو تطبيق ناضج **يستخدم بالفعل** `flutter_riverpod: ^2.6.1` و `signals_flutter: ^6.0.0`، ويحتوي على **23 ملف providers** و**99 ملفًا** يعتمد على Riverpod، و**49 فهرسًا (Index) معرّفة بالفعل** في قاعدة البيانات. لذا فالمطلوب فعليًا هو **إكمال هجرة قائمة + تحسينات**، وليس تبنّي من الصفر.

2. **حاجز تقني حاسم:** بيئة التنفيذ الحالية **لا تحتوي على Flutter/Dart SDK**. لا يمكن:
   - الترجمة (`flutter build` / `dart compile`)
   - التحليل الساكن (`flutter analyze`)
   - توليد الكود (`build_runner`) — وهو **إلزامي** لأن طبقة DAO والنماذج مُولّدة (`*.g.dart` + freezed)
   - اختبار هجرات Drift

   أي تعديل جماعي أعمى على ملفات تعتمد على كود مُولّد سيخاطر بكسر البناء، وهذا يخالف مباشرة قاعدتكم "توافق كامل، لا تغيير سلوكي". **لذلك هذا التقرير يقدّم التوصيات الجاهزة للتطبيق بدل تطبيقها عمياء**، تمامًا كما نصّت مهمتكم: "لا تطبّق أي تعديل بصمت".

3. **الأولويات الأعلى أثرًا** (بالترتيب): (أ) نقل عمليات التجزئة/التسلسل الثقيلة في المزامنة إلى Isolate، (ب) إصلاح إعادة البناء الكامل للشاشات الضخمة (Settings + booking_edit)، (ج) إضافة ~4 فهارس ناقصة، (د) إضافة Pagination/LIMIT لقوائم DAO المفتوحة، (هـ) إكمال هجرة Riverpod للـ singletons المتبقية.

---

## 1. الملفات التي تم تعديلها فعليًا في هذه الجولة

| الملف | التعديل | السبب |
|---|---|---|
| `mobile/REFACTORING_ANALYSIS_2026-07-12.md` | إنشاء هذا التقرير | توثيق التحليل والتوصيات (المطلب الثاني عشر) |

**لم تُطبّق أي تعديلات على كود Dart** لعدم توفر بيئة بناء للتحقق (انظر الملخص التنفيذي #2). كل التوصيات أدناه جاهزة للتطبيق فور توفر بيئة Flutter.

---

## 2. حالة Riverpod — ما هو مُدار وما ليس مُدارًا (المطلب الرابع)

### 2.1 خدمات طويلة العمر مُدارة بالفعل عبر Riverpod ✅
موجودة في `lib/providers/`:

| الخدمة | Provider | النوع |
|---|---|---|
| `AppDatabase` (`DatabaseManager.instance`) | `repository_providers.dart:46` | `Provider` |
| كل الـ Repositories (Rooms, Bookings, Employees, GuestInfos, Expenses, Cash, Payments, Debts, Notes, ShiftNotes, Blacklist...) | `repository_providers.dart:50-96` | `Provider` |
| `AppwriteService` | `appwrite_providers.dart:16` | `Provider` |
| `AppwriteSyncManager` | `appwrite_providers.dart:21` | `Provider` |
| `UnifiedSyncOrchestrator` | `appwrite_providers.dart:34` | `Provider` |
| `AutoSyncEngine` | `auto_sync_engine_providers.dart:7` | `Provider` |
| `GoogleDriveConflictResolver` (ConflictResolver) | `auto_sync_engine_providers.dart:28` | `Provider` |
| `SmartSyncManager` | `smart_sync_provider.dart:6` | `Provider` |
| `AutoBackupManager` | `auto_backup_provider.dart:8` | `Provider` |
| `ConnectivityService` | `service_providers.dart:64` | `Provider` + `ref.onDispose` |
| `RemoteConfigService` | `remote_config_provider.dart:8` | `Provider` |
| Auth | `auth_provider.dart:307` | `StateNotifierProvider` |
| Theme/Settings | `theme_provider.dart:25` | `StateNotifierProvider` |
| Logger (`DiagnosticsLogger`) | `repository_providers.dart:42` | `ChangeNotifierProvider` |

### 2.2 Singletons يدوية بلا Provider — يُوصى بنقلها إلى Riverpod ⚠️
(الوصول إليها مباشرة عبر `.instance` من داخل الشاشات)

| الصنف | التعريف | الاستهلاك المباشر من UI |
|---|---|---|
| `GeminiService` | `services/gemini_service.dart:239` | `ai_chat_screen.dart` (12 موضعًا) |
| `CrashlyticsService` | `services/crashlytics_service.dart:45` | `settings_screen.dart:674`, `payments_main_screen.dart`, `reports_screen.dart:170` |
| `NightAuditService` | `services/night_audit_service.dart:21` | `settings_screen.dart:543` |
| `SyncOrchestrator` | `services/sync_orchestrator.dart:235` | `enhanced_sync_button.dart:51,66`, `settings_maintenance.dart:579` |
| `SyncPerformanceOptimizer` | `services/sync_performance_optimizer.dart:13` | `sync_performance_settings_screen.dart` (5 مواضع) |
| `DataUsageManager` | `services/data_usage_manager.dart:12` | `sync_performance_settings_screen.dart:429` |
| `CentralSyncCoordinator` | `services/central_sync_coordinator.dart:7` | `booking_edit.dart:1028` |
| `SyncHealthMonitor` | `services/sync_health_monitor.dart:20` | `sync_health_screen.dart:51` |
| `SecondaryBackupService` | `services/secondary_backup_service.dart:127` | `secondary_appwrite_settings_screen.dart:284` |

**التوصية:** لفّ كل واحدة في `Provider` بسيط (لا تغيير في منطقها الداخلي)، ثم استبدال `X.instance` بـ `ref.read(xProvider)` في الشاشات. تعديل ميكانيكي منخفض الخطر.

### 2.3 خدمات لها Provider **ولكن** تُستهلك أيضًا كـ singleton (خطر ازدواج دورة الحياة) 🔴
- `SmartSyncManager` — له provider لكن `sync_debug_logs_screen.dart:28,50,57,64` تستخدم `.instance`.
- `RemoteConfigService` — له provider لكن `late_payment_whatsapp_screen.dart:104,120` تستخدم `.instance`.
- `AutoBackupManager` — له provider لكن `google_drive_login_screen.dart:41,65`, `booking_edit.dart:1024` تستخدم `.instance`.
- `DiagnosticsLogger` — له provider لكن `settings_maintenance.dart:155,548` تستخدم `.instance`.
- `WhatsAppService` — `whatsappServiceProvider` موجود (`repository_providers.dart:117`) لكن `whatsapp_settings_screen.dart:213` ينشئ نسخة جديدة بـ `new`.

**التوصية:** توحيد المصدر على الـ Provider لتفادي وجود نسختين حيتين.

### 2.4 إنشاء خدمات/DAOs بـ `new` داخل الشاشات بدل قراءتها من Provider
- تكرار `OutboxDao(...)`, `PaymentsDao(...)`, `ExpensesDao(...)`, `BookingsDao(...)`, `DebtsDao(...)`, `EmployeesDao(...)` inline في: `income_expense_report_screen.dart:85-136`, `expenses_report_screen.dart:202-203`, `payments_report_screen.dart:149-150`, `dashboard_sync_button.dart`, `sync_history_screen.dart:10`.
- **أسوأ حالة** — تمرير `DatabaseManager.instance` مباشرة متجاوزًا `databaseProvider`: `expenses_list.dart:1210`, `salary_entitlements_screen.dart:29`, `settings_employees.dart:1055`, `database_fixer_screen.dart:23`, `settings_maintenance.dart:734`.

**التوصية:** إنشاء providers خفيفة للـ DAOs (تعتمد على `databaseProvider`) واستهلاكها.

### 2.5 ملاحظة معمارية
لا يوجد استخدام لـ `Notifier` / `AsyncNotifier` (نمط Riverpod 2.x الحديث) في أي مكان — كل الحالة المتغيرة تستخدم `StateNotifierProvider` القديم. **التوصية (اختياري، منخفض الأولوية):** ترحيل تدريجي إلى `Notifier`/`AsyncNotifier` عند لمس هذه الأجزاء مستقبلًا.

---

## 3. Signals — الاستخدام الحالي والفرص (المطلب الخامس)

- **الاستخدام الحالي:** `signals_flutter` مُعرّف كاعتماد، لكنه **غير مستخدم عمليًا** في الشاشات (كل الحالة المحلية عبر `setState`). ملف `utils/stream_helpers.dart` يذكر كلمة "signal" بمعنى غير متعلق بالحزمة.
- **القاعدة الملتزم بها:** Signals للحالة المحلية داخل الشاشة فقط (بحث/فلاتر/عنصر محدد/مؤشر تحميل/تبويب/فتح نافذة/قيم نماذج مؤقتة). **يُمنع** استخدامها في الخدمات/DB/المزامنة/Repository/Auth/Settings.

### أفضل المرشحين لتحويل الحالة المحلية إلى Signals (أو `ValueNotifier` مع widget مُستخرج):
| الشاشة | الحالة المحلية | file:line |
|---|---|---|
| `expenses_list.dart` | نص البحث (يعيد بناء القائمة كاملة عند كل حرف) | `:263` |
| `expenses_list.dart` | رقائق الفلاتر | `:286, :412, :423, :496` |
| `guest_edit_screen.dart` | `_hasUnsavedChanges` (يعيد بناء النموذج كامل عند كل تعديل) | `:748` |
| `whatsapp_settings_screen.dart` | `_obscureToken` (عين كلمة المرور), `_selectedApiType` (dropdown) | `:767, :556` |
| `booking_edit.dart` | قيم الـ dropdowns (`_idType`, `_status`) | `:289, :418` |
| `data_protection_screen.dart` | أعلام الانشغال (`_backupBusy`, `_syncBusy`, `_appwriteBusy`) | متعددة |

---

## 4. أماكن إعادة البناء الزائدة (المطلب الرابع) — 420 استدعاء `setState` في 61 ملفًا

`analysis_options.yaml` **يُفعّل بالفعل** `prefer_const_constructors`, `prefer_const_constructors_in_immutables`, `prefer_const_declarations`, `prefer_const_literals_to_create_immutables`. لذا **مكاسب `const` اليدوية ضئيلة** (الـ linter يمسكها) — **المشكلة الحقيقية هي نطاق إعادة البناء**، لا `const`.

### أعلى 8 مخالفين (نسبة الهدر الأعلى):

| # | الملف | عدد setState | المشكلة الأساسية |
|---|---|---|---|
| 1 | `data_protection_screen.dart` (1405 سطر) | 32 | 24 منها مجرد تبديل علم انشغال يعيد بناء شجرة 1400 سطر مرتين لكل إجراء |
| 2 | `appwrite_settings_screen.dart` (1708 سطر) | 20 | 9 مفاتيح إعداد + 10 `_isLoading` تعيد بناء 1700 سطر؛ دوال `_build*Section` **ليست** حدود إعادة بناء |
| 3 | `whatsapp_settings_screen.dart` (1277 سطر) | 20 | `_isSaving/_isTesting/_isSyncing` تغلق أزرارًا مفردة لكنها تعيد بناء الكل |
| 4 | `secondary_appwrite_settings_screen.dart` (1272 سطر) | 18 | `setState(() {})` **فارغة** في `:66, :887, :1015, :1035` — إعادة بناء كل شيء لتعكس تغيّر controller |
| 5 | `guest_edit_screen.dart` (1397 سطر) | 13 | `_hasUnsavedChanges=true` عند كل ضغطة مفتاح يعيد بناء النموذج كامل |
| 6 | `smart_sync_settings_screen.dart` (799 سطر) | 12 | كلها أزواج `_isLoading` تعيد بناء الشاشة كاملة |
| 7 | `expenses_list.dart` (1306 سطر) | 12 | listener البحث يعيد بناء القائمة عند كل حرف (`:263`) |
| 8 | `booking_edit.dart` (1114 سطر) | 12 | أكبر `build()` منفرد (~580 سطر @231) يُعاد تنفيذه عند كل تغيير dropdown |

### نقطة معمارية جوهرية 🔑
عدة ملفات تبدو "مُقسّمة" (كثير من دوال `_buildXxx`) — لكن **دوال المساعدة ليست حدود إعادة بناء**؛ تُعاد تنفيذها بالكامل عند أي `setState` أبوي. **الحل الوحيد الفعّال** هو استخراجها إلى `StatefulWidget`/`ConsumerWidget` مستقلة (أو `ValueListenableBuilder`)، لا مجرد دوال.

### أكبر `build()` تحتاج تقسيمًا:
| الملف | بداية build | حجم الجسم |
|---|---|---|
| `booking_edit.dart` | @231 | ~580 سطر |
| `guest_edit_screen.dart` | @546 | ~230 سطر |
| `expenses_list.dart` | @94 | ~220 سطر |

**التوصية العملية:** استبدال `setState(() {})` الفارغة في `secondary_appwrite_settings_screen.dart` بـ `ValueListenableBuilder` على الـ controllers → أعلى مكسب بأقل خطر.

---

## 5. تحسين Widgets (المطلب الخامس)
- `const`: منخفض الأولوية لأن lints مُفعّلة. التوصية: تشغيل `flutter analyze` والاعتماد على مخرجاته بدل التدقيق اليدوي.
- منع إنشاء Controllers/Lists داخل `build`: مشمول ضمنًا في تقسيم الشاشات أعلاه.
- عملية ثقيلة داخل `build`: انظر §9.4 (`google_drive_logs_screen.dart:35` يُصفّي كل السجلات داخل `build`).

---

## 6. تحسين استعلامات Drift / SQLite (المطلبان السادس والثامن)

### 6.1 SELECT * / تحميل جداول كاملة (بدون WHERE أو LIMIT)
| الموقع | المشكلة |
|---|---|
| `services/repositories/salary_withdrawals_repository.dart:390` | `select(salaryWithdrawals).get()` **بلا WHERE إطلاقًا** (يحمّل حتى المحذوف) |
| `services/daos/bookings_dao.dart:184` | `getAll()` بلا limit (تحميل الجدول كاملًا) |
| `services/repositories/guest_infos_repository.dart:17,24` | تحميل كل guest_infos بلا limit |
| `services/repositories/rooms_repository.dart:209-229` | تحميل كل bookings + كل rooms في الذاكرة ثم حساب الإشغال في Dart (شبه-JOIN يدوي) |
| `services/daos/shift_notes_dao.dart:18,23,28` | جدول كامل بلا limit |
| `services/daos/debts_dao.dart:16,42` | كل الديون بلا limit |

### 6.2 التصفية في Dart بدل SQL
- `shift_notes_repository.dart:33-35, 44-46, 51-54` — تحميل كل الملاحظات ثم `.where((n) => n.isActive == 1)` في Dart → يجب `WHERE is_active = 1`.
- `rooms_repository.dart:213-224` — بناء مجموعة الغرف المشغولة بالمرور على كل الحجوزات في Dart → يمكن دفع `WHERE status IN (...)` إلى SQL.
- `salary_withdrawals_repository.dart:170-172` — تحميل كل الصفوف ثم `matchesExpenseRef` في Dart بدل `WHERE expense_id = ?`.

### 6.3 نقص Pagination / LIMIT (قوائم تُغذّي واجهات كبيرة)
تدعم الترقيم أصلًا: `bookings_dao.dart:56`, `rooms_dao.dart:33`, `sync_log_dao.dart:117`.
**ناقصة LIMIT:** `payments_dao.dart:31,66,166`, `debts_dao.dart:16,30,42`, `cash_transactions_dao.dart:22,48`, `expenses_dao.dart:28,52,98`, `shift_notes_dao.dart:18,23,28`, `guest_infos_repository.dart:17`.
**التوصية:** إضافة `limit`/`offset` (Infinite Scroll) للشاشات التي تعرض هذه القوائم.

### 6.4 JOINs
**لا يوجد أي JOIN في المشروع بأكمله** (`innerJoin`/`leftOuterJoin`/`join([...])` = صفر نتائج). العلاقات تُحلّ باستعلامات نقطية منفصلة أو في Dart. لا JOIN زائد لإزالته. (الحالة الوحيدة الشبيهة بـ JOIN يدوي: `rooms_repository.dart:209` — انظر 6.1.)

---

## 7. الفهارس (المطلب السابع)

### 7.1 الفهارس الموجودة — **49 فهرسًا** معرّفة في `services/local_db.dart`
تغطية جيدة: rooms(status,cleaning), bookings(status+hotel_day, room_number, guest_name, deleted_at), payments (6 فهارس), outbox (8 فهارس), audit_logs, debts, employees, expenses, shift_notes, cash_transactions... (القائمة الكاملة في §7 من التحليل الخام).

### 7.2 الفهارس المقترحة (ناقصة، مُتقاطعة مع WHERE/ORDER BY الفعلية)

| الفهرس المقترح | الجدول (العمود) | الدليل | السبب والتأثير المتوقع |
|---|---|---|---|
| `idx_bookings_checkin` | bookings(checkin_date) | `bookings_dao.dart:52-53,76` `ORDER BY checkin_date DESC` | كل قوائم الحجوزات تُرتّب بـ checkin_date ولا فهرس يغطيه (الموجود على hotel_day_checkin مختلف) → **filesort عند كل تحميل**. أثر عالٍ. |
| `idx_debts_payment_date` | debts(payment_date) | `debts_dao.dart:20-21,35-36,46` `ORDER BY payment_date DESC` | كل قوائم الديون تُرتّب بـ payment_date بلا فهرس → filesort. أثر متوسط-عالٍ. |
| `idx_salary_withdrawals_expense` | salary_withdrawals(expense_id) | `salary_withdrawals_repository.dart:130,329` `WHERE expense_id = ?` | مفتاح المطابقة الرئيسي؛ فقط employee_id مفهرس → **full scan لكل تعديل/حذف مصروف**. أثر عالٍ. |
| `idx_sync_log_created` | sync_log(created_at) | `sync_log_dao.dart:106-107,142-143` `ORDER BY created_at DESC LIMIT` | sync_log بلا فهارس → full scan+sort. أولوية أقل (الجدول مُقلّم). |
| `idx_*_server` (اختياري) | expenses/payments/employees/cash_transactions(server_id) | `getByServerId` أثناء المزامنة | full scan لكل سجل مُزامَن؛ يُنظر فيه إذا كبرت الجداول. |

### ⚠️ تنبيه بشأن القاعدة الثانية (لا تغيير مخطط)
إضافة فهرس في Drift تتطلب: (1) إضافته لـ `indexes` getter، (2) رفع `schemaVersion`، (3) إضافة خطوة `m.createIndex` في `onUpgrade`، (4) إعادة تشغيل `build_runner`. هذا يمسّ المخطط ويحتاج **اختبار هجرة على قاعدة موجودة** — وهو غير ممكن هنا لعدم توفر Flutter. **لذا الفهارس مُقترحة فقط ويجب تطبيقها واختبارها في بيئة بناء.**

---

## 8. العمليات المُوصى بنقلها إلى Isolates (المطلب التاسع) — الأعلى أثرًا 🔴

**اكتشاف مهم:** لا يوجد سوى **offload حقيقي واحد** في التطبيق كله: `income_expense_report_screen.dart:210` يستخدم `compute(_processReportData, ...)` — استخدمه كنمط مرجعي. كل معظم استدعاءات `compute` الأخرى هي **دوال اسمها compute** (`DeltaSyncService.compute`, `SyncChecksum.compute`) وليست `compute()` الخاصة بـ Flutter. كامل خط المزامنة/التجزئة يعمل متزامنًا على الـ main isolate.

| # | العملية | الموقع | العبء |
|---|---|---|---|
| 1 | `DeltaSyncService.compute()` + `_hashPayload` | `delta_sync_service.dart:61, 87-160, 660` | لكل صف من كل جدول: تطبيع تكراري + `Map.from` + `jsonEncode` + **SHA-1**. أكبر مخالف. |
| 2 | checksum لكامل قاعدة البيانات | `unified_sync_orchestrator.dart:408-421` | تحميل كل صفوف 11 جدولًا + `.toJson()` + `jsonEncode` + **SHA-256** على الـ UI thread |
| 3 | `uploadSnapshot()` | `google_drive_sync_service.dart:324-343` | ترميز JSON للـ snapshot 2-3 مرات + SHA-256 + gzip متزامنًا |
| 4 | checksum/gzip/sha256 للنسخ الاحتياطي | `google_drive_backup_service.dart:603,634,941,1037` | sha256 على كامل بايتات ملف SQLite (عدة MB) |
| 5 | integrity md5 | `sync_orchestrator.dart:525-526` | لكل جدول: `jsonEncode` حتى 1000 صف + **MD5** |

**التوصية:** كلها دوال نقية على `Map`/`bytes` قابلة للتسلسل → نقلها إلى `Isolate.run()` بنفس نمط `income_expense_report_screen.dart:210`. **UI يبقى مسؤولًا فقط عن الرسم والإدخال وتحديث مؤشرات التقدم.**

### 8.1 O(n²) وتحويلات JSON مكررة
- **O(n²)** في `google_drive_conflict_resolver.dart:342` — `indexWhere` خطي داخل حلقة `for (entry in resolutions)` → O(resolutions × records). **الحل:** بناء خريطة `uuid → index` مرة واحدة.
- ترميز JSON مكرر لنفس البيانات: `google_drive_sync_service.dart:326 + 342` (نفس الحمولة تُرمّز 2-3 مرات).
- round-trips متكررة لكل صف عبر `_persistMirrorSnapshot:242`, `_loadMirror:272`, `_rebuildMirror:368`.

---

## 9. تحليل الأداء الإضافي (المطلب العاشر)
- **9.1** إنشاء متكرر للكائنات: DAOs تُنشأ بـ `new` في build/شاشات (انظر §2.4) → استبدالها بـ providers مُخزّنة.
- **9.2** نسخ قوائم غير ضروري: `salary_withdrawals_repository.dart` يحمّل كل الصفوف ثم يُصفّي في Dart (§6.2).
- **9.3** تحويلات Model↔JSON متكررة: `unified_sync_orchestrator.dart:409-419` و `appwrite_sync_manager.dart:4485-4769` تعيد بناء JSON لكل الجداول على الـ main isolate.
- **9.4** عملية ثقيلة داخل `build`: `google_drive_logs_screen.dart:35` يستدعي `_filterLogs(logs)` داخل `build` (`:322-331` `where`+`toLowerCase`+`contains` لكل سجل عند كل إطار) → memoize أو نقلها خارج build.

---

## 10. جودة الكود (المطلب الحادي عشر)
- **DRY:** توحيد إنشاء DAOs في providers بدل تكراره في 6+ شاشات (§2.4).
- **SRP:** تقسيم شاشات الإعدادات الضخمة (1300-1700 سطر) إلى widgets فرعية.
- **KISS:** إزالة الازدواج بين الـ singleton والـ provider (§2.3).
- **كود ميت:** `providers/realtime_rooms_provider.dart:13` (`RealTimeRoomsProvider extends ChangeNotifier`) غير مُنشأ في أي مكان — مرشح للحذف أو التحويل إلى `StreamProvider`.
- `ConnectionStateManager` (`connection_state_manager.dart:16`, ChangeNotifier، بلا provider وبلا مستهلك) — زائد مع `connectionStatusProvider` الموجود.

---

## 11. المخاطر والملاحظات (المطلب الثاني عشر / 10)

1. **لا يمكن التحقق بدون بيئة Flutter.** كل تعديل على Dart يحتاج `build_runner` + `flutter analyze` + اختبار على الأقل لشاشة واحدة. تطبيق أعمى = خطر كسر بناء = مخالفة لقاعدة "توافق كامل".
2. **طبقة المزامنة مالية وحساسة.** أي تغيير في `DeltaSyncService`/`checksum`/conflict resolver يجب أن يكون byte-identical في المخرجات (قيم checksum و snapshotSize تُخزَّن وتُقارَن عبر الأجهزة). نقلها إلى Isolate يجب أن يحافظ على **نفس** خوارزمية الترميز/التجزئة تمامًا.
3. **الفهارس = تغيير مخطط.** يتعارض جزئيًا مع القاعدة الثانية؛ يتطلب رفع `schemaVersion` وهجرة مُختبَرة.
4. **ازدواج singleton/provider** (§2.3): عند التوحيد، تأكد أن لا كود خلفي (background/workmanager/alarm) يعتمد على النسخة الـ singleton خارج شجرة Riverpod.
5. **`.g.dart` مُولّدة** — لا تُحرّر يدويًا؛ عدّل ملف المصدر ثم أعد التوليد.

---

## 12. خطة التنفيذ المُقترحة (تدريجية وآمنة)

| المرحلة | العمل | الخطر | التحقق |
|---|---|---|---|
| A | Isolate offload للعمليات الخمس في §8 (أعلى أثر) | متوسط | مقارنة checksum قبل/بعد على بيانات ثابتة |
| B | إصلاح O(n²) + ترميز JSON مكرر (§8.1) | منخفض | اختبار وحدة على merge |
| C | إضافة LIMIT/Pagination لقوائم DAO (§6.3) | منخفض | التحقق من عدّ الصفوف |
| D | دفع التصفية إلى SQL (§6.2) | منخفض-متوسط | مقارنة النتائج |
| E | الفهارس الأربعة (§7.2) + هجرة | متوسط | اختبار هجرة على نسخة قاعدة |
| F | إكمال هجرة Riverpod للـ singletons (§2.2, §2.4) | منخفض (ميكانيكي) | flutter analyze |
| G | تقسيم شاشات الإعدادات الضخمة + Signals للحالة المحلية (§3, §4) | متوسط | اختبار سلوك بصري |

**كل مرحلة قابلة للتنفيذ في commit مستقل مع تحقق منفصل، حفاظًا على قاعدة "لا تغيير سلوكي".**
