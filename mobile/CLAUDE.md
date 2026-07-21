# Marina Hotel Mobile App - Analysis Report

## Architecture
- **Pattern**: Offline-First + Modified Clean Architecture
- **Layers**: screens/ (28), services/ (118), providers/ (22), models/ (5), components/ (12), widgets/ (7), utils/ (31), core/ (5)
- **Total**: ~379 Dart files in lib/

## State Management
- **Riverpod** (flutter_riverpod ^2.6.1) — StateNotifierProvider, Provider, StreamProvider, FutureProvider, Provider.family
- 22 provider files, good separation of concerns

## Local Database
- **Drift ORM** (^2.31.0) + SQLite with WAL mode
- 30 tables (Rooms, Bookings, Payments, Employees, Expenses, etc.)
- Current schema version: 50 (many migrations)
- Mixin `SyncFields` on all tables: localUuid, serverId, version, origin, vectorClock, deviceId, idempotencyKey
- Good: PRAGMA foreign_keys=ON, WAL, mmap_size=256MB, cache_size=-8192, temp_store=MEMORY

## Sync System (Multi-Layer)
- Legacy Sync: `sync_service.dart` (PHP REST API)
- Appwrite Sync: `appwrite_sync_manager.dart` (6445 lines — largest file)
- Google Drive Sync: `google_drive_auto_sync_engine.dart`
- Unified Orchestrator: `unified_sync_orchestrator.dart`
- Secondary Sync (failover), Smart Sync, Continuation Service
- Protection layers: SyncMutex, SyncGate, CircuitBreaker, SyncGuardian, SyncSafetyLayer, OptimisticLockHelper

## Dependencies (46 packages)

### Redundant Packages
- `dio` + `http` → keep `dio` only
- `encrypt` + `crypto` + `pointycastle` → three crypto packages with overlap
- `android_alarm_manager_plus` + `workmanager` → keep `workmanager` only

### Likely Unused Packages
- `signals_flutter: ^6.0.0` — no imports found
- `battery_plus: ^6.0.2` — no imports found

### Core (keep)
flutter_riverpod, drift, appwrite, sqflite, dio, firebase_core, firebase_crashlytics, firebase_messaging, firebase_analytics, firebase_remote_config, flutter_secure_storage, encrypt, crypto, google_sign_in, googleapis, pdf/printing, fl_chart, flutter_contacts, file_picker, share_plus, shimmer, flutter_animate, intl, shared_preferences, path_provider, connectivity_plus, permission_handler, device_info_plus, package_info_plus, url_launcher, uuid, web_socket_channel, freezed_annotation, json_annotation

## Critical Issues (Priority: HIGH)

1. **API Key exposed in `.env`**: `AGENT_ROUTER_API_KEY=sk-ZN9FooZG5Ji40MUzKIu86CIAfZIGG1JfavQa6QivLKOLXpzH` is a real OpenRouter key in plain text. Revoke immediately. Add `.env` to `.gitignore`.

2. **XOR obfuscation instead of real encryption**: `secure_storage.dart:6` uses XOR with static key `'marina_hotel_sync_secret_2024'`. Package `encrypt: ^5.0.3` exists in pubspec.yaml but is NOT used in SecureStorage.

## Medium Priority Issues

3. `appwrite_sync_manager.dart` is 6445 lines — split into smaller files
4. `sync_service.dart:_applyIncoming()` is 380 lines with 8 switch cases — split per entity
5. `SharedPreferences.getInstance()` called repeatedly in main.dart (lines 218, 379, 535, 567, 1148, 1206)
6. Redundant `http` package — `dio` covers all HTTP needs
7. `signals_flutter` and `battery_plus` unused
8. Legacy `sync_service.dart` uses old PHP REST API — may be dead code alongside Appwrite sync
9. Most models use manual `copyWith`/`fromJson` — `freezed` available but unused

## Low Priority
10. Triple crypto packages (encrypt + crypto + pointycastle)
11. Only 2 integration test files for 30 tables and 379 Dart files
12. `main()` runs 15+ init operations sequentially — slows app startup
13. Schema version 50 indicates frequent structural changes
