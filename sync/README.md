# Marina Hotel - Sync & Backup System

هذا المجلد يحتوي على نسخة احتياطية من جميع ملفات المزامنة والنسخ الاحتياطي والاستعادة من التطبيق.

## 📊 إحصائيات

- **إجمالي الملفات**: 77 ملف Dart
- **تاريخ النسخ**: 2026-01-01
- **تم التحقق**: نعم ✓ - تم نسخ جميع ملفات المزامنة

## 📁 البنية

```
sync/
├── data/                 # نماذج البيانات للمزامنة (1 ملف)
├── mixins/              # Mixins للمزامنة عند الخروج (1 ملف)
├── providers/           # Providers للمزامنة والنسخ الاحتياطي (6 ملفات)
├── screens/             # واجهات إعدادات المزامنة (9 ملفات)
├── services/            # خدمات المزامنة الأساسية (56 ملف)
│   ├── daos/           # Data Access Objects (1 ملف)
│   ├── logging/        # سجلات المزامنة (1 ملف)
│   ├── monitoring/     # نظام مراقبة المزامنة (1 ملف)
│   └── sync_core/      # الوحدات الأساسية للمزامنة (8 ملفات)
├── tasks/               # مهام المزامنة الخلفية (2 ملف)
├── widgets/             # واجهات المزامنة الذكية (1 ملف)
├── main.dart            # ملف التطبيق الرئيسي مع تهيئة المزامنة
└── main_with_auto_sync_engine.dart  # ملف تطبيق بديل مع محرك المزامنة
```

## 🔄 أنواع المزامنة

### 1. Smart Sync (المزامنة الذكية)
- `smart_sync_manager.dart` - مدير المزامنة الذكية
- `smart_google_drive_sync.dart` - مزامنة Google Drive الذكية
- `smart_sync_widgets.dart` - واجهات المزامنة الذكية
- `smart_sync_provider.dart` - Provider للمزامنة الذكية
- `smart_sync_settings_screen.dart` - شاشة إعدادات المزامنة الذكية

### 2. Delta Sync (المزامنة التفاضلية)
- `delta_sync_service.dart` - خدمة المزامنة التفاضلية
- `google_drive_delta_sync.dart` - مزامنة تفاضلية مع Google Drive
- `appwrite_delta_sync.dart` - مزامنة تفاضلية مع Appwrite

### 3. Auto Sync (المزامنة التلقائية)
- `google_drive_auto_sync_engine.dart` - محرك المزامنة التلقائية
- `auto_sync_task.dart` - مهمة المزامنة التلقائية
- `appwrite_auto_sync_task.dart` - مهمة المزامنة التلقائية مع Appwrite
- `auto_sync_engine_providers.dart` - Providers للمزامنة التلقائية
- `auto_sync_engine_monitor_screen.dart` - شاشة مراقبة المزامنة التلقائية

### 4. Unified Sync (المزامنة الموحدة)
- `unified_sync_orchestrator.dart` - منسق المزامنة الموحدة
- `google_drive_unified_sync_coordinator.dart` - منسق المزامنة الموحدة مع Google Drive

### 5. Realtime Sync (المزامنة الآنية)
- `realtime_sync_notifier.dart` - إشعارات المزامنة الآنية
- `screen_sync_controller.dart` - تحكم المزامنة للشاشات

## 💾 النسخ الاحتياطي والاستعادة

### Google Drive Backup
- `google_drive_backup_service.dart` - خدمة النسخ الاحتياطي على Google Drive
- `google_drive_backup_screen.dart` - شاشة النسخ الاحتياطي
- `google_drive_sync_service.dart` - خدمة مزامنة Google Drive

### Auto Backup (النسخ الاحتياطي التلقائي)
- `auto_backup_manager.dart` - مدير النسخ الاحتياطي التلقائي
- `auto_backup_task.dart` - مهمة النسخ الاحتياطي التلقائي
- `auto_backup_provider.dart` - Provider للنسخ الاحتياطي التلقائي
- `auto_backup_settings_screen.dart` - شاشة إعدادات النسخ الاحتياطي
- `database_auto_backup_hooks.dart` - خطافات النسخ الاحتياطي التلقائي

### Local Backup (النسخ الاحتياطي المحلي)
- `local_backup_service.dart` - خدمة النسخ الاحتياطي المحلي
- `sqlite_backup_restore.dart` - نسخ واستعادة SQLite

### Backup Utilities
- `backup_serializers.dart` - محولات النسخ الاحتياطي
- `backup_provider.dart` - Provider للنسخ الاحتياطي
- `alarm_backup.dart` - تنبيهات النسخ الاحتياطي
- `comprehensive_backup_screen.dart` - شاشة النسخ الاحتياطي الشامل

### Restore (الاستعادة)
- `restore_fix_service.dart` - خدمة إصلاح الاستعادة
- `restore_fix_screen.dart` - شاشة إصلاح الاستعادة

## 🗂️ ملفات إضافية مهمة

تم نسخ ملفات إضافية لا تحتوي على كلمات sync/backup/restore في اسمها ولكنها ضرورية لعمل نظام المزامنة:

