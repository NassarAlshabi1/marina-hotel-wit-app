/// تم تعطيل التكامل مع Supabase Sync.
/// يوفر هذا الملف بدائل بسيطة للحفاظ على التوافق دون أي منطق فعلي.
import 'dart:async';

import 'local_db.dart';

enum SyncStatus { idle, running, error }

enum SyncMode { push, pull }

enum SyncScope { full }

typedef SyncProgressCallback = void Function(double progress);

typedef SyncErrorHandler = void Function(Object error, StackTrace stackTrace);

class SupabaseSyncService {
  SupabaseSyncService(this.db);
  final AppDatabase db;

  SyncStatus get currentStatus => SyncStatus.idle;
  SyncScope get scope => SyncScope.full;
  SyncMode get mode => SyncMode.push;

  Stream<SyncStatus> get statusStream => Stream.value(SyncStatus.idle);

  Future<void> initialize() async {}
  Future<void> runOnce({SyncProgressCallback? onProgress}) async {}
  Future<void> dispose() async {}
}
