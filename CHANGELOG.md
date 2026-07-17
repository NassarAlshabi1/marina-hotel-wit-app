# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Quality Gate Pipeline** — 4 workflows احترافية (quality, test, security, build)
- **Architecture Validator** — سكريبت Python للتحقق من Clean Architecture + Riverpod
- **Dependency Audit** — سكريبت shell لفحص الحزم القديمة/غير المستخدمة/الثغرات
- **LICENSE** — MIT License
- **CONTRIBUTING.md** — دليل المساهمة
- `very_good_analysis` — مجموعة قواعد lint صارمة
- `analysis_options.yaml` — تكوين احترافي مع strict-casts, strict-inference, strict-raw-types
- `dart_code_metrics.yaml` — تكوين قياس تعقيد الكود
- Appwrite Messaging integration (`appwrite_messaging_service.dart`)
- WorkManager SyncContinuationService — إكمال المزامنة في الخلفية
- `messaging-notifier` Appwrite Function (بديل FCM المباشر)

### Fixed
- **Crash: AnimationController Null check** — Race condition بين dispose() و finally
- **11 Crash: Unprotected Timer callbacks** — كل Timer callbacks محمية بـ try-catch
- **Crash: Connection reset by peer** — createSyncLog أصبح non-fatal + retry mechanism
- **flutter analyze** — من 30 issues إلى `No issues found!`
- **dart format** — من 387 warnings إلى 0 (باستثناء ملفات .g.dart المُولّدة)

### Changed
- `analysis_options.yaml` — الترقية من `flutter_lints` إلى `very_good_analysis`
- Workflows — إعادة تنظيم لـ 4 مراحل احترافية بدلاً من 16 workflow متفرقة
- `dashboard_sync_button.dart` — `_safeStopAnimation()` بدلاً من `.stop()` مباشرة
- `appwrite_sync_manager.dart` — `createSyncLog` محاط بـ try-catch مستقل
- `central_sync_coordinator.dart` — Timer callback محمي بـ try-catch
- جميع Timer callbacks في مسار المزامنة — محمية بـ try-catch

### Removed
- `mobile/test/sync/` — 4 ملفات اختبار قديمة (1166 سطر)

## [1.2.0] — 2026-07-14

### Added
- FCM event parsing — support collections/documents format
- SyncGate — حارس مشترك لمنع تداخل المزامنة
- Comprehensive backup service
- Google Drive sync improvements

### Fixed
- FCM Function event parsing regex bugs
- Sync conflicts between AppwriteSyncManager و SmartSyncManager

## [1.1.0] — 2026-06-15

### Added
- Appwrite Cloud integration
- Offline-first architecture with Drift
- Real-time sync via WebSocket
- Telegram + WhatsApp notifications

## [1.0.0] — 2026-05-01

### Added
- Initial release
- Hotel management (rooms, bookings, payments, expenses)
- Employee management with salary cycles
- Reports (PDF generation)
- RTL Arabic UI