### الملفات الرئيسية
- `main.dart` - يحتوي على تهيئة كاملة لأنظمة المزامنة (SmartSync + AutoSync + Appwrite)
- `main_with_auto_sync_engine.dart` - نسخة مبسطة تركز على محرك المزامنة التلقائية

### Providers الأساسية
- `providers/appwrite_providers.dart` - يحتوي على appwriteSyncManagerProvider وموفري Appwrite
- `providers/core_providers.dart` - يحتوي على syncServiceProvider والموفرين الأساسيين

### خدمات Appwrite
- `services/appwrite_service.dart` - خدمة Appwrite الأساسية للاتصال بالسحابة
- `services/appwrite_cache_manager.dart` - إدارة الذاكرة المؤقتة لـ Appwrite
- `services/appwrite_logger.dart` - سجل أحداث Appwrite

### معالجة التعارضات
- `services/conflict_manager.dart` - مدير التعارضات العام
- `services/conflict_resolver.dart` - محلل التعارضات
- `services/google_drive_conflict_resolver.dart` - محلل تعارضات Google Drive
- `services/sync_core/conflict_resolver.dart` - محلل التعارضات الأساسي

### السجلات والمراقبة
- `services/google_drive_logger.dart` - سجل أحداث Google Drive
- `services/logging/log_models.dart` - نماذج السجلات

### إدارة قاعدة البيانات
- `services/daos/outbox_dao.dart` - إدارة صندوق الصادر (التغييرات المعلقة للمزامنة)

### الوحدات الأساسية (sync_core)
- `services/sync_core/circuit_breaker.dart` - قاطع الدائرة لمنع حلقات الفشل
- `services/sync_core/retry_strategy.dart` - استراتيجية إعادة المحاولة

## 🔧 الخدمات الأساسية

### Sync Core (النواة)
في مجلد `services/sync_core/`:
- `base_sync_manager.dart` - المدير الأساسي للمزامنة
- `sync_error_handler.dart` - معالج أخطاء المزامنة
- `sync_metrics.dart` - مقاييس المزامنة
- `sync_scheduler.dart` - جدولة المزامنة
- `sync_validator.dart` - التحقق من صحة المزامنة

### Sync Management
- `sync_manager.dart` - مدير المزامنة العام
- `sync_service.dart` - خدمة المزامنة
- `sync_queue_service.dart` - خدمة قائمة انتظار المزامنة
- `sync_config.dart` - إعدادات المزامنة
- `sync_constants.dart` - ثوابت المزامنة
- `sync_enums.dart` - تعدادات المزامنة

### Sync Safety & Monitoring
- `sync_safety_layer.dart` - طبقة أمان المزامنة
- `sync_guardian.dart` - حارس المزامنة
- `sync_health_monitor.dart` - مراقب صحة المزامنة
- `sync_locks.dart` - أقفال المزامنة
- `sync_mutex.dart` - Mutex للمزامنة

### Sync Performance
- `sync_performance_optimizer.dart` - محسن أداء المزامنة
- `sync_performance_settings.dart` - إعدادات أداء المزامنة
- `sync_performance_settings_screen.dart` - شاشة إعدادات الأداء

### Sync Notifications
- `sync_notification_manager.dart` - مدير إشعارات المزامنة

### Monitoring System
في مجلد `services/monitoring/`:
- نظام مراقبة شامل للمزامنة

## 📱 الشاشات والواجهات

### Settings Screens
- `smart_sync_settings_screen.dart` - إعدادات المزامنة الذكية
- `auto_backup_settings_screen.dart` - إعدادات النسخ الاحتياطي التلقائي
- `sync_performance_settings_screen.dart` - إعدادات أداء المزامنة
- `google_drive_backup_screen.dart` - شاشة النسخ الاحتياطي على Drive
- `comprehensive_backup_screen.dart` - شاشة النسخ الاحتياطي الشامل

### Monitoring Screens
- `auto_sync_engine_monitor_screen.dart` - مراقبة محرك المزامنة
- `appwrite_sync_stats_screen.dart` - إحصائيات مزامنة Appwrite
- `sync_debug_logs_screen.dart` - سجلات تصحيح المزامنة

### Repair Screens
- `restore_fix_screen.dart` - شاشة إصلاح الاستعادة

## 🔗 الاتصالات الخارجية

### Appwrite Integration
- `appwrite_sync_manager.dart` - مدير مزامنة Appwrite
- `appwrite_delta_sync.dart` - مزامنة تفاضلية مع Appwrite
- `appwrite_auto_sync_task.dart` - مهمة المزامنة التلقائية

### Repository Integration
- `bookings_repository_with_auto_backup.dart` - مستودع الحجوزات مع النسخ الاحتياطي
- `repository_auto_backup_examples.dart` - أمثلة على النسخ الاحتياطي للمستودعات

## 📦 النماذج والبيانات

- `sync_models.dart` - نماذج بيانات المزامنة

## 🎯 Mixins

- `sync_on_exit_mixin.dart` - Mixin للمزامنة عند الخروج من الشاشة

## 📋 المهام الخلفية

