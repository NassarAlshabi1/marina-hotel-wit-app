import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';

final syncProvider = Provider<SyncService>(
  (ref) => SyncService(DatabaseManager.instance),
);
