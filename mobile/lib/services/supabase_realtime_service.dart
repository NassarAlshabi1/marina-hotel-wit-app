/// تم تعطيل التكامل مع Supabase Realtime.
/// يحتفظ هذا الملف بتعاريف بديلة بسيطة لتفادي كسر الاستيرادات القديمة.
import 'dart:async';

import 'local_db.dart';

enum RealtimeStatus { disabled }

class RealtimeEvent {
  const RealtimeEvent({this.table = '', this.eventType = ''});
  final String table;
  final String eventType;
}

class RealtimeStats {
  const RealtimeStats();
  int get totalEvents => 0;
  Duration get averageLatency => Duration.zero;
}

class SupabaseRealtimeService {
  SupabaseRealtimeService(this.db);
  final AppDatabase db;

  Stream<RealtimeStatus> get statusStream => Stream.value(RealtimeStatus.disabled);
  Stream<RealtimeEvent> get eventsStream => const Stream.empty();

  RealtimeStatus get currentStatus => RealtimeStatus.disabled;
  RealtimeStats get stats => const RealtimeStats();

  Future<void> subscribeToAll() async {}
  Future<void> dispose() async {}
}