- `auto_sync_task.dart` - مهمة المزامنة التلقائية في الخلفية
- `appwrite_auto_sync_task.dart` - مهمة مزامنة Appwrite التلقائية

## ✨ الواجهات التفاعلية

- `smart_sync_widgets.dart` - واجهات المزامنة الذكية التفاعلية

## 🔍 الملاحظات

- جميع الملفات منسوخة من `mobile/lib/`
- تم الحفاظ على البنية الأصلية للمجلدات
- يمكن استخدام هذا المجلد كمرجع أو للاستعادة

## 📝 كيفية الاستخدام

هذا المجلد هو نسخة احتياطية فقط. لا يتم استخدام الملفات هنا في التطبيق مباشرة.
للعودة إلى نسخة سابقة، انسخ الملفات المطلوبة من هنا إلى موقعها الأصلي في `mobile/lib/`.

## 📋 القائمة الكاملة بجميع الملفات المنسوخة (77 ملف)

<details>
<summary>انقر لعرض القائمة الكاملة</summary>

### Root Files (2)
- `main.dart`
- `main_with_auto_sync_engine.dart`

### Data (1)
- `data/sync_models.dart`

### Mixins (1)
- `mixins/sync_on_exit_mixin.dart`

### Providers (6)
- `providers/appwrite_providers.dart`
- `providers/auto_backup_provider.dart`
- `providers/auto_sync_engine_providers.dart`
- `providers/backup_provider.dart`
- `providers/core_providers.dart`
- `providers/smart_sync_provider.dart`

### Screens (9)
- `screens/appwrite_sync_stats_screen.dart`
- `screens/auto_backup_settings_screen.dart`
- `screens/auto_sync_engine_monitor_screen.dart`
- `screens/comprehensive_backup_screen.dart`
- `screens/google_drive_backup_screen.dart`
- `screens/restore_fix_screen.dart`
- `screens/smart_sync_settings_screen.dart`
- `screens/sync_debug_logs_screen.dart`
- `screens/sync_performance_settings_screen.dart`

### Services (56)
- `services/alarm_backup.dart`
- `services/appwrite_cache_manager.dart`
- `services/appwrite_delta_sync.dart`
- `services/appwrite_logger.dart`
- `services/appwrite_service.dart`
- `services/appwrite_sync_manager.dart`
- `services/auto_backup_manager.dart`
- `services/auto_backup_task.dart`
- `services/backup_serializers.dart`
- `services/bookings_repository_with_auto_backup.dart`
- `services/conflict_manager.dart`
- `services/conflict_resolver.dart`
- `services/database_auto_backup_hooks.dart`
- `services/delta_sync_service.dart`
- `services/google_drive_auto_sync_engine.dart`
- `services/google_drive_backup_service.dart`
- `services/google_drive_conflict_resolver.dart`
- `services/google_drive_delta_sync.dart`
- `services/google_drive_logger.dart`
- `services/google_drive_sync_service.dart`
- `services/google_drive_unified_sync_coordinator.dart`
- `services/local_backup_service.dart`
- `services/realtime_sync_notifier.dart`
- `services/repository_auto_backup_examples.dart`
- `services/restore_fix_service.dart`
- `services/screen_sync_controller.dart`
- `services/smart_google_drive_sync.dart`
- `services/smart_sync_manager.dart`
- `services/sqlite_backup_restore.dart`
- `services/sync_config.dart`
- `services/sync_constants.dart`
- `services/sync_enums.dart`
- `services/sync_guardian.dart`
- `services/sync_health_monitor.dart`
- `services/sync_locks.dart`
- `services/sync_manager.dart`
- `services/sync_mutex.dart`
- `services/sync_notification_manager.dart`
- `services/sync_performance_optimizer.dart`
- `services/sync_performance_settings.dart`
- `services/sync_queue_service.dart`
- `services/sync_safety_layer.dart`
- `services/sync_service.dart`
- `services/unified_sync_orchestrator.dart`

#### Services/DAOs (1)
- `services/daos/outbox_dao.dart`

#### Services/Logging (1)
- `services/logging/log_models.dart`

#### Services/Monitoring (1)
- `services/monitoring/sync_monitoring_system.dart`

#### Services/Sync Core (8)
- `services/sync_core/base_sync_manager.dart`
- `services/sync_core/circuit_breaker.dart`
- `services/sync_core/conflict_resolver.dart`
- `services/sync_core/retry_strategy.dart`
- `services/sync_core/sync_error_handler.dart`
- `services/sync_core/sync_metrics.dart`
- `services/sync_core/sync_scheduler.dart`
- `services/sync_core/sync_validator.dart`

### Tasks (2)
- `tasks/appwrite_auto_sync_task.dart`
- `tasks/auto_sync_task.dart`

### Widgets (1)
- `widgets/smart_sync_widgets.dart`

</details>

---

**تم الإنشاء بواسطة**: Capy AI  
**التاريخ**: 2026-01-01  
**المستودع**: NassarAlshabi1/marina-hotel-wit-app  
**الفرع**: capy/S  
**الحالة**: ✅ مكتمل - تم نسخ جميع ملفات المزامنة والنسخ الاحتياطي (77 ملف)
